"""test_book.py - the spellbook's reading for /book (deckmem.py book_lines and read(books=True), navmem.py deck(books=True)
and its own cache, vision.py book_answer) on made-up readings - navmem / deckmem stood in for or imported with their
Windows parts stood in for (put back afterwards: no other test file meets them):
    python -m unittest test_book   (from AutoFarmer\\vision)"""
import os
import sys
import types
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spellplan  # noqa: E402   (pure: reads the answer back)


def import_deckmem():
    """deckmem with navmem as it is: the real one when it's imported already (Windows, or test_navroute's import), else a
    stand-in put in sys.modules for the import only (its ctypes.WinDLL can't load here). sys.modules is left as it was
    found - deckmem too when it wasn't there"""
    saved = {k: sys.modules.get(k) for k in ("navmem", "deckmem")}
    real = saved["deckmem"]
    if real is not None and getattr(real, "__file__", None) and hasattr(real, "book_lines"):
        return real
    try:
        if saved["navmem"] is None:
            nav = types.ModuleType("navmem")
            nav.ptr_ok = lambda v: 0x10000 <= v < 0x7FFFFFFF0000
            nav.ReadError = type("ReadError", (Exception,), {})
            sys.modules["navmem"] = nav
        sys.modules.pop("deckmem", None)
        import deckmem
        return deckmem
    finally:
        for k, v in saved.items():
            if v is None:
                sys.modules.pop(k, None)
            else:
                sys.modules[k] = v


D = import_deckmem()

READING = {"spellbook": [{"template_id": 1001, "retired": False, "tier_group": 0, "name": "Storm-Thunder Snake",
                          "display": "Thunder Snake", "school": "Storm", "type": "Damage", "pips": 1, "x_pips": False,
                          "kind": "damage", "value_text": "125-165"},
                         {"template_id": 1002, "retired": None, "tier_group": None, "name": "Ice|Tower\nShield",
                          "display": None, "school": "Ice", "type": "Ward", "pips": 0, "x_pips": None}],
           "treasure_book": [{"template_id": 2001, "count": 3, "name": "TC-Fire-Elf", "display": "Fire Elf",
                              "school": "Fire", "type": "Damage", "pips": 1}],
           "player_gid": 0x8A3F00001, "ms": 42.5, "why": "no deck worn"}


class BookLines(unittest.TestCase):
    def test_lines(self):
        self.assertEqual(D.book_lines(READING), [
            "book|1001|Storm-Thunder Snake|Thunder Snake|Storm|Damage|1|0|0|0|damage|125-165",
            "book|1002|Ice/Tower Shield||Ice|Ward|0|||||",
            "tcbook|2001|3|TC-Fire-Elf|Fire Elf|Fire|Damage|1||",
            "books|2|1|8a3f00001|42.5|no deck worn"])

    def test_not_read(self):
        self.assertEqual(D.book_lines({"decks": [], "why": "no GameClient yet"}), ["none|no GameClient yet"])
        self.assertEqual(D.book_lines({}), ["none|the books weren't read (read(books=True))"])
        self.assertEqual(D.book_lines({"spellbook": None, "treasure_book": [], "why": ""}),
                         ["books||0|||the spellbook couldn't be read"])
        self.assertEqual(D.book_lines({"spellbook": [], "treasure_book": None, "why": "x"})[-1],
                         "books|0||||the treasure book couldn't be read; x")

    def test_read_back(self):
        b = spellplan.parse_book("\n".join(D.book_lines(READING)))
        self.assertEqual([(e["template_id"], e["display"], e["kind"]) for e in b["spells"]],
                         [(1001, "Thunder Snake", "damage"), (1002, "", None)])
        self.assertEqual((b["n"], b["tc_n"], b["player_gid"]), (2, 1, "8a3f00001"))


PROPS = {"CoreObject": {"m_inactiveBehaviors": 0xE0, "m_globalID.m_full": 0x48, "m_templateID.m_full": 0x50},
         "InventoryBehaviorBase": {"m_itemList": 0x70}, "ClientEquipmentBehavior": {"m_itemList": 0x78},
         "DeckBehavior": {"m_spellList": 0x78}, "SpellData": {"m_templateID": 0x48, "m_quantity": 0x50},
         "GameObjectTemplate": {"m_objectName": 0x60}}


