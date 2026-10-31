"""test_spellplan.py - the spell-learning planner's checks (spellplan.py - pure, no game): the plan file, what to train
next, new spells, a deck's changes within its limits, spell quests, the helper's /book and /quests answers read back,
the command line (saved answers and a made-up helper), and the draft trainplans.txt that ships:
    python -m unittest test_spellplan   (from AutoFarmer\\vision)"""
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import spellplan as S  # noqa: E402

PLAN = """; a made-up plan
school|storm
train|Elemental Blade|balance|Alhazred|WizardCity/WC_Ravenwood|20|1||blade|1
school|life
school|any
train|Tower Shield|ice|Lydia Greyrose|WizardCity/WC_Ravenwood|10|1||ward|0
train|Fairy|life|Moolinda Wu|WizardCity/WC_Ravenwood|?|?||heal|0
train|Satyr|life|Moolinda Wu|WizardCity/WC_Ravenwood|30|2|Fairy|heal|1   ; needs Fairy
train|Feint|death|Dworgyn|WizardCity/WC_Ravenwood|26|1||trap|0
spellquest|title|spell quest
spellquest|prop|m_isSpellQuest|1
"""


class Names(unittest.TestCase):
    def test_norm(self):
        self.assertEqual(S.norm("Dr. Purreau"), "dr purreau")
        self.assertEqual(S.norm("  Tower   Shield "), "tower shield")
        self.assertEqual(S.norm("Hilda’s Potion"), S.norm("Hilda's potion"))
        self.assertEqual(S.norm(None), "")

    def test_known_keys(self):
        self.assertEqual(S.known_keys([{"display": "Tower Shield", "name": "Tower Shield-Ice"}, "Fairy", {"name": ""}]),
                         {"tower shield", "tower shield ice", "fairy"})


class Plan(unittest.TestCase):
    def test_parse(self):
        p = S.parse_plan(PLAN)
        self.assertEqual(p["errors"], [])
        self.assertEqual(sorted(p["schools"]), ["any", "life", "storm"])
        self.assertEqual([e["spell"] for e in p["schools"]["any"]], ["Tower Shield", "Fairy", "Satyr", "Feint"])
        sat = p["schools"]["any"][2]
        self.assertEqual((sat["teacher"], sat["level"], sat["cost"], sat["needs"], sat["need_keys"], sat["kind"],
                          sat["checked"], sat["line"]), ("life", 30, 2, ["Fairy"], ["fairy"], "heal", True, 8))
        fairy = p["schools"]["any"][1]
        self.assertEqual((fairy["level"], fairy["cost"], fairy["checked"]), (None, None, False))
        self.assertEqual([r[0] for r in p["rules"]], ["title", "prop"])
        self.assertEqual(p["rules"][1], ("prop", "m_isSpellQuest", "1"))

    def test_errors_said_and_the_rest_read(self):
        p = S.parse_plan("train|X|ice|a|b|1|1||ward|0\n"            # before a school
                         "school|astral\n"                           # not a school
                         "school|ice\n"
                         "train|Only|three\n"                         # fields
                         "train||ice|a|b|1|1||ward|0\n"               # no name
                         "train|X|wood|a|b|1|1||ward|0\n"             # not a teacher
                         "train|X|ice|a|b|ten|1||ward|0\n"            # level
                         "train|X|ice|a|b|1|1||ward|yes\n"            # checked
                         "spellquest|title|(\n"                       # bad regex
                         "spellquest|prop|isSpell|1\n"                # not m_
                         "hello\n"
                         "train|Good|star|a|b|?|3||aura|1\n")
        self.assertEqual([no for no, _l, _w in p["errors"]], [1, 2] + list(range(4, 12)))
        self.assertEqual([e["spell"] for e in p["schools"]["ice"]], ["Good"])
        self.assertIn("before any", p["errors"][0][2])
        self.assertIn("takes 9 fields, not 2", p["errors"][2][2])

    def test_plan_for(self):
        p = S.parse_plan(PLAN)
        self.assertEqual([e["spell"] for e in S.plan_for(p, "storm")],
                         ["Elemental Blade", "Tower Shield", "Fairy", "Satyr", "Feint"])
        # (a life wizard: any's life spells left out - they come with the school)
        self.assertEqual([e["spell"] for e in S.plan_for(p, "Life")], ["Tower Shield", "Feint"])
        self.assertEqual(S.plan_for(p, "astral"), [])

    def test_own_line_wins_over_any(self):
        p = S.parse_plan("school|any\ntrain|Feint|death|D|z|26|1||trap|0\nschool|fire\ntrain|Feint|death|D|z|20|1||trap|1\n")
        got = S.plan_for(p, "fire")
        self.assertEqual([(e["spell"], e["level"]) for e in got], [("Feint", 20)])


