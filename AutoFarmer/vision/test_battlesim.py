"""test_battlesim.py - the battle simulator's checks (standard library only):  python -m unittest vision\\test_battlesim.py"""
import datetime
import json
import os
import random
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import battlesim as S  # noqa: E402


def hit(name="Storm Lord", pips=7, value=1000, school="storm", aoe=False, count=1):
    return {"name": name, "display": name, "kind": "aoe" if aoe else "damage", "school": school, "pips": pips,
            "value": value, "heads_text": "%s:%d" % (school, value), "count": count, "side": "main"}


def boost(kind, name, pct, school="storm", count=1):
    return {"name": name, "display": name, "kind": kind, "school": school, "pips": 0, "value": pct,
            "boosts_text": "%s:%d" % (school, pct), "count": count, "side": "main"}


class Maths(unittest.TestCase):
    def test_damage_curve(self):
        self.assertAlmostEqual(S.damage_multiplier(0), 1.0)
        self.assertAlmostEqual(S.damage_multiplier(100), 2.0)
        self.assertAlmostEqual(S.damage_multiplier(150), 2.5)
        self.assertAlmostEqual(S.damage_multiplier(150.0001), 2.5, places=3)   # continuous at the knee
        self.assertLess(S.damage_multiplier(400), 3.0)                         # towards +200 %
        self.assertGreater(S.damage_multiplier(200), S.damage_multiplier(160))

    def test_crit(self):
        self.assertAlmostEqual(S.crit_mult(630, 90), 1.7, places=2)   # Decks.ahk's worked example
        self.assertEqual(S.crit_mult(500, 0), 2)
        self.assertEqual(S.crit_mult(0, 50), 1)
        self.assertAlmostEqual(S.crit_chance(300, 0, 100), 1.0)
        self.assertEqual(S.crit_chance(0, 0), 0)

    def test_pairs(self):
        self.assertEqual(S.parse_pairs("fire:230,ice:230,storm:230"), {"fire": 230, "ice": 230, "storm": 230})
        self.assertEqual(S.parse_pairs("all:25"), {"all": 25})
        self.assertEqual(S.parse_pairs("?"), {})
        self.assertEqual(S.fits({"all": 25}, "fire"), 25)
        self.assertEqual(S.fits({"ice": 35}, "fire"), 0)

    def test_resist_and_pierce(self):
        f = S.Foe("x", 100, "storm", resist={"storm": 0.6})
        self.assertAlmostEqual(f.resist_mult("storm"), 0.6)
        self.assertAlmostEqual(f.resist_mult("storm", pierce=10), 0.7)
        self.assertAlmostEqual(f.resist_mult("storm", pierce=90), 1.0)     # pierce never past nothing
        boosted = S.Foe("y", 100, "fire", resist={"storm": 1.2})
        self.assertAlmostEqual(boosted.resist_mult("storm", pierce=10), 1.2)
        plain = S.Foe("z", 100, "fire")
        self.assertAlmostEqual(plain.resist_mult("fire"), 0.85)            # its own school: the bot's 15 %
        self.assertAlmostEqual(plain.resist_mult("storm"), 0.85)           # nothing learned: 15 % on everything


class Pips(unittest.TestCase):
    def test_power_pips_double_for_school(self):
        b = S._Battle([], S.Me("storm"), [S.Foe("x", 10)], S.Opts(), random.Random(1))
        b.pips, b.power = 4, 3
        storm = S.Card("Storm Lord", "damage", "storm", 7, heads={"storm": 1})
        fire = S.Card("Fire Dragon", "damage", "fire", 7, heads={"fire": 1})
        self.assertTrue(b.pay(storm)[0])         # 1 + 3 x 2 = 7
        self.assertFalse(b.pay(fire)[0])         # 4 of another school
        b.spend(storm)
        self.assertEqual((b.pips, b.power), (0, 0))

    def test_x_pip(self):
        b = S._Battle([], S.Me("fire"), [S.Foe("x", 10)], S.Opts(), random.Random(1))
        b.pips, b.power = 5, 2
        x = S.Card("Meteor", "aoe", "fire", 0, x=True, heads={"fire": 100})
        self.assertEqual(b.pip_value(x), 7)
        self.assertAlmostEqual(b.least(x, 0), 7 * 100 * 0.85)     # every pip (power 2), the 15 % resist


