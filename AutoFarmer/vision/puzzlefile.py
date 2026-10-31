"""puzzlefile - READ-ONLY, files only: what a zone's own files say about a way that's blocked (a gate, a door, a wall the
walker can't get through) - for the vision helper's /blockers (which objects are a door or a gate), /zonepuzzle (what
the zone's triggers say opens one) and /navpass (does a route along the zone's nav graph go through a spot). Pure: it
can be imported without the helper (the tests import it alone), and it never reads the game's memory.

    is_blocker(name)                a template's or an object's name is a door, a gate, a wall... (BLOCKER_RX) and not a
                                    teleporter, a sigil, a duel circle, a shop... (BLOCKER_NOT) - case-insensitive
    t = zone_triggers(zone, game_dir='', volumes=None, texts=None)
                                    the zone's triggers.xml read: {kills, spawns, hints, uses, usedo, useobjs,
                                    useobjs_wait, triggers, why, complete}
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
                                      usedo   [(event, targets, states, acts)]   what each use event's triggers do
                                                           ("LeverPulled", ["CL-Gate01"], ["Open"], []) - every trigger
                                                           of the event's merged, in uses' order
                                      useobjs [{event, template, name, pos, n, at, how, targets, states, acts}]   the
                                                           zone's placements that may be what fires a use event
                                                           (event_objects - how "name": by the event's own words, a
                                                           guess) - [] till placements' things are built for the zone
                                      useobjs_wait         True: they aren't built yet - looked for again (USE_WAIT s
                                                           apart, never built here) whenever the answer's asked for,
                                                           the kept one filled in then (no file read again)
                                      triggers             how many triggers the file has
                                      why                  "" read; else why not ("no triggers.xml", "can't be read ...")
                                      complete             False: a dialogue's words couldn't be read (asked again in
                                                           RETRY s - not kept till then)
                                    kept per zone (and its .wad's size and time): the walker asks again at no cost
    objs = event_objects(usedo, rows, bound=None)
                                    the placements (placements.zone_things' rows) that may be what fires each use event:
                                    a thing with no name key (a lever the game names nowhere), not a door, an NPC, a
                                    teleporter... - by bound (a function row -> the events its own record or template names:
                                    how "file" - None until the property that ties an object to its event is known, see
                                    THE FILE), else by name (how "name": the event's words, its verb left out, all in the
                                    template's name - "PedestalUsed": CL-Pedestal-01); USE_CAP an event, the best first
    tpls = use_templates(zone, game_dir='')
                                    the templates of the zone's useobjs as kept (no file read but a stat, nothing built:
                                    an empty set till then) - navmem's objects thread and /items?far=1 take those things as
                                    kind "use"
    starts = match_start(live, placed, near=400.0)
                                    the zone file's starting state of each live door (the nearest placement of its template
                                    within near; "" none) - /blockers' start column
    hits = find_strings(u, text)    [(offset, hash, encoding, form)] every copy of text in u (ASCII, UTF-16LE) and the
                                    property hash before it - the --find tool's
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
NOT KNOWN YET (needs the game's files - the --find tool below): which file and property ties an object to the use event it
fires (its Root.wad template, its gamedata.bin record, or another file of the zone's .wad), and what a trigger's target
names (a placement's name, a template's). Till then event_objects matches by name only (how "name"); once known, its hash
goes in H_USEEVENT and the matcher in event_objects' bound (TODO - needs-live-game: plan step 5).

DISCOVERY (on a PC with Wizard101 installed - files only, nothing of the game's memory):
    python puzzlefile.py --uses [zone ...] [--out uses.txt]
                                    every zone's use events (or the zones given - "WizardCity/WC_Ravenwood", or the .wad's
                                    name): uses|<zone>|<event>|<targets>|<states>|<acts> (lists ; apart), total|... at the end
    python puzzlefile.py --find <zone> <event> [--out find.txt]
                                    every copy of the event's name (ASCII and UTF-16LE) in every file of the zone's .wad, in
                                    its gamedata.bin (the placement whose record holds it) and in the Root.wad template of
                                    every placement of the zone: hit|<where>|<file>|<offset>|<encoding>|<form>|<hash>|<what>
                                    (hash: the 4 bytes of the property before it - the H_USEEVENT to pin)
    [--game <folder>]               the game's folder (else the usual one)

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
# The property that ties an object (its template or its placement) to the use event it fires: not known yet (the --find
# tool's hash, plan step 5 - needs the game's files) - None: event_objects matches by name only
H_USEEVENT = None
# (a use event no object is looked for - one of its words a timer's, a quest's, a dialogue's...: NOT_USE lets them through
# as hints; whole words only - "CenterPedestalUsed" isn't an enter)
USE_NOT = re.compile(r"(?i)^(timers?|quests?|goals?|dialog|dialogue|cinematic|cutscene|spawn|spawned|kill|killed|death|dead|"
                     r"died|complete|completed|finish|finished|start|started|reset|init|load|loaded|music|sound|camera|"
                     r"enter|entered|exit|exited|leave|zone|player|combat|battle|duel|timeout|expired|begin|end|ended)$")
# (a use event's verb, left out of its words: "PedestalUsed" -> pedestal, "UsedBook" -> book, "Lever01Pulled" -> lever 01)
USE_VERB = re.compile(r"(?i)^(used|use|pulled|pull|activated|activate|pressed|press|touched|touch|clicked|click|"
                      r"interacted|interact|flipped|flip|turned|turn|read)$")
USE_STOP = {"the", "and", "for", "obj", "object", "item", "trigger", "event", "on", "off", "cl"}
USE_CAP = 4                 # placements a use event at most (event_objects)
USE_WAIT = 2.0              # s between looks for the zone's things while its use events' objects wait for them
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
    """parse_triggers' triggers made into zone_triggers' kills, spawns, hints, uses, usedo (useobjs [] - zone_triggers'
    own) (volumes: [(name, (x, y, z), r)]; texts: {key: text}) - and whether every hint's words were there"""
    kills, spawns, hints, uses = [], [], [], []
    usedo = collections.OrderedDict()       # (event -> (targets, states, acts): every trigger of the event's, merged)
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
        for e in t["events"]:
            if e and not NOT_USE.match(e):
                # (what the trigger does when the object's used - "LeverPulled" sets CL-Gate01 to Open: kept, not only
                # the event's name)
                did = usedo.setdefault(e, ([], [], []))
                for have, new in zip(did, (t["targets"], t["states"], t["acts"])):
                    have += [x for x in new if x and x not in have]
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
    return {"kills": _uniq(kills), "spawns": sp, "hints": hints, "uses": _uniq(uses), "triggers": len(trigs),
            "usedo": [(e, tg, st, ac) for e, (tg, st, ac) in usedo.items()], "useobjs": []}, complete


