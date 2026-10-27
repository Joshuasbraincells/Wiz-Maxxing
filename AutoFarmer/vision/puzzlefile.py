"""puzzlefile - READ-ONLY, files only: what a zone's own files say about a way that's blocked (a gate, a door, a wall the
walker can't get through) - for the vision helper's /blockers (which objects are a door or a gate), /zonepuzzle (what
the zone's triggers say opens one) and /navpass (does a route along the zone's nav graph go through a spot). Pure: it
can be imported without the helper (the tests import it alone), and it never reads the game's memory.

    is_blocker(name)                a template's or an object's name is a door, a gate, a wall... (BLOCKER_RX) and not a
                                    teleporter, a sigil, a duel circle, a shop... (BLOCKER_NOT) - case-insensitive
    t = zone_triggers(zone, game_dir='', volumes=None, texts=None)
                                    the zone's triggers.xml read: {kills, spawns, hints, uses, triggers, why, complete}
                                      kills   [template]   a Monster_Killed in a trigger that also sets an object's state
                                                           or fires an activation ("CL-DeepOne-GreenHead-R10": its kill
                                                           turns a pylon on) - in file order, each once
                                      spawns  [(object, (x, y, z) or None)]   the objects a trigger makes ("DynaTrigger_KT_
                                                           DoorCollision instance" - the wall a kill takes away) and where
                                      hints   [(volume, (x, y, z), r, text)]  a dialogue (a Hyperlink) a trigger plays when
                                                           the wizard walks into Enter_<volume> ("NearGateVolume": "The gate
                                                           has defenders. ...") - its centre and radius from the zone's
                                                           volumes (volumes: [(name, (x, y, z), r)], or a function (zone,
                                                           game_dir) giving them - the helper's zone_volumes), its words
                                                           from the name tables (texts: a function [keys] -> {key: text};
                                                           else placements' tables)
                                      uses    [event]      other object events ("PedestalUsed", "UsedBook",
                                                           "EVENT-SkeletonKeyLock-Gold") - hints only
                                      triggers             how many triggers the file has
                                      why                  "" read; else why not ("no triggers.xml", "can't be read ...")
                                      complete             False: a dialogue's words couldn't be read (asked again in
                                                           RETRY s - not kept till then)
                                    kept per zone (and its .wad's size and time): the walker asks again at no cost
    want_zone(zone, game_dir='', volumes=None)
                                    zone_triggers built in placements' worker thread (its steps wait for the memory reads
                                    in flight) - the helper's /nav at each zone change, so /zonepuzzle has it by the time
                                    the walker asks; never raises
    ok, nearest, length = path_pass(path, vx, vy, vr, fx=None, fy=None)
                                    a route (a list of x, y, z points) goes through the spot v: comes within vr of (vx,
                                    vy) - or, given where it's asked from (f: behind v, on the line the way runs - the
                                    puzzle's "back the way it came"), crosses the line through v square to f -> v within
                                    2 vr of v (a zone's nav nodes can be 500 apart: Storm Lord's Temple's way to its boss
                                    cuts the gate's corner 183 from v, crossing its line 259 aside). nearest: its least
                                    distance from v, length: its length (both across the ground, 2D)

THE FILE. triggers.xml in the zone's .wad is a BINd file (placements.bind_body): each property is a 4-byte hash, then a
length (one byte = 2 x the letters; an odd byte: a u32 = 2 x the letters + 1) and the letters. A trigger is the strings
from its name (hash 10 0c c9 b8) to the next trigger's name:
    adbea702 the event ("Monster_Killed", "Enter_NearGateVolume", "EnterZone", "PedestalUsed")
    1673be02 the monster a Monster_Killed is about ("<template>.AdjRef")
    8b04e6c6 an object whose state the trigger sets, ab753d7b the state ("CL-PylonLeft" "Turn On")
    feeb36d0 / 16a26202 activations ("ActivateFrom_LeftWatcher", "Disable_CollisionTrigger")
    f303faca an object the trigger spawns - its location (hash 1b dc 7e 85, x, y, z floats) 52 bytes before it, as in a
             placement (gamedata.bin)
    676982a3 an action's kind ("Hyperlink": a dialogue), cbdec46e the dialogue's name key ("WizardActorDialogue_00000329")
Only the strings after those hashes are looked at (bytes.find - no walk over every byte): printable ASCII, 2-4096 letters.

SAFETY. Files only: the zone's .wad and Root.wad opened with open(..., "rb") (navgeo.read_wad_files, placements) - never
written. No game memory, no process, no window, no network.

FAILS SOFT. Nothing here raises into the caller: a file that can't be read gives empty lists and why.
"""
import collections
import functools
import math
import os
import re
import struct
import threading
import time