class Simulate(unittest.TestCase):
    def test_easy_win(self):
        cards = S.deck_cards({"cards": [hit(count=20)]})
        me = S.Me("storm", 3000, damage=50)
        r = S.simulate(cards, me, [S.Foe("Rat", 500)], n=200, seed=1)
        self.assertGreater(r["won"], 0.95)
        self.assertLessEqual(r["rounds"], 8)

    def test_no_hits(self):
        cards = S.deck_cards({"cards": [boost("blade", "Stormblade", 35, count=10)]})
        r = S.simulate(cards, S.Me("storm"), [S.Foe("Rat", 500)], n=50, seed=1)
        self.assertEqual(r["won"], 0)
        self.assertIn("no hit in the deck", r["why"])

    def test_strong_foe_kills(self):
        cards = S.deck_cards({"cards": [hit(value=50, pips=1, count=40)]})
        foe = S.Foe("Ogre", 50000, spells=[("Smash", 1.0, {"pips": 1, "min": 900, "max": 1000, "accuracy": 100})])
        r = S.simulate(cards, S.Me("storm", 1500), [foe], n=100, seed=2)
        self.assertGreater(r["lost"], 0.95)

    def test_boosts_help(self):
        foe = S.Foe("Boss", 6000, spells=[("Hit", 1.0, {"pips": 2, "min": 150, "max": 200, "accuracy": 100})])
        me = S.Me("storm", 3000)
        plain = S.deck_cards({"cards": [hit(count=8)]})
        boosted = S.deck_cards({"cards": [hit(count=8), boost("blade", "Stormblade", 35, count=6),
                                          boost("trap", "Storm Trap", 30, count=6)]})
        a = S.simulate(plain, me, [foe], n=300, seed=3)
        b = S.simulate(boosted, me, [foe], n=300, seed=3)
        self.assertLessEqual(b["rounds"] or 99, a["rounds"] or 99)
        name, dmg, used = S.best_hit(boosted, me, foe)
        self.assertEqual(name, "Storm Lord")
        self.assertEqual(sorted(used), ["Storm Trap", "Stormblade"])
        self.assertAlmostEqual(dmg, 1000 * 1.35 * 1.30 * 0.85, places=3)

    def test_aoe_against_many(self):
        cards = S.deck_cards({"cards": [hit("Tempest", 6, 500, aoe=True, count=10)]})
        foes = [S.Foe("Imp %d" % i, 400) for i in range(4)]
        r = S.simulate(cards, S.Me("storm", 3000), foes, n=100, seed=4)
        self.assertGreater(r["won"], 0.9)

    def test_verdict_words(self):
        cards = S.deck_cards({"cards": [hit(count=20)]})
        me = S.Me("storm", 3000)
        foes = [S.Foe("Rat", 500)]
        r = S.simulate(cards, me, foes, n=100, seed=1)
        v = S.verdict(r, cards, me, foes)
        self.assertEqual(v["word"], "yes")
        self.assertIn("Rat 500 health", v["text"])
        lines = S.sim_lines(r, v, foes)
        self.assertTrue(lines[0].startswith("sim|"))
        self.assertTrue(any(x.startswith("verdict|yes|") for x in lines))

    def test_bad_input_never_raises(self):
        r = S.simulate(None, S.Me(), [S.Foe("x", 10)], n=5)
        self.assertTrue(r["why"])
        self.assertEqual(S.verdict({}, [], S.Me(), [])["word"], "unknown")