# ---------------------------------------------------------------- the objects a use event may be fired by
def _letters(s):
    return re.sub(r"[^a-z0-9]", "", (s or "").lower())


def event_words(event):
    """(words, numbers) a use event's name says what's used by - "PedestalUsed" (["pedestal"], []), "Lever01Pulled"
    (["lever"], [1]), "EVENT-SkeletonKeyLock-Gold" (["skeleton", "key", "lock", "gold"], []): its CamelCase words, case
    folded, its verb (USE_VERB), "EVENT-" and the little words (USE_STOP, under 3 letters) left out - ([], []) for one no
    object is looked for (NOT_USE's, a timer's or a quest's: USE_NOT; under 4 letters in all)"""
    e = event if isinstance(event, str) else ""
    if not e or NOT_USE.match(e):
        return [], []
    e = re.sub(r"(?i)^event[-_ ]*", "", e)
    toks = re.findall(r"[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z]+|[A-Z]+|\d+", e)
    if any(USE_NOT.match(t) for t in toks):
        return [], []
    words = [t.lower() for t in toks if not t.isdigit() and not USE_VERB.match(t)]
    words = [w for w in words if len(w) >= 3 and w not in USE_STOP]
    nums = [int(t) for t in toks if t.isdigit()]
    if sum(len(w) for w in words) < 4:
        return [], []
    return words, nums