import navgeo

BLOCKER_RX = re.compile(r"(?i)(door|gate|portcullis|barrier|blocker|forcefield|force_field|collision)")
BLOCKER_NOT = re.compile(r"(?i)(teleport|portal|sigil|duel circle|positional|ambient|player object|petobject|shop)")

H_TRIG, H_EVENT, H_MOB, H_TARGET, H_STATE, H_ACT, H_ACT2, H_SPAWN, H_KIND, H_DLG = (bytes.fromhex(h) for h in (
    "100cc9b8", "adbea702", "1673be02", "8b04e6c6", "ab753d7b", "feeb36d0", "16a26202", "f303faca", "676982a3",
    "cbdec46e"))
H_LOC = bytes.fromhex("1bdc7e85")
_ROLE = {H_TRIG: "trig", H_EVENT: "event", H_MOB: "mob", H_TARGET: "target", H_STATE: "state", H_ACT: "act",
         H_ACT2: "act", H_SPAWN: "spawn", H_KIND: "kind", H_DLG: "dlg"}
# (events that aren't an object being used: kills, walking in or out of a volume, the zone starting)
NOT_USE = re.compile(r"(?i)^(monster_killed|enterzone|exitzone|startzone|enter_|exit_|leave_)")
ZONES_KEPT = 32
RETRY = 30.0                # s before a zone whose dialogue words couldn't be read is read again
FILE_ERRORS = (OSError, ValueError, struct.error, IndexError, EOFError)
try:
    import zlib
    FILE_ERRORS = FILE_ERRORS + (zlib.error,)
except ImportError:  # pragma: no cover - zlib is always there
    pass

LOG = [lambda m: None]


def set_log(fn):
    LOG[0] = fn or (lambda m: None)


def _say(msg):
    try:
        LOG[0](msg)
    except Exception:  # noqa: BLE001 - never into the caller
        pass


def is_blocker(name):
    """name (a template's - "CL-StormLordTempleGate", "DynaTrigger_KT_DoorCollision" - or an object's) is a door, a gate, a
    portcullis, a barrier, a collision wall... and not a teleporter, a portal, a sigil, a duel circle, a positional or
    ambient sound, the player, a pet or a shop - False for anything that isn't a name"""
    if not isinstance(name, str) or not name:
        return False
    return _blocker_text(name)


@functools.lru_cache(maxsize=8192)
def _blocker_text(name):
    return bool(BLOCKER_RX.search(name)) and not BLOCKER_NOT.search(name)


def _lstring(u, p):
    """the text of a length-prefixed string at p (see the top), or None"""
    if p >= len(u):
        return None
    L = u[p]
    if L & 1:
        if p + 4 > len(u):
            return None
        n, p = struct.unpack_from("<I", u, p)[0] >> 1, p + 4
    else:
        n, p = L >> 1, p + 1
    if n < 2 or n > 4096 or p + n > len(u):
        return None
    s = u[p:p + n]
    if any(c < 32 or c > 126 for c in s):
        return None
    return s.decode("ascii")


def trigger_strings(u):
    """[(offset of its hash, role, text)] of a triggers.xml body's strings after the hashes it's read by, in file order"""
    out = []
    for h, role in _ROLE.items():
        k = u.find(h)
        while k >= 0:
            s = _lstring(u, k + 4)
            if s is not None:
                out.append((k, role, s))
            k = u.find(h, k + 1)
    out.sort()
    return out


def _spawn_pos(u, k):
    """the location of the object a trigger spawns, its name's hash at k: x, y, z 52 bytes before it (a placement's
    layout) - None when it isn't there"""
    at = k - 52
    if at < 0 or u[at:at + 4] != H_LOC or at + 16 > len(u):
        return None
    x, y, z = struct.unpack_from("<3f", u, at + 4)
    return (x, y, z) if all(math.isfinite(v) and abs(v) < 1e6 for v in (x, y, z)) else None


def parse_triggers(u):
    """[{name, events, mobs, targets, states, acts, spawns [(object, pos)], kinds, dlgs}] - the triggers of a
    triggers.xml body (bind_body's), in file order (strings before the first trigger's name: one with no name)"""
    trigs, cur = [], None
    for k, role, s in trigger_strings(u or b""):
        if role == "trig" or cur is None:
            cur = {"name": s if role == "trig" else "", "events": [], "mobs": [], "targets": [], "states": [],
                   "acts": [], "spawns": [], "kinds": [], "dlgs": []}
            trigs.append(cur)
            if role == "trig":
                continue
        if role == "spawn":
            cur["spawns"].append((s, _spawn_pos(u, k)))
        else:
            cur[{"event": "events", "mob": "mobs", "target": "targets", "state": "states", "act": "acts",
                 "kind": "kinds", "dlg": "dlgs"}[role]].append(s)
    return trigs


