"""test_bagmem.py - the window tree's checks (bagmem.BagMem.tree, subtree, tree_lines, nav_tree, the --tree command line)
on a made-up window tree in made-up memory - no game, no Windows (navmem stood in for: its ctypes.WinDLL can't load
here):  python -m unittest test_bagmem   (from AutoFarmer\\vision)"""
import io
import os
import struct
import sys
import tempfile
import threading
import types
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def _stub_navmem():
    """a stand-in navmem module (what bagmem / handmem / questmem use of it at import and in the parts tested) - the
    real one when it's already imported (Windows)"""
    m = sys.modules.get("navmem")
    if m is None:
        m = sys.modules["navmem"] = types.ModuleType("navmem")
    need = {"ptr_ok": lambda v: 0x10000 <= v < 0x7FFFFFFF0000, "ReadError": type("ReadError", (Exception,), {}),
            "DATA": {"window_name": 0x50}, "KNOWN": {}, "SIGS": {}, "NavMem": None, "find_pids": lambda *a: [],
            "foreground_pid": lambda: 0}
    for k, v in need.items():
        if not hasattr(m, k):
            setattr(m, k, v)
    return m


_stub_navmem()
import bagmem as B  # noqa: E402

# bagmem's offsets as they were in build 6A9721E9-370E000 (any will do - the reader takes them from props)
PROPS = {"Window": {"m_sName": 0x50, "m_Children": 0x70, "m_Flags": 0x9C, "m_Window": 0xA0},
         "ControlText": {"m_sText": 0x2C8},
         "ControlButton": {"m_sLabel": 0x2E0, "m_bGreyed": 0x328, "m_pButton": 0x308},
         "ControlCheckBox": {"m_bChecked": 0x40C},
         "ControlSprite": {"m_pMaterial": 0x2D0}, "Material": {"m_pDiffuseMap": 0x78}, "Texture": {"m_sFilename": 0x68},
         "CoreObject": {"m_inactiveBehaviors": 0xE0, "m_globalID.m_full": 0x48, "m_templateID.m_full": 0x60},
         "WizClientObject": {"m_gameStats": 0x230}, "WizGameStats": {"m_currentGold": 0x74, "m_baseGoldPouch": 0x58},
         "InventoryBehaviorBase": {"m_itemList": 0x70}, "ClientWizInventoryBehavior": {"m_numItemsAllowed": 0xA0}}


class Mem:
    """made-up memory: regions of bytes - try_read / try_string as navmem's Proc (None when it can't be read)"""

    def __init__(self):
        self.regions = {}
        self.next = 0x10000000
        self.reads = 0

    def alloc(self, n):
        a = self.next
        self.next += (n + 0xFFF) & ~0xFFF
        self.regions[a] = bytearray(n)
        return a

    def _at(self, a, n):
        for base, buf in self.regions.items():
            if base <= a and a + n <= base + len(buf):
                return buf, a - base
        return None, 0

    def write(self, a, data):
        buf, o = self._at(a, len(data))
        assert buf is not None, hex(a)
        buf[o:o + len(data)] = data

    def try_read(self, a, n):
        self.reads += 1
        buf, o = self._at(a, n)
        return bytes(buf[o:o + n]) if buf is not None else None

    def try_string(self, a, stable=False):
        raw = self.try_read(a, 0x20)
        if raw is None:
            return None
        size, cap = struct.unpack_from("<QQ", raw, 0x10)
        if size > 0x1000 or cap < size or cap > 0x100000:
            return None
        data = raw[:size] if cap < 16 else (self.try_read(struct.unpack_from("<Q", raw)[0], size) if size else b"")
        if data is None:
            return None
        s = data.decode("latin-1")
        return s if all(32 <= ord(ch) < 127 for ch in s) else None

    # (MSVC x64 layouts)
    def put_string(self, a, s):
        b = s.encode("latin-1")
        if len(b) < 16:
            self.write(a, b.ljust(16, b"\0") + struct.pack("<QQ", len(b), 15))
        else:
            h = self.alloc(len(b) + 1)
            self.write(h, b)
            self.write(a, struct.pack("<QQQQ", h, 0, len(b), len(b)))

    def put_wstring(self, a, s):
        b = s.encode("utf-16-le")
        if len(s) < 8:
            self.write(a, b.ljust(16, b"\0") + struct.pack("<QQ", len(s), 7))
        else:
            h = self.alloc(len(b) + 2)
            self.write(h, b)
            self.write(a, struct.pack("<QQQQ", h, 0, len(s), len(s)))


