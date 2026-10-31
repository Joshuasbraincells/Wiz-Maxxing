"""test_handmem_boxes.py - the hand's card boxes in the GUI's root (handmem: windows' way down, hand_offset, box_in_root,
/cards' fields 26-29 and root| line) and the cheap round phase (HandMem.phase, phase_state, phase_line, nav_phase) on a
made-up window tree - no game, no Windows (navmem stood in for while handmem is imported, then taken out again):
python3 -m unittest test_handmem_boxes   (from AutoFarmer\\vision)"""
import os
import sys
import threading
import types
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def import_handmem():
    """handmem with navmem as it is: the real one when it's imported already (Windows, or test_navroute's import), else a
    stand-in put in sys.modules for the import only (its ctypes.WinDLL can't load here). sys.modules is left as it was
    found - the stand-in taken out, handmem too when it wasn't there, another test file's stand-in handmem
    (test_navroute's import_bossmem) put back - so no other test file meets either; this file keeps its own handmem"""
    saved = {k: sys.modules.get(k) for k in ("navmem", "handmem")}
    real = saved["handmem"]
    if real is not None and getattr(real, "__file__", None) and hasattr(real, "phase_state"):
        return real
    try:
        if saved["navmem"] is None:
            nav = types.ModuleType("navmem")
            nav.ptr_ok = lambda v: 0x10000 <= v < 0x7FFFFFFF0000
            nav.ReadError = type("ReadError", (Exception,), {})
            nav.DATA, nav.KNOWN, nav.SIGS = {"window_name": 0x50}, {}, {}
            sys.modules["navmem"] = nav
        sys.modules.pop("handmem", None)
        import handmem
        return handmem
    finally:
        for k, v in saved.items():
            if v is None:
                sys.modules.pop(k, None)
            else:
                sys.modules[k] = v


H = import_handmem()

# made-up windows (any address navmem.ptr_ok takes) and vtables
ROOT, WV, PP, BOX, SS, HAND, C1, C2, C3, PET, OLD = (0x20000000 + 0x1000 * i for i in range(11))
VT = {"pp": 0x7FF600000010, "ss": 0x7FF600000020, "card": 0x7FF600000030, "other": 0x7FF600000040}
PART, G1, G2, G3 = 0x30000000, 0x31000000, 0x31001000, 0x31002000


