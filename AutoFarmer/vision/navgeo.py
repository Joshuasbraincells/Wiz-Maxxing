"""navgeo - pure-Python decoders for Wizard101 zone navigation graphs (zone.nav)
and binary collision data (collision.bcd), and a read-only reader for the
zone .wad archives that hold them (for the vision helper's /navmap).

    d = load_zone("WizardCity/WC_Ravenwood")     # {'nav': ..., 'bcd': ..., 'reader': ...}

The archives are read with the small KIWAD reader below (zlib only; byte for
byte the same as katsuba's on all 2,359 shipped .wads, and ~20x quicker), and
with katsuba (imported lazily, only if installed) when it can't parse one, so
nothing here needs more than numpy. Game files are only ever opened for reading.

Format layouts follow Katsuba's Rust readers (github.com/vbe0201/katsuba,
src/katsuba-nav/src/lib.rs and src/katsuba-bcd/src/lib.rs). Everything is
little-endian; strings are a u32 byte length followed by that many UTF-8 bytes
(no terminator).

NAV (NavigationGraph):
    u16  header            (discarded by Katsuba; the writer stores max node id,
                            but some shipped files hold the node count instead)
    u32  node_count
    node_count x { f32 x, f32 y, f32 z, u16 id }          14 bytes each
    u32  link_count
    link_count x { u16 first_id, u16 second_id }          4 bytes each
  ZoneNavigationGraph = NavigationGraph followed by
    u32  name_count, name_count x string                  (one name per node id)
  zone.nav files in zone .wads are plain NavigationGraphs (no names follow).
  Links name node IDS, not rows. 44 of 2,012 shipped zone.nav files repeat one
  id on two consecutive rows; links resolve to the first of them (see load_nav).

BCD:
    u32 collision_count
    collision_count x {
        u32 geometry_type      (same code as the GeomParams tag below)
        u32 category_flags     (what this shape IS: OBJECT, WALKABLE, WATER ...)
        u32 collision_flags    (what it collides WITH)
        if geometry_type == 6: ProxyMesh {
            u32 vertex_count, u32 face_count,
            vertex_count x f32[3],
            face_count x { u32[3] vertex indices, f32[3] normal } }
        ProxyGeometry {
            string name, f32[9] rotation (row-major 3x3), f32[3] location,
            f32 scale, string material,
            u32 type code, then params:
                0 Box      f32 length, width, depth
                1 Ray      f32 position, direction, length
                2 Sphere   f32 radius
                3 Cylinder f32 "radius", "length"   (Katsuba's names; see below)
                4 Tube     f32 "radius", "length"
                5 Plane    f32 normal[3], distance
                6 Mesh     (nothing) }
    }

Conventions established from the data (see the validation report, not Katsuba):
  * Z is up. Nav nodes sit on the walkable meshes' surfaces (within ~2 units)
    in almost every zone; a few (e.g. WC_SchoolMyth) have the whole graph
    floating ~550 above the floor, so trust nav X/Y more than nav Z.
  * Nav nodes form an 8-connected grid with a 480-unit pitch (edges 480 and
    679 = 480*sqrt2), plus hand-placed nodes/links. Every link is normally
    stored in both directions; a few one-way links exist.
  * world = R @ local * scale + location, with R built row-major from the 9
    floats exactly as stored (column-vector convention). Verified for meshes
    (walkable meshes only line up with the nav nodes once the location offset
    is added, and on 1,193 rotated walkable meshes R puts 43k nodes on the
    surface vs 24k for R^T) and for boxes (the other variants of R / R^T and
    axis order put many more nav nodes inside boxes).
  * Stored mesh face normals are all zero (1.44M faces checked); compute them.
    (v1-v0) x (v2-v0) points up for 97% of walkable faces.
  * Only box / cylinder / sphere / mesh occur in the shipped game (2,275 zones);
    ray, tube and plane are decoded but untested. collision_flags is always
    0x3443 and scale always 1.0.
  * Box params are FULL side lengths along local x, y, z, centred on location.
  * Cylinder: the SECOND float behaves as the radius and the FIRST as the
    height along local z (first is 500.0 for most cylinders). Katsuba calls
    them (radius, length); with Katsuba's reading ~2-30% of nav nodes would
    stand inside cylinders, with the swapped reading almost none, and the
    clearance of nodes from cylinders then matches their clearance from boxes.
    Both raw values are kept in shape["params"]; shape["radius"]/["height"]
    hold the interpreted values. Tube (code 4) is treated the same way
    (inferred only; tubes are rare).
  * scale is 1.0 in every zone checked; it is applied as a uniform multiplier.
"""