class World:
    """a made-up game: windows in Mem, their type names (st.tn.of), the GUI's root (hm.root) and a name table"""

    def __init__(self):
        self.p = Mem()
        self.types = {}
        self.tn = types.SimpleNamespace(of=lambda obj: self.types.get(obj))
        self.m = types.SimpleNamespace(build="TEST-1")

    def window(self, name, kind="Window", shown=True, rect=(0, 0, 100, 50), kids=(), text=None, label=None,
               greyed=None, checked=None, tex=None, flags=None):
        p, W = self.p, PROPS["Window"]
        w = p.alloc(0x500)
        p.put_string(w + W["m_sName"], name)
        if kids:
            vec = p.alloc(16 * len(kids))
            for i, k in enumerate(kids):
                p.write(vec + 16 * i, struct.pack("<QQ", k, 0))
            p.write(w + W["m_Children"], struct.pack("<QQ", vec, vec + 16 * len(kids)))
        p.write(w + W["m_Flags"], struct.pack("<I", flags if flags is not None else (1 if shown else 0)))
        p.write(w + W["m_Window"], struct.pack("<4i", *rect))
        if text is not None:
            p.put_wstring(w + PROPS["ControlText"]["m_sText"], text)
        if label is not None:
            p.put_wstring(w + PROPS["ControlButton"]["m_sLabel"], label)
        if greyed is not None:
            p.write(w + PROPS["ControlButton"]["m_bGreyed"], bytes([1 if greyed else 0]))
        if checked is not None:
            p.write(w + PROPS["ControlCheckBox"]["m_bChecked"], bytes([1 if checked else 0]))
        if tex is not None:
            mat, dm = p.alloc(0x100), p.alloc(0x100)
            p.write(w + PROPS["ControlSprite"]["m_pMaterial"], struct.pack("<Q", mat))
            p.write(mat + PROPS["Material"]["m_pDiffuseMap"], struct.pack("<Q", dm))
            p.put_string(dm + PROPS["Texture"]["m_sFilename"], tex)
        self.types[w] = kind
        return w


LANG = {"CombatPass": "Pass", "CombatFlee": "Flee"}