def fake_hand(cards_shown=(C1, C2, C3), pet=False, planning=True, in_battle=True, items=None, size=None):
    """a HandMem made without the game: its window tree, rects, names, flags and vtables from dicts; the spell, me and
    participant readers stood in for"""
    hm = object.__new__(H.HandMem)
    hm.log = lambda msg: None
    hm.o, hm.how, hm._cand, hm._prov, hm._next_scan, hm.win = {}, {}, {}, {}, {}, {}
    hm.school_of_id = dict(H.SCHOOL_IDS)
    hm.build = H.HAND_BUILD
    hm.vt = {"CombatPlanningPhaseWindow": {VT["pp"]}, "SpellSelectionWindow": {VT["ss"]}, "SpellCheckBox": {VT["card"]},
             "GraphicalSpell": set(), "Spell": set(), "ClientCombatParticipant": set()}
    kids = {ROOT: [WV], WV: [PP], PP: [BOX], BOX: [SS], SS: [HAND], HAND: [OLD, C1, C2, C3, PET]}
    rects = {ROOT: (0, 0, 1827, 1027), WV: (0, 0, 1827, 1027), PP: (100, 600, 1700, 1000), BOX: (10, 20, 1500, 400),
             SS: (50, 100, 1400, 300), HAND: (300, 30, 1000, 200),
             # (Card1 is the rightmost - windows are reused, the name is no place)
             C1: (534, 0, 601, 100), C2: (467, 0, 534, 100), C3: (400, 0, 467, 100), PET: (333, 0, 400, 100),
             OLD: (200, 0, 267, 100)}
    names = {HAND: "Hand", C1: "Card1", C2: "Card2", C3: "Card3", PET: "PetCard", OLD: "Card4"}
    vts = {PP: VT["pp"], SS: VT["ss"], C1: VT["card"], C2: VT["card"], C3: VT["card"], PET: VT["card"], OLD: VT["card"]}
    shown = set(cards_shown) | ({PET} if pet else set())
    flags = {PP: 1 if planning else 0}
    flags.update({w: 1 for w in shown})
    hm.kids = lambda w: list(kids.get(w, []))
    hm.rect = lambda w: rects.get(w)
    hm.wname = lambda w: names.get(w, "")
    hm.flags = lambda w: flags.get(w, 0)
    hm._vt = lambda w: vts.get(w, VT["other"])
    hm.root = lambda: ROOT
    hm.participant = lambda ss: (PART if in_battle else 0, None)
    spells = {C1: G1, C2: G2, C3: G3, PET: 0x31003000}
    own = [spells[w] for w in (C1, C2, C3) if w in shown]
    lst = list(own) if items is None else items
    hm.card_spell = lambda w: spells.get(w, 0)
    hm.spell = lambda g: {"template_id": g & 0xFFFF, "name": "Spell%x" % (g & 0xFFFF), "display": "Spell", "school": "Fire",
                          "type": "Damage", "effects": [], "pips": 2, "x_pips": False, "shadow_pips": 0,
                          "school_pips": {}, "accuracy": 75, "treasure": False, "item_card": False, "enchantment_id": 0}
    hm.hand_list = lambda c: (lst, len(lst) if size is None else size)
    hm.me = lambda c: ({"owner": 1, "school_id": 2343174, "school": "fire", "health": 500, "max_health": 600,
                        "pips": {"generic": 3, "power": 0}}, ) + hm.hand_list(c)
    hm.rects = rects
    return hm