from __future__ import annotations

import math
import os
import struct
import zlib
from typing import Any

import numpy as np

GAME_DIR = r"C:\ProgramData\KingsIsle Entertainment\Wizard101"

# --------------------------------------------------------------------------- #
# NAV
# --------------------------------------------------------------------------- #

_NODE_DT = np.dtype([("pos", "<f4", 3), ("id", "<u2")])  # 14 bytes, packed


def load_nav(data: bytes) -> dict[str, Any]:
    """Decode a zone.nav (NavigationGraph) or zonenav (ZoneNavigationGraph).

    Returns a dict:
      header     int   leading u16 (not meaningful; max id or count)
      ids        (N,)  uint16 node ids, in file order
      positions  (N,3) float32 world positions (x, y, z), z up
      links      (M,2) uint16 directed links as (from_id, to_id), file order
      edges      (K,2) int32  undirected unique edges as node INDICES (i<j)
      index_of   dict  node id -> row index into ids/positions
      duplicate_rows list[int]  rows whose id repeats an earlier row (orphans)
      truncated  bool  file ended inside the link table (whole links kept)
      zone_names list[str] | None  (only for ZoneNavigationGraph files)
    """
    mv = memoryview(data)
    if len(data) < 6:
        raise ValueError("nav: file too short")
    header, n = struct.unpack_from("<HI", data, 0)
    off = 6
    end = off + n * _NODE_DT.itemsize
    if end + 4 > len(data):
        raise ValueError(f"nav: node table ({n} nodes) runs past end of file")
    nodes = np.frombuffer(mv[off:end], dtype=_NODE_DT, count=n)
    off = end
    (m,) = struct.unpack_from("<I", data, off)
    off += 4
    end = off + m * 4
    truncated = end > len(data)
    if truncated:  # seen once in 2,275 zones: file ends mid link table
        m = (len(data) - off) // 4
        end = off + m * 4
    links = np.frombuffer(mv[off:end], dtype="<u2", count=m * 2).reshape(m, 2).copy()
    off = end

    zone_names = None
    if not truncated and off < len(data):  # ZoneNavigationGraph tail
        (k,) = struct.unpack_from("<I", data, off)
        off += 4
        zone_names = []
        for _ in range(k):
            (ln,) = struct.unpack_from("<I", data, off)
            off += 4
            zone_names.append(bytes(mv[off:off + ln]).decode("utf-8", "replace"))
            off += ln
    if not truncated and off != len(data):
        raise ValueError(f"nav: {len(data) - off} unexplained trailing bytes")

    ids = nodes["id"].copy()
    positions = nodes["pos"].astype(np.float32)
    # Links name node ids. ~2% of shipped files repeat one id on two consecutive
    # rows (and every later row's id is one lower than its row number). Links
    # match the FIRST row (checked on all 44 such files by link length), so the
    # second row is an orphan that nothing links to.
    index_of: dict[int, int] = {}
    duplicate_rows = []
    for r, i in enumerate(ids.tolist()):
        if i in index_of:
            duplicate_rows.append(r)
        else:
            index_of[i] = r
    bad = [tuple(l) for l in links.tolist() if l[0] not in index_of or l[1] not in index_of]
    if bad:
        raise ValueError(f"nav: {len(bad)} links reference unknown node ids, e.g. {bad[:3]}")

    if m:
        a = np.fromiter((index_of[int(v)] for v in links[:, 0]), np.int32, m)
        b = np.fromiter((index_of[int(v)] for v in links[:, 1]), np.int32, m)
        e = np.stack([np.minimum(a, b), np.maximum(a, b)], 1)
        e = e[e[:, 0] != e[:, 1]]
        edges = np.unique(e, axis=0) if len(e) else np.zeros((0, 2), np.int32)
    else:
        edges = np.zeros((0, 2), np.int32)

    return {
        "header": int(header),
        "ids": ids,
        "positions": positions,
        "links": links,
        "edges": edges.astype(np.int32),
        "index_of": index_of,
        "duplicate_rows": duplicate_rows,
        "truncated": truncated,
        "zone_names": zone_names,
    }