def event_objects(usedo, rows, bound=None):
    """[{event, template, name, pos, n, at, how, targets, states, acts}] - for each use event of usedo ([(event, targets,
    states, acts)] - zone_triggers' usedo), the placements of rows (placements.zone_things' rows: {name, template, n, pos,
    at, key, kind}) that may be what fires it, USE_CAP at most, the best first: only a thing with no name key (kind "",
    key "" - a lever the game names nowhere: one with a name is /items' already), not a door or a gate (is_blocker), not a
    teleporter, a sigil, a sound... (BLOCKER_NOT). bound: a function row -> the events its own record or template names
    (the property not known yet - H_USEEVENT: None till then): how "file", first; else how "name" - every word of the
    event's (event_words) in the template's name, its number (if any) the template's ("Lever01Pulled": CL-Lever-01 before
    CL-Lever-02). Never raises"""
    out = []
    try:
        cands = []
        for r in rows or ():
            tpl = r.get("template") or ""
            if not tpl or r.get("key") or r.get("kind") or is_blocker(tpl) or BLOCKER_NOT.search(tpl):
                continue
            pos = r.get("pos")
            if not pos or len(pos) < 3:
                continue
            cands.append((r, tpl, _letters(tpl), {int(g) for g in re.findall(r"\d+", tpl)}))
        for item in usedo or ():
            event = item[0]
            targets, states, acts = (list(item[1]), list(item[2]), list(item[3])) if len(item) >= 4 else ([], [], [])
            words, nums = event_words(event)
            hits = []
            for r, tpl, lt, tn in cands:
                how, score = "", 0
                if bound is not None:
                    try:
                        if event in (bound(r) or ()):
                            how, score = "file", 1000
                    except Exception:  # noqa: BLE001 - not by its record then
                        pass
                if not how and words and all(w in lt for w in words):
                    how, score = "name", sum(len(w) for w in words)
                    if nums and tn:
                        score += 5 if set(nums) & tn else -2      # (Lever01Pulled: CL-Lever-01 before CL-Lever-02)
                if how:
                    hits.append((-score, r.get("n") if r.get("n") is not None else 1 << 20, r.get("at") or 0, r, tpl, how))
            hits.sort(key=lambda h: h[:3])
            for _s, _n, _at, r, tpl, how in hits[:USE_CAP]:
                out.append({"event": event, "template": tpl, "name": r.get("name") or "",
                            "pos": tuple(float(c) for c in r["pos"][:3]), "n": r.get("n"), "at": r.get("at"), "how": how,
                            "targets": list(targets), "states": list(states), "acts": list(acts)})
    except Exception as e:  # noqa: BLE001 - never into the caller: none
        _say("puzzlefile: the use objects couldn't be matched (%r)" % (e,))
        return []
    return out


def match_start(live, placed, near=400.0):
    """[the zone file's starting state of each of live's doors] - live: [{template, pos}] (the game's memory's), placed:
    [{template, pos, state}] (placements rows): the state of the placement of the same template (any case) nearest it
    within near ("" none, or no state in the file) - so a state read in the game's memory can be told changed since the
    zone began without knowing its names. Never raises"""
    out = []
    for d in live or ():
        best, bd = "", None
        try:
            tl, (x, y) = (d.get("template") or "").lower(), d["pos"][:2]
            for p in placed or ():
                if not tl or (p.get("template") or "").lower() != tl:
                    continue
                dist = math.hypot(p["pos"][0] - x, p["pos"][1] - y)
                if dist <= near and (bd is None or dist < bd):
                    best, bd = p.get("state") or "", dist
        except (KeyError, TypeError, IndexError, ValueError):
            best = ""
        out.append(best)
    return out


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
    return {"kills": [], "spawns": [], "hints": [], "uses": [], "triggers": 0, "usedo": [], "useobjs": [], "why": why,
            "complete": True}


def _copy(ans):
    return {k: ([dict(x) if isinstance(x, dict) else x for x in v] if isinstance(v, list) else v) for k, v in ans.items()}


def _fill_uses(zone, game_dir, ans):
    """ans (a kept answer) whose use events' objects wait for the zone's things (useobjs_wait): its useobjs made once
    placements' worker has built them - looked for at most every USE_WAIT s, never built here (placements.built_things
    asks the worker) - in place, under the lock"""
    if not ans.get("useobjs_wait") or time.monotonic() - ans.get("useobjs_at", 0.0) < USE_WAIT:
        return
    with _LOCK:
        if not ans.get("useobjs_wait") or time.monotonic() - ans.get("useobjs_at", 0.0) < USE_WAIT:
            return
        ans["useobjs_at"] = time.monotonic()
        try:
            import placements
            rows = placements.built_things(zone, game_dir)
        except Exception:  # noqa: BLE001 - looked for again in USE_WAIT s
            rows = None
        if rows is not None:
            ans["useobjs"], ans["useobjs_wait"] = event_objects(ans["usedo"], rows), False


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
            _fill_uses(zone, game_dir, got[1])
            return _copy(got[1])
        with _LOCK:
            got = _CACHE.get(key)
            if got is not None and got[0] == stamp and (got[1]["complete"] or time.monotonic() - got[2] < RETRY):
                _fill_uses(zone, game_dir, got[1])
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
                # (the objects a use event may be fired by: from the zone's things placements' worker built - never
                # built here; not built yet - its worker's zone job runs first, so seldom -: filled in when asked again)
                if any(event_words(e)[0] for e, *_rest in ans["usedo"]):
                    ans["useobjs_wait"], ans["useobjs_at"] = True, 0.0
                    _fill_uses(zone, game_dir, ans)
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
            _fill_uses(zone, game_dir, got[1])
            return _copy(got[1])
    except Exception:  # noqa: BLE001
        pass
    return None