def _uniq(seq):
    return list(dict.fromkeys(x for x in seq if x))


def triggers_answer(trigs, volumes=None, texts=None):
    """parse_triggers' triggers made into zone_triggers' kills, spawns, hints, uses (volumes: [(name, (x, y, z), r)];
    texts: {key: text}) - and whether every hint's words were there"""
    kills, spawns, hints, uses = [], [], [], []
    vols = {}
    for v in volumes or ():
        try:
            name, pos, r = v[0], tuple(float(c) for c in v[1][:3]), float(v[2] or 0.0)
        except (TypeError, ValueError, IndexError):
            continue
        vols.setdefault(str(name).lower(), (str(name), pos, r))
    complete = True
    for t in trigs:
        if "Monster_Killed" in t["events"] and ((t["targets"] and t["states"]) or t["acts"]):
            kills += [m[:-len(".AdjRef")] if m.endswith(".AdjRef") else m for m in t["mobs"]]
        spawns += t["spawns"]
        uses += [e for e in t["events"] if not NOT_USE.match(e)]
        if "Hyperlink" in t["kinds"] and t["dlgs"]:
            for e in t["events"]:
                if not e.startswith("Enter_"):
                    continue
                v = vols.get(e[len("Enter_"):].lower())
                if v is None:
                    continue                    # (no centre for it: a hint that can't be placed isn't one)
                for key in t["dlgs"]:
                    words = (texts or {}).get(key)
                    if words is None:
                        complete = False
                        continue
                    words = re.sub(r"\s+", " ", re.sub(r"<[^>]*>", "", words)).strip()
                    if words and (v[0], words) not in [(h[0], h[3]) for h in hints]:
                        hints.append((v[0], v[1], v[2], words))
    seen = set()
    sp = []
    for name, pos in spawns:
        k = (name, None if pos is None else tuple(round(c) for c in pos))
        if k not in seen:
            seen.add(k)
            sp.append((name, pos))
    return {"kills": _uniq(kills), "spawns": sp, "hints": hints, "uses": _uniq(uses), "triggers": len(trigs)}, complete


def _lang_texts(keys, game_dir=""):
    """{key: text} of the name tables' (placements' set - read once each, kept); a key whose table can't be read: left
    out"""
    if not keys:
        return {}
    import placements                       # (here: placements imports navmem)
    L = placements.lang(game_dir)
    L.load(list(keys), block=True)
    out = {}
    for k in keys:
        t = L.text(k)
        if t is not None:
            out[k] = t
    return out


_CACHE = collections.OrderedDict()      # (zone, game folder) -> (the .wad's stamp, answer, when made)
_LOCK = threading.RLock()


def _gd(game_dir):
    return os.path.normcase(os.path.abspath(game_dir or navgeo.GAME_DIR))


def _empty(why):
    return {"kills": [], "spawns": [], "hints": [], "uses": [], "triggers": 0, "why": why, "complete": True}


def _copy(ans):
    return {k: (list(v) if isinstance(v, list) else v) for k, v in ans.items()}