class NextToTrain(unittest.TestCase):
    def setUp(self):
        self.p = S.parse_plan(PLAN)

    def test_in_order_and_known_skipped(self):
        e, why, waiting = S.next_to_train(self.p, "storm", [], level=40, tp=5)
        self.assertEqual(e["spell"], "Elemental Blade")
        self.assertIn("Elemental Blade (balance, Alhazred in WizardCity/WC_Ravenwood)", why)
        e, why, _w = S.next_to_train(self.p, "storm", [{"display": "Elemental Blade"}], level=40, tp=5)
        self.assertEqual(e["spell"], "Tower Shield")
        self.assertIn("not checked in the game yet", why)

    def test_level_passes_by_needs_pass_by(self):
        e, why, waiting = S.next_to_train(self.p, "storm", ["Elemental Blade", "Tower Shield"], level=12, tp=5)
        self.assertEqual(e["spell"], "Fairy")                       # (its level not in the plan: taken, said)
        self.assertIn("its level isn't in the plan", why)
        self.assertIn("its cost isn't in the plan (1 taken)", why)
        e, why, waiting = S.next_to_train(self.p, "storm", ["Elemental Blade", "Tower Shield", "Fairy"], level=12, tp=5)
        self.assertIsNone(e)
        self.assertEqual(waiting, [("Satyr", "level 30 (the wizard's 12)"), ("Feint", "level 26 (the wizard's 12)")])
        self.assertEqual(why, "nothing to train yet")
        e, _why, waiting = S.next_to_train(self.p, "storm", ["Elemental Blade", "Tower Shield"], level=40, tp=5,
                                           skip=["fairy"])
        self.assertEqual(e["spell"], "Feint")
        self.assertEqual(waiting, [("Fairy", "passed by (tried before)"), ("Satyr", "needs Fairy first")])

    def test_saving_for_one_stops_the_rest(self):
        e, why, _w = S.next_to_train(self.p, "storm", ["Elemental Blade", "Tower Shield", "Fairy"], level=40, tp=1)
        self.assertIsNone(e)
        self.assertEqual(why, "saving for Satyr: 2 training points, 1 there")
        e, why, _w = S.next_to_train(self.p, "storm", [], level=40, tp=0)
        self.assertEqual(why, "saving for Elemental Blade: 1 training point, 0 there")

    def test_unknowns_said(self):
        e, why, _w = S.next_to_train(self.p, "storm", [], level=None, tp=None)
        self.assertEqual(e["spell"], "Elemental Blade")
        self.assertIn("the wizard's level isn't known", why)
        self.assertIn("the training points aren't known", why)
        self.assertEqual(S.next_to_train(self.p, "", [])[:2], (None, "the wizard's school isn't known"))
        self.assertEqual(S.next_to_train(S.parse_plan(""), "fire", [])[:2], (None, "no plan for fire (nor for any school)"))
        known = ["Elemental Blade", "Tower Shield", "Fairy", "Satyr", "Feint"]
        self.assertEqual(S.next_to_train(self.p, "storm", known)[:2], (None, "every spell of the plan is known"))