class FakeDeckMem(D.DeckMem):
    """DeckMem's _read on made-up books: the wizard (gid 0x77), its behaviors, no item worn"""
    CO, EQ, SB, TB = 0x100000, 0x200000, 0x300000, 0x400000

    def __init__(self):
        st = types.SimpleNamespace(p=None, m=types.SimpleNamespace(build="test"))
        super().__init__(st, hm=None, props=PROPS)
        self.asked = []

    def player(self):
        return self.CO, ""

    def u64(self, a):
        return 0x77 if a == self.CO + 0x48 else 0

    def behaviors(self, obj):
        return {"ClientWizEquipmentBehavior": self.EQ, "ClientSpellbookBehavior": self.SB,
                "ClientTreasureBookBehavior": self.TB} if obj == self.CO else {}

    def spellbook(self, sb):
        return [{"template_id": 1001, "retired": False, "tier_group": 0}, {"template_id": None, "retired": None,
                                                                            "tier_group": None}]

    def treasure_book(self, tb):
        return [{"template_id": 2001, "count": 3}]

    def brief(self, tid):
        self.asked.append(("brief", tid))
        return {"template_id": tid, "name": "N%d" % tid, "display": "D%d" % tid, "school": "Storm", "type": "Damage",
                "pips": 2, "x_pips": False, "max_copies": 4, "tc_flag": False}

    def card(self, tid):
        self.asked.append(("card", tid))
        return dict(self.brief(tid), kind="damage", value=150, value_text="125-175")

    def items(self, beh, prop_cls, cap):
        return 0, []


class ReadBooks(unittest.TestCase):
    def test_books_named_by_brief(self):
        dm = FakeDeckMem()
        r = dm.read(books=True, kinds=False, only_equipped=True)
        self.assertEqual(r["player_gid"], 0x77)
        self.assertEqual(r["spellbook"][0], {"template_id": 1001, "retired": False, "tier_group": 0, "name": "N1001",
                                             "display": "D1001", "school": "Storm", "type": "Damage", "pips": 2,
                                             "x_pips": False})
        # (a template id not read: kept, nothing looked up for it - its names empty)
        self.assertEqual((r["spellbook"][1]["template_id"], r["spellbook"][1]["name"]), (None, None))
        self.assertNotIn(("brief", None), dm.asked)
        self.assertEqual(r["treasure_book"][0]["count"], 3)
        self.assertNotIn(("card", 1001), dm.asked)
        self.assertEqual((r["spellbook_n"], r["treasure_book_n"]), (2, 1))
        self.assertIn("no deck worn", r["why"])
        self.assertEqual(D.book_lines(r)[-1].split("|")[:4], ["books", "2", "1", "77"])

    def test_kinds_by_card(self):
        dm = FakeDeckMem()
        r = dm.read(books=True, kinds=True, only_equipped=True)
        self.assertEqual((r["spellbook"][0]["kind"], r["spellbook"][0]["value_text"]), ("damage", "125-175"))
        self.assertNotIn("value", r["spellbook"][0])          # (only BOOK_KEYS and kind, value_text)
        self.assertIn(("card", 2001), dm.asked)

    def test_without_books_no_book_and_the_gid_still_there(self):
        r = FakeDeckMem().read(books=False, kinds=False, only_equipped=True)
        self.assertNotIn("spellbook", r)
        self.assertEqual(r["player_gid"], 0x77)
        self.assertEqual(D.book_lines(r)[0][:5], "none|")


