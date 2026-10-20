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

Mobs (the game's memory: navmem's mobs, those the caller wants avoided - not the ones the quest is about)
  * Each square within MOB_NEAR of a mob (on the wizard's storey) costs MOB_COST more, and up to MOB_SOFT away
    less and less more: the route goes round them where there's room. Not a wall: with no other way it's still
    a route. The field is worked out again when a mob near it has moved MOB_MOVED, or turned MOB_TURNED (at most
    every MOB_REPLAN s).
  * A mob notices you in a cone in front of it too (its sight): the squares in a cone cone[0] degrees wide and
    cone[1] long in front of it (its facing off the game's memory - none known, no cone) cost MOB_COST more as well,
    a little wider and longer less and less more - behind a wall from it too (whether a mob sees through walls isn't
    known; the collision grid has fences, posts and the like): the route keeps out of it where there's room.
  * The route on (MOB_AHEAD of it) still coming nearer a mob (on the wizard's storey) than the wizard is now, to
    within MOB_NEAR, or into its cone (the wizard not in it now; not where a wall hides him from it - no wait for
    that): the answer says so ('mob': the seconds it's waited, 'mob_at', 'mob_name') - the walker stands still till
    it moves off. A mob behind the wizard, or whose ring the route leads out of, doesn't count. One wait
    however the mobs take turns blocking: after MOB_GIVEUP s those mobs aren't avoided for MOB_IGNORE s (walked
    past - one may come for the wizard) - only their cone, when only their cone was in the way (their ring kept).

Teleports
  * The zone's nav graph has links that aren't walked: a trolley, a portal, a hole down to the sewers - a link
    far longer than walking ones (JUMP_LEN), or between heights far apart and steeper than stairs (JUMP_DZ,
    JUMP_SLOPE) - unless the zone's map has floor all along it, with no ledge (and, a long one, nothing solid on
    the way): a long straight corridor is walked. The game's quest path takes
    them, even one this character can't use (locked till a quest's done) - and even one the wrong way: the
    zone's nav graph has most teleports one way only (a way out of the sewers isn't a way in), the game's quest
    helper doesn't mind which way a link goes. One taken the wrong way is routed round straight away (by the
    nav graph's links, which way they go). The carrot never goes past one: it
    stops at the link's start, and while the wizard is right there (JUMP_NEAR) the answer says so ('jump': the
    seconds it's waited) - the walker walks on into it, X at its prompt. If it hasn't taken the wizard after
    JUMP_GIVEUP seconds there, it's given up (BLOCK_FOR) and the route goes by the zone's nav graph round it -
    another teleport, or a way walked; with none, no route ('locked') and the walker says so.
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
JUMP_LEN = 2500.0       # a nav link longer than this, or between heights more than JUMP_DZ apart and steeper than
JUMP_DZ = 400.0         # JUMP_SLOPE (up / across - stairs are at most ~0.65): a teleport - unless the zone's map has
                        # floor all along it (and, a long one, nothing solid on the way): walked