class NewSpells(unittest.TestCase):
    def test_new_and_gone(self):
        prev = [{"template_id": 1}, {"template_id": 2}, {"template_id": 3}]
        book = [{"template_id": 1, "display": "A"}, {"template_id": 4, "display": "D"}, {"template_id": 3},
                {"template_id": None}, {"template_id": 5, "display": "E"}]
        new, gone = S.new_spells(prev, book)
        self.assertEqual([e["template_id"] for e in new], [4, 5])
        self.assertEqual(gone, [2])
        self.assertEqual(S.new_spells([1, "2"], [2, 3]), ([3], [1]))
        self.assertEqual(S.new_spells(None, None), ([], []))


def card(tid, kind, value, school="storm", count=1, side="main", name=None, **kw):
    return dict({"template_id": tid, "name": name or "C%d" % tid, "display": name or "C%d" % tid, "school": school,
                 "kind": kind, "value": value, "count": count, "side": side}, **kw)


def deck(cards, max_spells=10, school_max=4, generic_max=2, school="Storm"):
    return {"school": school, "limits": {"max_spells": max_spells, "school_max_copies": school_max,
                                         "generic_max_copies": generic_max}, "cards": cards}


class DeckChanges(unittest.TestCase):
    def test_added_while_there_is_room_within_the_copy_limits(self):
        d = deck([card(1, "damage", 200, count=4)], max_spells=20)
        book = [card(10, "damage", 300), card(11, "heal", 400, school="life"), card(12, "ward", 50, school="ice",
                                                                                     max_copies=1)]
        ch, notes = S.deck_changes(d, book)
        self.assertEqual([(c["op"], c["template_id"], c["count"]) for c in ch],
                         [("add", 11, 2), ("add", 10, 4), ("add", 12, 1)])   # (strongest first; heal: generic max 2)
        self.assertEqual(notes, [])

    def test_full_deck_swaps_the_weakest_of_the_kind_when_stronger(self):
        d = deck([card(1, "damage", 200, count=4), card(2, "damage", 500, count=4), card(3, "heal", 300, school="life",
                                                                                         count=2)], max_spells=10)
        ch, notes = S.deck_changes(d, [card(10, "damage", 300)])
        self.assertEqual([(c["op"], c["template_id"], c["count"]) for c in ch], [("remove", 1, 4), ("add", 10, 4)])
        self.assertIn("the weakest damage (200)", ch[0]["why"])
        # (not 15% stronger: kept out, said)
        ch, notes = S.deck_changes(d, [card(10, "damage", 220)])
        self.assertEqual(ch, [])
        self.assertIn("not 15% stronger than C1 (220 against 200)", notes[0])
        # (swap off: never a card's place)
        ch, notes = S.deck_changes(d, [card(10, "damage", 900)], {"swap": False})
        self.assertEqual(ch, [])
        self.assertIn("no room (0 free)", notes[0])

    def test_a_strength_not_known_never_swaps(self):
        d = deck([card(1, "damage", None, value_text="50/pip", count=10)], max_spells=10)
        ch, notes = S.deck_changes(d, [card(10, "damage", 300)])
        self.assertEqual(ch, [])
        self.assertIn("a card of its kind with no strength read", notes[0])
        d = deck([card(1, "damage", 100, count=10)], max_spells=10)
        ch, notes = S.deck_changes(d, [card(10, "damage", None, value_text="?")])
        self.assertEqual(ch, [])
        self.assertIn("its strength isn't known", notes[0])

    def test_strength_from_text(self):
        self.assertEqual(S.strength({"value": "295-335"}), 315.0)
        self.assertEqual(S.strength({"value": None, "value_text": "+35%"}), 35.0)
        self.assertEqual(S.strength({"value": 40}), 40.0)
        self.assertIsNone(S.strength({"value": True, "value_text": "50/pip"}))

    def test_treasure_and_item_cards_never_touched_and_other_schools_hits_left_out(self):
        d = deck([card(1, "damage", 100, count=4), card(5, "damage", 50, count=3, side="treasure")], max_spells=6)
        ch, notes = S.deck_changes(d, [card(10, "damage", 600), card(11, "damage", 900, school="fire"),
                                       card(12, "blade", 35, school="life"), card(13, "heal", 300, school="life")])
        # (the treasure card isn't counted for room and never removed; the fire hit and the life blade left out; the
        # strongest first: 600 takes the 100's place - 2 free, 4 out, 4 in -, then the heal's 2 go in the room left)
        self.assertEqual([(c["op"], c["template_id"], c["count"]) for c in ch],
                         [("remove", 1, 4), ("add", 10, 4), ("add", 13, 2)])
        self.assertTrue(any("C11: a fire damage - only the deck's own school's (storm) go in" in n for n in notes))
        self.assertTrue(any("C12: a life blade" in n for n in notes))

    def test_limits_not_read_change_nothing(self):
        d = deck([card(1, "damage", 100)])
        d["limits"]["max_spells"] = None
        self.assertEqual(S.deck_changes(d, [card(10, "damage", 500)]),
                         ([], ["the deck's size or copy limits weren't read - nothing changed"]))

    def test_want_only_those_and_kinds_said(self):
        d = deck([], max_spells=20)
        book = [card(10, "damage", 300), card(11, "damage", 400), card(12, "polymorph", 0)]
        ch, notes = S.deck_changes(d, book, {"want": [10, 12]})
        self.assertEqual([c["template_id"] for c in ch], [10])
        self.assertEqual(notes, ["C12: a polymorph - not a kind put in decks here"])

    def test_part_room_with_none_of_its_kind(self):
        d = deck([card(1, "damage", 100, count=9)], max_spells=10)
        ch, _n = S.deck_changes(d, [card(13, "heal", 300, school="life")])
        self.assertEqual([(c["op"], c["template_id"], c["count"]) for c in ch], [("add", 13, 1)])