def nav_adjacency(nav: dict) -> list[list[int]]:
    """Undirected neighbour lists by node index."""
    adj: list[list[int]] = [[] for _ in range(len(nav["ids"]))]
    for a, b in nav["edges"].tolist():
        adj[a].append(b)
        adj[b].append(a)
    return adj


def nav_components(nav: dict) -> list[list[int]]:
    """Connected components (undirected), largest first, as lists of indices."""
    adj = nav_adjacency(nav)
    seen = [False] * len(adj)
    comps = []
    for s in range(len(adj)):
        if seen[s]:
            continue
        stack, comp = [s], []
        seen[s] = True
        while stack:
            u = stack.pop()
            comp.append(u)
            for v in adj[u]:
                if not seen[v]:
                    seen[v] = True
                    stack.append(v)
        comps.append(comp)
    comps.sort(key=len, reverse=True)
    return comps


def nav_edge_lengths(nav: dict, planar: bool = False) -> np.ndarray:
    p = nav["positions"].astype(np.float64)
    d = p[nav["edges"][:, 1]] - p[nav["edges"][:, 0]]
    if planar:
        d = d[:, :2]
    return np.linalg.norm(d, axis=1)


# --------------------------------------------------------------------------- #
# BCD
# --------------------------------------------------------------------------- #

COLLISION_FLAGS = {  # katsuba-bcd CollisionFlags
    "OBJECT": 0x1,
    "WALKABLE": 0x2,
    "HITSCAN": 0x8,
    "LOCAL_PLAYER": 0x10,
    "WATER": 0x40,
    "CLIENT_OBJECT": 0x80,
    "TRIGGER": 0x100,
    "FOG": 0x200,
    "GOO": 0x400,
    "FISH": 0x800,
    "MUCK": 0x1000,
}

GEOM_TYPES = {0: "box", 1: "ray", 2: "sphere", 3: "cylinder", 4: "tube", 5: "plane", 6: "mesh"}
_PARAM_NAMES = {  # Katsuba's field names, in file order
    0: ("length", "width", "depth"),
    1: ("position", "direction", "length"),
    2: ("radius",),
    3: ("radius", "length"),
    4: ("radius", "length"),
    5: ("nx", "ny", "nz", "distance"),
    6: (),
}
_FACE_DT = np.dtype([("idx", "<u4", 3), ("normal", "<f4", 3)])  # 24 bytes


def flag_names(value: int) -> list[str]:
    names = [n for n, b in COLLISION_FLAGS.items() if value & b]
    rest = value & ~sum(COLLISION_FLAGS.values())
    if rest:
        names.append(f"0x{rest:x}")
    return names


class _Reader:
    __slots__ = ("b", "mv", "o")

    def __init__(self, b: bytes):
        self.b, self.mv, self.o = b, memoryview(b), 0

    def u32(self) -> int:
        (v,) = struct.unpack_from("<I", self.b, self.o)
        self.o += 4
        return v

    def f32s(self, n: int) -> tuple:
        v = struct.unpack_from(f"<{n}f", self.b, self.o)
        self.o += 4 * n
        return v

    def string(self) -> str:
        n = self.u32()
        if self.o + n > len(self.b):
            raise ValueError("bcd: string runs past end of file")
        s = bytes(self.mv[self.o:self.o + n]).decode("utf-8", "replace")
        self.o += n
        return s

    def array(self, dtype, count: int) -> np.ndarray:
        dtype = np.dtype(dtype)
        end = self.o + dtype.itemsize * count
        if end > len(self.b):
            raise ValueError("bcd: array runs past end of file")
        a = np.frombuffer(self.mv[self.o:end], dtype=dtype, count=count).copy()
        self.o = end
        return a


