"""test_puzzlefile.py - the zone files' puzzle reads (vision\\puzzlefile.py: triggers.xml parsed, its kills / spawns / hints /
use events and what each does, the objects a use event may be fired by, the doors' starting states, the --find / --uses
tools' pure parts, zone_triggers on a made-up .wad), the vision helper's /zonepuzzle, /blockers and /items?far=1 lines
built from them, and navmem's objects thread taking a use event's object as a thing of kind "use" - made-up bytes, no
game, no Windows (placements stood in for: it imports navmem, whose ctypes.WinDLL can't load here; the real navmem with
its DLLs stood in for, as test_navroute.py does):  python -m unittest test_puzzlefile   (from AutoFarmer\\vision)"""
import io
import os
import struct
import sys
import tempfile
import time
import types
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import puzzlefile as P  # noqa: E402

H = {k: getattr(P, "H_" + k).hex() for k in ("TRIG", "EVENT", "MOB", "TARGET", "STATE", "ACT", "ACT2", "SPAWN", "KIND",
                                              "DLG", "LOC")}


def bstr(h, text):
    """a BINd string: the property's hash, its length (a byte 2 x the letters - or, 128 letters or more, a u32 2 x the
    letters + 1) and the letters"""
    b = text.encode("ascii")
    n = len(b)
    return bytes.fromhex(h) + (bytes([2 * n]) if 2 * n < 256 else struct.pack("<I", 2 * n + 1)) + b


def trig(name, events=(), mobs=(), targets=(), states=(), acts=(), kinds=(), dlgs=(), spawns=()):
    """a made-up trigger's bytes (its strings in the order a triggers.xml holds them; spawns: [(object, (x, y, z) or
    None)] - a location 52 bytes before its name's hash, as a placement's)"""
    out = bstr(H["TRIG"], name)
    for e in events:
        out += bstr(H["EVENT"], e)
    for m in mobs:
        out += bstr(H["MOB"], m)
    for t in targets:
        out += bstr(H["TARGET"], t)
    for s in states:
        out += bstr(H["STATE"], s)
    for a in acts:
        out += bstr(H["ACT"], a)
    for k in kinds:
        out += bstr(H["KIND"], k)
    for d in dlgs:
        out += bstr(H["DLG"], d)
    for obj, pos in spawns:
        if pos is not None:
            out += bytes.fromhex(H["LOC"]) + struct.pack("<3f", *pos) + bytes(36)
        out += bstr(H["SPAWN"], obj)
    return out


def body():
    """a made-up triggers.xml body: a kill that turns a pylon on, a lever that opens a gate (two triggers on its event),
    a pedestal, a timer, a dialogue on entering a volume, a spawned collision wall"""
    return (bstr(H["KIND"], "Header") +                                    # (before the first trigger: a nameless one)
            trig("KillGuard", events=["Monster_Killed"], mobs=["CL-DeepOne-GreenHead-R10.AdjRef"], targets=["CL-PylonLeft"],
                 states=["Turn On"]) +
            trig("Lever1", events=["LeverPulled"], targets=["CL-Gate01"], states=["Open"]) +
            trig("Lever2", events=["LeverPulled"], acts=["Disable_CollisionTrigger"]) +
            trig("Pedestal", events=["PedestalUsed"]) +
            trig("Clock", events=["TimerExpired"]) +
            trig("Talk", events=["Enter_NearGateVolume"], kinds=["Hyperlink"], dlgs=["WizardActorDialogue_00000329"]) +
            trig("Wall", events=["EnterZone"], spawns=[("DynaTrigger_KT_DoorCollision instance", (100.0, 200.0, 5.0)),
                                                         ("NoPlace", None)]))


def row(name, template, pos, n=None, key="", kind="", state="", at=0):
    return {"name": name, "template": template, "pos": pos, "n": n, "key": key, "kind": kind, "state": state, "at": at}