def battle_world():
    """the root (1827x1027) -> windowHUD (shown, a TipWindow in it) and CombatPlanningPhaseWindow (at 100,700) ->
    SpellSelectionWindow -> passButton ("<string;CombatPass>", greyed 0), fleeButton (a long label, greyed 1), a hidden
    drawButton with a child, a check box, a sprite with a texture, a text with | in it; and a hidden copy of
    CombatPlanningPhaseWindow (its own Pass) - returns (world, hm, {name: address})"""
    wd = World()
    a = {}
    a["pass"] = wd.window("passButton", "ControlButton", rect=(10, 20, 110, 60), label="<string;CombatPass>", greyed=False)
    a["flee"] = wd.window("fleeButton", "ControlButton", rect=(120, 20, 220, 60),
                          label="<center>Flee the battle now</center>", greyed=True)
    a["drawkid"] = wd.window("drawLabel", "ControlText", rect=(1, 1, 5, 5), text="Draw")
    a["draw"] = wd.window("drawButton", "ControlButton", shown=False, rect=(230, 20, 330, 60), kids=[a["drawkid"]],
                          label="Draw", greyed=False)
    a["chk"] = wd.window("autoCheck", "ControlCheckBox", rect=(0, 70, 20, 90), label="", checked=True, greyed=False)
    a["spr"] = wd.window("timerImage", "ControlSprite", rect=(300, 0, 340, 40), tex="GUI/Combat/Timer.dds")
    a["txt"] = wd.window("caption", "ControlText", rect=(0, 0, 50, 10), text="a|b\nc")
    a["sel"] = wd.window("SpellSelectionWindow", "SpellSelectionWindow", rect=(5, 6, 600, 200),
                         kids=[a["pass"], a["flee"], a["draw"], a["chk"], a["spr"], a["txt"]])
    a["cpp"] = wd.window("CombatPlanningPhaseWindow", "CombatPlanningPhaseWindow", rect=(100, 700, 700, 900),
                         kids=[a["sel"]])
    a["pass2"] = wd.window("passButton", "ControlButton", rect=(0, 0, 10, 10), label="old", greyed=False)
    a["cpp2"] = wd.window("CombatPlanningPhaseWindow", "CombatPlanningPhaseWindow", shown=False, rect=(0, 0, 9, 9),
                          kids=[a["pass2"]])
    a["tip"] = wd.window("TipWindow", "TipFrame", rect=(1807, 128, 1827, 799))
    a["hud"] = wd.window("windowHUD", "Window", rect=(0, 0, 1827, 1027), kids=[a["tip"]])
    a["root"] = wd.window("", "Window", rect=(0, 0, 1827, 1027), kids=[a["cpp2"], a["hud"], a["cpp"]], flags=0x11)
    hm = types.SimpleNamespace(root=lambda: a["root"], lang_text=lambda k: LANG.get(k), st=wd)
    return wd, hm, a


def reader(wd):
    return B.BagMem(wd, props=PROPS)


class Pure(unittest.TestCase):
    def found(self):
        """a made-up walk() list: R -> A (shown) -> A1 (shown), A2 (hidden) -> A2x; R -> C (shown)"""
        def f(w, name, chain_w, chain, shown):
            return {"w": w, "name": name, "chain_w": chain_w, "chain": chain, "shown": shown, "rect": (0, 0, 1, 1),
                    "prect": None, "kids": [], "flags": 1 if shown else 0}
        return [f(1, "R", (), (), True), f(2, "A", (1,), ("R",), True), f(3, "A1", (1, 2), ("R", "A"), True),
                f(4, "A2", (1, 2), ("R", "A"), False), f(5, "A2x", (1, 2, 4), ("R", "A", "A2"), False),
                f(6, "C", (1,), ("R",), True)]

    def test_subtree_shown_and_parents(self):
        fd = self.found()
        rows, capped = B.subtree(fd, fd[0])
        self.assertFalse(capped)
        self.assertEqual([(f["name"], d, p) for f, d, p in rows], [("R", 0, 0), ("A", 1, 1), ("A1", 2, 2), ("C", 1, 1)])
        rows, _ = B.subtree(fd, fd[0], shown_only=False)
        self.assertEqual([(f["name"], d, p) for f, d, p in rows],
                         [("R", 0, 0), ("A", 1, 1), ("A1", 2, 2), ("A2", 2, 2), ("A2x", 3, 4), ("C", 1, 1)])

    def test_subtree_under_depth_cap(self):
        fd = self.found()
        rows, _ = B.subtree(fd, fd[1], shown_only=False)           # under A: A's windows only, A at depth 0
        self.assertEqual([(f["name"], d, p) for f, d, p in rows], [("A", 0, 0), ("A1", 1, 1), ("A2", 1, 1), ("A2x", 2, 3)])
        rows, _ = B.subtree(fd, fd[1], shown_only=False, depth=1)
        self.assertEqual([f["name"] for f, _, _ in rows], ["A", "A1", "A2"])
        rows, capped = B.subtree(fd, fd[0], shown_only=False, cap=3)
        self.assertEqual([f["name"] for f, _, _ in rows], ["R", "A", "A1"])
        self.assertTrue(capped)
        rows, capped = B.subtree(fd, fd[0], cap=4)                  # exactly cap rows: not capped
        self.assertEqual(len(rows), 4)
        self.assertFalse(capped)

    def test_tree_under(self):
        self.assertEqual(B.tree_under(""), "")
        self.assertEqual(B.tree_under(None), "")
        self.assertEqual(B.tree_under(" CombatPlanningPhaseWindow/passButton "), "CombatPlanningPhaseWindow/passButton")
        for bad in ("a,b", "a//b", "a/b/", "../x", "a b", "a|b"):
            self.assertIsNone(B.tree_under(bad), bad)

    def test_tree_lines(self):
        self.assertEqual(B.tree_lines(None, "no GUI root|not in the world"), ["none|no GUI root not in the world"])
        t = {"root": (1827, 1027), "under": "A/B", "matches": 2, "dups": 1, "walked": 40, "capped": False, "all": True,
             "rows": [{"depth": 0, "parent": 0, "name": "B", "type": "ControlButton", "shown": True,
                       "rect": (1, 2, 3, 4), "text": "Pass|now", "key": "CombatPass", "greyed": False, "checked": None,
                       "tex": None, "kids": 2, "flags": 0x11},
                      {"depth": 1, "parent": 1, "name": "C", "type": "", "shown": False, "rect": None, "text": None,
                       "key": "", "greyed": None, "checked": None, "tex": "a.dds", "kids": 0, "flags": None}]}
        ln = B.tree_lines(t)
        self.assertEqual(ln[0], "root|1827|1027")
        self.assertEqual(ln[1], "tree|A/B|2|1|2|40|0|1")
        self.assertEqual(ln[2], "0|B|ControlButton|1|1|2|3|4|Pass now|CombatPass|0|||2|0|11")
        self.assertEqual(ln[3], "1|C||0|||||||||a.dds|0|1|")
        for x in ln[2:]:
            self.assertEqual(len(x.split("|")), 16)
        self.assertEqual(B.tree_lines(t, indent=True)[3].split("|")[1], "  C")