def load_bcd(data: bytes, step=None) -> list[dict[str, Any]]:
    """Decode a collision.bcd into a list of shape dicts (step, if given, is
    called before each shape: a caller's thread may wait there - the overlay's
    map in vision.py, while the walker's memory reads go first):

      index, name, material
      type            'box'|'ray'|'sphere'|'cylinder'|'tube'|'plane'|'mesh'
      type_code       int
      category_flags  int, category (list of flag names)  - what the shape is
      collision_flags int, collides (list of flag names)  - what it hits
      rotation (3,3) float64, location (3,) float64, scale float
      params   dict of the raw floats under Katsuba's names
      size     box: (3,) full side lengths along local x,y,z (scaled)
      radius, height   sphere/cylinder/tube (interpreted, scaled; see module doc)
      normal, distance plane
      mesh     {'vertices' (V,3) float32 LOCAL, 'faces' (F,3) int32,
                'normals' (F,3) float32} for meshes, else None
    """
    r = _Reader(data)
    count = r.u32()
    shapes = []
    for i in range(count):
        if step is not None:
            step()
        gtype = r.u32()
        cat = r.u32()
        col = r.u32()
        mesh = None
        if gtype == 6:
            nv = r.u32()
            nf = r.u32()
            verts = r.array("<f4", nv * 3).reshape(nv, 3)
            faces = r.array(_FACE_DT, nf)
            idx = faces["idx"].astype(np.int64)
            if nf and idx.max() >= nv:
                raise ValueError(f"bcd: shape {i} face index out of range")
            mesh = {
                "vertices": verts,
                "faces": idx.astype(np.int32),
                "normals": faces["normal"].astype(np.float32),
            }
        name = r.string()
        rot = np.array(r.f32s(9), dtype=np.float64).reshape(3, 3)
        loc = np.array(r.f32s(3), dtype=np.float64)
        (scale,) = r.f32s(1)
        material = r.string()
        ptype = r.u32()
        if ptype not in _PARAM_NAMES:
            raise ValueError(f"bcd: shape {i} invalid GeomParams type {ptype}")
        if ptype != gtype:
            raise ValueError(f"bcd: shape {i} geometry type {gtype} != params type {ptype}")
        vals = r.f32s(len(_PARAM_NAMES[ptype]))
        params = dict(zip(_PARAM_NAMES[ptype], vals))
        s = {
            "index": i,
            "name": name,
            "material": material,
            "type": GEOM_TYPES[ptype],
            "type_code": ptype,
            "category_flags": cat,
            "category": flag_names(cat),
            "collision_flags": col,
            "collides": flag_names(col),
            "rotation": rot,
            "location": loc,
            "scale": float(scale),
            "params": params,
            "mesh": mesh,
        }
        if ptype == 0:
            s["size"] = np.array(vals, dtype=np.float64) * scale
        elif ptype == 2:
            s["radius"] = vals[0] * scale
        elif ptype in (3, 4):
            # Katsuba: (radius, length). Data says: (height, radius). See module doc.
            s["height"] = vals[0] * scale
            s["radius"] = vals[1] * scale
        elif ptype == 5:
            s["normal"] = np.array(vals[:3], dtype=np.float64)
            s["distance"] = vals[3]
        shapes.append(s)
    if r.o != len(data):
        raise ValueError(f"bcd: {len(data) - r.o} unexplained trailing bytes")
    return shapes


# --------------------------------------------------------------------------- #
# Geometry helpers
# --------------------------------------------------------------------------- #