class Triggers(unittest.TestCase):
    """parse_triggers and triggers_answer on made-up bytes"""

    def test_parse(self):
        ts = P.parse_triggers(body())
        self.assertEqual([t["name"] for t in ts], ["", "KillGuard", "Lever1", "Lever2", "Pedestal", "Clock", "Talk", "Wall"])
        self.assertEqual(ts[0]["kinds"], ["Header"])
        self.assertEqual((ts[1]["mobs"], ts[1]["targets"], ts[1]["states"]),
                         (["CL-DeepOne-GreenHead-R10.AdjRef"], ["CL-PylonLeft"], ["Turn On"]))
        self.assertEqual(ts[3]["acts"], ["Disable_CollisionTrigger"])
        sp = dict(ts[7]["spawns"])
        self.assertEqual(sp["DynaTrigger_KT_DoorCollision instance"], (100.0, 200.0, 5.0))
        self.assertIsNone(sp["NoPlace"])
        self.assertEqual(P.parse_triggers(b""), [])
        self.assertEqual(P.parse_triggers(None), [])

    def test_long_string(self):
        long = "Q" * 200                                             # (the u32 length form)
        ts = P.parse_triggers(trig("T", events=[long]))
        self.assertEqual(ts[0]["events"], [long])

    def test_answer(self):
        vols = [("NearGateVolume", (10.0, 20.0, 0.0), 300.0)]
        texts = {"WizardActorDialogue_00000329": "<b>The gate</b>   has\ndefenders."}
        ans, complete = P.triggers_answer(P.parse_triggers(body()), vols, texts)
        self.assertTrue(complete)
        self.assertEqual(ans["kills"], ["CL-DeepOne-GreenHead-R10"])
        self.assertEqual(ans["uses"], ["LeverPulled", "PedestalUsed", "TimerExpired"])
        # (what each use event's triggers do - both of LeverPulled's merged, in uses' order)
        self.assertEqual(ans["usedo"], [("LeverPulled", ["CL-Gate01"], ["Open"], ["Disable_CollisionTrigger"]),
                                        ("PedestalUsed", [], [], []), ("TimerExpired", [], [], [])])
        self.assertEqual(ans["useobjs"], [])
        self.assertEqual(ans["hints"], [("NearGateVolume", (10.0, 20.0, 0.0), 300.0, "The gate has defenders.")])
        self.assertEqual([s[0] for s in ans["spawns"]], ["DynaTrigger_KT_DoorCollision instance", "NoPlace"])
        self.assertEqual(ans["triggers"], 8)

    def test_answer_words_missing(self):
        ans, complete = P.triggers_answer(P.parse_triggers(body()), [("NearGateVolume", (0, 0, 0), 1)], {})
        self.assertFalse(complete)
        self.assertEqual(ans["hints"], [])
        # (a volume the zone doesn't have: no hint - and nothing missing)
        ans, complete = P.triggers_answer(P.parse_triggers(body()), [], {})
        self.assertTrue(complete)

    def test_not_use(self):
        for e in ("Monster_Killed", "EnterZone", "Enter_X", "exit_Y", "Leave_Z", "StartZone"):
            self.assertTrue(P.NOT_USE.match(e), e)
        self.assertFalse(P.NOT_USE.match("PedestalUsed"))


