"""navroute - the wizard's route through its zone, round walls and along the floor, for the walker (vision.py
/nav?route=1) and the dashboard's map.

READ-ONLY: it works from the zone's own files (navgeo: the floor, water and obstacles in collision.bcd) and the
readings /nav already makes of the game's memory (navmem) - nothing in the game is touched, no keys are sent.

    p = Planner(log=print)
    res = p.route(r)       # r: a navmem reading made with path=True
    # res: {'aim': (x, y), 'left': units, 'route': [(x, y), ...], 'why': ''} - or {'why': '...'} with no aim

How it plans
  * Where to: the game's own quest path (navmem 'path': nodes of the zone's nav graph, 480 apart) leads to the
    goal (navmem 'goal': the quest goal, or the way out of the zone when it's in another one). The planner
    heads for the farthest point of [path..., goal] within REACH of the wizard - the "carrot" - in a window
    round the wizard, the carrot and the path between them, in CELL squares. The carrot it has stays while
    it's still ahead and no more than KEEP further than that (a way round a wall can lead away from it for a
    while); it stops short of where the path comes back over (or under) an earlier stretch on another storey.
  * The height the wizard walks at there: the wizard's own height where it stands, the game's path's further
    on (its nodes can float above the floor in a few zones: they're moved by however far the nearest one is
    off the wizard's feet), in between along the path. In each square the floor is the walkable surface nearest
    that height - a walkable mesh, a walkable box's top, or the top of an obstacle box (many ramps, stair slabs
    and hillsides are boxes, walked on) - within FLOOR_BAND of it, so the storeys above and below don't count.
    A square with none is "no floor": a gap, a drop, a cliff's face - not walked or looked across (unless the
    window has no floor at all: then the files miss it, and it's walked as floor); water costs COST_WATER.
  * Obstacles - boxes and cylinders (by their real top and bottom in each square, sampled 3 x 3 times: many
    boxes are tilted, and logs and pipes lie on their sides), spheres, collision meshes - block a square when
    they reach into the wizard's body standing on its floor (from STEP_UP to HEAD above it). An obstacle box
    whose top is the floor of a square (no floor mesh under it) but stands more than STEP_EDGE above the floor
    beside it - a desk, a counter, a low wall - is solid there too. They're grown by CLEAR (forbidden) and are dearer up to SOFT
    away (so it keeps to the middle of a corridor when there's room). Two neighbouring squares whose floors are
    more than STEP_EDGE apart aren't walked between (a ledge, a cliff).
  * The cost to the carrot from every square of the window (a "field") is worked out in a background thread,
    ~30-200 ms, and kept: from wherever the wizard is in the window, the route is a walk downhill on it (a
    millisecond or two). A new field is worked out when the carrot moves on, the wizard nears the window's edge
    or climbs / drops far, or the goal changes; the old one is used meanwhile.
  * The aim: the farthest point along the route within LOOK_FAR that can be seen in a straight line keeping
    CLEAR_SEE from walls (else within LOOK_NEAR keeping CLEAR) - the walker steers at it.
  * left: the route's length to the carrot plus the game's path on from there to the goal - how far is left to
    walk, for the walker's "is it getting anywhere" checks (going round a wall gets no closer as the crow flies).

Things the zone files don't have - NPCs, other players, doors that open - aren't avoided; the walker's own
"stuck: back up and go round" handles those as before.
"""
import collections
import math
import threading
import time

import numpy as np
from PIL import Image, ImageDraw

CELL = 20.0             # game units per grid square
CLEAR = 40.0            # walls grown by this much: the wizard's middle never goes nearer (2 squares: 30-50)
SOFT = 120.0            # ...and keeps away up to this far when there's room
SOFT_COST = 3.0         # extra cost right outside CLEAR, fading to nothing at SOFT
CLEAR_SEE = 80.0        # a straight line to the far aim keeps this far from walls (4 squares)
STEP_UP = 60.0          # obstacles no higher than this above the floor are stepped over (a nav node of the
                        # game's own sits on a cylinder 50 high in Ravenwood)
HEAD = 170.0            # obstacles whose bottom is this high above the floor are walked under
STEP_EDGE = 60.0        # neighbouring squares whose floors are further apart than this: a ledge, not walked
FLOOR_BAND = 260.0      # a floor more than this above / below the height walked at there is another storey
BOX_BAND = 120.0        # ...an obstacle box's top counts as floor (a ramp, a stair slab) only this near it (a roof
                        # or an awning 200 up, with no floor mesh under it, isn't where the wizard walks)
COST_WATER = 4.0
COST_OFF = 6.0
REACH = 2400.0          # the carrot: the farthest point of the game's path within this of the wizard
KEEP = 400.0            # ...the one it has stays (till one further on is in reach) up to this much further
OVERLAP = 200.0         # the game's path back this near (x / y) an earlier stretch of it on another storey: the
                        # carrot stops before
GOAL_RINGS = 12         # the goal inside something (a counter, a wall): the free square nearest it within this many
MARGIN = 600.0          # the window: round the wizard, the carrot and the path between, this much more
MAX_CELLS = 300         # ...at most this many squares across (6000 units)
LOOK_FAR = 600.0
LOOK_NEAR = 220.0
REPLAN_Z = 250.0        # the wizard this much higher / lower than when the field was made: a new one
EDGE_CELLS = 6          # ...or this near the window's edge
ZONES_KEPT = 3