class Learn(unittest.TestCase):
    def test_support_and_boss(self):
        boss_deck = {"gid": 0x1234, "display": "Boss Storm", "school": "Storm", "sets": [2],
                     "cards": [hit(count=4), boost("blade", "Stormblade", 35, count=3),
                               boost("trap", "Storm Trap", 30, count=3),
                               {"name": "Tower Shield", "display": "Tower Shield", "kind": "ward", "count": 2}]}
        mob_deck = {"gid": 0x99, "display": "Mobs", "school": "storm", "sets": [1],
                    "cards": [hit("Tempest", 6, 500, aoe=True, count=8), hit("Thunder Snake", 2, 125, count=2)]}
        loose = {"gid": 0x7, "display": "Spare", "sets": [], "cards": []}
        learned = S.learn_decks({"decks": [boss_deck, mob_deck, loose]})
        self.assertEqual(len(learned), 2)
        b, m = learned
        self.assertEqual((b["gid"], b["school"], b["eqset"], b["when"]), ("1234", "storm", 2, ["boss"]))
        self.assertEqual(b["vals"].get("cardlogic"), 1)
        self.assertNotIn("useblades", b["vals"])
        self.assertNotIn("usetower", b["vals"])
        self.assertEqual(b["vals"]["useheal"], 0)
        self.assertEqual((m["eqset"], m["when"]), (1, ["default", "collect"]))
        self.assertEqual(m["vals"]["useblades"], 0)
        self.assertEqual(m["vals"]["cardlogic"], 2)
        line = S.learn_lines([b])[0]
        self.assertTrue(line.startswith("learn|1234|Boss Storm|storm|2|boss|"))

    def test_only_deck_is_default(self):
        d = {"gid": 1, "display": "Only", "equipped": True, "sets": [], "cards": [hit(count=5)]}
        (L,) = S.learn_decks({"decks": [d]})
        self.assertEqual(L["when"], ["default"])
        self.assertEqual(L["eqset"], 0)


class Book(unittest.TestCase):
    def test_learned_from_records(self):
        battle = {"me": {"sc": 4, "school": "storm"},
                  "parts": [{"sc": 0, "side": "enemy", "name": "Bonestriker", "max": 2400, "school": "death"},
                            {"sc": 4, "side": "me", "name": "Me"}],
                  "rounds": [{"hand": [{"school": "storm"}], "played": {"hand_i": 0, "targets": [0]},
                              "casts": [{"sc": 4, "spell": "Storm Lord", "res": [[0, 20, 0.8]], "crit": [[1, 2, 1, 2]]},
                                        {"sc": 0, "spell": "Deathblade"}]},
                             {"hand": [], "played": {},
                              "casts": [{"sc": 0, "spell": "Wraith", "hp": [[4, 3000, -420]]}]}]}
        book = S.FoeBook(battles=[battle, battle])
        f = book.foe("Bonestriker")
        self.assertEqual((f.maxhp, f.school), (2400, "death"))
        self.assertAlmostEqual(f.resist["storm"], 0.8)
        self.assertEqual(f.block_p, 1.0)
        self.assertEqual(f.hits, [420, 420])
        self.assertAlmostEqual(f.hit_p, 0.5)
        unknown = book.foe("Nobody")
        self.assertIn("generic hitter", unknown.src)
        self.assertEqual(unknown.maxhp, 1000)