class UseObjects(unittest.TestCase):
    """event_words and event_objects: the placements a use event may be fired by"""

    def test_words(self):
        self.assertEqual(P.event_words("PedestalUsed"), (["pedestal"], []))
        self.assertEqual(P.event_words("UsedBook"), (["book"], []))
        self.assertEqual(P.event_words("Lever01Pulled"), (["lever"], [1]))
        self.assertEqual(P.event_words("EVENT-SkeletonKeyLock-Gold"), (["skeleton", "key", "lock", "gold"], []))
        self.assertEqual(P.event_words("CenterPedestalUsed"), (["center", "pedestal"], []))     # (not an "enter")
        for e in ("TimerExpired", "QuestComplete", "Monster_Killed", "Enter_Volume", "Use", "OnUse", "", None, 5):
            self.assertEqual(P.event_words(e), ([], []), e)

    def rows(self):
        return [row("CL-Pedestal-01 instance (1)", "CL-Pedestal-01", (10.0, 0.0, 0.0), n=1, at=10),
                row("CL-Pedestal-01 instance (2)", "CL-Pedestal-01", (20.0, 0.0, 0.0), n=2, at=20),
                row("named", "CL-PedestalShop", (30.0, 0.0, 0.0), key="WizQst_01", kind="object"),     # (a name: /items')
                row("gate", "CL-PedestalGate", (40.0, 0.0, 0.0)),                                      # (a door)
                row("tp", "CL-PedestalTeleporter", (50.0, 0.0, 0.0)),                                  # (a teleporter)
                row("CL-Lever-01", "CL-Lever-01", (1.0, 2.0, 3.0), n=0, at=60),
                row("CL-Lever-02", "CL-Lever-02", (4.0, 5.0, 6.0), n=0, at=70),
                row("noplace", "CL-Pedestal-01", None)]

    def test_by_name(self):
        usedo = [("PedestalUsed", ["CL-Gate01"], ["Open"], []), ("Lever02Pulled", [], [], ["Act"]), ("TimerExpired", [], [], [])]
        got = P.event_objects(usedo, self.rows())
        ped = [g for g in got if g["event"] == "PedestalUsed"]
        self.assertEqual([(g["template"], g["n"], g["how"]) for g in ped],
                         [("CL-Pedestal-01", 1, "name"), ("CL-Pedestal-01", 2, "name")])
        self.assertEqual((ped[0]["targets"], ped[0]["states"], ped[0]["pos"]), (["CL-Gate01"], ["Open"], (10.0, 0.0, 0.0)))
        lev = [g for g in got if g["event"] == "Lever02Pulled"]
        self.assertEqual([g["template"] for g in lev], ["CL-Lever-02", "CL-Lever-01"])    # (its number's first)
        self.assertEqual(lev[0]["acts"], ["Act"])
        self.assertFalse([g for g in got if g["event"] == "TimerExpired"])                # (a timer: no object)

    def test_cap_and_bound(self):
        rows = [row("p%d" % i, "CL-Pedestal-01", (float(i), 0.0, 0.0), n=i) for i in range(10)]
        got = P.event_objects([("PedestalUsed", [], [], [])], rows)
        self.assertEqual(len(got), P.USE_CAP)
        # (bound - the property that ties an object to its event, once known: first, how "file")
        rows.append(row("odd", "CL-Statue", (99.0, 0.0, 0.0)))
        got = P.event_objects([("PedestalUsed", [], [], [])], rows,
                              bound=lambda r: ["PedestalUsed"] if r["template"] == "CL-Statue" else [])
        self.assertEqual((got[0]["template"], got[0]["how"]), ("CL-Statue", "file"))
        got = P.event_objects([("PedestalUsed", [], [], [])], rows, bound=lambda r: 1 / 0)    # (a bad bound: by name)
        self.assertEqual(got[0]["how"], "name")
        self.assertEqual(P.event_objects(None, rows), [])
        self.assertEqual(P.event_objects([("PedestalUsed",)], rows)[0]["targets"], [])
        self.assertEqual(P.event_objects([("PedestalUsed", [], [], [])], [{"template": 5}]), [])   # (never raises)

    def test_match_start(self):
        live = [{"template": "CL-Gate", "pos": (0.0, 0.0, 0.0)}, {"template": "cl-gate", "pos": (1000.0, 0.0, 0.0)},
                {"template": "Other", "pos": (0.0, 0.0, 0.0)}, {"pos": None}]
        placed = [{"template": "CL-Gate", "pos": (300.0, 0.0, 0.0), "state": "Closed"},
                  {"template": "CL-Gate", "pos": (100.0, 0.0, 0.0), "state": "Shut"},
                  {"template": "CL-Gate", "pos": (1200.0, 0.0, 0.0), "state": None}]
        self.assertEqual(P.match_start(live, placed), ["Shut", "", "", ""])
        self.assertEqual(P.match_start(live, placed, near=50.0), ["", "", "", ""])
        self.assertEqual(P.match_start(None, placed), [])