class Quests(unittest.TestCase):
    def setUp(self):
        self.rule = S.spell_rule(S.parse_plan(PLAN)["rules"])
        self.qs = [{"id": 5, "title": "Main Story", "goals": [{"status": "INCOMPLETE"}], "props": {}},
                   {"id": 9, "title": "A Spell Quest", "goals": [{"status": "INCOMPLETE"}], "props": {}},
                   {"id": 7, "title": "Odd", "goals": [{"status": "INCOMPLETE"}], "props": {"m_isSpellQuest": "1"}},
                   {"id": 3, "title": "Done spell quest", "goals": [{"status": "COMPLETE"}], "props": {}}]

    def test_rule(self):
        self.assertEqual([self.rule(q) for q in self.qs], [False, True, True, True])
        self.assertFalse(S.spell_rule([])(self.qs[1]))
        self.assertTrue(S.spell_rule([("prop", "m_flag", "1")])({"props": {"m_flag": True}}) is False)  # (as written: 1)

    def test_pick(self):
        self.assertEqual(S.pick_quest(self.qs, 5, None, self.rule)[:2], ("track", 7))      # (open ones by id; done: no)
        self.assertEqual(S.pick_quest(self.qs, 9, 5, self.rule)[:2], ("keep", 9))
        open_ = [q for q in self.qs if q["id"] in (5, 3)]
        self.assertEqual(S.pick_quest(open_, 3, 5, self.rule)[:2], ("keep", 3))           # (a spell quest tracked)
        self.assertEqual(S.pick_quest([self.qs[0]], 11, 5, self.rule)[:2], ("back", 5))
        self.assertEqual(S.pick_quest([self.qs[0]], 5, 5, self.rule)[:2], ("keep", 5))
        self.assertEqual(S.pick_quest([self.qs[0]], 11, 99, self.rule)[:2], ("keep", 11))   # (the main one gone)
        self.assertEqual(S.pick_quest([], None, None, self.rule)[:2], ("keep", None))
        self.assertIn("then back to Main Story", S.pick_quest(self.qs, 5, None, self.rule)[2])


BOOK = """book|1001|Storm-Thunder Snake|Thunder Snake|Storm|Damage|1|0|0|0|damage|125-165
book|1002|Ice-TowerShield|Tower Shield|Ice|Ward|0|0||-1||
tcbook|2001|3|TC-Fire-Elf|Fire Elf|Fire|Damage|1|dot|
books|2|1|8a3f00001|42.5|
bookage|3.0"""