def use_templates(zone, game_dir=""):
    """the templates of the zone's use objects (zone_triggers' useobjs) as kept - complete or not (a dialogue's words
    missing doesn't matter here) - no file read but a stat, nothing built (the zone's things looked for again while its
    useobjs wait for them: _fill_uses): an empty set while none is kept. navmem's objects thread asks at every look;
    never raises"""
    try:
        if not zone:
            return frozenset()
        st = os.stat(navgeo.wad_path(zone, game_dir or navgeo.GAME_DIR))
        got = _CACHE.get((zone, _gd(game_dir)))
        if got is not None and got[0] == (st.st_size, st.st_mtime_ns):
            _fill_uses(zone, game_dir, got[1])
            return frozenset(u["template"] for u in got[1].get("useobjs") or () if u.get("template"))
    except Exception:  # noqa: BLE001 - none
        pass
    return frozenset()


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


# ---------------------------------------------------------------- discovery: which file ties an object to its use event
def find_strings(u, text):
    """[(offset, hash, encoding, form)] of every copy of text in the bytes u - ASCII ("ascii") and UTF-16LE ("utf16"), in
    offset order: form how its length is written before it - "bind" (a BINd length byte: 2 x the letters), "bind32" (its
    u32 form: 2 x the letters + 1), "u16" (gamedata.bin's u16 length - the letters, or a UTF-16 one's bytes), "" none of
    those; hash the 4 bytes before that length, hex - the property's hash ("" with no form). Never raises"""
    out = []
    if not text or not u:
        return out
    try:
        n = len(text)
        for enc, pat in (("ascii", text.encode("ascii", "replace")), ("utf16", text.encode("utf-16-le"))):
            k = u.find(pat)
            while k >= 0:
                form, h = "", ""
                if k >= 5 and 2 * n < 256 and u[k - 1] == 2 * n:
                    form, h = "bind", u[k - 5:k - 1].hex()
                elif k >= 8 and struct.unpack_from("<I", u, k - 4)[0] == 2 * n + 1:
                    form, h = "bind32", u[k - 8:k - 4].hex()
                elif k >= 6 and struct.unpack_from("<H", u, k - 2)[0] in (n, len(pat)):
                    form, h = "u16", u[k - 6:k - 2].hex()
                out.append((k, h, enc, form))
                k = u.find(pat, k + 1)
    except Exception:  # noqa: BLE001 - what was found so far
        pass
    out.sort()
    return out


def placement_at(rows, off):
    """the placement (placements.parse_placements' rows: {name, pos, at...}) whose record holds offset off of its
    gamedata.bin: the one whose location (at) is nearest before it - None when none is"""
    best = None
    for r in rows or ():
        at = r.get("at")
        if isinstance(at, int) and at <= off and (best is None or at > best["at"]):
            best = r
    return best


def _cell(v):
    """a field of a discovery line: no | or line breaks, no ; (the lists' separator)"""
    return re.sub(r"[|\r\n]+", " ", str(v)).replace(";", ",").strip()


def uses_lines(zone, ans):
    """the --uses lines of one zone (zone_triggers' or triggers_answer's ans): uses|<zone>|<event>|<targets>|<states>|<acts>
    each (lists ; apart)"""
    return ["uses|%s|%s|%s|%s|%s" % (_cell(zone), _cell(e), ";".join(_cell(x) for x in tg),
                                     ";".join(_cell(x) for x in st), ";".join(_cell(x) for x in ac))
            for e, tg, st, ac in ans.get("usedo") or ()]


def wad_zones(game_dir=""):
    """[(zone - the .wad's name without .wad -, its path)] of every zone .wad in the game's Data\\GameData (not Root.wad,
    not a world's -WorldData.wad), by name"""
    gd = os.path.join(game_dir or navgeo.GAME_DIR, "Data", "GameData")
    out = []
    for f in sorted(os.listdir(gd)):
        low = f.lower()
        if low.endswith(".wad") and low != "root.wad" and not low.endswith("-worlddata.wad"):
            out.append((f[:-4], os.path.join(gd, f)))
    return out


