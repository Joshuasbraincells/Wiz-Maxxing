"""test_book.py - the spellbook's reading for /book (deckmem.py book_lines and read(books=True), navmem.py deck(books=True)
and its own cache, a worn-deck reading never taking every deck's place, one fresh deck read at a time, vision.py
book_answer and decks_reading with the battle recorder off) on made-up readings - navmem / deckmem stood in for or
imported with their Windows parts stood in for (put back afterwards: no other test file meets them):
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


class WornReadKeepsEveryDeck(unittest.TestCase):
    """navmem.NavMem.deck: the recorder's worn-deck reading (only_equipped, no kinds - after an Equipment Set is put on)
    never takes the place of every deck's with their kinds (_deck_all): /deckfor, /sim and /plan still answered from it,
    the decks worn marked as the newer reading has them - deckzone put its zone's deck on, the recorder read it, /deckfor
    answered "not read yet" and DeckPick's set went back on (the real navmem, test_navroute's import)"""

    @classmethod
    def setUpClass(cls):
        from test_navroute import import_navmem
        cls.N = import_navmem()

    def nav(self):
        nm = self.N.NavMem(log=lambda m: None)
        st = types.SimpleNamespace(close=lambda: None)
        worn = [0xA1]
        reads = []
        cards = {0xA1: [{"template_id": 7, "count": 3, "side": "main"}, {"template_id": 9, "count": 2, "side": "treasure"}],
                 0xB2: [{"template_id": 8, "count": 4, "side": "main"}]}
        self.who, self.unread = [0x77], set()           # (the wizard's gid; decks whose card list won't read)

        class DM:
            def signature(self_, pace=None):
                return ("worn", self.who[0], worn[0], repr(cards[worn[0]]), worn[0] in self.unread)

            def read(self_, books=False, kinds=True, only_equipped=False, pace=None):
                reads.append((kinds, only_equipped))
                decks = [{"gid": g, "where": "equipped" if g == worn[0] else "backpack", "equipped": g == worn[0],
                          "sets": [n], "kinds": kinds, "cards": [] if g in self.unread else [dict(c) for c in cards[g]],
                          "ok": g not in self.unread} for n, g in enumerate(sorted(cards), 1)]
                if only_equipped:
                    decks = [d for d in decks if d["equipped"]]
                return {"decks": decks, "equipped": worn[0], "equipped_set": 1 if worn[0] == 0xA1 else 2,
                        "sets": [{"n": 1, "equipped": worn[0] == 0xA1}, {"n": 2, "equipped": worn[0] == 0xB2}],
                        "player_gid": self.who[0], "why": ""}
        dm = DM()
        dm.st, dm.hm = st, nm._hand
        nm.st = st
        nm._deck_readers = lambda wait: (st, dm, "")
        return nm, worn, reads, cards

    def test_every_deck_kept_through_a_worn_read(self):
        nm, worn, reads, cards = self.nav()
        # (DeckLearnGame's /decks?fresh=1: every deck with their kinds)
        r, why = nm.deck(fresh=True, only_equipped=False, kinds=True)
        self.assertEqual((len(r["decks"]), why), (2, ""))
        everyd = nm._deck_all
        self.assertIs(everyd, nm._deck_cache)
        # (deckzone's set 2 put on: the recorder's worn-deck read)
        worn[0] = 0xB2
        r, why = nm.deck(fresh=True)
        self.assertEqual([d["gid"] for d in r["decks"]], [0xB2])
        self.assertFalse(nm._deck_cache["all"])
        self.assertIs(nm._deck_all, everyd)
        # (/deckfor's, /plan's, /sim's ask: every deck still - B worn now, A in the backpack; no signature)
        r, why = nm.deck(only_equipped=False, kinds=True)
        self.assertEqual(why, "")
        self.assertEqual([(d["gid"], d["equipped"], d["where"], d["kinds"]) for d in r["decks"]],
                         [(0xA1, False, "backpack", True), (0xB2, True, "equipped", True)])
        self.assertEqual((r["equipped"], r["equipped_set"], r["sig"]), (0xB2, 2, None))
        self.assertTrue(everyd["r"]["decks"][0]["equipped"])                # (the kept reading itself untouched)
        # (the recorder's next look: its own reading's signature - not read again)
        n = len(reads)
        nm.deck(fresh=True)
        self.assertEqual(len(reads), n)
        # (a fresh read of every deck reads again - never answered by the kept reading's old signature)
        r, why = nm.deck(fresh=True, only_equipped=False, kinds=True)
        self.assertEqual(reads[-1], (True, False))
        self.assertIs(nm._deck_all, nm._deck_cache)
        self.assertEqual([d["gid"] for d in r["decks"] if d["equipped"]], [0xB2])
        nm.close()
        self.assertIsNone(nm._deck_all)

    def test_a_worn_deck_edited_since_isnt_answered(self):
        nm, worn, reads, cards = self.nav()
        nm.deck(fresh=True, only_equipped=False, kinds=True)
        # (treasure cards used up in a battle - a known spell's too, read "main" - the signature changes: still answered)
        cards[0xA1][1]["count"] = 1
        cards[0xA1][0]["count"] = 2
        nm.deck(fresh=True)
        r, why = nm.deck(only_equipped=False, kinds=True)
        self.assertEqual(why, "")
        self.assertEqual(r["decks"][0]["cards"][1]["count"], 2)              # (every deck's reading as it was read)
        # (a spell put in it: edited - not answered, every deck read again)
        cards[0xA1].append({"template_id": 11, "count": 4, "side": "main"})
        nm.deck(fresh=True)
        self.assertEqual(nm.deck(only_equipped=False, kinds=True), (None, "not read yet"))
        self.assertIsNone(nm._deck_all)                                      # (dropped for good)
        # (another deck worn then - its cards as they were: the edited one's old cards never come back)
        worn[0] = 0xB2
        nm.deck(fresh=True)
        self.assertEqual(nm.deck(only_equipped=False, kinds=True), (None, "not read yet"))
        r, why = nm.deck(fresh=True, only_equipped=False, kinds=True)
        self.assertEqual(r["decks"][0]["cards"][-1]["template_id"], 11)
        self.assertEqual(nm.deck(only_equipped=False, kinds=True)[0]["decks"][0]["cards"][-1]["template_id"], 11)

    def test_another_character_or_a_new_deck_isnt_answered(self):
        nm, worn, reads, cards = self.nav()
        nm.deck(fresh=True, only_equipped=False, kinds=True)
        # (another character logged in on the same game: its worn deck read - the first one's decks never answered)
        self.who[0], worn[0] = 0x88, 0xB2
        nm.deck(fresh=True)
        self.assertEqual(nm.deck(only_equipped=False, kinds=True), (None, "not read yet"))
        self.assertIsNone(nm._deck_all)
        # (the same character, a deck worn that every deck's reading hasn't - made since)
        nm.deck(fresh=True, only_equipped=False, kinds=True)
        cards[0xC3] = [{"template_id": 5, "count": 1, "side": "main"}]
        nm._deck_all["r"]["decks"] = [d for d in nm._deck_all["r"]["decks"] if d["gid"] != 0xC3]
        worn[0] = 0xC3
        nm.deck(fresh=True)
        self.assertEqual(nm.deck(only_equipped=False, kinds=True), (None, "not read yet"))

    def test_a_side_moved_by_one_reads_spellbook_isnt_an_edit(self):
        # (deckmem works each card's side out from that read's spellbook: one not read moves a treasure card the
        # wizard doesn't know to main, an entry not read moves a known spell to treasure - no edit, every deck kept)
        nm, worn, reads, cards = self.nav()
        cards[0xA1].append({"template_id": 6, "count": 1, "side": "main"})
        nm.deck(fresh=True, only_equipped=False, kinds=True)
        cards[0xA1][1]["side"] = "main"                 # (the treasure card 9: main in this read)
        cards[0xA1][2]["side"] = "treasure"             # (the main card 6: treasure in this read)
        nm.deck(fresh=True)
        r, why = nm.deck(only_equipped=False, kinds=True)
        self.assertEqual(why, "")
        self.assertIsNotNone(nm._deck_all)
        # (a spell put in still is an edit)
        cards[0xA1].append({"template_id": 12, "count": 1, "side": "treasure"})
        nm.deck(fresh=True)
        self.assertEqual(nm.deck(only_equipped=False, kinds=True), (None, "not read yet"))

    def test_a_worn_deck_not_read_isnt_judged(self):
        # (its card list not read in the worn reading - ok False: no "edit" made of it, every deck's reading answers)
        nm, worn, reads, cards = self.nav()
        nm.deck(fresh=True, only_equipped=False, kinds=True)
        worn[0] = 0xB2
        self.unread.add(0xB2)
        nm.deck(fresh=True)
        r, why = nm.deck(only_equipped=False, kinds=True)
        self.assertEqual((why, r["equipped"]), ("", 0xB2))
        self.assertEqual(r["decks"][1]["cards"], [{"template_id": 8, "count": 4, "side": "main"}])

    def test_no_every_deck_reading_still_not_read(self):
        nm, worn, reads, cards = self.nav()
        nm.deck(fresh=True)
        self.assertEqual(nm.deck(only_equipped=False, kinds=True), (None, "not read yet"))
        self.assertIsNone(nm._deck_all)
        # (every deck read without their kinds: not kept as every deck's with them)
        nm.deck(fresh=True, only_equipped=False)
        self.assertIsNone(nm._deck_all)
        self.assertEqual(nm.deck(only_equipped=False, kinds=True), (None, "not read yet"))

    def test_another_game_not_answered(self):
        nm, worn, reads, cards = self.nav()
        nm.deck(fresh=True, only_equipped=False, kinds=True)
        nm.st = object()
        self.assertEqual(nm.deck(only_equipped=False, kinds=True), (None, "not read yet"))


class OneDeckReadAtATime(unittest.TestCase):
    """navmem.NavMem.deck(fresh=True): one paced read at a time (DeckMem._pace is the read's own state - a second read
    run in the first one's gap left the rest of the first unpaced): a read asked with no queue (the recorder's) while
    another runs gives way at once; a gated request's (queue s - vision.py DECK_QUEUE_S) waits while the one in progress
    gives way to it; every read paced to its end either way; deck_sig waits it out too (the real navmem, test_navroute's
    import)"""

    @classmethod
    def setUpClass(cls):
        from test_navroute import import_navmem
        cls.N = import_navmem()

    def setup(self):
        """(nm, log [(thread ident, unpaced, k)], n [gated requests in flight], res, the recorder's thread) - the
        recorder's read (idle: nothing gated in flight - gate.idle, own 0) started and 5 entries into the spellbook"""
        import threading
        import time
        log = []

        class DM(FakeDeckMem):
            def spellbook(self_, sb):
                out = []
                for k in range(40):
                    log.append((threading.get_ident(), self_._pace is None, k))
                    self_.pace()
                    time.sleep(0.004)
                    out.append({"template_id": 1000 + k, "retired": False, "tier_group": 0})
                return out
        nm = self.N.NavMem(log=lambda m: None)
        st = types.SimpleNamespace(alive=lambda: True)
        nm.st = st
        dm = DM()
        dm.st, dm.hm = st, nm._hand
        nm._deck_readers = lambda wait: (st, dm, "")
        nm._deckm = dm              # (deck_sig's reader)
        n = [0]
        res = {}

        def recorder():
            res["A"] = nm.deck(fresh=True, idle=lambda d: n[0] == 0)
        ta = threading.Thread(target=recorder, daemon=True)
        ta.start()
        t0 = time.monotonic()
        while not any(k >= 5 for _t, _u, k in log) and time.monotonic() - t0 < 5:
            time.sleep(0.001)
        return nm, log, n, res, ta

    def test_no_queue_gives_way_at_once_and_the_first_stays_paced(self):
        import threading
        import time
        nm, log, n, res, ta = self.setup()
        n[0] = 1                    # (a gated request in flight: the recorder lets go at its next pace point)
        time.sleep(0.03)
        try:
            # (no queue: refused at once - it'd have run in the recorder's gap)
            self.assertEqual(nm.deck(fresh=True, idle=lambda d: n[0] <= 1, books=True),
                             (None, "gave way to another deck read in progress - read again later"))
            self.assertEqual(nm.deck_sig(), (None, "a deck read is in progress"))
        finally:
            n[0] = 0
            ta.join(5)
        self.assertFalse(ta.is_alive())
        r, why = res["A"]
        self.assertEqual(why, "")
        self.assertEqual(r["spellbook_n"], 40)
        mine = [u for t, u, _k in log if t == ta.ident]
        self.assertEqual((len(mine), sum(mine)), (40, 0))            # (paced at every point, to its end)
        self.assertNotIn(threading.get_ident(), [t for t, _u, _k in log])   # (the second read never touched it)
        # (let go afterwards: the next read runs, and the signature is read again)
        r, why = nm.deck(fresh=True, books=True)
        self.assertEqual((why, len(r["spellbook"])), ("", 40))
        self.assertIsNotNone(nm.deck_sig()[0])

    def test_a_gated_read_waits_while_the_recorder_gives_way(self):
        import threading
        nm, log, n, res, ta = self.setup()
        nm.DECK_IDLE = 0.2          # (the recorder gives way sooner - the test's own)
        n[0] = 1                    # (/book's request in flight, waiting: the recorder lets go and gives way)
        try:
            r, why = nm.deck(fresh=True, idle=lambda d: n[0] <= 1, books=True, queue=1.0)
        finally:
            n[0] = 0
            ta.join(5)
        self.assertFalse(ta.is_alive())
        self.assertEqual((why, len(r["spellbook"])), ("", 40))
        self.assertIsNone(res["A"][0])
        self.assertTrue(res["A"][1].startswith("gave way to the gated reads"), res["A"][1])
        me = threading.get_ident()
        self.assertEqual(sum(u for _t, u, _k in log), 0)             # (both paced at every point)
        first_mine = next(i for i, (t, _u, _k) in enumerate(log) if t == me)
        self.assertNotIn(ta.ident, [t for t, _u, _k in log[first_mine:]])   # (the recorder's read over before it began)
        # (a queue too short for it: given way, the recorder's read left as it was)
        nm2, log2, n2, res2, ta2 = self.setup()
        try:
            self.assertEqual(nm2.deck(fresh=True, idle=lambda d: True, books=True, queue=0.05),
                             (None, "gave way to another deck read in progress - read again later"))
        finally:
            ta2.join(5)
        self.assertEqual(res2["A"][1], "")
        self.assertEqual(sum(u for _t, u, _k in log2), 0)

    def test_let_go_when_the_read_fails(self):
        nm = self.N.NavMem(log=lambda m: None)
        st = object()
        nm.st = st

        class DM:
            def signature(self_, pace=None):
                raise ValueError("boom")
        dm = DM()
        dm.st, dm.hm = st, nm._hand
        nm._deck_readers = lambda wait: (st, dm, "")
        r, why = nm.deck(fresh=True)
        self.assertIsNone(r)
        self.assertIn("boom", why)
        self.assertFalse(nm._deck_busy.locked())
        self.assertFalse(nm.lock.locked())


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
        self.assertEqual(kw["queue"], V.DECK_QUEUE_S)           # (a gated request: waits for another read to give way)
        V.book_answer(False, kinds=True)
        self.assertEqual((asked[-1]["fresh"], asked[-1]["kinds"], asked[-1]["stop"], asked[-1]["queue"]),
                         (False, True, None, 0.0))

    def test_not_read(self):
        V = self.V

        class Nav:
            def deck(self, **kw):
                return None, "not read|yet"
        V.nav_reader = lambda: Nav()
        V.REC = None
        self.assertEqual(V.book_answer(False), ["none|not read yet"])

    def test_decks_with_the_recorder_off(self):
        # (/decks?fresh=1&ob=1 - Decks.ahk DeckLearnGame's - with the battle recorder off: read, no stop - it raised
        # AttributeError on rec None before)
        V = self.V
        asked = []

        class Nav:
            def deck(self, **kw):
                asked.append(kw)
                return {"decks": [], "read_at": None}, ""
        V.nav_reader = lambda: Nav()
        V.REC = None
        self.assertEqual(V.decks_reading(True), (None, "the battle recorder isn't following the game's log (a battle "
                                                       "can't be ruled out)"))
        self.assertEqual(asked, [])
        r, why = V.decks_reading(True, out=True)
        self.assertEqual((r["decks"], why), ([], ""))
        kw = asked[-1]
        self.assertEqual((kw["fresh"], kw["stop"], kw["only_equipped"], kw["kinds"], kw["queue"]),
                         (True, None, False, True, V.DECK_QUEUE_S))

    def test_gated(self):
        self.assertTrue({"/book", "/quests", "/deck", "/goal"} <= self.V.GATED)


if __name__ == "__main__":
    unittest.main()