class Fixes(unittest.TestCase):
    """v0.9.0: what v0.8.0 got wrong"""

    def test_value_text_from_facts(self):
        # (cards.jsonl keeps handmem's value_text: an item card's kind and value only from there)
        facts = {123: {"kind": "damage", "value": "295-335", "school": "storm", "pips": 4, "heads": "storm:295"},
                 124: {"kind": "aoe", "value": "100/pip", "school": "fire", "pips": 0},
                 125: {"kind": "blade", "value": "35%", "school": "storm", "boosts": "storm:35"}}
        cards = S.deck_cards({"item_cards": [{"template_id": 123, "count": 1}, {"template_id": 124, "count": 1},
                                             {"template_id": 125, "count": 2}]}, facts)
        self.assertEqual(len(cards), 4)
        hit, meteor, blade = cards[0], cards[1], cards[2]
        self.assertEqual(hit.value, 295)
        self.assertAlmostEqual(hit.top, 335 / 295.0)
        self.assertTrue(meteor.x)
        self.assertEqual(meteor.value, 100)
        self.assertEqual(blade.boosts, {"storm": 35})
        self.assertEqual(S.value_of("+10%"), (10.0, None, False))
        self.assertEqual(S.value_of(""), (None, None, False))
        # (and deck learning with such an item card doesn't fall over)
        L = S.learn_decks({"decks": [{"gid": 5, "sets": [1], "display": "D", "cards": [hit_dict()],
                                      "item_cards": [{"template_id": 123, "count": 1, "name": "Wand"}]}]}, facts)
        self.assertEqual(L[0]["kinds"]["damage"], 2)

    def test_range_top_from_value_text(self):
        c = S.card_of({"display": "Kraken", "kind": "damage", "school": "storm", "pips": 4, "value": 485,
                       "value_text": "485-525", "heads_text": "storm:485"})
        self.assertAlmostEqual(c.top, 525 / 485.0)
        plain = S.card_of({"display": "X", "kind": "damage", "school": "storm", "pips": 4, "value": 100})
        self.assertEqual(plain.top, S.RANGE_TOP)

    def test_torn_line_keeps_the_rest(self):
        today = datetime.date.today()
        with tempfile.TemporaryDirectory() as base:
            folder = os.path.join(base, today.strftime("%Y-%m"))
            os.makedirs(folder)
            def battle(i):
                return json.dumps({"rec": "battle", "v": 1, "id": today.strftime("%Y%m%d") + "-0000%02d-%d" % (i, i),
                                   "me": {"sc": 4}, "parts": [{"sc": 0, "side": "enemy", "name": "Foe%d" % i,
                                                               "max": 100 * (i + 1)}], "rounds": []},
                                  separators=(",", ":"))      # (compact, as the recorder writes them)
            with open(os.path.join(folder, today.isoformat() + ".jsonl"), "w") as f:
                f.write('{"rec":"header","v":1}\n' + battle(1) + "\n" + battle(2)[:40] + "\n" + battle(3) + "\n")
            book = S.FoeBook(base, days=2)
        self.assertEqual(book.why, "")
        self.assertEqual(sorted(book.by), ["Foe1", "Foe3"])

    def test_crit_chance_learned(self):
        battle = {"me": {"sc": 4, "school": "storm"},
                  "parts": [{"sc": 0, "side": "enemy", "name": "Tank", "max": 3000}],
                  "rounds": [{"hand": [], "played": {"targets": [0]},
                              "casts": [{"sc": 4, "spell": "Kraken", "crit_p": [600, 150, 150, 0.2]}]},
                             {"hand": [], "played": {"targets": [0]},
                              "casts": [{"sc": 4, "spell": "Kraken", "crit_p": [600, 150, 150, 30]}]}]}
        f = S.FoeBook(battles=[battle]).foe("Tank")
        self.assertAlmostEqual(f.crit_p, 0.25)     # 0.2 and 30% -> their median
        # (no criticals at all when the game says 0, whatever the rating)
        f.crit_p = 0.0
        cards = S.deck_cards({"cards": [hit(count=30)]})
        none = S.simulate(cards, S.Me("storm", 5000, crit=900), [f], n=60, seed=5)
        f.crit_p = 1.0
        every = S.simulate(cards, S.Me("storm", 5000, crit=900), [f], n=60, seed=5)
        self.assertLess(every["rounds"], none["rounds"])

    def test_unknown_block_is_not_zero(self):
        f = S.Foe("x", 100)
        me = S.Me("storm", crit=400)
        self.assertEqual(f.block_for(me), 400)
        self.assertAlmostEqual(S.crit_chance(400, f.block_for(me)), 0.75)
        v = S.verdict(S.simulate(S.deck_cards({"cards": [hit(count=5)]}), me, [f], n=10, seed=1),
                      S.deck_cards({"cards": [hit(count=5)]}), me, [f])
        self.assertTrue(any("critical chance isn't known" in n for n in v["notes"]))

    def test_identical_blades_dont_stack(self):
        cards = S.deck_cards({"cards": [boost("blade", "Stormblade", 35, count=4)]})
        b = S._Battle(cards, S.Me("storm"), [S.Foe("x", 1000)], S.Opts(), random.Random(1))
        b.draw()
        blades = [c for c in b.hand if c.kind == "blade"]
        b.me.accuracy = 100
        b.cast(blades[0])
        b.cast(blades[1])
        self.assertEqual(len(b.blades), 1)
        plan = S.Card("Storm Lord", "damage", "storm", 7, heads={"storm": 1000})
        self.assertIsNone(b.pick_boost(plan))      # another Stormblade adds nothing


def hit_dict():
    return hit()


if __name__ == "__main__":
    unittest.main()