class Pure(unittest.TestCase):
    """is_blocker, path_pass, find_strings, placement_at, uses_lines"""

    def test_blocker(self):
        for n in ("CL-StormLordTempleGate", "DynaTrigger_KT_DoorCollision", "Portcullis_01", "ForceField"):
            self.assertTrue(P.is_blocker(n), n)
        for n in ("CL-Lever-01", "Gate Teleporter", "Sigil_Door", "Basic Positional", "", None, 5):
            self.assertFalse(P.is_blocker(n), n)

    def test_path_pass(self):
        self.assertEqual(P.path_pass([], 0, 0, 100), (False, None, 0.0))
        ok, near, length = P.path_pass([(0, -500, 0), (0, 500, 0)], 50, 0, 100)
        self.assertTrue(ok)
        self.assertAlmostEqual(near, 50.0)
        self.assertAlmostEqual(length, 1000.0)
        # (far from v, but across the line through v square to f -> v within 2 vr: nav nodes far apart)
        path = [(150, -600, 0), (210, 600, 0)]                     # (180 aside where it crosses y = 0, 180 off v)
        self.assertFalse(P.path_pass(path, 0, 0, 100)[0])
        self.assertTrue(P.path_pass(path, 0, 0, 100, fx=0, fy=-500)[0])
        self.assertFalse(P.path_pass([(350, -600, 0), (410, 600, 0)], 0, 0, 100, fx=0, fy=-500)[0])

    def test_find_strings(self):
        u = (b"xx" + bstr("aabbccdd", "LeverPulled") + b"yy" + bytes.fromhex("11223344") + struct.pack("<H", 11)
             + b"LeverPulled" + bytes.fromhex("55667788") + struct.pack("<I", 23) + b"LeverPulled" + b"zz"
             + "LeverPulled".encode("utf-16-le") + b"LeverPulledX")
        got = P.find_strings(u, "LeverPulled")
        self.assertEqual([(g[1], g[2], g[3]) for g in got],
                         [("aabbccdd", "ascii", "bind"), ("11223344", "ascii", "u16"), ("55667788", "ascii", "bind32"),
                          ("", "utf16", ""), ("", "ascii", "")])
        self.assertEqual(got[0][0], 7)
        self.assertEqual(P.find_strings(b"", "x"), [])
        self.assertEqual(P.find_strings(u, ""), [])

    def test_placement_at(self):
        rows = [{"name": "a", "at": 100}, {"name": "b", "at": 300}, {"name": "c", "at": None}]
        self.assertEqual(P.placement_at(rows, 350)["name"], "b")
        self.assertEqual(P.placement_at(rows, 299)["name"], "a")
        self.assertIsNone(P.placement_at(rows, 50))

    def test_uses_lines(self):
        ans = {"usedo": [("LeverPulled", ["CL-Gate01", "x;y"], ["Open"], []), ("P|q", [], [], ["A"])]}
        self.assertEqual(P.uses_lines("Z/One", ans), ["uses|Z/One|LeverPulled|CL-Gate01;x,y|Open|", "uses|Z/One|P q|||A"])


def kiwad(files):
    """a made-up KIWAD archive (version 2): {name: bytes}, none compressed"""
    head = b"KIWAD" + struct.pack("<II", 2, len(files)) + b"\0"
    names = [n.encode() + b"\0" for n in files]
    off = len(head) + sum(21 + len(n) for n in names)
    table, data = b"", b""
    for (n, d), nb in zip(files.items(), names):
        table += struct.pack("<IIIBII", off + len(data), len(d), len(d), 0, 0, len(nb)) + nb
        data += d
    return head + table + data


class StubPlacements:
    """placements stood in for in sys.modules (bind_body, built_things - the rows given; Wad, parse_placements,
    zone_placements, root_wad for the --find tool) - the one there before put back by undo()"""

    def __init__(self, rows=None):
        self.had = sys.modules.get("placements")
        m = types.ModuleType("placements")
        m.rows = rows
        m.bind_body = lambda d: d[8:] if d is not None and d[:4] == b"BINd" else d
        m.built_things = lambda zone, game_dir="": None if m.rows is None else [dict(r) for r in m.rows]
        self.m = m
        sys.modules["placements"] = m

    def undo(self):
        if self.had is None:
            sys.modules.pop("placements", None)
        else:
            sys.modules["placements"] = self.had