class Boxes(unittest.TestCase):
    """the cards' places in the root: each card's m_Window plus every window's left / top on the way down from the root"""

    def test_windows_keeps_the_way_down(self):
        hm = fake_hand()
        self.assertEqual(hm.windows(), (PP, SS, HAND))
        self.assertEqual(hm.win["chain"], [ROOT, WV, PP, BOX, SS, HAND])
        self.assertEqual(hm.win["root"], ROOT)
        # (kept: the second call finds them by their checks, the way down still there)
        self.assertEqual(hm.windows(), (PP, SS, HAND))
        self.assertEqual(hm.win["chain"], [ROOT, WV, PP, BOX, SS, HAND])

    def test_hand_offset_adds_every_window_below_the_root(self):
        hm = fake_hand()
        hm.windows()
        # (WV 0,0 + PP 100,600 + BOX 10,20 + SS 50,100 + HAND 300,30 - the root's own left / top not added)
        self.assertEqual(hm.hand_offset(), (460, 750))
        self.assertEqual(hm.root_size(), (1827, 1027))

    def test_hand_offset_none_when_a_window_isnt_read(self):
        hm = fake_hand()
        hm.windows()
        del hm.rects[BOX]
        self.assertIsNone(hm.hand_offset())
        self.assertIsNone(object.__new__(H.HandMem).__dict__.get("win"))      # (sanity: a bare one has no windows)
        hm2 = fake_hand()
        hm2.win = {}
        self.assertIsNone(hm2.hand_offset())

    def test_box_in_root_pure(self):
        self.assertEqual(H.box_in_root((400, 0, 467, 100), (460, 750)), (860, 750, 927, 850))
        self.assertIsNone(H.box_in_root(None, (1, 2)))
        self.assertIsNone(H.box_in_root((1, 2, 3, 4), None))
        self.assertIsNone(H.box_in_root((10, 0, 10, 5), (0, 0)))              # (empty)
        self.assertIsNone(H.box_in_root((10, 9, 20, 5), (0, 0)))              # (inside out)
        self.assertEqual(H.offset_of([(1, 2, 9, 9), (10, 20, 99, 99)]), (11, 22))
        self.assertIsNone(H.offset_of([]))
        self.assertIsNone(H.offset_of([(1, 2, 3, 4), None]))
        self.assertEqual(H.size_of((0, 0, 1827, 1027)), (1827, 1027))
        self.assertIsNone(H.size_of((0, 0, 0, 1027)))
        self.assertIsNone(H.size_of((0, 0, 30000, 10)))
        self.assertIsNone(H.size_of(None))

    def test_read_gives_each_card_its_box_and_the_root(self):
        r = fake_hand().read()
        self.assertEqual(r["state"], "hand", r["why"])
        self.assertEqual(r["root"], (1827, 1027))
        # (left to right on screen: Card3, Card2, Card1)
        self.assertEqual([c["slot"] for c in r["cards"]], ["Card3", "Card2", "Card1"])
        self.assertEqual([c["box"] for c in r["cards"]], [(860, 750, 927, 850), (927, 750, 994, 850), (994, 750, 1061, 850)])

    def test_answer_fields_26_to_29_and_the_root_line(self):
        r = fake_hand(pet=True).read()
        lines = H.answer(r).split("\n")
        self.assertTrue(lines[0].startswith("me|"))
        cards = [ln.split("|") for ln in lines if ln.startswith("card|")]
        self.assertEqual(len(cards), 4)
        for f in cards:
            self.assertEqual(len(f), 29)                  # (29 fields, "card" the first - AutoFarmer counts from 1)
        self.assertEqual([f[1] for f in cards], ["PetCard", "Card3", "Card2", "Card1"])
        self.assertEqual(cards[0][25:29], ["793", "750", "860", "850"])     # (fields 26-29)
        self.assertEqual(cards[3][25:29], ["994", "750", "1061", "850"])
        # (the old fields where they were: x the left edge in the hand's units, 25 the boosts)
        self.assertEqual(cards[1][2], "400")
        self.assertIn("root|1827|1027", lines)
        self.assertTrue(lines[-1].startswith("hand|4|"))
        self.assertEqual(lines.index("root|1827|1027"), len(lines) - 2)

    def test_answer_without_boxes_keeps_29_fields_and_no_root_line(self):
        r = {"in_battle": True, "planning": True, "settled": True, "me": {}, "ms": 1.0,
             "cards": [{"slot": "Card1", "x": 5, "name": "Fire Cat"}]}
        lines = H.answer(r).split("\n")
        f = lines[1].split("|")
        self.assertEqual(len(f), 29)
        self.assertEqual(f[25:29], ["", "", "", ""])
        self.assertFalse(any(ln.startswith("root|") for ln in lines))
        self.assertEqual(H.answer(None, "the game is not running"), "none|the game is not running")