def zone_triggers(zone, game_dir="", volumes=None, texts=None):
    """the zone's triggers.xml read (see the top) - kept per zone and .wad; never raises"""
    try:
        if not zone:
            return _empty("no zone")
        path = navgeo.wad_path(zone, game_dir or navgeo.GAME_DIR)
        try:
            st = os.stat(path)
        except OSError:
            return _empty("no zone file")
        stamp = (st.st_size, st.st_mtime_ns)
        key = (zone, _gd(game_dir))
        got = _CACHE.get(key)
        if got is not None and got[0] == stamp and (got[1]["complete"] or time.monotonic() - got[2] < RETRY):
            return _copy(got[1])
        with _LOCK:
            got = _CACHE.get(key)
            if got is not None and got[0] == stamp and (got[1]["complete"] or time.monotonic() - got[2] < RETRY):
                return _copy(got[1])
            try:
                d = navgeo.read_wad_files(path, ["triggers.xml"]).get("triggers.xml")
            except FILE_ERRORS as e:
                _say("puzzlefile: %s's triggers can't be read (%r)" % (zone, e))
                return _empty("the zone's file can't be read (%r)" % (e,))
            if not d:
                ans = _empty("no triggers.xml")
            else:
                import placements                   # (bind_body: a BINd file's body)
                try:
                    u = placements.bind_body(d)
                except FILE_ERRORS as e:
                    return _empty("triggers.xml can't be read (%r)" % (e,))
                trigs = parse_triggers(u or b"")
                vols, vols_failed = volumes, False
                if callable(vols):
                    want = any("Hyperlink" in t["kinds"] and t["dlgs"] for t in trigs)
                    try:
                        vols = vols(zone, game_dir) if want else []
                    except Exception as e:  # noqa: BLE001 - the hints without places: asked again in RETRY s
                        _say("puzzlefile: %s's volumes can't be read (%r)" % (zone, e))
                        vols = None
                    # (the helper's zone_volumes: None when the file can't be read now)
                    vols_failed = vols is None
                keys = _uniq(k for t in trigs if "Hyperlink" in t["kinds"] for k in t["dlgs"])
                words = {}
                if keys:
                    try:
                        words = texts(keys) if callable(texts) else (texts if isinstance(texts, dict)
                                                                      else _lang_texts(keys, game_dir))
                    except Exception as e:  # noqa: BLE001 - the hints without words: asked again in RETRY s
                        _say("puzzlefile: %s's dialogue words can't be read (%r)" % (zone, e))
                        words = {}
                ans, complete = triggers_answer(trigs, vols, words)
                ans["why"], ans["complete"] = "", complete and not vols_failed
            _CACHE[key] = (stamp, ans, time.monotonic())
            _CACHE.move_to_end(key)
            while len(_CACHE) > ZONES_KEPT:
                _CACHE.popitem(last=False)
            return _copy(ans)
    except Exception as e:  # noqa: BLE001 - never into the caller
        return _empty("reading the zone's triggers failed (%r)" % (e,))


def cached(zone, game_dir=""):
    """zone_triggers' answer if it's kept and fresh (no file read: only a stat), else None"""
    try:
        path = navgeo.wad_path(zone, game_dir or navgeo.GAME_DIR)
        st = os.stat(path)
        got = _CACHE.get((zone, _gd(game_dir)))
        if got is not None and got[0] == (st.st_size, st.st_mtime_ns) and got[1]["complete"]:
            return _copy(got[1])
    except Exception:  # noqa: BLE001
        pass
    return None


def want_zone(zone, game_dir="", volumes=None):
    """zone_triggers built in placements' worker (once per zone and .wad: nothing when it's kept) - never raises"""
    try:
        if not zone or cached(zone, game_dir) is not None:
            return False
        import placements
        return placements._submit(("puzzle", zone, _gd(game_dir)), lambda: zone_triggers(zone, game_dir, volumes))
    except Exception as e:  # noqa: BLE001 - asked again by the request itself
        _say("puzzlefile: %s's triggers couldn't be asked for (%r)" % (zone, e))
        return False


def _seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    t = 0.0 if L2 <= 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / L2))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def path_pass(path, vx, vy, vr, fx=None, fy=None):
    """(passes, nearest, length) of a route - [(x, y, z), ...], its points in order: passes True when it comes within vr
    of (vx, vy), or (f given) crosses the line through v square to f -> v within 2 vr of v; nearest its least distance
    from (vx, vy) (None: no points); length its length - both across the ground (2D)"""
    pts = [(float(p[0]), float(p[1])) for p in (path or ())]
    if not pts:
        return False, None, 0.0
    if len(pts) == 1:
        near = math.hypot(pts[0][0] - vx, pts[0][1] - vy)
        return near <= vr, near, 0.0
    near, length = float("inf"), 0.0
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        near = min(near, _seg_dist(vx, vy, ax, ay, bx, by))
        length += math.hypot(bx - ax, by - ay)
    crossed = False
    if fx is not None and fy is not None and near > vr:
        nx, ny = vx - fx, vy - fy
        n = math.hypot(nx, ny)
        if n > 1e-6:
            nx, ny = nx / n, ny / n
            for (ax, ay), (bx, by) in zip(pts, pts[1:]):
                sa, sb = (ax - vx) * nx + (ay - vy) * ny, (bx - vx) * nx + (by - vy) * ny
                if (sa < 0) != (sb < 0) and sa != sb:
                    k = sa / (sa - sb)
                    qx, qy = ax + k * (bx - ax), ay + k * (by - ay)
                    if abs((qx - vx) * -ny + (qy - vy) * nx) <= 2 * vr:
                        crossed = True
                        break
    return near <= vr or crossed, near, length