DIRS = [(-1, 0, 1.0), (1, 0, 1.0), (0, -1, 1.0), (0, 1, 1.0),
        (-1, -1, math.sqrt(2)), (-1, 1, math.sqrt(2)), (1, -1, math.sqrt(2)), (1, 1, math.sqrt(2))]
SUB = (np.arange(3) + 0.5) / 3          # 3 x 3 looks per square


class ZoneGeo:
    """One zone's floor, water and obstacles from its .wad (navgeo), kept for cutting out windows.
    why: why there's nothing ('' when there is)"""

    def __init__(self, zone, game_dir=''):
        self.zone, self.why = zone, ''
        empty3 = np.zeros((0, 3, 3))
        self.floor = self.water = self.otris = empty3       # (F, 3, 3) world triangles
        self.boxes = []          # (R, location, half sizes, x1, y1, x2, y2, zlo, zhi, walkable)
        self.cyls = []           # cylinders, tubes: (centre, axis, radius, half length, x1, y1, x2, y2, zlo, zhi, walkable)
        self.round = []          # spheres: (polygon (k, 2), zlo, zhi, walkable)
        try:
            import navgeo
            d = navgeo.load_zone(zone, game_dir or navgeo.GAME_DIR)
        except Exception as e:  # noqa: BLE001 - no route, the walker steers as before
            self.why = str(e) if isinstance(e, FileNotFoundError) else f"the zone file can't be read ({e!r})"
            return
        floor, water, otris = [], [], []
        for s in d['bcd'] or []:
            cat, t = s['category_flags'], s['type']
            if t == 'mesh':
                if not len(s['mesh']['faces']):
                    continue
                v, f = navgeo.mesh_world(s)
                tris = v[f]
                if cat & 0x2:
                    floor.append(tris)
                elif cat & 0x40:
                    water.append(tris)
                elif cat & 0x81:
                    otris.append(tris)
            elif t in ('box', 'cylinder', 'sphere', 'tube') and cat & 0x83:
                ab = navgeo.aabb(s)
                if ab is None:
                    continue
                walk = bool(cat & 0x2)
                if t == 'box':
                    self.boxes.append((np.asarray(s['rotation'], float), np.asarray(s['location'], float), np.asarray(s['size'], float) / 2,
                                       ab[0][0], ab[0][1], ab[1][0], ab[1][1], ab[0][2], ab[1][2], walk))
                elif t in ('cylinder', 'tube'):
                    self.cyls.append((np.asarray(s['location'], float), np.asarray(s['rotation'], float)[:, 2], float(s['radius']),
                                      float(s['height']) / 2, ab[0][0], ab[0][1], ab[1][0], ab[1][1], ab[0][2], ab[1][2], walk))
                else:
                    self.round += [(p, ab[0][2], ab[1][2], walk) for p in navgeo.footprint(s, 28) if len(p) >= 3]
        self.floor = np.concatenate(floor) if floor else empty3
        self.water = np.concatenate(water) if water else empty3
        self.otris = np.concatenate(otris) if otris else empty3
        if not len(self.floor) and not any(b[9] for b in self.boxes):
            self.why = 'the zone file has no floor'

    @staticmethod
    def _tri_pick(tris, x1, y1, x2, y2, zlo, zhi):
        if not len(tris):
            return tris
        mn, mx = tris.min(1), tris.max(1)
        keep = (mx[:, 0] >= x1) & (mn[:, 0] <= x2) & (mx[:, 1] >= y1) & (mn[:, 1] <= y2) & (mx[:, 2] >= zlo) & (mn[:, 2] <= zhi)
        return tris[keep]

    def grids(self, x0, y0, nx, ny, ref):
        """(ground, H, solid) for the window whose square (0, 0) has its lower left corner at world (x0, y0) -
        row j, column i is world (x0 + (i + .5) * CELL, y0 + (j + .5) * CELL). ref: the polyline [(x, y, z)...]
        the wizard walks along (its heights pick the storey). ground: 0 no floor, 1 floor, 2 water; H: the
        floor's height (the height walked at where there's none); solid: an obstacle in the way there"""
        X = x0 + (np.arange(nx) + 0.5) * CELL
        Y = y0 + (np.arange(ny) + 0.5) * CELL
        XX, YY = np.meshgrid(X, Y)
        R = self._ref_heights(XX, YY, ref)
        x1, y1, x2, y2 = x0, y0, x0 + nx * CELL, y0 + ny * CELL
        rlo, rhi = R.min() - FLOOR_BAND, R.max() + FLOOR_BAND
        H = np.full((ny, nx), np.nan)
        best = np.full((ny, nx), FLOOR_BAND)                     # how far the floor so far is from R
        ground = np.zeros((ny, nx), np.uint8)
        btop = np.zeros((ny, nx), bool)                          # the floor there is an obstacle box's top

        def offer(j1, i1, z, kind, band=FLOOR_BAND, obox=False):
            """floor candidates z (nan: none) for the block of squares from (j1, i1): kept where nearer R (and
            within band of it)"""
            jj, ii = slice(j1, j1 + z.shape[0]), slice(i1, i1 + z.shape[1])
            d = np.abs(z - R[jj, ii])
            take = np.isfinite(d) & (d < best[jj, ii]) & (d <= band)
            if take.any():
                best[jj, ii] = np.where(take, d, best[jj, ii])
                H[jj, ii] = np.where(take, z, H[jj, ii])
                ground[jj, ii] = np.where(take, kind, ground[jj, ii])
                btop[jj, ii] = np.where(take, obox, btop[jj, ii])

        for tris, kind in ((self.floor, 1), (self.water, 2)):
            for tri in self._tri_pick(tris, x1, y1, x2, y2, rlo, rhi):
                blk = self._tri_cells(tri, x0, y0, nx, ny)
                if blk is not None:
                    offer(blk[0], blk[1], blk[2], kind)
        # box tops are floors too (walkable boxes; and ramps, stair slabs and hillsides made of obstacle boxes),
        # sampled at the square's middle; and the tops of round ones marked walkable
        cols = []
        for box in self.boxes:
            if box[5] >= x1 and box[3] <= x2 and box[6] >= y1 and box[4] <= y2 and box[8] >= rlo and box[7] <= rhi + HEAD:
                c = self._box_cols(box, x0, y0, nx, ny)
                if c is not None:
                    cols.append((box, c))
                    j1, i1, tmin, tmax = c
                    top = np.where(tmin <= tmax, tmax, np.nan)[1::3, 1::3]
                    offer(j1, i1, top, 1, FLOOR_BAND if box[9] else BOX_BAND, not box[9])
        for cyl in self.cyls:
            if cyl[6] >= x1 and cyl[4] <= x2 and cyl[7] >= y1 and cyl[5] <= y2 and cyl[9] >= rlo and cyl[8] <= rhi + HEAD:
                c = self._cyl_cols(cyl, x0, y0, nx, ny)
                if c is not None:
                    cols.append((cyl, c))
                    if cyl[10]:
                        j1, i1, tmin, tmax = c
                        offer(j1, i1, np.where(tmin <= tmax, tmax, np.nan)[1::3, 1::3], 1)
        rounds = [(p, lo, hi, walk) for p, lo, hi, walk in self.round
                  if hi >= rlo and lo <= rhi + HEAD and p[:, 0].max() >= x1 and p[:, 0].min() <= x2 and p[:, 1].max() >= y1 and p[:, 1].min() <= y2]
        for p, lo, hi, walk in rounds:
            if walk:
                m = self._poly_mask(p, x0, y0, nx, ny)
                if m is not None:
                    offer(m[0], m[1], np.where(m[2], hi, np.nan), 1)
        # small holes between floor triangles: from the neighbours
        hole = ~np.isfinite(H)
        if hole.any():
            pad = np.pad(np.where(hole, 0.0, H), 1)
            cnt = np.pad((~hole).astype(float), 1)
            s = sum(pad[1 + dj:1 + dj + ny, 1 + di:1 + di + nx] for dj, di, _ in DIRS[:4])
            n = sum(cnt[1 + dj:1 + dj + ny, 1 + di:1 + di + nx] for dj, di, _ in DIRS[:4])
            fill = hole & (n >= 3)
            H[fill] = (s / np.maximum(n, 1))[fill]
            ground[fill] = 1
        Hs = np.where(np.isfinite(H), H, R)
        # obstacles reaching into the body of a wizard standing on that floor
        solid = np.zeros((ny, nx), bool)
        for box, (j1, i1, tmin, tmax) in cols:
            h, w = tmin.shape[0] // 3, tmin.shape[1] // 3
            Hb = np.repeat(np.repeat(Hs[j1:j1 + h, i1:i1 + w], 3, 0), 3, 1)
            hit = (tmin <= tmax) & (tmax > Hb + STEP_UP) & (tmin < Hb + HEAD)
            solid[j1:j1 + h, i1:i1 + w] |= hit.reshape(h, 3, w, 3).any(axis=(1, 3))
        for p, lo, hi, walk in rounds:
            m = self._poly_mask(p, x0, y0, nx, ny)
            if m is not None:
                j1, i1, mm = m
                sl = (slice(j1, j1 + mm.shape[0]), slice(i1, i1 + mm.shape[1]))
                solid[sl] |= mm & (hi > Hs[sl] + STEP_UP) & (lo < Hs[sl] + HEAD)
        for tri in self._tri_pick(self.otris, x1, y1, x2, y2, rlo + STEP_UP, rhi + HEAD):
            m = self._poly_mask(tri[:, :2], x0, y0, nx, ny)
            if m is not None:
                j1, i1, mm = m
                sl = (slice(j1, j1 + mm.shape[0]), slice(i1, i1 + mm.shape[1]))
                solid[sl] |= mm & (tri[:, 2].max() > Hs[sl] + STEP_UP) & (tri[:, 2].min() < Hs[sl] + HEAD)
        # an obstacle box's top more than STEP_EDGE above the floor beside it (a desk, a counter, a low wall with
        # no floor mesh under it) is a wall to whoever walks beside it: solid, so it's kept clear of too
        fl = ground > 0
        for dj, di, _ in DIRS[:4]:
            (dj_s, sj_s), (di_s, si_s) = _sl(dj, ny), _sl(di, nx)
            dst, src = (dj_s, di_s), (sj_s, si_s)
            solid[dst] |= btop[dst] & fl[src] & (Hs[dst] - Hs[src] > STEP_EDGE)
        return ground, Hs, solid

    @staticmethod
    def _ref_heights(XX, YY, ref):
        """the height walked at in each square: that of the nearest point on the polyline ref"""
        ref = np.asarray(ref, dtype=float)
        if len(ref) == 1:
            return np.full(XX.shape, ref[0, 2])
        best = np.full(XX.shape, np.inf)
        R = np.full(XX.shape, ref[0, 2])
        for a, b in zip(ref[:-1], ref[1:]):
            dx, dy = b[0] - a[0], b[1] - a[1]
            L2 = dx * dx + dy * dy
            t = np.zeros(XX.shape) if L2 < 1e-9 else np.clip(((XX - a[0]) * dx + (YY - a[1]) * dy) / L2, 0, 1)
            d2 = (XX - a[0] - t * dx) ** 2 + (YY - a[1] - t * dy) ** 2
            take = d2 < best
            best = np.where(take, d2, best)
            R = np.where(take, a[2] + t * (b[2] - a[2]), R)
        return R

    @staticmethod
    def _tri_cells(tri, x0, y0, nx, ny):
        """(j1, i1, z) - the triangle's height at the middles of the squares in its bounds (nan outside it)"""
        i1 = max(0, int((tri[:, 0].min() - x0) // CELL))
        i2 = min(nx - 1, int((tri[:, 0].max() - x0) // CELL))
        j1 = max(0, int((tri[:, 1].min() - y0) // CELL))
        j2 = min(ny - 1, int((tri[:, 1].max() - y0) // CELL))
        if i1 > i2 or j1 > j2:
            return None
        (ax, ay, az), (bx, by, bz), (cx, cy, cz) = tri
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-6:
            return None
        X = x0 + (np.arange(i1, i2 + 1) + 0.5) * CELL
        Y = y0 + (np.arange(j1, j2 + 1) + 0.5) * CELL
        XX, YY = np.meshgrid(X, Y)
        l0 = ((by - cy) * (XX - cx) + (cx - bx) * (YY - cy)) / den
        l1 = ((cy - ay) * (XX - cx) + (ax - cx) * (YY - cy)) / den
        l2 = 1 - l0 - l1
        e = -0.02
        z = np.where((l0 >= e) & (l1 >= e) & (l2 >= e), l0 * az + l1 * bz + l2 * cz, np.nan)
        return j1, i1, z

    @staticmethod
    def _box_cols(box, x0, y0, nx, ny):
        """(j1, i1, tmin, tmax): the box's bottom and top along the vertical lines through 3 x 3 points in each
        square of its bounds (tmin > tmax: no box there)"""
        R, loc, half, bx1, by1, bx2, by2 = box[:7]
        i1, i2 = max(0, int((bx1 - x0) // CELL)), min(nx - 1, int((bx2 - x0) // CELL))
        j1, j2 = max(0, int((by1 - y0) // CELL)), min(ny - 1, int((by2 - y0) // CELL))
        if i1 > i2 or j1 > j2:
            return None
        xs = x0 + (np.arange(i1, i2 + 1)[:, None] + SUB[None, :]).ravel() * CELL
        ys = y0 + (np.arange(j1, j2 + 1)[:, None] + SUB[None, :]).ravel() * CELL
        XX, YY = np.meshgrid(xs, ys)
        dx, dy, dz = XX - loc[0], YY - loc[1], -loc[2]
        tmin = np.full(XX.shape, -np.inf)
        tmax = np.full(XX.shape, np.inf)
        # the vertical line through (X, Y) is (X, Y, t); in the box's own axes it's a + t * u
        for k in range(3):
            a = R[0, k] * dx + R[1, k] * dy + R[2, k] * dz
            u = R[2, k]
            if abs(u) < 1e-9:
                out = np.abs(a) > half[k]
                tmin[out], tmax[out] = np.inf, -np.inf
                continue
            t1, t2 = (-half[k] - a) / u, (half[k] - a) / u
            tmin = np.maximum(tmin, np.minimum(t1, t2))
            tmax = np.minimum(tmax, np.maximum(t1, t2))
        return j1, i1, tmin, tmax

    @staticmethod
    def _cyl_cols(cyl, x0, y0, nx, ny):
        """(j1, i1, tmin, tmax) like _box_cols, for a cylinder along its own axis (a log lying on its side)"""
        c, a, r, hl, bx1, by1, bx2, by2 = cyl[:8]
        i1, i2 = max(0, int((bx1 - x0) // CELL)), min(nx - 1, int((bx2 - x0) // CELL))
        j1, j2 = max(0, int((by1 - y0) // CELL)), min(ny - 1, int((by2 - y0) // CELL))
        if i1 > i2 or j1 > j2:
            return None
        xs = x0 + (np.arange(i1, i2 + 1)[:, None] + SUB[None, :]).ravel() * CELL
        ys = y0 + (np.arange(j1, j2 + 1)[:, None] + SUB[None, :]).ravel() * CELL
        XX, YY = np.meshgrid(xs, ys)
        dx, dy = XX - c[0], YY - c[1]
        # the vertical line (X, Y, c.z + t): within r of the axis where A t^2 - 2 p a.z t + C <= 0, and within
        # hl along it
        p = a[0] * dx + a[1] * dy
        A = 1.0 - a[2] * a[2]
        if A < 1e-9:
            out = dx * dx + dy * dy > r * r
            tmin, tmax = np.full(XX.shape, -np.inf), np.full(XX.shape, np.inf)
        else:
            disc = (p * a[2]) ** 2 - A * (dx * dx + dy * dy - p * p - r * r)
            out = disc < 0
            sq = np.sqrt(np.maximum(disc, 0.0))
            tmin, tmax = (p * a[2] - sq) / A, (p * a[2] + sq) / A
        if abs(a[2]) < 1e-9:
            out = out | (np.abs(p) > hl)
        else:
            t1, t2 = (-hl - p) / a[2], (hl - p) / a[2]
            tmin, tmax = np.maximum(tmin, np.minimum(t1, t2)), np.minimum(tmax, np.maximum(t1, t2))
        tmin, tmax = tmin + c[2], tmax + c[2]
        tmin[out], tmax[out] = np.inf, -np.inf
        return j1, i1, tmin, tmax

    @staticmethod
    def _poly_mask(p, x0, y0, nx, ny):
        """(j1, i1, mask) - the squares the polygon covers (its outline too, so thin ones aren't missed), for
        the block of squares of its bounds from (j1, i1); None when it's outside the window"""
        p = np.asarray(p, dtype=float)[:, :2]
        i1 = max(0, int((p[:, 0].min() - x0) // CELL))
        i2 = min(nx - 1, int((p[:, 0].max() - x0) // CELL))
        j1 = max(0, int((p[:, 1].min() - y0) // CELL))
        j2 = min(ny - 1, int((p[:, 1].max() - y0) // CELL))
        if i1 > i2 or j1 > j2:
            return None
        img = Image.new('L', (i2 - i1 + 1, j2 - j1 + 1), 0)
        q = [((x - x0) / CELL - 0.5 - i1, (y - y0) / CELL - 0.5 - j1) for x, y in p.tolist()]
        ImageDraw.Draw(img).polygon(q, fill=1, outline=1)
        return j1, i1, np.asarray(img) > 0


def _grow(mask, cells):
    """distance in squares from mask (0 on it, 1, 2 ... up to cells; cells + 1 beyond) - octagonal steps"""
    dist = np.where(mask, 0, cells + 1).astype(np.int16)
    cur = mask.copy()
    for k in range(1, cells + 1):
        nxt = cur.copy()
        nxt[1:, :] |= cur[:-1, :]
        nxt[:-1, :] |= cur[1:, :]
        nxt[:, 1:] |= cur[:, :-1]
        nxt[:, :-1] |= cur[:, 1:]
        if k % 2 == 0:                                       # the diagonals every other step: octagons
            nxt[1:, 1:] |= cur[:-1, :-1]
            nxt[1:, :-1] |= cur[:-1, 1:]
            nxt[:-1, 1:] |= cur[1:, :-1]
            nxt[:-1, :-1] |= cur[1:, 1:]
        dist[nxt & ~cur] = k
        cur = nxt
    return dist


def _sl(d, n):
    """(destination, source) slices along one axis for a neighbour offset d"""
    return (slice(max(0, -d), n - max(0, d)), slice(max(0, d), n - max(0, -d)))


class Field:
    """The cost to the carrot from every square of a window"""

    def __init__(self, geo, pos, carrot, goal, rest, via=(), carrot_z=None, carrot_goal=True):
        t0 = time.perf_counter()
        self.zone, self.z, self.carrot, self.goal, self.rest = geo.zone, pos[2], carrot, goal, rest
        self.why, self.D = '', None
        # (round the wizard, the carrot and the game's path between them - a way round that strays further than
        # MARGIN from those isn't looked for)
        xs = [pos[0], carrot[0]] + [p[0] for p in via]
        ys = [pos[1], carrot[1]] + [p[1] for p in via]
        self.x0, self.y0 = min(xs) - MARGIN, min(ys) - MARGIN
        self.nx = int(math.ceil((max(xs) + MARGIN - self.x0) / CELL))
        self.ny = int(math.ceil((max(ys) + MARGIN - self.y0) / CELL))
        if self.nx > MAX_CELLS or self.ny > MAX_CELLS:
            self.why = 'too far to plan in one go'
            return
        # the heights walked at: the wizard's feet; the path's nodes moved by how far the nearest one is off them
        ref = [(pos[0], pos[1], pos[2])]
        nodes = [tuple(p) for p in via]
        if nodes:
            same = [q for q in range(len(nodes)) if abs(nodes[q][2] - pos[2]) <= FLOOR_BAND] or range(len(nodes))
            k = min(same, key=lambda q: math.hypot(nodes[q][0] - pos[0], nodes[q][1] - pos[1]))
            off = pos[2] - nodes[k][2] if math.hypot(nodes[k][0] - pos[0], nodes[k][1] - pos[1]) < 400 else 0.0
            ref += [(x, y, z + off) for x, y, z in nodes]
        else:
            off = 0.0
        if carrot_z is not None:
            ref.append((carrot[0], carrot[1], carrot_z if carrot_goal else carrot_z + off))
        ground, H, solid = geo.grids(self.x0, self.y0, self.nx, self.ny, ref)
        hard_cells = int(round(CLEAR / CELL))
        soft_cells = int(round(SOFT / CELL))
        see_cells = int(round(CLEAR_SEE / CELL))
        dist = _grow(solid, soft_cells)
        self.blocked = dist <= hard_cells
        self.see_blocked = dist <= see_cells
        cost = np.where(ground == 1, 1.0, np.where(ground == 2, COST_WATER, COST_OFF))
        if not (ground > 0).any():
            cost[:] = 1.0                                       # (no floor at all here: the files miss it)
        else:
            # (a square with no floor where the window has some: a gap, a drop, a cliff's face - not walked or looked
            # across; its H is only the height walked at, so the ledge test can't see it)
            self.blocked |= ground == 0
            self.see_blocked |= ground == 0
        near = (dist > hard_cells) & (dist <= soft_cells)
        cost = cost + np.where(near, SOFT_COST * (soft_cells + 1 - dist) / (soft_cells + 1 - hard_cells), 0.0)
        cost[self.blocked] = np.inf
        self.cost, self.ground, self.H = cost, ground, H
        g = self._free_near(*self.cell(carrot), GOAL_RINGS)
        if g is None:
            self.why = "the goal is inside a wall (no free spot near it)"
            return
        self.gcell = g
        self.D = self._solve(g)
        self.ms = (time.perf_counter() - t0) * 1000
        self.made = time.time()

    def cell(self, p):
        return int(math.floor((p[1] - self.y0) / CELL)), int(math.floor((p[0] - self.x0) / CELL))

    def world(self, j, i):
        return self.x0 + (i + 0.5) * CELL, self.y0 + (j + 0.5) * CELL

    def inside(self, j, i, edge=0):
        return edge <= j < self.ny - edge and edge <= i < self.nx - edge

    def _free_near(self, j, i, rings):
        """the free square nearest (j, i) within rings squares, or None"""
        best = None
        for r in range(rings + 1):
            for jj in range(j - r, j + r + 1):
                for ii in range(i - r, i + r + 1):
                    if max(abs(jj - j), abs(ii - i)) != r or not self.inside(jj, ii) or self.blocked[jj, ii]:
                        continue
                    d = (jj - j) ** 2 + (ii - i) ** 2
                    if best is None or d < best[0]:
                        best = (d, jj, ii)
            if best is not None:
                return best[1], best[2]
        return None

    def _passable(self, dst, src):
        """the step between the squares dst and src is walkable: their floors no further apart than STEP_EDGE"""
        return np.abs(self.H[dst] - self.H[src]) <= STEP_EDGE

    def _solve(self, g):
        ny, nx, c = self.ny, self.nx, self.cost
        D = np.full((ny, nx), np.inf)
        D[g] = 0.0
        free = ~self.blocked
        steps = []
        for dj, di, w in DIRS:
            dj_s, sj_s = _sl(dj, ny)
            di_s, si_s = _sl(di, nx)
            dst, src = (dj_s, di_s), (sj_s, si_s)
            step = w * 0.5 * (c[dst] + c[src])
            ok = self._passable(dst, src)
            if dj and di:                                    # no cutting a wall's corner
                ok &= free[(sj_s, di_s)] & free[(dj_s, si_s)]
            steps.append((dst, src, np.where(ok, step, np.inf)))
        for _ in range(4 * (nx + ny)):
            changed = False
            for dst, src, step in steps:
                cand = D[src] + step
                better = cand < D[dst] - 1e-9
                if better.any():
                    D[dst] = np.where(better, cand, D[dst])
                    changed = True
            if not changed:
                break
        return D

    def walk(self, pos):
        """the squares downhill from pos to the carrot: (squares, length in game units), or (None, why)"""
        j, i = self.cell(pos)
        if not self.inside(j, i):
            return None, 'off the planned area'
        if self.blocked[j, i] or not np.isfinite(self.D[j, i]):
            s = self._free_near(j, i, 8)
            if s is None or not np.isfinite(self.D[s]):
                return None, 'no way from here' if s is not None else 'right against a wall'
            j, i = s
        cells, length, D, c, H = [(j, i)], 0.0, self.D, self.cost, self.H
        for _ in range(4 * (self.nx + self.ny)):
            if D[j, i] <= 0:
                break
            best = None
            for dj, di, w in DIRS:
                jj, ii = j + dj, i + di
                if not self.inside(jj, ii) or not np.isfinite(D[jj, ii]) or abs(H[jj, ii] - H[j, i]) > STEP_EDGE:
                    continue
                if dj and di and (self.blocked[j + dj, i] or self.blocked[j, i + di]):
                    continue
                v = D[jj, ii] + w * 0.5 * (c[j, i] + c[jj, ii])
                if best is None or v < best[0]:
                    best = (v, jj, ii, w)
            if best is None or best[0] >= D[j, i] + 1e-6:
                break
            j, i = best[1], best[2]
            cells.append((j, i))
            length += best[3] * CELL
        return cells, length

    def seen(self, a, b, mask, skip=0.0):
        """a straight line from world a to world b crosses no square of mask, and no ledge (the first skip
        units left out: the wizard brushing a wall starts inside its margin - the wall itself, further on,
        still counts)"""
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        n = int(L / (CELL * 0.4)) + 2
        t = np.linspace(0.0, 1.0, n)
        if skip > 0 and L > 0:
            t = t[t * L >= skip]
        xs, ys = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
        jj = np.floor((ys - self.y0) / CELL).astype(int)
        ii = np.floor((xs - self.x0) / CELL).astype(int)
        ok = (jj >= 0) & (jj < self.ny) & (ii >= 0) & (ii < self.nx)
        jj, ii = jj[ok], ii[ok]
        if mask[jj, ii].any():
            return False
        h = self.H[jj, ii]
        return not (len(h) > 1 and (np.abs(np.diff(h)) > STEP_EDGE).any())


class Planner:
    """Routes for /nav?route=1: route(r) answers at once from the field it has and asks the background thread
    for a new one when that's needed (see the top of this file)"""

    def __init__(self, log=print, game_dir=''):
        self.log, self.game_dir = log, game_dir
        self.zones = collections.OrderedDict()
        self.field = None
        self.want = None
        self.busy = False
        self.failed = None                   # the last job that found no plan: (job, why)
        self.cv = threading.Condition()
        self.thread = None
        self.last = None                     # the last answer, for the map: (time, zone, route, aim)

    # ---- the background thread
    def _geo(self, zone):
        g = self.zones.get(zone)
        if g is None:
            t0 = time.perf_counter()
            g = self.zones[zone] = ZoneGeo(zone, self.game_dir)
            self.log(f'route: zone {zone} read in {(time.perf_counter() - t0) * 1000:.0f} ms'
                     f' ({len(g.floor)} floor triangles, {len(g.boxes)} boxes, {len(g.round)} round obstacles)' + (f' - {g.why}' if g.why else ''))
            while len(self.zones) > ZONES_KEPT:
                self.zones.popitem(last=False)
        self.zones.move_to_end(zone)
        return g

    def _run(self):
        while True:
            with self.cv:
                while self.want is None:
                    self.cv.wait()
                job, self.want = self.want, None
                self.busy = True
            f, why = None, ''
            try:
                geo = self._geo(job['zone'])
                if geo.why:
                    why = geo.why
                else:
                    f = Field(geo, job['pos'], job['carrot'], job['goal'], job['rest'], job['via'], job['carrot_z'], job['carrot_goal'])
                    why = f.why
            except Exception as e:  # noqa: BLE001 - logged; no route, the walker steers as before
                why = f'the planner failed ({e!r})'
                self.log(f'route: planning failed: {e!r}')
            with self.cv:
                if f is not None and f.D is not None:
                    self.field, self.failed = f, None
                else:
                    self.failed = (job, why or '?')
                    if self.field is not None and self.field.zone != job['zone']:
                        self.field = None
                self.busy = False

    def _ask(self, job):
        with self.cv:
            self.want = job
            if self.thread is None:
                self.thread = threading.Thread(target=self._run, name='route', daemon=True)
                self.thread.start()
            self.cv.notify()

    # ---- answering
    @staticmethod
    def carrot(pos, path, goal, keep=None):
        """(carrot (x, y), its height, is it the goal, the game's path on from it to the goal, the path's points
        up to it) - the farthest point of [path..., goal] within REACH of pos, from the one nearest pos on;
        carrot None when none is that near"""
        G = [tuple(p) for p in (path or ())] + [tuple(goal)]
        dists = [math.hypot(p[0] - pos[0], p[1] - pos[1]) for p in G]
        # (the nearest on the wizard's own storey - one right above or below it is on another)
        same = [k for k in range(len(G)) if abs(G[k][2] - pos[2]) <= FLOOR_BAND] or range(len(G))
        k0 = min(same, key=lambda k: dists[k])
        best = None
        for k in range(k0, len(G)):
            if dists[k] <= REACH:
                best = k
        # (the carrot it has stays while it's still on the path ahead and not much out of reach: a route round a
        # wall can lead away from it, and dropping back to a nearer one would turn the wizard round - and back)
        if keep is not None:
            kk = [k for k in range(k0, len(G)) if math.hypot(G[k][0] - keep[0], G[k][1] - keep[1]) <= 2 * CELL]
            if kk and dists[kk[-1]] <= REACH + KEEP and (best is None or kk[-1] > best):
                best = kk[-1]
        # (nearer when the path up to it wanders wider than a window can be)
        span = MAX_CELLS * CELL - 2 * MARGIN - 2 * CELL
        while best is not None and best > k0:
            xs = [pos[0]] + [p[0] for p in G[k0:best + 1]]
            ys = [pos[1]] + [p[1] for p in G[k0:best + 1]]
            if max(xs) - min(xs) <= span and max(ys) - min(ys) <= span:
                break
            best -= 1
        if best is not None and best > k0:
            best = Planner._before_overlap(pos, G, k0, best)
        if best is None:
            return None, None, True, 0.0, []
        rest = sum(math.hypot(G[k + 1][0] - G[k][0], G[k + 1][1] - G[k][1]) for k in range(best, len(G) - 1))
        # (the goal's own height is real; a path node's is moved like the rest - see Field)
        return (G[best][0], G[best][1]), G[best][2], best == len(G) - 1, rest, G[k0:best]

    @staticmethod
    def _before_overlap(pos, G, k0, best):
        """best, or the node before the first stretch of [pos, G[k0]..G[best]] that comes back within OVERLAP
        (x / y) of an earlier one more than FLOOR_BAND higher or lower - another storey (a square's height is
        taken from the path nearest it in x / y, so there it would be the wrong storey's)"""
        P = np.array([pos] + list(G[k0:best + 1]), float)
        lens = [math.hypot(*(P[k, :2] - P[k - 1, :2])) for k in range(1, len(P))]
        step = max(2 * CELL, sum(lens) / 400)                # (at most ~400 points: a long path stays quick)
        pts, seg, run = [P[0]], [k0], [0.0]
        for k in range(1, len(P)):
            L = lens[k - 1]
            n = max(1, int(L / step))
            for t in np.arange(1, n + 1) / n:
                pts.append(P[k - 1] + t * (P[k] - P[k - 1]))
                seg.append(k0 + k - 1)
                run.append(run[-1] + L / n)
        pts, run = np.array(pts), np.array(run)
        d = np.hypot(pts[:, None, 0] - pts[None, :, 0], pts[:, None, 1] - pts[None, :, 1])
        bad = (d < OVERLAP) & (np.abs(pts[:, None, 2] - pts[None, :, 2]) > FLOOR_BAND) & (run[:, None] - run[None, :] > OVERLAP)
        hit = np.flatnonzero(bad.any(1))
        if len(hit):
            return max(k0, seg[hit[0]] - 1)
        return best

    def route(self, r):
        if r is None or r.get('pos') is None or r.get('goal') is None or not r.get('zone'):
            return {'why': 'no position or goal'}
        pos, goal, zone = tuple(r['pos']), tuple(r['goal']), r['zone']
        f = self.field
        if f is not None and (f.zone != zone or math.hypot(f.goal[0] - goal[0], f.goal[1] - goal[1]) > 60):
            f = None                                              # (another zone, or a new goal)
        carrot, cz, cgoal, rest, via = self.carrot(pos, r.get('path'), goal, f.carrot if f is not None else None)
        if carrot is None:
            return {'why': "the game's path is out of reach"}
        j, i = f.cell(pos) if f is not None else (0, 0)
        stale = (f is None or not f.inside(j, i, EDGE_CELLS) or abs(pos[2] - f.z) > REPLAN_Z
                 or math.hypot(f.carrot[0] - carrot[0], f.carrot[1] - carrot[1]) > 2 * CELL)
        failed = self.failed
        if stale and not self.busy and self.want is None:
            same_fail = (failed is not None and failed[0]['zone'] == zone
                         and math.hypot(failed[0]['carrot'][0] - carrot[0], failed[0]['carrot'][1] - carrot[1]) <= 2 * CELL
                         and math.hypot(failed[0]['pos'][0] - pos[0], failed[0]['pos'][1] - pos[1]) <= 4 * CELL
                         and abs(failed[0]['pos'][2] - pos[2]) <= REPLAN_Z and time.time() - failed[0]['at'] < 5)
            if not same_fail:
                self._ask({'zone': zone, 'pos': pos, 'carrot': carrot, 'carrot_z': cz, 'carrot_goal': cgoal, 'goal': goal,
                           'rest': rest, 'via': via, 'at': time.time()})
        # (the last job, for the carrot as it is now, found no plan: the old field leads only to the old carrot -
        # walked to it, it would hold the wizard there. No aim: the walker steers at the arrow meanwhile)
        if (f is not None and failed is not None and failed[0]['zone'] == zone
                and math.hypot(f.carrot[0] - carrot[0], f.carrot[1] - carrot[1]) > 2 * CELL
                and math.hypot(failed[0]['carrot'][0] - carrot[0], failed[0]['carrot'][1] - carrot[1]) <= 2 * CELL):
            return {'why': failed[1]}
        if f is None or not f.inside(j, i):
            return {'why': failed[1] if failed is not None and failed[0]['zone'] == zone else 'planning'}
        cells, length = f.walk(pos)
        if cells is None:
            return {'why': length}
        pts = [(pos[0], pos[1])] + [f.world(*c) for c in cells[1:]]
        aim = None
        j0, i0 = f.cell(pos)
        for look, mask, margin in ((LOOK_FAR, f.see_blocked, CLEAR_SEE), (LOOK_NEAR, f.blocked, CLEAR)):
            skip = margin if mask[j0, i0] else 0.0
            run = 0.0
            for k in range(1, len(pts)):
                run += math.hypot(pts[k][0] - pts[k - 1][0], pts[k][1] - pts[k - 1][1])
                if run > look:
                    break
                if f.seen(pts[0], pts[k], mask, skip):
                    aim = pts[k]
            if aim is not None and math.hypot(aim[0] - pos[0], aim[1] - pos[1]) >= 40:
                break
        if aim is None:
            aim = pts[min(3, len(pts) - 1)]
        # (the last stretch: straight at the goal itself, not the free square beside it)
        if len(pts) <= 2 and math.hypot(carrot[0] - pos[0], carrot[1] - pos[1]) < 2 * CELL:
            aim = carrot
        left = length + math.hypot(carrot[0] - pts[-1][0], carrot[1] - pts[-1][1]) + rest
        step = max(1, len(pts) // 60)
        route = pts[::step] + ([pts[-1]] if (len(pts) - 1) % step else [])
        self.last = (time.time(), zone, route, aim)
        return {'aim': aim, 'left': left, 'route': route, 'why': ''}