class Phase(unittest.TestCase):
    """the round's phase without reading a spell"""

    def test_phase_state_rules(self):
        S = H.phase_state
        self.assertEqual(S(False, False, False, None, None, None, None)[0], "none")
        self.assertEqual(S(True, False, True, None, None, None, None), ("none", "not in a battle"))
        self.assertEqual(S(True, True, False, None, None, None, None)[0], "round")
        self.assertEqual(S(True, True, True, 0, 0, 3, 3)[0], "waiting")
        self.assertEqual(S(True, True, True, 0, 0, 0, 0), ("hand", ""))      # (an empty hand: the deck used up)
        self.assertEqual(S(True, True, True, 0, 0, None, None)[0], "changing")
        self.assertEqual(S(True, True, True, 3, 3, 3, 3), ("hand", ""))
        self.assertEqual(S(True, True, True, 4, 3, 3, 3), ("hand", ""))      # (the pet's card besides)
        self.assertEqual(S(True, True, True, 2, 2, 3, 3)[0], "changing")
        self.assertEqual(S(True, True, True, 3, 3, 3, 4)[0], "changing")
        self.assertEqual(S(True, True, True, 3, 3, None, 3)[0], "changing")

    def test_phase_on_the_made_up_hand(self):
        p = fake_hand(pet=True).phase()
        self.assertEqual((p["state"], p["in_battle"], p["planning"], p["shown"], p["own"], p["size"]),
                         ("hand", True, True, 4, 3, 3))
        p = fake_hand(cards_shown=(), items=[G1, G2]).phase()
        self.assertEqual((p["state"], p["shown"], p["size"]), ("waiting", 0, 2))
        p = fake_hand(cards_shown=(C1, C2), items=[G1, G2, G3]).phase()
        self.assertEqual(p["state"], "changing")
        p = fake_hand(planning=False).phase()
        self.assertEqual((p["state"], p["shown"], p["size"]), ("round", None, None))
        p = fake_hand(in_battle=False).phase()
        self.assertEqual((p["state"], p["why"]), ("none", "not in a battle"))
        self.assertIn("ms", p)

    def test_phase_never_raises(self):
        hm = fake_hand()

        def boom(w):
            raise RuntimeError("torn read")
        hm.kids = boom
        p = hm.phase()
        self.assertEqual(p["state"], "none")
        self.assertIn("couldn't be read", p["why"])

    def test_phase_line(self):
        p = {"state": "waiting", "in_battle": True, "planning": True, "shown": 0, "own": 0, "size": 3, "ms": 0.4,
             "why": "planning, no card shown - a card's chosen, waiting for the round"}
        self.assertEqual(H.phase_line(p), "phase|waiting|1|1|0|0|3|0.4|planning, no card shown - a card's chosen, "
                                          "waiting for the round")
        self.assertEqual(H.phase_line({"state": "none", "in_battle": False, "planning": False, "shown": None, "own": None,
                                       "size": None, "ms": 0.1, "why": "a|b"}), "phase|none|0|0||||0.1|a/b")
        self.assertEqual(H.phase_line(None, "the game is not running"), "none|the game is not running")
        self.assertEqual(H.phase_line(None), "none|the game can't be read")

    def test_nav_phase_through_a_made_up_navmem(self):
        hm = fake_hand()
        st = object()
        hm.st = st
        nm = types.SimpleNamespace(lock=threading.Lock(), _ensure=lambda wait: (st, ""),
                                   _hand_reader=lambda s, wait: (hm, "") if s is st else (None, "?"))
        p, why = H.nav_phase(nm)
        self.assertEqual((p["state"], why), ("hand", ""))
        nm2 = types.SimpleNamespace(lock=threading.Lock(), _ensure=lambda wait: (None, "the game is not running"))
        self.assertEqual(H.nav_phase(nm2), (None, "the game is not running"))
        nm3 = types.SimpleNamespace(lock=threading.Lock(), _ensure=lambda wait: (None, "a signature isn't there"),
                                    _cards_light=lambda why: (None, why + "; no light"))
        self.assertEqual(H.nav_phase(nm3), (None, "a signature isn't there; no light"))
        nm4 = types.SimpleNamespace(lock=threading.Lock(), _ensure=lambda wait: (st, ""),
                                    _hand_reader=lambda s, wait: (None, "reading the game's card classes"))
        self.assertEqual(H.nav_phase(nm4), (None, "reading the game's card classes"))
        other = fake_hand()
        other.st = object()
        nm5 = types.SimpleNamespace(lock=threading.Lock(), _ensure=lambda wait: (st, ""),
                                    _hand_reader=lambda s, wait: (other, ""))
        self.assertEqual(H.nav_phase(nm5), (None, "the game changed"))

        def boom(wait):
            raise RuntimeError("x")
        p, why = H.nav_phase(types.SimpleNamespace(lock=threading.Lock(), _ensure=boom))
        self.assertIsNone(p)
        self.assertIn("failed", why)


if __name__ == "__main__":
    unittest.main()