class ZoneTriggers(unittest.TestCase):
    """zone_triggers / cached / use_templates on a made-up game folder (a zone .wad holding triggers.xml)"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        gd = os.path.join(self.tmp.name, "Data", "GameData")
        os.makedirs(gd)
        with open(os.path.join(gd, "Test-Zone.wad"), "wb") as f:
            f.write(kiwad({"triggers.xml": b"BINd\0\0\0\0" + body(), "other.txt": b"PedestalUsed"}))
        with open(os.path.join(gd, "Test-Empty.wad"), "wb") as f:
            f.write(kiwad({"other.txt": b"nothing"}))
        self.stub = StubPlacements(None)
        self.retry, self.wait = P.RETRY, P.USE_WAIT
        P._CACHE.clear()

    def tearDown(self):
        P.RETRY, P.USE_WAIT = self.retry, self.wait
        P._CACHE.clear()
        self.stub.undo()
        self.tmp.cleanup()

    def test_useobjs_once_built(self):
        gd = self.tmp.name
        texts = {"WizardActorDialogue_00000329": "The gate has defenders."}
        vols = lambda zone, game_dir: [("NearGateVolume", (0.0, 0.0, 0.0), 100.0)]     # noqa: E731
        t = P.zone_triggers("Test/Zone", gd, vols, texts)
        self.assertEqual(t["why"], "")
        self.assertEqual(t["uses"], ["LeverPulled", "PedestalUsed", "TimerExpired"])
        self.assertEqual(t["hints"][0][3], "The gate has defenders.")
        self.assertTrue(t["complete"])
        # (the zone's things not built yet: none - waiting for them, looked for again when asked)
        self.assertEqual((t["useobjs"], t["useobjs_wait"]), ([], True))
        self.assertEqual(P.cached("Test/Zone", gd)["useobjs"], [])
        self.assertEqual(P.use_templates("Test/Zone", gd), frozenset())
        # (built now: the kept answer filled in when next asked - USE_WAIT s apart -, the file not read again)
        self.stub.m.rows = [row("CL-Pedestal-01 instance (1)", "CL-Pedestal-01", (5.0, 6.0, 7.0), n=1),
                            row("CL-Lever", "CL-Lever", (8.0, 9.0, 0.0), n=0)]
        self.assertEqual(P.use_templates("Test/Zone", gd), frozenset())         # (within USE_WAIT: not looked yet)
        P.USE_WAIT = 0.0
        self.assertEqual(P.use_templates("Test/Zone", gd), frozenset({"CL-Lever", "CL-Pedestal-01"}))
        t = P.zone_triggers("Test/Zone", gd, vols, texts)
        self.assertFalse(t["useobjs_wait"])
        self.assertEqual([(u["event"], u["template"], u["how"]) for u in t["useobjs"]],
                         [("LeverPulled", "CL-Lever", "name"), ("PedestalUsed", "CL-Pedestal-01", "name")])
        c = P.cached("Test/Zone", gd)
        self.assertEqual(c["useobjs"], t["useobjs"])
        c["useobjs"][0]["template"] = "changed"           # (a copy: the kept answer isn't changed)
        self.assertEqual(P.use_templates("Test/Zone", gd), frozenset({"CL-Lever", "CL-Pedestal-01"}))
        self.assertEqual(P.use_templates("", gd), frozenset())

    def test_useobjs_built_first(self):
        # (the usual order: placements' worker builds the zone's things before the triggers' job - filled at once)
        self.stub.m.rows = [row("CL-Lever", "CL-Lever", (8.0, 9.0, 0.0), n=0)]
        t = P.zone_triggers("Test/Zone", self.tmp.name, [], {})
        self.assertEqual((t["useobjs_wait"], [u["template"] for u in t["useobjs"]]), (False, ["CL-Lever"]))

    def test_no_triggers(self):
        t = P.zone_triggers("Test/Empty", self.tmp.name)
        self.assertEqual((t["why"], t["usedo"], t["useobjs"]), ("no triggers.xml", [], []))
        self.assertEqual(P.zone_triggers("Test/None", self.tmp.name)["why"], "no zone file")
        self.assertEqual(P.zone_triggers("", self.tmp.name)["why"], "no zone")

    def test_uses_report(self):
        import navgeo
        lines = P.uses_report(["Test/Zone", "Test/Empty", "Test/None"], self.tmp.name)
        self.assertIn("uses|Test/Zone|LeverPulled|CL-Gate01|Open|Disable_CollisionTrigger", lines)
        self.assertTrue(any(x.startswith("none|Test/None|") for x in lines))
        self.assertEqual(lines[-1], "total|2 zones read|1 with use events|3 use events")
        self.assertEqual([z for z, _p in P.wad_zones(self.tmp.name)], ["Test-Empty", "Test-Zone"])
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(P._main(["--uses", "Test/Zone", "--game", self.tmp.name]), 0)
        self.assertIn("uses|Test/Zone|PedestalUsed|||", out.getvalue())
        self.assertTrue(navgeo.GAME_DIR)


class Helper(unittest.TestCase):
    """the vision helper's /zonepuzzle, /blockers and /items?far=1 lines (vision.py imports on any system)"""

    @classmethod
    def setUpClass(cls):
        import vision
        cls.V = vision
        cls.log = vision.log
        vision.log = lambda *a, **kw: None             # (nothing into vision\vision.log from the tests)

    @classmethod
    def tearDownClass(cls):
        cls.V.log = cls.log

    def setUp(self):
        self.stub = StubPlacements(None)
        self.zt = P.zone_triggers
        self.ut = P.use_templates

    def tearDown(self):
        P.zone_triggers = self.zt
        P.use_templates = self.ut
        self.stub.undo()

    def test_zonepuzzle_lines(self):
        V = self.V
        ans = P._empty("")
        ans.update(kills=["CL-Mob"], uses=["LeverPulled", "PedestalUsed"],
                   usedo=[("LeverPulled", ["CL-Gate01", "B;C"], ["Open"], ["Act|1"]), ("PedestalUsed", [], [], [])],
                   useobjs=[{"event": "LeverPulled", "template": "CL-Lever", "pos": (1.0, 2.0, 3.0), "how": "name"}])
        P.zone_triggers = lambda zone, game_dir="", volumes=None, texts=None: ans
        lines = V.zonepuzzle_lines("Test/Zone")
        self.assertEqual(lines, ["kill|CL-Mob", "use|LeverPulled|CL-Gate01;B,C|Open|Act 1", "use|PedestalUsed|||",
                                 "useobj|LeverPulled|CL-Lever|1.0|2.0|3.0|name"])
        # (an older bot's PzZoneHints reads a use line's second field alone)
        self.assertEqual(lines[1].split("|")[1], "LeverPulled")
        # (an older puzzlefile answer - no usedo / useobjs: the use lines as before, empty fields after)
        old = {"kills": [], "spawns": [], "hints": [], "uses": ["UsedBook"], "why": ""}
        P.zone_triggers = lambda zone, game_dir="", volumes=None, texts=None: old
        self.assertEqual(V.zonepuzzle_lines("Z"), ["use|UsedBook|||"])
        P.zone_triggers = lambda zone, game_dir="", volumes=None, texts=None: P._empty("no triggers.xml")
        self.assertEqual(V.zonepuzzle_lines("Z"), ["none"])
        P.zone_triggers = lambda zone, game_dir="", volumes=None, texts=None: P._empty("can't|be read")
        self.assertEqual(V.zonepuzzle_lines("Z"), ["ERR can't be read"])

    def test_blocker_lines(self):
        V = self.V

        class NM:
            game_dir = ""

            def blockers(self):
                return [{"name": "CL-Gate", "template": "CL-Gate", "pos": (100.0, 0.0, 0.0), "gid": 7, "state": "Closed"},
                        {"name": "DynaTrigger_KT_DoorCollision", "template": "DynaTrigger_KT_DoorCollision",
                         "pos": (50.0, 0.0, 0.0), "gid": 8, "state": None}], ""
        self.stub.m.rows = [row("CL-Gate instance (1)", "CL-Gate", (150.0, 0.0, 0.0), n=1, state="Shut"),
                            row("lever", "CL-Lever", (0.0, 0.0, 0.0))]
        lines = V.blocker_lines({"zone": "Test/Zone", "pos": (0.0, 0.0, 0.0)}, NM())
        f = [x.split("|") for x in lines]
        self.assertEqual([len(x) for x in f], [10, 10, 10])
        self.assertEqual([(x[1], x[7], x[8], x[9]) for x in f],
                         [("DynaTrigger_KT_DoorCollision", "mem", "", ""), ("CL-Gate", "mem", "Closed", "Shut"),
                          ("CL-Gate", "file", "Shut", "Shut")])
        self.assertEqual(f[2][6], "f:CL-Gate:1")
        # (no file yet: the memory's alone, no start)
        self.stub.m.rows = None
        f = [x.split("|") for x in V.blocker_lines({"zone": "Test/Zone", "pos": (0.0, 0.0, 0.0)}, NM())]
        self.assertEqual([(x[8], x[9]) for x in f], [("", ""), ("Closed", "")])

        class Bad:
            game_dir = ""

            def blockers(self):
                return None, "not|attached"
        self.assertEqual(V.blocker_lines({"zone": "Z"}, Bad()), ["ERR not attached"])

    def test_merge_things_uses(self):
        V = self.V
        live = [{"name": "", "pos": (0.0, 0.0, 0.0), "gid": 5, "template": "CL-Lever", "key": "", "kind": "use"}]
        placed = [row("CL-Lever instance (1)", "CL-Lever", (100.0, 0.0, 0.0), n=1),               # (the live one's)
                  row("CL-Lever instance (2)", "CL-Lever", (5000.0, 0.0, 0.0), n=2),
                  row("CL-Pedestal", "CL-Pedestal", (9000.0, 0.0, 0.0)),
                  row("other", "CL-Rock", (10.0, 0.0, 0.0))]
        placed[2]["at"] = 77
        got = V.merge_things(live, placed, frozenset({"CL-Lever", "CL-Pedestal"}))
        self.assertEqual([(t["gid"], t["kind"], t["src"], t["name"], t["key"]) for t in got],
                         [(5, "use", "mem", "", ""), ("f:CL-Lever:2", "use", "file", "", ""),
                          ("f:CL-Pedestal@77", "use", "file", "", "")])
        # (no uses - an older puzzlefile, nothing kept yet: as before)
        self.assertEqual(len(V.merge_things(live, placed)), 1)
        self.assertEqual(len(V.merge_things(live, placed, frozenset())), 1)
        # (a use thing's line: name and key empty, kind use)
        f = V.item_line(dict(got[1], quest=False), (0.0, 0.0, 0.0)).split("|")
        self.assertEqual((f[1], f[8], f[9], f[10], f[11]), ("", "", "CL-Lever", "file", "use"))
        self.assertFalse(V.quest_item(got[1], "Use the Lever", {"text": "Use the Lever", "exact": True, "item": "Lever"}))