def to_world(shape: dict, local_pts: np.ndarray) -> np.ndarray:
    """Local -> world: R @ p * scale + location (row vectors: p @ R.T)."""
    p = np.asarray(local_pts, dtype=np.float64)
    return p @ shape["rotation"].T * shape["scale"] + shape["location"]


def to_local(shape: dict, world_pts: np.ndarray) -> np.ndarray:
    p = np.asarray(world_pts, dtype=np.float64) - shape["location"]
    return (p @ shape["rotation"]) / shape["scale"]


def mesh_world(shape: dict) -> tuple[np.ndarray, np.ndarray]:
    """(world vertices (V,3), faces (F,3)) for a mesh shape."""
    m = shape["mesh"]
    return to_world(shape, m["vertices"]), m["faces"]


def box_corners(shape: dict) -> np.ndarray:
    """8 world-space corners of a box (size = full side lengths, already scaled)."""
    h = shape["size"] / 2 / shape["scale"]
    c = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)], float)
    return to_world(shape, c * h)


def footprint(shape: dict, segments: int = 24) -> list[np.ndarray]:
    """Top-down (world XY) outline polygons for a shape, as a list of (k,2) arrays.
    Box -> one quad (convex hull of its 8 corners), sphere/cylinder/tube -> circle,
    mesh -> one triangle per face, ray/plane -> []."""
    t = shape["type"]
    if t == "box":
        return [_hull2d(box_corners(shape)[:, :2])]
    if t in ("sphere", "cylinder", "tube"):
        a = np.linspace(0, 2 * math.pi, segments, endpoint=False)
        c = shape["location"][:2]
        return [np.stack([c[0] + shape["radius"] * np.cos(a), c[1] + shape["radius"] * np.sin(a)], 1)]
    if t == "mesh":
        v, f = mesh_world(shape)
        return list(v[f][:, :, :2])
    return []


def aabb(shape: dict) -> tuple[np.ndarray, np.ndarray] | None:
    """World-space axis-aligned bounds (min, max), or None for ray/plane."""
    t = shape["type"]
    if t == "box":
        c = box_corners(shape)
    elif t == "mesh":
        c = mesh_world(shape)[0]
        if not len(c):
            return None
    elif t == "sphere":
        r = shape["radius"]
        return shape["location"] - r, shape["location"] + r
    elif t in ("cylinder", "tube"):
        r, h = shape["radius"], shape["height"] / 2
        loc = np.array([[sx * r, sy * r, sz * h] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)])
        c = to_world(shape, loc / shape["scale"])
    else:
        return None
    return c.min(0), c.max(0)


def _hull2d(p: np.ndarray) -> np.ndarray:
    pts = sorted(set(map(tuple, np.round(p, 4).tolist())))
    if len(pts) <= 2:
        return np.array(pts)

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for q in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], q) <= 0:
            lower.pop()
        lower.append(q)
    for q in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], q) <= 0:
            upper.pop()
        upper.append(q)
    return np.array(lower[:-1] + upper[:-1])


# --------------------------------------------------------------------------- #
# WAD access (read-only: read_wad_files, else katsuba when installed)
# --------------------------------------------------------------------------- #