class NavDeckBooks(unittest.TestCase):
    """navmem.NavMem.deck(books=True): its own cache, never answered by the worn deck's signature, the decks' cache left
    as it was (the real navmem, its Windows DLLs stood in for - test_navroute's import)"""

    @classmethod
    def setUpClass(cls):
        from test_navroute import import_navmem
        cls.N = import_navmem()

    def nav(self, sig=("S",), spellbook=True):
        nm = self.N.NavMem(log=lambda m: None)
        st = object()
        reads = []

        class DM:
            def signature(self_, pace=None):
                return sig

            def read(self_, books=False, kinds=True, only_equipped=False, pace=None):
                reads.append((books, kinds, only_equipped))
                r = {"decks": [{"gid": 1}], "why": ""}
                if books:
                    r.update(spellbook=[{"template_id": 5}] if spellbook else None, treasure_book=[])
                return r
        dm = DM()
        dm.st, dm.hm = st, nm._hand
        nm.st = st
        nm._deck_readers = lambda wait: (st, dm, "")
        return nm, st, reads

    def test_books_read_even_when_the_deck_is_the_same(self):
        nm, st, reads = self.nav()
        decks = {"st": st, "r": {"decks": [{"gid": 1}], "kinds": "yes"}, "sig": ("S",), "read_at": 1.0, "all": True,
                 "kinds": True}
        nm._deck_cache = decks
        # (no books: the signature answers - the decks' reading as it was)
        r, why = nm.deck(fresh=True)
        self.assertEqual((r["kinds"], reads), ("yes", []))
        r, why = nm.deck(fresh=True, books=True)
        self.assertEqual(why, "")
        self.assertEqual(r["spellbook"], [{"template_id": 5}])
        self.assertEqual(reads, [(True, False, True)])
        self.assertIs(nm._deck_cache, decks)                         # (the decks' cache untouched)
        self.assertEqual(nm._book_cache["r"]["spellbook"], [{"template_id": 5}])
        # (asked again: read again - never the signature's)
        nm.deck(fresh=True, books=True)
        self.assertEqual(len(reads), 2)
        # (fresh 0: each its own last reading)
        self.assertEqual(nm.deck(books=True)[0]["spellbook"], [{"template_id": 5}])
        self.assertNotIn("spellbook", nm.deck()[0])
        self.assertEqual(nm.deck(books=True, kinds=True), (None, "not read yet"))   # (read without kinds)

    def test_a_book_not_read_isnt_kept(self):
        nm, st, reads = self.nav(spellbook=False)
        r, why = nm.deck(fresh=True, books=True)
        self.assertIsNone(r["spellbook"])
        self.assertIsNone(nm._book_cache)
        self.assertEqual(nm.deck(books=True), (None, "not read yet"))
        self.assertIsNone(nm._deck_cache)                           # (a book read never fills the decks' cache)


class BookAnswer(unittest.TestCase):
    """vision.py's /book: refused fresh when a battle can't be ruled out, its lines and its age"""

    def setUp(self):
        import vision as V
        self.V = V
        self.keep = (V.nav_reader, V.REC, sys.modules.get("deckmem"))
        sys.modules["deckmem"] = D

    def tearDown(self):
        V = self.V
        V.nav_reader, V.REC, had = self.keep
        if had is None:
            sys.modules.pop("deckmem", None)
        else:
            sys.modules["deckmem"] = had

    def test_answer(self):
        V = self.V
        asked = []

        class Nav:
            def deck(self, **kw):
                asked.append(kw)
                return dict(READING, read_at=None), ""
        V.nav_reader = lambda: Nav()
        V.REC = None
        self.assertEqual(V.book_answer(True), ["none|the battle recorder isn't following the game's log (a battle "
                                               "can't be ruled out)"])
        self.assertEqual(asked, [])
        lines = V.book_answer(True, out=True)
        self.assertEqual(lines[0], "book|1001|Storm-Thunder Snake|Thunder Snake|Storm|Damage|1|0|0|0|damage|125-165")
        self.assertEqual(lines[-1], "bookage|0.0")
        kw = asked[-1]
        self.assertEqual((kw["fresh"], kw["books"], kw["only_equipped"], kw["kinds"]), (True, True, True, False))
        V.book_answer(False, kinds=True)
        self.assertEqual((asked[-1]["fresh"], asked[-1]["kinds"], asked[-1]["stop"]), (False, True, None))

    def test_not_read(self):
        V = self.V

        class Nav:
            def deck(self, **kw):
                return None, "not read|yet"
        V.nav_reader = lambda: Nav()
        V.REC = None
        self.assertEqual(V.book_answer(False), ["none|not read yet"])

    def test_gated(self):
        self.assertTrue({"/book", "/quests", "/deck", "/goal"} <= self.V.GATED)


if __name__ == "__main__":
    unittest.main()