class Tree(unittest.TestCase):
    def setUp(self):
        self.wd, self.hm, self.a = battle_world()
        self.bm = reader(self.wd)

    def rows(self, t):
        return [(r["depth"], r["name"], r["parent"]) for r in t["rows"]]

    def test_whole_tree_shown(self):
        t, why = self.bm.tree(self.hm)
        self.assertEqual(why, "")
        self.assertEqual(t["root"], (1827, 1027))
        self.assertEqual((t["under"], t["matches"], t["dups"], t["capped"], t["all"]), ("", 1, 1, False, False))
        # (the hidden CombatPlanningPhaseWindow, the hidden drawButton and its label: left out - and the windows in the
        # two hidden ones not even read: 12 of the 14)
        self.assertEqual(t["walked"], 12)
        self.assertEqual(self.rows(t), [(0, "", 0), (1, "windowHUD", 1), (2, "TipWindow", 2),
                                        (1, "CombatPlanningPhaseWindow", 1), (2, "SpellSelectionWindow", 4),
                                        (3, "passButton", 5), (3, "fleeButton", 5), (3, "autoCheck", 5),
                                        (3, "timerImage", 5), (3, "caption", 5)])
        r = {x["name"]: x for x in t["rows"]}
        self.assertEqual(r["passButton"]["rect"], (100 + 5 + 10, 700 + 6 + 20, 100 + 5 + 110, 700 + 6 + 60))
        self.assertEqual(r["passButton"]["prect"], (105, 706, 700, 900))
        self.assertEqual((r["passButton"]["type"], r["passButton"]["greyed"], r["passButton"]["raw"]),
                         ("ControlButton", False, "<string;CombatPass>"))
        self.assertTrue(r["fleeButton"]["greyed"])
        self.assertTrue(r["autoCheck"]["checked"])
        self.assertEqual(r["timerImage"]["tex"], "GUI/Combat/Timer.dds")
        self.assertEqual(r["caption"]["raw"], "a|b\nc")
        self.assertEqual(r["SpellSelectionWindow"]["kids"], 6)
        self.assertEqual(r[""]["flags"], 0x11)

    def test_under_and_lines(self):
        t, why = self.bm.tree(self.hm, "CombatPlanningPhaseWindow")
        B.finish_tree(t, self.hm.lang_text)
        # (two windows of that name: the shown one picked)
        self.assertEqual((t["matches"], t["dups"]), (2, 1))
        self.assertEqual(self.rows(t)[:3], [(0, "CombatPlanningPhaseWindow", 0), (1, "SpellSelectionWindow", 1),
                                            (2, "passButton", 2)])
        ln = B.tree_lines(t)
        # (walked: 12 finding it - the hidden windows' windows not read -, then the 8 under it)
        self.assertEqual(ln[1], "tree|CombatPlanningPhaseWindow|2|1|7|20|0|0")
        self.assertEqual(ln[4], "2|passButton|ControlButton|1|115|726|215|766|Pass|CombatPass|0|||0|2|1")
        self.assertEqual(ln[5].split("|")[8], "Flee the battle now")
        self.assertEqual(ln[-1].split("|")[8], "a b c")          # (no | or line break in a field)

    def test_hidden_too_and_depth(self):
        t, _ = self.bm.tree(self.hm, "CombatPlanningPhaseWindow/SpellSelectionWindow", shown_only=False, depth=1)
        names = [(r["depth"], r["name"], r["shown"]) for r in t["rows"]]
        self.assertIn((1, "drawButton", False), names)
        self.assertNotIn("drawLabel", [n for _, n, _ in names])       # depth 2: left out
        t, _ = self.bm.tree(self.hm, "SpellSelectionWindow", shown_only=False)
        self.assertIn((2, "drawLabel", False), [(r["depth"], r["name"], r["shown"]) for r in t["rows"]])
        self.assertTrue(t["all"])

    def test_not_found_and_hidden_only(self):
        t, why = self.bm.tree(self.hm, "NoSuchWindow")
        self.assertEqual((why, t["matches"], t["rows"]), ("", 0, []))
        self.assertEqual(B.tree_lines(t)[1:], ["tree|NoSuchWindow|0|0|0|12|0|0"])
        # (only a hidden match: picked, but it and its windows aren't shown - no rows unless all)
        t, _ = self.bm.tree(self.hm, "drawButton")
        self.assertEqual((t["matches"], t["dups"], t["rows"]), (1, 0, []))
        t, _ = self.bm.tree(self.hm, "drawButton", shown_only=False)
        self.assertEqual(self.rows(t), [(0, "drawButton", 0), (1, "drawLabel", 1)])

    def test_cap(self):
        t, _ = self.bm.tree(self.hm, cap=3)
        self.assertEqual(len(t["rows"]), 3)
        self.assertTrue(t["capped"])
        self.assertEqual(B.tree_lines(t)[1].split("|")[6], "1")

    def test_no_root_and_never_raises(self):
        hm = types.SimpleNamespace(root=lambda: 0, lang_text=lambda k: None)
        self.assertEqual(self.bm.tree(hm), (None, "no GUI root (not in the game world)"))

        def boom():
            raise RuntimeError("x")
        t, why = self.bm.tree(types.SimpleNamespace(root=boom))
        self.assertIsNone(t)
        self.assertIn("window tree failed", why)

    def test_gui_unchanged(self):
        # (walk() now takes want=None too: gui()'s own reading - names wanted - as before)
        g, why = self.bm.gui(self.hm, ["CombatPlanningPhaseWindow/passButton", "fleeButton", "Nope"])
        g = B.finish_gui(g, self.hm.lang_text)
        w = g["wins"]
        self.assertEqual((w["CombatPlanningPhaseWindow/passButton"]["text"], w["CombatPlanningPhaseWindow/passButton"]["key"],
                          w["CombatPlanningPhaseWindow/passButton"]["dups"], w["CombatPlanningPhaseWindow/passButton"]["matches"]),
                         ("Pass", "CombatPass", 1, 2))
        self.assertTrue(w["fleeButton"]["greyed"])
        self.assertIsNone(w["Nope"])
        self.assertIsNone(g["box"])