QUESTS = """quest|101|Main Story|1|2|1|QuestTitle_1|m_level=12,m_flag=1
goal|101|11|BOUNTY|COMPLETE|3|3|Defeat Gobblers in X (3 of 3)|Gobblers|||Triton Avenue|WizardQuestGoals_Kill
goal|101|12|PERSONA|INCOMPLETE|||Talk to Ambrose|||Merle Ambrose|Ravenwood|WizardQuestGoals_TalkNPC
quest|102|Spell: Storm Shark|0|0|0|QuestTitle_2|
quests|2|101|12.3|"""


class Answers(unittest.TestCase):
    def test_parse_book(self):
        b = S.parse_book(BOOK)
        self.assertIsNone(b["none"])
        self.assertEqual([(e["template_id"], e["display"], e["pips"], e["x_pips"], e["retired"], e["kind"],
                           e["value_text"]) for e in b["spells"]],
                         [(1001, "Thunder Snake", 1, False, False, "damage", "125-165"),
                          (1002, "Tower Shield", 0, False, None, None, None)])
        self.assertEqual(b["spells"][1]["tier_group"], -1)
        self.assertEqual([(e["template_id"], e["count"], e["kind"]) for e in b["treasure"]], [(2001, 3, "dot")])
        self.assertEqual((b["n"], b["tc_n"], b["player_gid"], b["ms"], b["why"]), (2, 1, "8a3f00001", 42.5, ""))
        self.assertEqual(S.parse_book("none|in a battle")["none"], "in a battle")

    def test_parse_quests(self):
        q = S.parse_quests(QUESTS)
        self.assertEqual([(x["id"], x["title"], x["tracked"], len(x["goals"])) for x in q["quests"]],
                         [(101, "Main Story", True, 2), (102, "Spell: Storm Shark", False, 0)])
        self.assertEqual(q["quests"][0]["props"], {"m_level": "12", "m_flag": "1"})
        g = q["quests"][0]["goals"][1]
        self.assertEqual((g["gid"], g["type"], g["status"], g["count"], g["npc"], g["name_key"]),
                         (12, "PERSONA", "INCOMPLETE", None, "Merle Ambrose", "WizardQuestGoals_TalkNPC"))
        self.assertEqual((q["n"], q["tracked"]), (2, 101))
        self.assertEqual(S.parse_quests("none|no quests")["none"], "no quests")


