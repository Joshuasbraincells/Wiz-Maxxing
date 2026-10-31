"""test_petplan.py - the perfect-pets decisions (vision\\petplan.py: the wanted talents parsed, a pet's missing ones, the
pets Quick Sell keeps - every pet whose talents aren't read -, the parents' pick, the snack's pick - never a Crowns one -,
when to stop, /pets' want| and keep| lines) on stand-in pets - pure, no game, no Windows:
python -m unittest test_petplan   (from AutoFarmer\\vision)"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import petplan as P  # noqa: E402

WANT = "Spell-Proof, Spell-Defying, Mighty, Pain-Giver, Pain-Bringer"


def pet(gid, talents, level=6, where="backpack", derby=None):
    return {"gid": gid, "talents": talents, "level": level, "where": where, "derby": derby}


class Wanted(unittest.TestCase):

    def test_parse(self):
        self.assertEqual(P.parse_wanted(WANT), ["Spell-Proof", "Spell-Defying", "Mighty", "Pain-Giver", "Pain-Bringer"])
        # (any separator, spaces squeezed, the same talent once whatever its case and dashes)
        self.assertEqual(P.parse_wanted(" spell proof ;Spell-Proof|  Pain   Giver\r\nMIGHTY,, "),
                         ["spell proof", "Pain Giver", "MIGHTY"])
        self.assertEqual(P.parse_wanted(""), [])
        self.assertEqual(P.parse_wanted(None), [])
        self.assertEqual(len(P.parse_wanted(",".join("T%d" % i for i in range(40)))), P.WANT_CAP)
        self.assertEqual(P.norm("Pain-Giver"), P.norm("pain giver"))

    def test_has_all_and_missing(self):
        w = P.parse_wanted(WANT)
        perfect = pet(1, ["Spell Proof", "SPELL-DEFYING", "Mighty", "Pain-Giver", "Pain-Bringer"])
        self.assertIs(P.has_all(perfect, w), True)
        self.assertEqual(P.missing(perfect, w), [])
        half = pet(2, ["Mighty", "Pain-Giver", "Fairy Friend"])
        self.assertIs(P.has_all(half, w), False)
        self.assertEqual(P.missing(half, w), ["Spell-Proof", "Spell-Defying", "Pain-Bringer"])
        unread = pet(3, None)
        self.assertIsNone(P.has_all(unread, w))
        self.assertIsNone(P.missing(unread, w))
        self.assertIsNone(P.has_all(perfect, []))                       # (nothing wanted: no answer)
        # (derby talents count once read)
        self.assertIs(P.has_all(pet(4, ["Mighty"], derby=["Sprint"]), ["mighty", "sprint"]), True)


class Keepers(unittest.TestCase):

    def test_nothing_wanted_nothing_kept(self):
        self.assertEqual(P.keepers([pet(1, None), pet(2, ["Mighty"])], [], False), {})

    def test_unread_kept_perfect_kept_others_not(self):
        w = P.parse_wanted(WANT)
        pets = [pet(1, None), pet(2, ["Spell-Proof", "Spell-Defying", "Mighty", "Pain-Giver", "Pain-Bringer"]),
                pet(3, ["Mighty"]), pet(4, [], level=1), {"gid": 0, "talents": None}]
        k = P.keepers(pets, w, False)
        self.assertEqual(sorted(k), [1, 2])
        self.assertIn("kept to be safe", k[1])
        self.assertIn("every wanted talent", k[2])

    def test_hatching_keeps_the_young_and_the_parents(self):
        w = P.parse_wanted("Mighty, Pain-Giver, Spell-Proof")
        pets = [pet(10, ["Mighty", "Pain-Giver"], level=6), pet(11, ["Spell-Proof"], level=6),
                pet(12, ["Fairy Friend"], level=6), pet(13, [], level=1), pet(14, ["Mighty"], level=3)]
        k = P.keepers(pets, w, True)
        self.assertEqual(sorted(k), [10, 11, 13, 14])
        self.assertIn("a parent", k[10])
        self.assertIn("in training (Baby)", k[13])
        self.assertIn("Mighty so far", k[14])
        self.assertNotIn(12, k)
        # (hatching on with nothing wanted: every pet kept)
        self.assertEqual(sorted(P.keepers(pets, [], True)), [10, 11, 12, 13, 14])


class Parents(unittest.TestCase):

    def test_most_covered_then_most_each(self):
        w = P.parse_wanted("A, B, C, D")
        pets = [pet(1, ["A", "B"]), pet(2, ["C"]), pet(3, ["C", "D"]), pet(4, ["A"]), pet(5, None)]
        a, b, cov, miss = P.pick_parents(pets, w)
        self.assertEqual((a, b), (1, 3))
        self.assertEqual((cov, miss), (["A", "B", "C", "D"], []))
        # (a tie on what's covered goes to the pair with more on each)
        w2 = P.parse_wanted("A, B")
        pets2 = [pet(1, ["A"]), pet(2, ["B"]), pet(3, ["A", "B"]), pet(4, [])]
        self.assertEqual(P.pick_parents(pets2, w2)[:2], (1, 3))
        # (then the higher levels, then the lower gids)
        pets3 = [pet(7, ["A"], level=6), pet(8, ["B"], level=7), pet(9, ["B"], level=6)]
        self.assertEqual(P.pick_parents(pets3, w2)[:2], (7, 8))

    def test_none(self):
        self.assertIsNone(P.pick_parents([pet(1, ["A"])], ["A"]))
        self.assertIsNone(P.pick_parents([pet(1, ["A"]), pet(2, None)], ["A"]))
        self.assertIsNone(P.pick_parents([pet(1, ["A"]), pet(2, ["A"])], []))
        self.assertIsNone(P.pick_parents([pet(1, ["A"], level=2), pet(2, ["A"])], ["A"], min_level=3))


class Snacks(unittest.TestCase):

    def test_never_crowns_liked_first(self):
        snacks = [{"name": "Crown Cake", "xp": 99, "category": "Sweet", "crowns": True},
                  {"name": "Mystery", "xp": 50, "category": "Sweet", "crowns": None},
                  {"name": "Carrot", "xp": 5, "category": "Vegetable", "crowns": False, "rank": 1},
                  {"name": "Steak", "xp": 20, "category": "Meat", "crowns": False, "rank": 3},
                  {"name": "Ribs", "xp": 20, "category": "Meat", "crowns": False, "rank": 2}]
        self.assertEqual(P.best_snack(snacks, {"likes": []})["name"], "Ribs")       # (most XP, cheaper rank)
        self.assertEqual(P.best_snack(snacks, {"likes": ["vegetable"]})["name"], "Carrot")
        self.assertIsNone(P.best_snack(snacks[:2], {}))
        self.assertIsNone(P.best_snack([], {}))


class Stop(unittest.TestCase):

    def test_reasons(self):
        w = ["Mighty"]
        self.assertIn("every wanted talent", P.stop_reason(pet(1, ["Mighty"], level=2), w, target_level=6))
        self.assertIn("Mega", P.stop_reason(pet(1, [], level=6), w, target_level=6))
        self.assertIn("gold", P.stop_reason(pet(1, [], level=2), w, 6, gold=900, gold_floor=1000))
        self.assertIn("energy", P.stop_reason(pet(1, [], level=2), w, 6, gold=5000, gold_floor=1000, energy=0))
        self.assertEqual(P.stop_reason(pet(1, None, level=None), w, 6, gold=None, gold_floor=1000, energy=None), "")


class Lines(unittest.TestCase):

    def test_pets_answer(self):
        r = {"pets": [pet(0x22, None, where="equipped"), pet(0x33, ["Mighty"])], "whole": True, "ms": 2.0, "why": ""}
        ln = P.pets_answer(r, "", "Mighty|Pain-Giver", False)
        self.assertEqual([x.split("|")[0] for x in ln], ["pet", "pet", "energy", "pets", "want", "keep"])
        self.assertEqual(ln[-2:], ["want|2|Mighty, Pain-Giver|0", "keep|22|equipped|talents not read - kept to be safe"])
        self.assertEqual(P.pets_answer(None, "the game is not running", "Mighty"), ["none|the game is not running"])
        self.assertEqual(P.keep_lines([], [], True), ["want|0||1"])


if __name__ == "__main__":
    unittest.main()