class Reach(unittest.TestCase):
    """how far the walks go: WIN_CAP windows (a small one here), TREE_DEPTH levels - asked under a window, its windows
    walked on their own; a cut always said (capped)"""

    def setUp(self):
        self.keep = B.WIN_CAP

    def tearDown(self):
        B.WIN_CAP = self.keep

    def world(self, tops):
        """the root (shown) -> tops: [(name, number of plain shown windows in it, shown)] - (world, hm, {name: address})"""
        wd, a = World(), {}
        kids = []
        for name, n, shown in tops:
            inner = [wd.window("%s_%d" % (name, i), rect=(i, 0, i + 1, 1)) for i in range(n)]
            a[name] = wd.window(name, shown=shown, rect=(10, 20, 30, 40), kids=inner)
            kids.append(a[name])
        a["root"] = wd.window("", rect=(0, 0, 1827, 1027), kids=kids, flags=0x11)
        return wd, types.SimpleNamespace(root=lambda: a["root"], lang_text=lambda k: None, st=wd), a

    def test_under_gets_past_the_cap(self):
        B.WIN_CAP = 30
        wd, hm, _a = self.world([("Pre", 10, True), ("Target", 25, True), ("Post", 10, True)])
        bm = reader(wd)
        t, _ = bm.tree(hm)                          # the whole tree: cut 17 windows into Target's
        self.assertEqual((t["walked"], t["capped"], len(t["rows"])), (30, True, 30))
        self.assertNotIn("Target_24", [r["name"] for r in t["rows"]])
        t, _ = bm.tree(hm, "Target")                # asked under it: its 25 windows walked on their own - all of them
        self.assertEqual((t["matches"], t["dups"], t["capped"]), (1, 1, False))
        self.assertEqual([r["name"] for r in t["rows"]], ["Target"] + ["Target_%d" % i for i in range(25)])
        self.assertEqual(t["rows"][-1]["rect"], (10 + 24, 20, 10 + 25, 21))       # (in the root, as before)
        self.assertEqual(t["walked"], 30 + 26)
        # (past where finding it stops: not found - and said to be cut, not "no such window")
        t, _ = bm.tree(hm, "Post")
        self.assertEqual((t["matches"], t["rows"], t["capped"]), (0, [], True))
        self.assertEqual(B.tree_lines(t)[1], "tree|Post|0|0|0|30|1|0")
        # (the walk under it cut too: said)
        B.WIN_CAP = 20
        t, _ = bm.tree(hm, "Target")
        self.assertEqual((t["matches"], t["capped"], len(t["rows"])), (1, True, 20))

    def test_hidden_windows_not_walked(self):
        B.WIN_CAP = 30
        # (a closed window's 40 windows before the one asked for: shown only, they aren't read - nothing cut)
        wd, hm, _a = self.world([("Closed", 40, False), ("Target", 5, True)])
        bm = reader(wd)
        t, _ = bm.tree(hm, "Target")
        self.assertEqual((t["matches"], t["capped"], len(t["rows"])), (1, False, 6))
        t, _ = bm.tree(hm)
        self.assertEqual((t["walked"], t["capped"], len(t["rows"])), (1 + 1 + 1 + 5, False, 7))
        t, _ = bm.tree(hm, "Target", shown_only=False)     # (all: they're read - finding it stops in them)
        self.assertEqual((t["matches"], t["capped"]), (0, True))

    def chain(self, n):
        """the root -> level1 -> level2 ... -> level<n>, each one shown"""
        wd, a = World(), {}
        kid = []
        for i in range(n, 0, -1):
            a[i] = wd.window("level%d" % i, rect=(1, 1, 50, 50), kids=kid)
            kid = [a[i]]
        a[0] = wd.window("", rect=(0, 0, 1827, 1027), kids=kid, flags=0x11)
        return wd, types.SimpleNamespace(root=lambda: a[0], lang_text=lambda k: None, st=wd), a

    def test_depth_below_the_window_and_said(self):
        wd, hm, _a = self.chain(30)
        bm = reader(wd)
        # (under a window the depth counts from it: level20's 10 levels all there)
        t, _ = bm.tree(hm, "level20")
        self.assertEqual(([r["name"] for r in t["rows"]][-1], len(t["rows"]), t["capped"]), ("level30", 11, False))
        self.assertEqual(t["rows"][-1]["depth"], 10)
        self.assertEqual(t["rows"][-1]["rect"], (30, 30, 79, 79))
        # (the whole tree: TREE_DEPTH levels - the deeper ones left out, said)
        t, _ = bm.tree(hm)
        self.assertEqual((len(t["rows"]), t["rows"][-1]["name"], t["capped"]), (B.TREE_DEPTH + 1, "level24", True))
        # (a depth asked for isn't a cut)
        t, _ = bm.tree(hm, depth=5)
        self.assertEqual((len(t["rows"]), t["rows"][-1]["name"], t["capped"]), (6, "level5", False))
        t, _ = bm.tree(hm, "level3", depth=0)
        self.assertEqual(([r["name"] for r in t["rows"]], t["capped"]), (["level3"], False))
        # (deeper than finding it goes: not found - said to be cut)
        t, _ = bm.tree(hm, "level28")
        self.assertEqual((t["matches"], t["rows"], t["capped"]), (0, [], True))

    def test_shown_kept_from_above(self):
        # (a window VISIBLE itself in a hidden one: hidden - its walk starts from it, its ancestors' state kept)
        wd, a = World(), {}
        a["leaf"] = wd.window("leaf")
        a["inner"] = wd.window("inner", kids=[a["leaf"]])
        a["outer"] = wd.window("outer", shown=False, kids=[a["inner"]])
        a["root"] = wd.window("", rect=(0, 0, 1827, 1027), kids=[a["outer"]], flags=0x11)
        hm = types.SimpleNamespace(root=lambda: a["root"], lang_text=lambda k: None, st=wd)
        bm = reader(wd)
        t, _ = bm.tree(hm, "inner", shown_only=False)
        self.assertEqual([(r["name"], r["shown"], r["depth"], r["parent"]) for r in t["rows"]],
                         [("inner", False, 0, 0), ("leaf", False, 1, 1)])
        t, _ = bm.tree(hm, "inner")
        self.assertEqual((t["matches"], t["dups"], t["rows"], t["capped"]), (0, 0, [], False))   # (in a hidden one)