def read_wad_files(path: str, wanted) -> dict[str, bytes | None]:
    """{name: bytes or None} for the files named in wanted (case-insensitive) from a
    KIWAD archive, read-only, without katsuba. Layout: b"KIWAD", u32 version, u32
    file count, (version >= 2: u8 flags), then per file u32 offset, u32 size,
    u32 compressed size, u8 compressed, u32 crc, u32 name length, the name
    (NUL-terminated); a compressed file is one zlib stream. A file the game has
    not downloaded yet (its data all zero) comes back as None."""
    want = {n.lower(): n for n in wanted}
    out: dict[str, bytes | None] = {n: None for n in wanted}
    with open(path, "rb") as f:
        head = f.read(14)
        if head[:5] != b"KIWAD":
            raise ValueError(f"wad: {path} is not a KIWAD archive")
        version, count = struct.unpack_from("<II", head, 5)
        pos = 13 + (1 if version >= 2 else 0)
        f.seek(pos)
        found = {}
        for _ in range(count):
            e = f.read(21)
            if len(e) < 21:
                raise ValueError("wad: file table runs past end of file")
            off, size, csize, comp, _crc, nlen = struct.unpack("<IIIBII", e)
            name = f.read(nlen).rstrip(b"\0").decode("utf-8", "replace")
            if name.lower() in want:
                found[want[name.lower()]] = (off, size, csize, comp)
        for n, (off, size, csize, comp) in found.items():
            f.seek(off)
            raw = f.read(csize if comp else size)
            if not raw.strip(b"\0"):
                continue                                    # not downloaded yet
            data = zlib.decompress(raw) if comp else raw
            if len(data) != size:
                raise ValueError(f"wad: {n} is {len(data)} bytes, the table says {size}")
            out[n] = data
    return out


def _read_with_katsuba(path: str, wanted) -> dict[str, bytes | None]:
    import katsuba.wad as kwad  # imported lazily: optional
    arc = kwad.Archive.mmap(path) if hasattr(kwad.Archive, "mmap") else kwad.Archive.heap(path)
    lower = {n.lower(): n for n in arc}
    out: dict[str, bytes | None] = {}
    for n in wanted:
        key = lower.get(n.lower())
        out[n] = bytes(arc[key]) if key is not None else None
    return out


def wad_path(zone_name: str, game_dir: str = GAME_DIR) -> str:
    """'WizardCity/WC_Ravenwood', 'WizardCity-WC_Ravenwood', '...wad' or a full path."""
    if os.path.isfile(zone_name):
        return zone_name
    z = zone_name.replace("\\", "/").strip("/")
    if z.lower().endswith(".wad"):
        z = z[:-4]
    z = z.replace("/", "-")
    return os.path.join(game_dir, "Data", "GameData", z + ".wad")


def load_zone(zone_name: str, game_dir: str = GAME_DIR, use_katsuba: bool = True, step=None) -> dict[str, Any]:
    """Open <GameData>/<zone>.wad read-only (the built-in reader, else katsuba
    if installed) and decode zone.nav and collision.bcd. Either may be None
    when the archive lacks it (or the game hasn't downloaded it yet). Raises
    OSError when the .wad isn't there, ValueError when it can't be decoded.
    step: load_bcd's (called before each collision shape)."""
    path = wad_path(zone_name, game_dir)
    if not os.path.isfile(path):
        raise FileNotFoundError(f"no zone file {path}")
    wanted = ("zone.nav", "collision.bcd")
    try:
        files, reader = read_wad_files(path, wanted), "built-in"
    except (ValueError, struct.error, zlib.error):
        if not use_katsuba:
            raise
        try:
            files, reader = _read_with_katsuba(path, wanted), "katsuba"
        except ImportError:
            raise ValueError(f"wad: can't read {path} (and katsuba isn't installed)") from None
    nav_b, bcd_b = files["zone.nav"], files["collision.bcd"]
    return {
        "zone": os.path.splitext(os.path.basename(path))[0],
        "wad": path,
        "reader": reader,
        "nav": load_nav(nav_b) if nav_b else None,
        "bcd": load_bcd(bcd_b, step) if bcd_b else None,
    }


if __name__ == "__main__":
    import sys

    for z in sys.argv[1:] or ["WizardCity-WC_Ravenwood"]:
        d = load_zone(z)
        nav, bcd = d["nav"], d["bcd"]
        print(d["zone"])
        if nav:
            print(f"  nav: {len(nav['ids'])} nodes, {len(nav['links'])} links, "
                  f"{len(nav['edges'])} undirected edges, {len(nav_components(nav))} component(s)")
        if bcd is not None:
            from collections import Counter
            print(f"  bcd: {len(bcd)} shapes {dict(Counter(s['type'] for s in bcd))}")