def uses_report(zones, game_dir=""):
    """--uses: the lines of every zone's use events (or zones' - a zone path or a .wad's name) - files only"""
    import placements                       # (bind_body - here: placements imports navmem, which needs Windows)
    todo = [(z, navgeo.wad_path(z, game_dir or navgeo.GAME_DIR)) for z in zones] if zones else wad_zones(game_dir)
    lines, n_read, n_with, n_ev = [], 0, 0, 0
    for zone, path in todo:
        try:
            d = navgeo.read_wad_files(path, ["triggers.xml"]).get("triggers.xml")
            u = placements.bind_body(d) if d else None
        except FILE_ERRORS as e:
            lines.append("none|%s|can't be read (%r)" % (_cell(zone), e))
            continue
        n_read += 1
        if not u:
            continue
        ans, _ = triggers_answer(parse_triggers(u))
        got = uses_lines(zone, ans)
        if got:
            n_with += 1
            n_ev += len(got)
            lines += got
    lines.append("total|%d zones read|%d with use events|%d use events" % (n_read, n_with, n_ev))
    return lines


def find_report(zone, event, game_dir=""):
    """--find: the lines of every copy of event's name in the zone's .wad files (in its gamedata.bin: the placement whose
    record holds it), and in the Root.wad templates of its placements - files only"""
    import placements
    lines = []
    wad = placements.Wad(navgeo.wad_path(zone, game_dir or navgeo.GAME_DIR))
    names = sorted(wad.table())
    rows = []
    for name in names:
        try:
            d = wad.read(name)
        except FILE_ERRORS as e:
            lines.append("none|zone|%s|can't be read (%r)" % (_cell(name), e))
            continue
        if not d:
            continue
        gdb = name.lower() == "gamedata.bin"
        if gdb:
            rows = placements.parse_placements(d)
        for off, h, enc, form in find_strings(placements.bind_body(d) if d[:4] == b"BINd" else d, event):
            what = ""
            if gdb:
                r = placement_at(rows, off)
                what = ("in the record of %s at (%.0f, %.0f, %.0f) - %d bytes after its location" % (
                    r["name"], r["pos"][0], r["pos"][1], r["pos"][2], off - r["at"])) if r else "before any placement"
            lines.append("hit|zone|%s|%d|%s|%s|%s|%s" % (_cell(name), off, enc, form, h, _cell(what)))
    # (the templates of the zone's placements, each file once)
    try:
        placed = placements.zone_placements(zone, game_dir) or []
    except Exception as e:  # noqa: BLE001 - the zone's own files alone
        placed = []
        lines.append("none|template||the zone's placements can't be read (%r)" % (e,))
    by_file = collections.OrderedDict()
    for r in placed:
        if r.get("file"):
            by_file.setdefault(r["file"], []).append(r)
    rw = placements.root_wad(game_dir)
    for f, rs in by_file.items():
        try:
            u = placements.bind_body(rw.read(f))
        except FILE_ERRORS:
            continue
        for off, h, enc, form in find_strings(u or b"", event):
            lines.append("hit|template|%s|%d|%s|%s|%s|%s" % (_cell(f), off, enc, form, h, _cell("placed %d time(s): %s" % (
                len(rs), ", ".join(r["name"] for r in rs[:3]) + (" ..." if len(rs) > 3 else "")))))
    lines.append("total|%d files of the zone|%d templates|%d hits" % (
        len(names), len(by_file), sum(1 for x in lines if x.startswith("hit|"))))
    return lines


def _main(argv=None):
    import argparse
    import sys
    argv = sys.argv[1:] if argv is None else list(argv)
    ap = argparse.ArgumentParser(description="files only: the zones' use events, and where an event's name is held")
    ap.add_argument("--uses", nargs="*", metavar="ZONE", help="every zone's use events (or these zones')")
    ap.add_argument("--find", nargs=2, metavar=("ZONE", "EVENT"), help="every copy of EVENT's name in ZONE's files")
    ap.add_argument("--game", default="", help="the game's folder (else %s)" % navgeo.GAME_DIR)
    ap.add_argument("--out", default="", help="also written to this file")
    a = ap.parse_args(argv)
    if a.uses is None and not a.find:
        ap.print_help()
        return 2
    head = "# python puzzlefile.py %s (%s) - %s" % (" ".join(argv), time.strftime("%Y-%m-%d %H:%M"),
                                                     a.game or navgeo.GAME_DIR)
    try:
        lines = find_report(a.find[0], a.find[1], a.game) if a.find else uses_report(a.uses, a.game)
    except FILE_ERRORS as e:
        lines = ["none|%r" % (e,)]
    text = "\n".join([head] + lines)
    print(text)
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            f.write(text + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