class FakeNav:
    """navmem.NavMem as nav_tree uses it: _bag_readers, lock, st, close"""

    def __init__(self, wd, hm, bm, why=""):
        self.wd, self.hm, self.bm, self.why = wd, hm, bm, why
        self.st = wd
        self.lock = threading.RLock()
        self.closed = False

    def _bag_readers(self, wait):
        if self.why:
            return None, None, None, self.why
        return self.wd, self.bm, self.hm, ""

    def close(self):
        self.closed = True


class Nav(unittest.TestCase):
    def setUp(self):
        self.wd, self.hm, self.a = battle_world()
        self.bm = reader(self.wd)

    def test_nav_tree(self):
        t, why = B.nav_tree(FakeNav(self.wd, self.hm, self.bm), "SpellSelectionWindow/passButton")
        self.assertEqual(why, "")
        self.assertEqual([(r["name"], r["text"], r["key"]) for r in t["rows"]], [("passButton", "Pass", "CombatPass")])
        self.assertEqual(B.nav_tree(FakeNav(self.wd, self.hm, self.bm, why="the game is not running")),
                         (None, "the game is not running"))
        nv = FakeNav(self.wd, self.hm, self.bm)
        nv.st = object()                           # (the game changed between the readers and the lock)
        self.assertEqual(B.nav_tree(nv), (None, "the game changed"))
        nv = FakeNav(self.wd, self.hm, self.bm)
        nv._bag_readers = None                     # (anything thrown: never into the server)
        t, why = B.nav_tree(nv)
        self.assertIsNone(t)
        self.assertIn("window tree failed", why)

    def test_command_line_out(self):
        nv = FakeNav(self.wd, self.hm, self.bm)
        N = B.N
        old_nm, old_argv = N.NavMem, sys.argv
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "tree.txt")
            try:
                N.NavMem = lambda log=None: nv
                sys.argv = ["bagmem.py", "--tree", "--under", "CombatPlanningPhaseWindow", "--indent", "--out", out]
                buf = io.StringIO()
                with redirect_stdout(buf):
                    B._main()
            finally:
                N.NavMem, sys.argv = old_nm, old_argv
            with open(out, encoding="utf-8") as f:
                lines = f.read().splitlines()
        self.assertTrue(nv.closed)
        self.assertTrue(lines[0].startswith("# python bagmem.py --tree --under CombatPlanningPhaseWindow ("))
        self.assertEqual(lines[1], "root|1827|1027")
        self.assertEqual(lines[2].split("|")[:3], ["tree", "CombatPlanningPhaseWindow", "2"])
        self.assertEqual(lines[5].split("|")[1], "    passButton")
        self.assertIn("written to", buf.getvalue())