class CommandLine(unittest.TestCase):
    def run_cli(self, *argv):
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = S._main(list(argv))
        return rc, buf.getvalue()

    def test_saved_answers(self):
        with tempfile.TemporaryDirectory() as d:
            paths = {}
            for name, text in (("plan.txt", PLAN + "spellquest|title|^Spell:\n"), ("book.txt", BOOK),
                               ("quests.txt", QUESTS)):
                paths[name] = os.path.join(d, name)
                with open(paths[name], "w", encoding="utf-8") as f:
                    f.write(text)
            rc, out = self.run_cli("--plan", paths["plan.txt"], "--school", "storm", "--level", "40", "--tp", "3",
                                   "--book", paths["book.txt"], "--quests", paths["quests.txt"])
        self.assertEqual(rc, 0)
        self.assertIn("plan: any 4, life 0, storm 1; 3 spell-quest rule(s); 0 line(s) not taken", out)
        self.assertIn("the plan for storm, in order: Elemental Blade, Tower Shield, Fairy, Satyr, Feint", out)
        self.assertIn("book: 2 spells known (wizard 8a3f00001)", out)
        self.assertIn("the plan's spells known: Tower Shield", out)
        self.assertIn("next to train: Elemental Blade (balance, Alhazred in WizardCity/WC_Ravenwood)", out)
        self.assertIn("spell quests by the plan's rules: Spell: Storm Shark [102]", out)
        self.assertIn("pick_quest: track 102", out)

    def live(self, *args, book=BOOK):
        """(rc, out, urls asked) of the command line --live against a made-up helper answering book / QUESTS"""
        asked = []

        class Resp(io.BytesIO):
            def __enter__(self):
                return self

            def __exit__(self, *a):
                return False

        class Opener:
            def open(self, url, timeout=None):
                asked.append(url)
                return Resp((book if "/book" in url else QUESTS).encode())
        keep = S.ask_helper
        S.ask_helper = lambda path, port=S.PORT, timeout=15.0, opener=None: keep(path, port, timeout, Opener())
        try:
            with tempfile.TemporaryDirectory() as d:
                plan = os.path.join(d, "plan.txt")
                with open(plan, "w", encoding="utf-8") as f:
                    f.write(PLAN)
                rc, out = self.run_cli("--plan", plan, "--school", "life", "--live", *args)
        finally:
            S.ask_helper = keep
        return rc, out, asked

    def test_live_asks_the_helper_only(self):
        rc, out, asked = self.live("--fresh")
        self.assertEqual(rc, 0)
        # (--fresh alone: no ob=1 - the helper reads only when its battle recorder rules a battle out)
        self.assertEqual(asked, ["http://127.0.0.1:47128/book?fresh=1", "http://127.0.0.1:47128/quests"])
        self.assertIn("next to train: Feint", out)             # (Tower Shield known; life's own left out)
        self.assertIn("pick_quest: keep 101", out)
        self.assertEqual(self.live()[2][0], "http://127.0.0.1:47128/book")

    def test_live_ob_only_when_you_say_so(self):
        rc, out, asked = self.live("--fresh", "--ob")
        self.assertEqual(asked[0], "http://127.0.0.1:47128/book?fresh=1&ob=1")
        # (refused for the recorder: said, with the way round)
        refused = "none|the battle recorder isn't following the game's log (a battle can't be ruled out)\n"
        rc, out, asked = self.live("--fresh", book=refused)
        self.assertEqual(rc, 0)
        self.assertIn("book: not read - the battle recorder isn't following the game's log (a battle can't be ruled "
                      "out) - add --ob if the wizard is out of battle", out)
        rc, out, asked = self.live("--fresh", book="none|in a battle\n")
        self.assertIn("book: not read - in a battle\n", out + "\n")

    def test_helper_not_running(self):
        class Opener:
            def open(self, url, timeout=None):
                raise OSError("refused")
        text, why = S.ask_helper("/book", opener=Opener())
        self.assertIsNone(text)
        self.assertIn("is the bot running?", why)
        self.assertIn("book: not read - ", "\n".join(S.report(S.parse_plan(PLAN), "storm", book={"none": why})))

    def test_plan_path_prefers_yours(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(S.plan_path(d), os.path.join(d, "trainplans.txt"))
            os.makedirs(os.path.join(d, "learned"))
            with open(os.path.join(d, "learned", "trainplans.txt"), "w") as f:
                f.write("school|any\n")
            self.assertEqual(S.plan_path(d), os.path.join(d, "learned", "trainplans.txt"))
        rc, out = self.run_cli("--plan", os.path.join(os.path.dirname(os.path.abspath(__file__)), "no-such-plan.txt"))
        self.assertEqual(rc, 2)


class ShippedPlan(unittest.TestCase):
    """the draft that ships (AutoFarmer\\trainplans.txt): every line taken, every school's plan there, and every line
    still marked not checked in the game (nobody has seen these names in it yet)"""

    def test_trainplans_txt(self):
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "trainplans.txt")
        with open(path, encoding="utf-8-sig") as f:
            p = S.parse_plan(f.read())
        self.assertEqual(p["errors"], [])
        self.assertEqual(set(p["schools"]), set(S.SCHOOLS) | {"any"})
        entries = [e for v in p["schools"].values() for e in v]
        self.assertTrue(entries)
        self.assertFalse(any(e["checked"] for e in entries))
        for school in S.SCHOOLS:
            for e in S.plan_for(p, school):
                self.assertNotEqual(e["teacher"], school)         # (no school buys its own spells)


if __name__ == "__main__":
    unittest.main()