def import_navmem():
    """the real navmem, its Windows DLLs stood in for (test_navroute.py's way - another test file's stand-in put back)"""
    from test_navroute import import_navmem as imp
    return imp()


class NavmemUse(unittest.TestCase):
    """navmem's objects thread: an object with no name key whose template a use event may be fired by is a thing of kind
    "use" (puzzlefile.use_templates stood in for); a door stays a door, anything else a duel candidate as before"""

    @classmethod
    def setUpClass(cls):
        cls.N = import_navmem()

    def setUp(self):
        self.ut = P.use_templates
        self.consts = (self.N.OBJ_QUICK, self.N.OBJ_IDLE)

    def tearDown(self):
        P.use_templates = self.ut
        self.N.OBJ_QUICK, self.N.OBJ_IDLE = self.consts

    def world(self):
        N = self.N
        CZ, VT = 0x200000, 0x7FF600001000
        tpls = {0x10: ("", "CL-Lever", "", "", ""), 0x20: ("", "CL-StormGate", "", "", ""),
                0x30: ("", "Basic Positional", "", "", ""), 0x40: ("", "CL-Lever", "", "WizQst_01", "object")}
        mem = {}
        for i, tpl in enumerate(tpls):
            raw = bytearray(N.OBJ_SPAN)
            struct.pack_into("<Q", raw, 0, VT)
            struct.pack_into("<Q", raw, N.DATA["co_gid"], 100 + i)
            struct.pack_into("<Q", raw, N.DATA["co_template"], tpl)
            struct.pack_into("<Q", raw, N.DATA["co_zone"], CZ)
            struct.pack_into("<6f", raw, 0xA8, float(i), 2.0, 3.0, 0.0, 0.0, 0.5)
            mem[0x500000 + i * 0x1000] = bytes(raw)

        class St:
            o = {}
            p = types.SimpleNamespace(try_read=lambda a, n: mem.get(a, b"")[:n] or None, u64=lambda a: 0)
            m = types.SimpleNamespace(in_section=lambda v, s: True)
            tn = types.SimpleNamespace(of_vtable=lambda v: "WizClientObject")

            def gameclient(self):
                return 0x100000

            def zone_ptr(self, gc):
                return CZ

            def zone(self, gc):
                return "Test/Zone"

            def scan_objects(self, cz, regions=None):
                return list(mem), [(0x500000, 0x10000)]

            def template_kind(self, tpl, names, cache):
                return tpls.get(tpl)
        return St(), mem

    def run_once(self, nm):
        N = self.N
        N.OBJ_QUICK, N.OBJ_IDLE = 0.0, 0.2
        nm._obj_asked = time.monotonic()
        nm._objects_run()                                           # (one look, then nobody's asked: it ends)

    def test_use_branch(self):
        N = self.N
        nm = N.NavMem(log=lambda m: None)
        st, mem = self.world()
        nm.st = st
        nm._names = lambda: {}
        nm._thing_name = lambda key, want=None: "Named"
        asked = []
        P.use_templates = lambda zone, game_dir="": asked.append(zone) or frozenset({"CL-Lever"})
        self.run_once(nm)
        self.assertEqual(asked[:1], ["Test/Zone"])
        kinds = sorted((v[2], v[5]) for v in nm._items.values())
        self.assertEqual(kinds, [("CL-Lever", "object"), ("CL-Lever", "use")])
        self.assertEqual([v[1] for v in nm._blockers.values()], ["CL-StormGate"])
        self.assertEqual(nm.obj_stats["uses"], 1)
        nm._obj_asked = time.monotonic()
        nm._obj_thread = types.SimpleNamespace(is_alive=lambda: True)       # (no thread started by the read)
        items, why = nm._live("items")
        use = [t for t in items if t["kind"] == "use"]
        self.assertEqual(why, "")
        self.assertEqual([(t["name"], t["key"], t["template"], t["src"]) for t in use], [("", "", "CL-Lever", "mem")])
        self.assertEqual(use[0]["pos"], (0.0, 2.0, 3.0))

    def test_no_uses_as_before(self):
        nm = self.N.NavMem(log=lambda m: None)
        st, mem = self.world()
        nm.st = st
        nm._names = lambda: {}
        nm._thing_name = lambda key, want=None: "Named"
        P.use_templates = lambda zone, game_dir="": frozenset()
        self.run_once(nm)
        self.assertEqual([v[5] for v in nm._items.values()], ["object"])
        self.assertEqual(nm.obj_stats["uses"], 0)
        P.use_templates = lambda zone, game_dir="": 1 / 0                    # (a failure: none, as before)
        self.run_once(nm)
        self.assertEqual([v[5] for v in nm._items.values()], ["object"])


if __name__ == "__main__":
    unittest.main()