class Route(unittest.TestCase):
    """the vision helper's /guitree on a local server (127.0.0.1, any free port), its game reader the made-up one"""

    def test_guitree(self):
        try:
            import vision as V
        except ImportError as e:                   # (numpy / Pillow: the helper's own needs)
            self.skipTest("vision.py can't be imported here (%s)" % e)
        import urllib.error
        import urllib.request
        from http.server import ThreadingHTTPServer
        wd, hm, _a = battle_world()
        bm = reader(wd)
        keep = (V.nav_reader, V.LOG)
        with tempfile.TemporaryDirectory() as d:
            V.nav_reader, V.LOG = (lambda: FakeNav(wd, hm, bm)), os.path.join(d, "vision.log")
            srv = ThreadingHTTPServer(("127.0.0.1", 0), V.Handler)
            th = threading.Thread(target=srv.serve_forever, daemon=True)
            th.start()
            try:
                def get(path):
                    try:
                        with urllib.request.urlopen("http://127.0.0.1:%d%s" % (srv.server_address[1], path), timeout=5) as r:
                            return r.status, r.read().decode().split("\n")
                    except urllib.error.HTTPError as e:
                        return e.code, e.read().decode().split("\n")
                code, ln = get("/guitree?under=CombatPlanningPhaseWindow%2FSpellSelectionWindow&all=1&depth=1")
                self.assertEqual(code, 200)
                self.assertEqual(ln[:2], ["root|1827|1027", "tree|CombatPlanningPhaseWindow/SpellSelectionWindow|1|1|7|21|0|1"])
                self.assertIn("1|drawButton|ControlButton|0|335|726|435|766|Draw||0|||1|1|0", ln)
                code, ln = get("/guitree")
                self.assertEqual((code, ln[1]), (200, "tree||1|1|10|12|0|0"))
                code, ln = get("/guitree?under=a,b")
                self.assertEqual(code, 400)
                self.assertTrue(ln[0].startswith("ERR under:"))
            finally:
                srv.shutdown()
                srv.server_close()
                V.nav_reader, V.LOG = keep
        self.assertIn("/guitree", V.GATED)
        self.assertEqual(V.GATE.n, 0)              # (every gated request left the gate)


if __name__ == "__main__":
    unittest.main()