JUMP_SLOPE = 0.7
JUMP_NEAR = 160.0       # the wizard this near a teleport's start (or at the free spot nearest it): waiting for it
JUMP_RINGS = 30         # ...that free spot looked for this many squares round it (its start can be inside its object)
JUMP_GIVEUP = 15.0      # ...given up after this many seconds there (counted only while it's asked about)
BLOCK_FOR = 1800.0      # ...for this long (it may open once a quest is done)
JUMP_COST = 500.0       # a teleport's cost when routing round one on the nav graph
MOB_NEAR = 300.0        # a mob avoided: the wizard kept at least this far from it (they come for it nearer)
MOB_SOFT = 520.0        # ...and dearer up to this far
MOB_COST = 40.0         # extra cost of a square within MOB_NEAR (not a wall: with no other way, it's walked past)
MOB_SOFT_COST = 4.0     # ...right outside it, fading to nothing at MOB_SOFT
MOB_MOVED = 60.0        # a mob near the field this far from where the field has it: a new field...
MOB_TURNED = 0.35       # ...or turned this far (radians, 20 degrees: its cone swung round)
MOB_CONE = (60.0, 600.0)   # its sight: a cone this wide (degrees) and long (game units) in front of it
MOB_REPLAN = 0.7        # ...at most this often (s)
MOB_AHEAD = 900.0       # the route this far on passing within MOB_NEAR of a mob: wait for it to move off...
MOB_GIVEUP = 25.0       # ...for this long at most (s); then it isn't avoided...
MOB_IGNORE = 60.0       # ...for this long (s)

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
        # the zone's nav graph (navgraph), which nodes have links and their connected parts, teleports checked
        self.nav, self._adj, self._linked, self._part, self._jcache = None, None, None, None, {}
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
        # the zone's nav graph, for routing round a teleport that doesn't work (navgraph)
        self.nav = d.get('nav')

    def navgraph(self):
        """(positions (N, 3), adjacency [[(b, cost, jump), ...] per node]) of the zone's nav graph - its links one
        way each, as stored - or None"""
        if self.nav is None or not len(self.nav['positions']):
            return None
        if self._adj is None:
            P, idx = self.nav['positions'], self.nav['index_of']
            adj = [[] for _ in range(len(P))]
            for a_id, b_id in self.nav['links'].tolist():
                a, b = idx.get(int(a_id)), idx.get(int(b_id))
                if a is None or b is None or a == b:
                    continue
                j = self.is_jump(P[a], P[b])
                cost = JUMP_COST if j else float(np.linalg.norm(P[a] - P[b]))
                adj[a].append((b, cost, j))
            # (nodes with links, and the connected part each is in - links either way - for nav_path's ends)
            linked = np.zeros(len(P), bool)
            und = [[] for _ in range(len(P))]
            for a in range(len(P)):
                for b, _, _ in adj[a]:
                    linked[a] = linked[b] = True
                    und[a].append(b), und[b].append(a)
            part = np.full(len(P), -1)
            for s in range(len(P)):
                if part[s] >= 0 or not linked[s]:
                    continue
                part[s], todo = s, [s]
                while todo:
                    u = todo.pop()
                    for v in und[u]:
                        if part[v] < 0:
                            part[v] = s
                            todo.append(v)
            self._adj, self._linked, self._part = adj, linked, part
        return self.nav['positions'], self._adj

    def is_jump(self, a, b):
        """is_jump - but only when its floor can't be walked: a square along it with no floor, or a step of more than
        STEP_EDGE from one to the next (a steep slope is walked: Empyrea's Aeroplains, MooShu's waterfall cave); a
        long link also when something solid is on the way (a long straight corridor is walked: Krokotopia's Pyramid
        - a trolley's or a portal's crosses walls or gaps). Kept per node pair"""
        if not is_jump(a, b):
            return False
        h = math.hypot(a[0] - b[0], a[1] - b[1])
        long_link = h > JUMP_LEN
        key = tuple(round(float(c)) for c in (a[0], a[1], a[2], b[0], b[1], b[2]))
        if key in self._jcache:
            return self._jcache[key]
        x0, y0 = min(a[0], b[0]) - 2 * CELL, min(a[1], b[1]) - 2 * CELL
        nx = int(math.ceil((abs(a[0] - b[0]) + 4 * CELL) / CELL))
        ny = int(math.ceil((abs(a[1] - b[1]) + 4 * CELL) / CELL))
        jump = True
        try:
            ground, H, solid = self.grids(x0, y0, nx, ny, [tuple(map(float, a)), tuple(map(float, b))])
            jump, prev = False, None
            for t in np.linspace(0.0, 1.0, max(2, int(h / (CELL / 2))) + 1):
                x, y = a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])
                j, i = min(ny - 1, int((y - y0) // CELL)), min(nx - 1, int((x - x0) // CELL))
                if (ground[j, i] == 0 or (prev is not None and abs(H[j, i] - prev) > STEP_EDGE)
                        or (long_link and solid[j, i])):
                    jump = True
                    break
                prev = H[j, i]
        except Exception:  # noqa: BLE001 - can't tell: a teleport, as the plain rule says
            jump = True
        self._jcache[key] = jump
        return jump

    def node_at(self, p, near=12.0):
        """the nav node at p (a point of the game's path: its nodes), or None"""
        g = self.navgraph()
        if g is None:
            return None
        P = g[0]
        d = np.hypot(P[:, 0] - p[0], P[:, 1] - p[1])
        k = int(np.argmin(d))
        return k if d[k] <= near and abs(P[k, 2] - p[2]) <= 60 else None

    def start_node(self, pos):
        """the nav node a route on the zone's nav graph starts from: the one with links nearest pos, on its storey
        if there's one - or None"""
        g = self.navgraph()
        if g is None:
            return None
        P = g[0]
        d = np.hypot(P[:, 0] - pos[0], P[:, 1] - pos[1])
        same = np.abs(P[:, 2] - pos[2]) <= FLOOR_BAND
        s = int(np.argmin(np.where(same & self._linked, d, np.where(self._linked, d + 1e9, np.inf))))
        return s if self._linked[s] else None

    def nav_path(self, pos, goal, blocked):
        """[(x, y, z), ...] along the zone's nav graph from the node nearest pos (on its storey) to the one nearest
        goal, not taking the links in blocked ({(a, b)} node pairs) - or None when there's no way"""
        g = self.navgraph()
        if g is None:
            return None
        P, adj = g
        # (its ends: nodes with links - a zone has a few on their own - the goal's in the wizard's connected part)
        s = self.start_node(pos)
        if s is None:
            return None
        dg = np.hypot(np.hypot(P[:, 0] - goal[0], P[:, 1] - goal[1]), P[:, 2] - goal[2])
        t = int(np.argmin(np.where(self._part == self._part[s], dg, np.inf)))
        import heapq
        best, prev, todo = {s: 0.0}, {}, [(0.0, s)]
        while todo:
            c, u = heapq.heappop(todo)
            if u == t:
                break
            if c > best.get(u, 1e18):
                continue
            for v, w, j in adj[u]:
                if (u, v) in blocked:
                    continue
                if c + w < best.get(v, 1e18):
                    best[v], prev[v] = c + w, u
                    heapq.heappush(todo, (c + w, v))
        if t not in best:
            return None
        out = [t]
        while out[-1] != s:
            out.append(prev[out[-1]])
        return [tuple(float(c) for c in P[k]) for k in reversed(out)]

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


def is_jump(a, b):
    """a link between nav nodes a and b ((x, y, z)) that isn't walked: a teleport (see Teleports at the top)"""
    h, dz = math.hypot(a[0] - b[0], a[1] - b[1]), abs(a[2] - b[2])
    return h > JUMP_LEN or (dz > JUMP_DZ and dz > JUMP_SLOPE * h)


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

    def __init__(self, geo, pos, carrot, goal, rest, via=(), carrot_z=None, carrot_goal=True, rings=GOAL_RINGS,
                 mobs=(), mob_near=MOB_NEAR, cone=MOB_CONE):
        t0 = time.perf_counter()
        self.zone, self.z, self.carrot, self.goal, self.rest = geo.zone, pos[2], carrot, goal, rest
        self.why, self.D = '', None
        self.mobs, self.mob_near, self.mob_mask, self.cone = (), mob_near, None, cone
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
        self.wall = np.asarray(solid, dtype=bool)      # (what a mob can't see through)
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
        # the mobs avoided: dearer near them (on this storey; within the window or near enough to reach into it)
        soft = max(MOB_SOFT, mob_near + 2 * CELL)
        x1, y1 = self.x0 + self.nx * CELL, self.y0 + self.ny * CELL
        sight = cone[1] if cone and cone[0] > 0 else 0.0
        reach = max(soft, sight + 2 * CELL)
        kept = tuple((m[0], m[1], m[2], m[3] if len(m) > 3 else None) for m in mobs
                     if self.x0 - reach <= m[0] <= x1 + reach and self.y0 - reach <= m[1] <= y1 + reach
                     and abs(m[2] - pos[2]) <= FLOOR_BAND)
        self.mobs, self.mob_mask, self.cone = kept, np.zeros((self.ny, self.nx), dtype=bool), cone
        if kept:
            cx = self.x0 + (np.arange(self.nx) + 0.5) * CELL
            cy = self.y0 + (np.arange(self.ny) + 0.5) * CELL
            for mx, my, _, myaw in kept:
                dx, dy = cx[None, :] - mx, cy[:, None] - my
                d = np.hypot(dx, dy)
                inner = d <= mob_near
                cost = cost + np.where(inner, MOB_COST, np.where(d <= soft, MOB_SOFT_COST * (soft - d) / (soft - mob_near), 0.0))
                # (its sight: the cone in front of it; a little wider and longer, dearer less and less)
                if sight > 0 and myaw is not None:
                    fx, fy = -math.sin(myaw), -math.cos(myaw)
                    along = dx * fx + dy * fy
                    ang = np.degrees(np.arccos(np.clip(along / np.maximum(d, 1e-6), -1.0, 1.0)))
                    half = cone[0] / 2
                    seen = (ang <= half) & (d <= sight)
                    edge = (~seen) & (ang <= half + 15) & (d <= sight + 150)
                    cost = cost + np.where(seen, MOB_COST, np.where(edge, MOB_SOFT_COST, 0.0))
                    inner = inner | seen
                self.mob_mask |= inner
        cost[self.blocked] = np.inf
        self.cost, self.ground, self.H = cost, ground, H
        g = self._free_near(*self.cell(carrot), rings)
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

    def _sees(self, mx, my, jj, ii):
        """which of the squares (rows jj, columns ii) a mob at mx, my can see: no wall square on the straight line
        between (the first 1.5 squares from it and the last one left out: it stands by a wall, the square is by
        one); outside the window counts as open. In batches: a long, wide cone is many squares"""
        out = np.ones(len(jj), dtype=bool)
        for s in range(0, len(jj), 3000):
            j, i = jj[s:s + 3000], ii[s:s + 3000]
            tx, ty = self.x0 + (i + 0.5) * CELL, self.y0 + (j + 0.5) * CELL
            L = np.hypot(tx - mx, ty - my)
            n = int(L.max() / (CELL * 0.5)) + 2 if len(L) else 2
            t = np.linspace(0.0, 1.0, n)[None, :]
            along = L[:, None] * t
            sj = np.floor((my + (ty[:, None] - my) * t - self.y0) / CELL).astype(np.int32)
            si = np.floor((mx + (tx[:, None] - mx) * t - self.x0) / CELL).astype(np.int32)
            use = ((sj >= 0) & (sj < self.ny) & (si >= 0) & (si < self.nx)
                   & (along >= CELL * 1.5) & (along <= L[:, None] - CELL))
            hit = np.zeros(sj.shape, dtype=bool)
            hit[use] = self.wall[sj[use], si[use]]
            out[s:s + 3000] = ~hit.any(axis=1)
        return out

    def sees(self, m, p):
        """mob m (its 'pos') can see world point p: no wall between, as _sees"""
        j, i = self.cell(p)
        if not (0 <= j < self.ny and 0 <= i < self.nx):
            return True
        return bool(self._sees(m['pos'][0], m['pos'][1], np.array([j]), np.array([i]))[0])

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
        self.blocked = {}                    # teleports given up: (zone, node a, node b) -> when
        self.wrong_way = set()               # teleports the game's path took the wrong way (logged once each)
        self._round = None                   # the last _path_round: (key, answer)
        self.jwait = None                    # waiting at one: {'key', 'waited', 'last'}
        self.mwait = None                    # waiting for mobs to move off the way: {'waited', 'last', 'gids'}
        self.mob_ignored = {}                # mobs waited for too long: gid -> when (not avoided for MOB_IGNORE)
        self.pose_stale = None               # the field a mob on the way isn't where (or facing as) it has it: a new one

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
                    f = Field(geo, job['pos'], job['carrot'], job['goal'], job['rest'], job['via'], job['carrot_z'], job['carrot_goal'],
                              job.get('rings', GOAL_RINGS), job.get('mobs', ()), job.get('mob_near', MOB_NEAR),
                              job.get('cone', MOB_CONE))
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
    def carrot(pos, path, goal, keep=None, jumps=is_jump):
        """(carrot (x, y), its height, is it the goal, the game's path on from it to the goal, the path's points
        up to it, the teleport it's the start of ((x, y, z) its start, (x, y, z) its end) or None) - the farthest
        point of [path..., goal] within REACH of pos, from the one nearest pos on, and not past a teleport on the
        path (is_jump); carrot None when none is that near"""
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
            return None, None, True, 0.0, [], None
        # (not past a teleport: the first on the path from the nearest node on - its start is the carrot)
        jump = None
        for k in range(k0, min(best, len(G) - 2) + 1):
            if k + 1 < len(G) - 1 and jumps(G[k], G[k + 1]):
                best, jump = k, (G[k], G[k + 1])
                break
        rest = sum(math.hypot(G[k + 1][0] - G[k][0], G[k + 1][1] - G[k][1]) for k in range(best, len(G) - 1))
        # (the goal's own height is real; a path node's is moved like the rest - see Field)
        return (G[best][0], G[best][1]), G[best][2], best == len(G) - 1, rest, G[k0:best], jump

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

    def _blocked_now(self, zone):
        """the teleports given up in zone, still given up: {(a, b)} node pairs"""
        now = time.time()
        for k in [k for k, at in self.blocked.items() if now - at > BLOCK_FOR]:
            del self.blocked[k]
        return {(k[1], k[2]) for k in self.blocked if k[0] == zone}

    def _path_round(self, zone, pos, path, goal):
        """(path, why): the game's path - or, when it takes a teleport given up (_blocked_now) or one the wrong way
        (the zone's nav graph has that link only the other way), one round it on the zone's nav graph; path None
        (why says) when there's no way round"""
        if path is None:
            path = []                                   # (the game's path not read: as before, the goal itself)
        geo = self.zones.get(zone)
        if geo is None or not path or geo.navgraph() is None:
            return path, ''
        blocked = self._blocked_now(zone)
        # (a route round starts from the nav node nearest the wizard: worked out again when that changes)
        key = (zone, tuple(map(tuple, path)), tuple(goal), frozenset(blocked), geo.start_node(pos))
        if self._round is not None and self._round[0] == key:
            return self._round[1]
        adj = geo.navgraph()[1]
        bad = False
        for p, q in zip(path, path[1:]):
            if not geo.is_jump(p, q):
                continue
            a, b = geo.node_at(p), geo.node_at(q)
            if a is None or b is None:
                continue
            if (a, b) in blocked:
                bad = True
            elif not any(v == b for v, _, _ in adj[a]):
                bad = True
                if (zone, a, b) not in self.wrong_way:
                    self.wrong_way.add((zone, a, b))
                    self.log(f"route: the game's path takes the teleport at {p[0]:.0f}, {p[1]:.0f} the wrong way (the zone's "
                             f'paths have it only from {q[0]:.0f}, {q[1]:.0f}) - routing round it')
        if not bad:
            answer = (path, '')
        else:
            alt = geo.nav_path(pos, goal, blocked)
            answer = (alt, '') if alt is not None else (
                None, "the way on is a teleport that doesn't take the wizard (locked, or only the other way) - no other way on the zone's paths")
        self._round = (key, answer)
        return answer

    @staticmethod
    def _by_nodes(pos, path, goal, jumps=is_jump):
        """(aim, left): straight along the zone's nav graph (its links are walked) - the node of [path..., goal] on
        from the one nearest pos, the next once it's passed or right at it, not across a teleport"""
        G = [tuple(p) for p in path] + [tuple(goal)]
        same = [k for k in range(len(G)) if abs(G[k][2] - pos[2]) <= FLOOR_BAND] or range(len(G))
        k = min(same, key=lambda q: math.hypot(G[q][0] - pos[0], G[q][1] - pos[1]))
        if k + 1 < len(G) and not (k + 1 < len(G) - 1 and jumps(G[k], G[k + 1])):
            seg = math.hypot(G[k + 1][0] - G[k][0], G[k + 1][1] - G[k][1])
            if (math.hypot(G[k][0] - pos[0], G[k][1] - pos[1]) < 80
                    or math.hypot(G[k + 1][0] - pos[0], G[k + 1][1] - pos[1]) < seg):
                k += 1
        left = math.hypot(G[k][0] - pos[0], G[k][1] - pos[1]) + sum(
            math.hypot(G[q + 1][0] - G[q][0], G[q + 1][1] - G[q][1]) for q in range(k, len(G) - 1))
        return (G[k][0], G[k][1]), left

    @staticmethod
    def _mobs_moved(f, mobs):
        """the mobs near f's window aren't where f has them (moved MOB_MOVED or turned MOB_TURNED, come or gone)"""
        if f is None:
            return False
        cone = getattr(f, 'cone', None)
        sight = cone[1] if cone and cone[0] > 0 else 0.0
        reach = max(MOB_SOFT, f.mob_near + 2 * CELL, sight + 2 * CELL)
        x1, y1 = f.x0 + f.nx * CELL, f.y0 + f.ny * CELL
        now = [m for m in mobs if f.x0 - reach <= m[0] <= x1 + reach and f.y0 - reach <= m[1] <= y1 + reach
               and abs(m[2] - f.z) <= FLOOR_BAND]
        if len(now) != len(f.mobs):
            return True
        for m in now:
            q = min(f.mobs, key=lambda q: math.hypot(m[0] - q[0], m[1] - q[1]), default=None)
            if q is None or math.hypot(m[0] - q[0], m[1] - q[1]) > MOB_MOVED:
                return True
            yaw_now, yaw_then = (m[3] if len(m) > 3 else None), q[3]
            if sight > 0 and yaw_now is not None and yaw_then is not None:
                if abs((yaw_now - yaw_then + math.pi) % (2 * math.pi) - math.pi) > MOB_TURNED:
                    return True
        return False

    def route(self, r, wait=True, mobs=None, mob_near=MOB_NEAR, cone=MOB_CONE):
        """the answer (see the top); wait: count the time at a teleport or a mob (the walker's asks - not the
        map's); mobs: [{'pos': (x, y, z), 'yaw', 'gid', 'name'}] to keep away from - mob_near round each, and out of
        a cone (degrees wide, long) in front of it"""
        if r is None or r.get('pos') is None or r.get('goal') is None or not r.get('zone'):
            return {'why': 'no position or goal'}
        pos, goal, zone = tuple(r['pos']), tuple(r['goal']), r['zone']
        now = time.time()
        for gid in [g for g, v in list(self.mob_ignored.items()) if now - v[0] > MOB_IGNORE]:
            self.mob_ignored.pop(gid, None)      # (the map's asks run alongside the walker's)
        # (given up: a ring wait drops the mob; a cone wait only its cone - no facing, its ring still kept)
        mobs = [m if m.get('gid') not in self.mob_ignored else dict(m, yaw=None) for m in (mobs or ())
                if self.mob_ignored.get(m.get('gid'), (0.0, 'cone'))[1] != 'ring']
        mob_pts = [tuple(m['pos'][:3]) + (m.get('yaw'),) for m in mobs]
        # (the wait at a teleport is one visit's: forgotten once the wizard's well away from it, or elsewhere)
        w = self.jwait
        if w is not None and (w['key'][0] != zone or math.hypot(w['key'][1][0] - pos[0], w['key'][1][1] - pos[1]) > 1200
                              or abs(w['key'][1][2] - pos[2]) > FLOOR_BAND):
            self.jwait = None
        geo0 = self.zones.get(zone)
        jumps = geo0.is_jump if geo0 is not None else is_jump
        f = self.field
        if f is not None and (f.zone != zone or math.hypot(f.goal[0] - goal[0], f.goal[1] - goal[1]) > 60):
            f = None                                              # (another zone, or a new goal)
        path, why = self._path_round(zone, pos, r.get('path'), goal)
        if path is None:
            self.jwait = None
            return {'why': why, 'locked': True}
        game = [tuple(q) for q in (r.get('path') or ())]
        rerouted = [tuple(q) for q in path] != game
        carrot, cz, cgoal, rest, via, jump = self.carrot(pos, path, goal, f.carrot if f is not None else None, jumps)

        def fail(why):
            """no route round walls: the walker steers at the arrow - unless the game's path was routed round (a
            teleport given up, or taken the wrong way): the arrow leads there, so straight along the nav graph"""
            if not rerouted:
                return {'why': why}
            aim, left = self._by_nodes(pos, path, goal, jumps)
            out = {'aim': aim, 'left': left, 'route': [(pos[0], pos[1]), aim], 'why': '', 'bynodes': why}
            if waited is not None:
                out['jump'], out['jump_at'] = waited, (jump[0][0], jump[0][1])
            return out
        # (right at a teleport on the path: how long it's waited there - counted only while it's asked about, so
        # a battle meanwhile isn't waiting - and given up after JUMP_GIVEUP: routed round it)
        waited = None
        # (at it: near its start - or at the free spot nearest it, when its start is inside its object)
        at_spot = (jump is not None and f is not None and getattr(f, 'gcell', None) is not None
                   and math.hypot(f.carrot[0] - jump[0][0], f.carrot[1] - jump[0][1]) <= 2 * CELL
                   and math.hypot(f.world(*f.gcell)[0] - pos[0], f.world(*f.gcell)[1] - pos[1]) <= 2 * CELL + 40)
        if wait and jump is not None and (math.hypot(jump[0][0] - pos[0], jump[0][1] - pos[1]) <= JUMP_NEAR or at_spot):
            now, key = time.time(), (zone, jump[0], jump[1])
            w = self.jwait
            if w is None or w['key'] != key:
                w = self.jwait = {'key': key, 'waited': 0.0, 'last': now}
            elif now - w['last'] < 2.0:
                w['waited'] += now - w['last']
            w['last'] = now
            waited = w['waited']
            if waited > JUMP_GIVEUP:
                geo = self.zones.get(zone)
                a = geo.node_at(jump[0]) if geo is not None else None
                b = geo.node_at(jump[1]) if geo is not None else None
                self.jwait, waited = None, None
                if a is not None and b is not None:
                    self.blocked[(zone, a, b)] = time.time()
                    self.log(f'route: the teleport at {jump[0][0]:.0f}, {jump[0][1]:.0f} (to {jump[1][0]:.0f}, {jump[1][1]:.0f}) '
                             f"hasn't taken the wizard in {JUMP_GIVEUP:.0f} s (locked?) - routing round it for {BLOCK_FOR / 60:.0f} minutes")
                    path, why = self._path_round(zone, pos, r.get('path'), goal)
                    if path is None:
                        return {'why': why, 'locked': True}
                    rerouted = [tuple(q) for q in path] != game
                    carrot, cz, cgoal, rest, via, jump = self.carrot(pos, path, goal, None, jumps)
        if carrot is None:
            return fail("the game's path is out of reach")
        j, i = f.cell(pos) if f is not None else (0, 0)
        mobs_moved = self._mobs_moved(f, mob_pts)
        stale = (f is None or not f.inside(j, i, EDGE_CELLS) or abs(pos[2] - f.z) > REPLAN_Z
                 or math.hypot(f.carrot[0] - carrot[0], f.carrot[1] - carrot[1]) > 2 * CELL
                 or (mobs_moved and time.time() - f.made >= MOB_REPLAN)
                 # (how far to keep from the mobs changed - the settings: a new field, while there are mobs to keep from)
                 or (bool(mob_pts) and (f.mob_near != mob_near or tuple(getattr(f, 'cone', None) or ()) != tuple(cone or ())))
                 # (the mob on the way turned or stepped a little since the field: its cone or ring isn't there)
                 or (self.pose_stale is not None and self.pose_stale is f and time.time() - f.made >= MOB_REPLAN))
        failed = self.failed
        if stale and not self.busy and self.want is None:
            same_fail = (failed is not None and failed[0]['zone'] == zone
                         and math.hypot(failed[0]['carrot'][0] - carrot[0], failed[0]['carrot'][1] - carrot[1]) <= 2 * CELL
                         and math.hypot(failed[0]['pos'][0] - pos[0], failed[0]['pos'][1] - pos[1]) <= 4 * CELL
                         and abs(failed[0]['pos'][2] - pos[2]) <= REPLAN_Z and time.time() - failed[0]['at'] < 5)
            if not same_fail:
                self._ask({'zone': zone, 'pos': pos, 'carrot': carrot, 'carrot_z': cz, 'carrot_goal': cgoal, 'goal': goal,
                           'rest': rest, 'via': via, 'at': time.time(), 'rings': JUMP_RINGS if jump is not None else GOAL_RINGS,
                           'mobs': mob_pts, 'mob_near': mob_near, 'cone': cone})
                self.pose_stale = None
        # (the last job, for the carrot as it is now, found no plan: the old field leads only to the old carrot -
        # walked to it, it would hold the wizard there. No aim: the walker steers at the arrow meanwhile)
        if (f is not None and failed is not None and failed[0]['zone'] == zone
                and math.hypot(f.carrot[0] - carrot[0], f.carrot[1] - carrot[1]) > 2 * CELL
                and math.hypot(failed[0]['carrot'][0] - carrot[0], failed[0]['carrot'][1] - carrot[1]) <= 2 * CELL):
            return fail(failed[1])
        if f is None or not f.inside(j, i):
            return fail(failed[1] if failed is not None and failed[0]['zone'] == zone else 'planning')
        cells, length = f.walk(pos)
        if cells is None:
            return fail(length)
        pts = [(pos[0], pos[1])] + [f.world(*c) for c in cells[1:]]
        aim = None
        j0, i0 = f.cell(pos)
        # (the aim isn't looked for across a mob's ring either - unless the wizard's in one: then out along the route)
        mm = f.mob_mask if f.mob_mask is not None and f.mob_mask.any() and not f.mob_mask[j0, i0] else None
        for look, mask, margin in ((LOOK_FAR, f.see_blocked if mm is None else f.see_blocked | mm, CLEAR_SEE),
                                   (LOOK_NEAR, f.blocked if mm is None else f.blocked | mm, CLEAR)):
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
        out = {'aim': aim, 'left': left, 'route': route, 'why': ''}
        if waited is not None:
            out['jump'], out['jump_at'] = waited, (jump[0][0], jump[0][1])
        # a mob on the way the route can't go round: wait for it to move off - one wait however mobs take turns being
        # the one in the way (asks less than 2 s apart), given up as a whole after MOB_GIVEUP. (Not cleared while a
        # new field is being worked out for mobs that moved: only a field that knows where they are clears it)
        blocker = self._mob_on_way(pts, mobs, mob_near, pos[2], cone, f) if mobs else None
        # (the field doesn't have it where it is now, or facing as it is: a new field - the way round it may be
        # clear - before a long wait on this one)
        if blocker is not None and not self._pose_known(f, blocker, cone):
            self.pose_stale = f
        if wait:
            w = self.mwait
            if blocker is None:
                if not mobs_moved:
                    self.mwait = None
            else:
                if w is None or now - w['last'] >= 2.0:
                    w = self.mwait = {'waited': 0.0, 'last': now, 'gids': {}}
                else:
                    w['waited'] += now - w['last']
                w['last'] = now
                # (what of it was in the way: its ring, or only its cone - the ring counts once it has been)
                gid = blocker.get('gid')
                w['gids'][gid] = 'ring' if blocker.get('block') == 'ring' or w['gids'].get(gid) == 'ring' else 'cone'
                if w['waited'] > MOB_GIVEUP:
                    for g, kind in w['gids'].items():
                        self.mob_ignored[g] = (now, kind)
                    self.mwait = None
                    if w['gids'][gid] == 'cone':
                        self.log(f"route: {blocker.get('name') or 'a mob'} has faced the way for {MOB_GIVEUP:.0f} s - walking on "
                                 f"through its sight (still keeping {mob_near:.0f} from it)")
                    else:
                        self.log(f"route: {blocker.get('name') or 'a mob'} has stood on the way for {MOB_GIVEUP:.0f} s - walking on past it")
                else:
                    out['mob'], out['mob_at'], out['mob_name'] = w['waited'], tuple(blocker['pos'][:2]), blocker.get('name') or ''
        return out

    @staticmethod
    def _in_cone(m, p, cone, shrink=1.0):
        """p is in mob m's sight: the cone (degrees wide, long) in front of it, shrunk by shrink"""
        if not cone or cone[0] <= 0 or m.get('yaw') is None:
            return False
        dx, dy = p[0] - m['pos'][0], p[1] - m['pos'][1]
        d = math.hypot(dx, dy)
        if d < 1e-6 or d > cone[1] * shrink:
            return d < 1e-6
        fx, fy = -math.sin(m['yaw']), -math.cos(m['yaw'])
        return math.degrees(math.acos(max(-1.0, min(1.0, (dx * fx + dy * fy) / d)))) <= cone[0] / 2 * shrink

    @staticmethod
    def _pose_known(f, m, cone):
        """the field f has mob m where it is now (within a square) and facing as it does now (to a tenth of the
        cone's half - the slack _mob_on_way's shrunk cone leaves)"""
        if f is None or not f.mobs:
            return False
        q = min(f.mobs, key=lambda q: math.hypot(m['pos'][0] - q[0], m['pos'][1] - q[1]))
        if math.hypot(m['pos'][0] - q[0], m['pos'][1] - q[1]) > CELL:
            return False
        if cone and cone[0] > 0 and m.get('yaw') is not None and q[3] is not None:
            tol = max(math.radians(1.0), math.radians(cone[0] / 2 * 0.1))
            if abs((m['yaw'] - q[3] + math.pi) % (2 * math.pi) - math.pi) > tol:
                return False
        return True

    @staticmethod
    def _mob_on_way(pts, mobs, mob_near, z, cone=None, f=None):
        """the first mob along the route's first MOB_AHEAD that it comes within 0.85 mob_near of - and nearer than
        the wizard is to it now (not one behind, nor one whose ring it leads out of) - or into whose sight cone it
        walks (the wizard not in it now; a wall between - field f's - hides him), on the wizard's storey; or None.
        The mob comes back as a copy with 'block': 'ring' or 'cone' (what of it is in the way)"""
        near = mob_near * 0.85

        def spots(m, p):
            return Planner._in_cone(m, p, cone, 0.85) and (f is None or f.sees(m, p))
        here = [(m, math.hypot(m['pos'][0] - pts[0][0], m['pos'][1] - pts[0][1]), spots(m, pts[0]))
                for m in mobs if abs(m['pos'][2] - z) <= FLOOR_BAND]
        run, prev = 0.0, pts[0]
        for q in pts[1:]:
            run += math.hypot(q[0] - prev[0], q[1] - prev[1])
            prev = q
            if run > MOB_AHEAD:
                break
            for m, d0, seen0 in here:
                d = math.hypot(m['pos'][0] - q[0], m['pos'][1] - q[1])
                if d <= near and d < d0 - CELL:
                    return dict(m, block='ring')
                if not seen0 and spots(m, q):
                    return dict(m, block='cone')
        return None
