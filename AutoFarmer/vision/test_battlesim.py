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
    """v1.0.0: what the simulator's first build got wrong"""

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


class FromState(unittest.TestCase):
    """v1.0.0: a battle started in the middle (the planner's round now)"""

    def cards(self):
        lord = S.Card("Storm Lord", "damage", "storm", 7, heads={"storm": 1000}, tid=1)
        snake = S.Card("Thunder Snake", "damage", "storm", 2, heads={"storm": 150}, tid=2)
        blade = S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tid=3)
        trap = S.Card("Storm Trap", "trap", "storm", 0, boosts={"storm": 30}, tid=4)
        return lord, snake, blade, trap

    def test_of_deck_takes_the_hand_out(self):
        lord, snake, blade, trap = self.cards()
        pet = S.Card("Pet Blade", "blade", "storm", 0, boosts={"storm": 20}, tid=99)
        st = S.State.of_deck([lord, snake, snake, pet], [lord] * 3 + [snake] * 4 + [blade] * 2, rnd=3)
        self.assertEqual(sorted(c.name for c in st.pile), ["Storm Lord"] * 2 + ["Stormblade"] * 2 + ["Thunder Snake"] * 2)
        self.assertEqual(st.used, 2)                  # (about a card a round drawn before)
        self.assertEqual(S.State([lord], rnd=1, used=5).used, 5)

    def test_state_carried_over(self):
        lord, snake, blade, trap = self.cards()
        st = S.State([lord, blade], [snake] * 10 + [trap] * 5, pips=5, power=2, hp=1234, fhp=[800, None, 0],
                     blades=[("Stormblade", {"storm": 35}), ("Stormblade", {"storm": 35})],
                     traps=[[], [{"storm": 30}]], aura=({"storm": 25}, 2), rnd=4, boosts_run=1, me_first=True,
                     fpips=[3, None, 1])
        foes = [S.Foe("A", 1000), S.Foe("B", 2000), S.Foe("C", 500)]
        b = S._Battle.from_state(st, S.Me("storm", 3000), foes, S.Opts(), random.Random(1))
        self.assertEqual([c.name for c in b.hand], ["Storm Lord", "Stormblade"])
        self.assertEqual(len(b.pile), 15 - 3)       # (the 3 cards drawn before round 4 taken off)
        self.assertEqual((b.pips, b.power, b.hp, b.fhp), (5, 2, 1234, [800, 2000, 0]))
        self.assertEqual(b.blades, [("Stormblade", {"storm": 35})])   # (identical blades don't stack)
        self.assertEqual(b.traps, [[], [{"storm": 30}], []])
        self.assertEqual((b.aura, b.round0, b.boosts_run, b.me_first), (({"storm": 25}, 2), 4, 1, True))
        self.assertEqual(b.fpips[0], 3)
        self.assertEqual(b.fpips[2], 1)
        self.assertEqual(b.alive(), [0, 1])
        # (the state itself is never changed by a rollout)
        b.run_from(None, None, 3)
        self.assertEqual((st.pips, len(st.hand), len(st.pile), st.blades[0][0]), (5, 2, 15, "Stormblade"))

    def test_forced_play_and_aim(self):
        lord, snake, blade, trap = self.cards()
        foes = [S.Foe("A", 3000), S.Foe("B", 900)]
        st = S.State([lord, trap], [snake] * 10, pips=7, fhp=[3000, 900], me_first=True)
        me = S.Me("storm", 3000, accuracy=30)        # (never a miss)
        b = S._Battle.from_state(st, me, foes, S.Opts(), random.Random(2))
        b.run_from(b.hand[0], 1, horizon=1)          # (Storm Lord at B, not the one with the most health)
        self.assertEqual(b.fhp[1], 0)
        self.assertEqual(b.fhp[0], 3000)
        self.assertIsNone(b.aim)
        b = S._Battle.from_state(st, me, foes, S.Opts(), random.Random(2))
        b.force(b.hand[1], 1)                         # (the trap on B)
        self.assertEqual(b.traps, [[], [{"storm": 30}]])
        b = S._Battle.from_state(st, me, foes, S.Opts(), random.Random(2))
        b.force(b.hand[1])                            # (no aim: the bot's own - the most health)
        self.assertEqual(b.traps, [[{"storm": 30}], []])

    def test_round_now_has_no_pip_or_draw(self):
        lord, snake, blade, trap = self.cards()
        st = S.State([snake], [lord] * 10, pips=2, fhp=[5000], me_first=True)
        b = S._Battle.from_state(st, S.Me("storm", 3000, power_pip=0), [S.Foe("A", 5000)], S.Opts(), random.Random(3))
        r = b.run_from(None, None, horizon=1)        # (a pass: nothing spent, nothing drawn in the round now)
        self.assertEqual((r, b.pips, len(b.hand), b.rounds_run), ("cut", 2, 1, 1))
        b = S._Battle.from_state(st, S.Me("storm", 3000, power_pip=0), [S.Foe("A", 5000)], S.Opts(), random.Random(3))
        b.run_from(None, None, horizon=2)            # (round two: a pip and the hand refilled)
        self.assertEqual(b.pips, 3 - (2 if b.casts.get("Thunder Snake") else 0))
        self.assertGreaterEqual(len(b.hand) + sum(b.casts.values()), 7)

    def test_chain_as_simulate_plays_it(self):
        # (play=False: the round now is the bot's chain - choose - with no draw or discard)
        lord, snake, blade, trap = self.cards()
        st = S.State([snake, blade], [lord] * 5, pips=3, fhp=[5000], me_first=True)
        b = S._Battle.from_state(st, S.Me("storm", 3000, accuracy=30), [S.Foe("A", 5000)], S.Opts(cardlogic=1),
                                 random.Random(4))
        self.assertIs(b.choose(), b.hand[1])        # (boost first: the blade for the planned hit)
        b.run_from(False, None, horizon=1)
        self.assertEqual(b.casts, {"Stormblade": 1})


def hit_dict():
    return hit()


# ============================================================================ v1.0.0 batch 3: what the simulator lacked
def lord(tid=1, dot=None, value=1000, pips=7):
    return S.Card("Storm Lord", "damage", "storm", pips, heads={"storm": value}, tid=tid, dot=dot)


def biter(name="Biter", hp=6000, lo=100, hi=120, passes=False):
    """an enemy biting every round it can (passes: half its rounds a pass)"""
    return S.Foe(name, hp, spells=([(None, 1.0, None)] if passes else []) +
                 [("Bite", 1.0, {"pips": 1, "min": lo, "max": hi, "accuracy": 100})])


def sure(**kw):
    kw.setdefault("accuracy", 30)
    return S.Me("storm", kw.pop("maxhp", 3000), **kw)


class Dots(unittest.TestCase):
    def test_a_hits_damage_over_time_ticks(self):
        # (Fire Dragon's kind: 1000 now and 600 over 3 rounds - a tick of 200 at each of the next rounds' start)
        c = S.card_of({"display": "Dragon", "kind": "damage", "school": "storm", "pips": 1, "value": 1000,
                       "heads_text": "storm:1000", "dot": 600})
        self.assertEqual(c.dot, 600)
        self.assertEqual(S.card_of({"display": "X", "kind": "damage", "school": "storm", "value": 5}).dot, 0)
        self.assertEqual(S.Card("B", "blade", "storm", value=35, dot=600).dot, 0)     # (only a hit's)
        foe = S.Foe("Tank", 5000, resist={"storm": 1.0})
        tower = S.Card("Tower Shield", "ward", "ice", 0, value=50)
        st = S.State([c], [tower] * 20, pips=7, fhp=[5000], me_first=True)
        b = S._Battle.from_state(st, sure(power_pip=0), [foe], S.Opts(discardunused=0), random.Random(1))
        b.force(b.hand[0], 0)
        after = b.fhp[0]
        self.assertEqual(b.fdots[0], [[200.0, 3]])
        # (no hit in hand: the ticks only - its Tower Shields now go on me as the chain's filler, which deals nothing)
        r = b.run_from(None, None, horizon=5)
        self.assertEqual(r, "cut")
        self.assertEqual(after - b.fhp[0], 600)
        b = S._Battle.from_state(st, sure(power_pip=0), [foe], S.Opts(), random.Random(1))
        b.force(b.hand[0], 0)
        b.round = 1
        for _ in range(4):
            b.tick_dots()
        self.assertEqual(after - b.fhp[0], 600)                     # (3 ticks, then none)
        self.assertEqual(b.fdots[0], [])

    def test_no_dot_on_a_dead_enemy(self):
        c = S.Card("Dragon", "damage", "storm", 1, heads={"storm": 1000}, dot=600)
        st = S.State([c], [], pips=7, fhp=[500], me_first=True)
        b = S._Battle.from_state(st, sure(), [S.Foe("Rat", 500)], S.Opts(), random.Random(1))
        b.force(b.hand[0], 0)
        self.assertEqual((b.fhp[0], b.fdots[0]), (0, []))


def foe_rounds(foe, team=1, mates=None, n=3000, seed=1):
    """enemy foe's rounds alone against my side (nobody ever down): (the share of them it healed in, damage a round on
    me, on my whole side)"""
    st = S.State([], [], hp=10 ** 9, fhp=[1000], me_first=False, mates=mates or [])
    b = S._Battle.from_state(st, S.Me("storm", 10 ** 9, team=team), [foe], S.Opts(), random.Random(seed))
    heals = on_me = on_side = 0
    for _ in range(n):
        b.fhp[0] = 1000
        hp0 = [b._wiz(k).hp for k in b.wizards()]
        b.foe_round()
        hp1 = [b._wiz(k).hp for k in b.wizards()]
        heals += b.fhp[0] > 1000
        on_me += hp0[0] - hp1[0]
        on_side += sum(hp0) - sum(hp1)
    return heals / float(n), on_me / float(n), on_side / float(n)


def enemy_record(acts_round, n_rounds=4, zone="WizardCity/WC_Streets"):
    """a battle record where the enemy (sc 0, 'Shaman') does acts_round's casts (its hang / hp / fx) each round"""
    rounds = []
    for k in range(n_rounds):
        rounds.append({"n": k + 1, "hand": [], "played": None, "casts": [dict(acts_round, sc=0)]})
    return {"zone": zone, "me": {"sc": 4, "school": "storm"},
            "parts": [{"sc": 0, "side": "enemy", "name": "Shaman", "max": 3000},
                      {"sc": 1, "side": "enemy", "name": "Imp", "max": 800},
                      {"sc": 4, "side": "me"}, {"sc": 5, "side": "ally"}], "rounds": rounds}


class LearnedActs(unittest.TestCase):
    def test_what_an_enemy_does_besides_hitting(self):
        shield = {"spell": "Dark Shield", "hang": [[0, "kModifyIncomingDamage", 0, -50]]}
        heal = {"spell": "Mend", "hp": [[1, 300, 400]]}
        blade = {"spell": "Deathblade", "hang": [[0, "ModifyOutgoingDamage", 1, 35]]}
        trap = {"spell": "Death Trap", "hang": [[4, "kModifyIncomingDamage", 0, 30]]}
        weak = {"spell": "Weakness", "hang": [[5, "kModifyOutgoingDamage", 1, -25]]}
        stun = {"spell": "Stun", "fx": [[4, "kStun", 1]]}
        bite = {"spell": "Bite", "hp": [[4, 3000, -300]]}
        recs = [enemy_record(shield), enemy_record(heal), enemy_record(blade), enemy_record(trap), enemy_record(weak),
                enemy_record(stun), enemy_record(bite, n_rounds=12)]
        f = S.FoeBook(battles=recs).foe("Shaman")
        self.assertEqual(set(f.acts), {"heal", "shield", "blade", "trap", "weak", "stun"})
        self.assertAlmostEqual(f.acts["shield"]["p"], 4 / 36.0)
        self.assertEqual((f.acts["shield"]["v"], f.acts["heal"]["v"], f.acts["blade"]["v"], f.acts["trap"]["v"],
                          f.acts["weak"]["v"]), (50, 400, 35, 30, 25))
        self.assertIsNone(f.acts["stun"]["v"])
        self.assertAlmostEqual(f.dmg_p, 12 / 36.0)
        self.assertIn("besides its hits", f.src)
        self.assertEqual(f.hits, [300] * 12)

    def test_damage_over_time_ticks_learned(self):
        # (its DoT on me in round 1, ticks of 90 on me at the start of rounds 2-4 - outside any cast)
        dot = {"spell": "Poison", "hp": [[4, 3000, -100]], "hang": [[4, "kDamageOverTime", 0, 270]]}
        rec = enemy_record({"spell": "Bite", "hp": [[4, 3000, -100]]}, n_rounds=4)
        rec["rounds"][0]["casts"] = [dict(dot, sc=0)]
        for k in (1, 2, 3):
            rec["rounds"][k]["fx"] = {"hp": [[4, 2900, -90]]}
        f = S.FoeBook(battles=[rec]).foe("Shaman")
        self.assertEqual(f.acts["dot"], {"p": 0.25, "v": 90.0})

    def test_nothing_learned_nothing_changes(self):
        f = S.FoeBook(battles=[enemy_record({"spell": "Bite", "hp": [[4, 3000, -300]]})]).foe("Shaman")
        self.assertEqual(f.acts, {})
        self.assertNotIn("besides", f.src)
        # (a foe with acts {} and the same foe never given any: the same battles, number for number)
        cards = S.deck_cards({"cards": [hit(count=20)]})
        a = S.simulate(cards, S.Me("storm", 3000), [biter()], n=80, seed=7)
        g = biter()
        g.acts, g.dmg_p = {}, 0.5
        b = S.simulate(cards, S.Me("storm", 3000), [g], n=80, seed=7)
        self.assertEqual((a["won"], a["rounds"], a["hp_left"], a["dmg_in"]), (b["won"], b["rounds"], b["hp_left"],
                                                                              b["dmg_in"]))

    def test_acts_in_the_battle(self):
        cards = S.deck_cards({"cards": [hit("Bolt", 1, 500, count=40)]})
        me = S.Me("storm", 30000)
        plain = S.simulate(cards, me, [biter("Tank", 4000, passes=True)], n=120, seed=3)
        shielder = biter("Tank", 4000, passes=True)
        shielder.acts, shielder.dmg_p = {"shield": {"p": 0.5, "v": 50}}, 0.5
        shielded = S.simulate(cards, me, [shielder], n=120, seed=3)
        self.assertGreater(shielded["rounds"], plain["rounds"])
        healer = biter("Tank", 4000, passes=True)
        healer.acts, healer.dmg_p = {"heal": {"p": 0.5, "v": 300}}, 0.5
        self.assertGreater(S.simulate(cards, me, [healer], n=120, seed=3)["rounds"], plain["rounds"])
        # (a blade on itself and a trap on me: its hits harder)
        bladed = biter("Tank", 4000, passes=True)
        bladed.acts, bladed.dmg_p = {"blade": {"p": 0.5, "v": 100}, "trap": {"p": 0.5, "v": 100}}, 0.5
        # (the same seed: a blade and a trap that did nothing would leave it as plain's - 100% each: well over)
        self.assertGreater(S.simulate(cards, me, [bladed], n=120, seed=3)["dmg_in"], plain["dmg_in"] * 1.5)

    def test_acts_not_inflated_by_the_team(self):
        # (it hits one of my side 80% of the rounds and healed in 20%: 20% whoever of us its hits land on - alone with
        # Me.team 4 a single hit on another wizard is still a round it hit, not one free for a heal)
        def foe():
            f = S.Foe("Ogre", 90000, spells=[(None, 0.2, None), ("Bite", 0.8, {"pips": 0, "min": 10, "max": 10,
                                                                                 "accuracy": 100})])
            f.acts, f.dmg_p = {"heal": {"p": 0.2, "v": 100}}, 0.8
            return f
        for team in (1, 4):
            heals, _me, _side = foe_rounds(foe(), team=team)
            self.assertTrue(0.16 < heals < 0.24, (team, heals))
        # (known by its hits only, recorded in a party: on me 20% of the rounds, on one of us 80%, a heal 20%)
        f = S.Foe("Ghoul", 90000, hits=[300] * 10, hit_p=0.2)
        f.acts, f.dmg_p = {"heal": {"p": 0.2, "v": 100}}, 0.8
        heals, on_me, _side = foe_rounds(f)
        self.assertTrue(0.16 < heals < 0.24, heals)
        self.assertTrue(50 < on_me < 70, on_me)                     # (300 a hit, 20% of the rounds)

    def test_stun_skips_my_round(self):
        st = S.State([lord()], [], pips=7, fhp=[5000], me_first=True, stun=1)
        b = S._Battle.from_state(st, sure(), [S.Foe("Rat", 5000)], S.Opts(), random.Random(1))
        self.assertFalse(b.my_round(fresh=False))
        self.assertEqual((b.stun, len(b.hand)), (0, 1))
        stunner = S.Foe("Stunner", 5000, spells=[(None, 1.0, None)])
        stunner.acts, stunner.dmg_p = {"stun": {"p": 1.0, "v": None}}, 0.0
        b = S._Battle.from_state(S.State([lord()], [], pips=7, fhp=[5000], me_first=False), sure(), [stunner],
                                 S.Opts(), random.Random(1))
        b.foe_round()
        self.assertEqual(b.stun, 1)


class Charms(unittest.TestCase):
    """the charms on now (State: from the bot or the game's log - charms_from) in the battle"""

    def test_shields_and_weakness_on_my_hit(self):
        foe = S.Foe("Tank", 9000, resist={"storm": 1.0})
        st = S.State([lord()], [], pips=7, fhp=[9000], fshields=[[(50, ["storm"]), (20, ["fire"])]],
                     myweak=[(25, None)], me_first=True)
        b = S._Battle.from_state(st, sure(), [foe], S.Opts(), random.Random(1))
        self.assertAlmostEqual(b.least(b.hand[0], 0), 1000 * 0.5 * 0.75)
        b.force(b.hand[0], 0)
        self.assertEqual(b.fshields[0], [(20, ["fire"])])           # (the storm one used, the fire one left)
        self.assertEqual(b.myweak, [])

    def test_shields_traps_absorb_on_me(self):
        foe = S.Foe("Smasher", 9000, school="death", spells=[("Smash", 1.0, {"pips": 0, "min": 1000, "max": 1000,
                                                                           "accuracy": 100})])
        st = S.State([lord()], [], pips=0, fhp=[9000], shields=[(50, ["death"]), (40, ["fire"])],
                     mytraps=[(20, None)], absorb=100, me_first=False)
        b = S._Battle.from_state(st, sure(), [foe], S.Opts(), random.Random(1))
        b.foe_round()
        self.assertEqual(b.hp, 3000 - int(1000 * 1.2 * 0.5 - 100))
        self.assertEqual((b.shields, b.mytraps, b.absorb), ([(40, ["fire"])], [], 0))

    def test_charms_from_the_log(self):
        import battlerec
        facts = {104: {"name": "Stormblade", "boosts": "storm:35"}, 105: {"name": "Storm Trap", "boosts": "storm:30"}}
        d = {"me_sc": 4, "rounds": [{"n": 1, "casts": [
            {"sc": 5, "spell": "Stormblade", "hang": [[4, "kModifyOutgoingDamage", 1, 35]]},
            {"sc": 5, "spell": "Storm Trap", "hang": [[1, "kModifyIncomingDamage", 0, 30]]},
            {"sc": 1, "spell": "Shield", "hang": [[1, "kModifyIncomingDamage", 0, -50]]},
            {"sc": 0, "spell": "Curse", "hang": [[4, "kModifyIncomingDamage", 0, 25]]}]}]}
        ch = battlerec.charms_now(d, facts)
        st = S.State([lord()], [], pips=7, fhp=[900, 900], blades=[("storm/blade", {"storm": 35})])
        n = st.charms_from(ch, None, [0, 1])
        self.assertEqual(n, 4)
        self.assertEqual(st.blades, [("Stormblade", {"storm": 35.0})])
        self.assertEqual(st.traps, [[], [{"storm": 30.0}]])
        self.assertEqual(st.fshields, [[], [(50, None)]])
        self.assertEqual(st.mytraps, [(25, None)])
        # (an enemy not matched to its subcircle: nothing put on it)
        st = S.State([lord()], [], fhp=[900, 900])
        st.charms_from(ch, 4, [None, None])
        self.assertEqual((st.traps, st.fshields), ([[], []], [[], []]))
        self.assertEqual(S.State([lord()]).charms_from(None), 0)
        self.assertEqual(S.State([lord()]).charms_from({"by": "junk"}), 0)

    def test_an_enemy_not_matched_keeps_the_bots_count(self):
        # (the bot's Storm Trap on enemy 0; the log matched to enemy 1 only: enemy 0's trap kept, 1's from the log)
        import battlerec
        d = {"me_sc": 4, "rounds": [{"n": 1, "casts": [
            {"sc": 1, "spell": "Shield", "hang": [[1, "kModifyIncomingDamage", 0, -50]]}]}]}
        ch = battlerec.charms_now(d, {})
        st = S.State([lord()], [], fhp=[900, 900], traps=[[{"storm": 30}], [{"fire": 25}]],
                     fshields=[[(20, None)]], fblades=[[], [(10, None)], [(5, None)]])
        self.assertEqual(st.charms_from(ch, 4, [None, 1]), 1)
        self.assertEqual(st.traps, [[{"storm": 30}], []])
        self.assertEqual(st.fshields, [[(20, None)], [(50, None)]])
        self.assertEqual(st.fblades, [[], [], [(5, None)]])          # (one past the plates: kept as it was)

    def test_blade_named_as_the_hand_shows_it(self):
        # (the log names a spell by its template; the hand by its display - the blade on is the hand's card's name, so
        # a copy in hand is "on already" and never stacked)
        import battlerec
        facts = {104: {"tid": 104, "name": "Storm Blade", "display": "Stormblade", "kind": "blade",
                       "boosts": "storm:35"}}
        d = {"me_sc": 4, "rounds": [{"n": 1, "casts": [
            {"sc": 4, "spell": "Storm Blade", "hang": [[4, "kModifyOutgoingDamage", 1, 35]]}]}]}
        st = S.State([], [])
        st.charms_from(battlerec.charms_now(d, facts))
        self.assertEqual(st.blades, [("Stormblade", {"storm": 35.0})])
        blade = S.card_of({"template_id": 104, "name": "Storm Blade", "display": "Stormblade", "kind": "blade",
                           "school": "storm", "boosts_text": "storm:35"})
        self.assertEqual(blade.name, st.blades[0][0])

    def test_empty_charms_change_nothing(self):
        hand = [lord(), S.Card("Snake", "damage", "storm", 2, heads={"storm": 150}, tid=2),
                S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tid=3)]
        foes = [biter("A", 2400), biter("B", 1200)]
        a = S.plan_round(S.State(hand, hand * 3, pips=6, fhp=[2000, 900], rnd=3), sure(), foes, n=30, seed=5,
                         budget_ms=10000)
        b = S.plan_round(S.State(hand, hand * 3, pips=6, fhp=[2000, 900], rnd=3, shields=[], fshields=[[], []],
                                 fblades=[], mytraps=None, myweak=[], absorb=0, stun=0, mates=[]), sure(), foes, n=30,
                         seed=5, budget_ms=10000)
        strip = lambda p: [(x["name"], x["aim"], x["n"], round(x["score"], 9)) for x in p["plays"]]  # noqa: E731
        self.assertEqual(strip(a), strip(b))

    def test_junk_charms(self):
        st = S.State([lord()], shields=[("x", None), (30, "storm"), None, (float("nan"), None), (25, ["storm", "q"])],
                     fshields="junk", fblades=[[(-5, None)]], stun="9", absorb="abc", mates=["no", 5], seat="x")
        self.assertEqual(st.shields, [(30, None), (25, ["storm"])])
        self.assertEqual((st.fshields, st.fblades, st.stun, st.absorb, st.mates, st.seat), ([], [[]], 3, 0, [], 0))


def mate(name, seat, role="hitter", hand=None, hp=None, maxhp=3000, pips=0):
    return S.Mate(name, seat, S.Me("storm", maxhp, accuracy=30), role, hand, [], pips, 0, hp)


class Team(unittest.TestCase):
    def test_side_in_cast_order(self):
        st = S.State([lord()], [], pips=7, fhp=[9000], seat=6,
                     mates=[mate("Bob", 7), mate("Ann", 4, "blader", []), mate("Cy", None, "healer", [])])
        b = S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
        self.assertEqual([b._wiz(k).name if k else "me" for k in b.wizards()], ["Ann", "me", "Bob", "Cy"])
        self.assertTrue(b.side[1].nohand)                            # (Bob: its hand not known)
        self.assertFalse(b.side[2].nohand)                           # (Ann: an empty hand is known)
        self.assertEqual(b.hitter(), 0)                              # (me, before Bob)

    def test_blader_puts_its_blade_on_the_hitter(self):
        blade = S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tid=3)
        trap = S.Card("Storm Trap", "trap", "storm", 0, boosts={"storm": 30}, tid=4)
        st = S.State([lord()], [], pips=0, fhp=[9000], seat=5, me_first=True,
                     mates=[mate("Ann", 4, "blader", [blade, trap])])
        b = S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
        b.side_round(0, {})
        self.assertEqual(b.blades, [("Stormblade", {"storm": 35})])   # (on me - Ann's own: none)
        self.assertEqual(b.side[1].blades, [])
        self.assertEqual(b.cur, 0)
        b.side_round(1, {})                                          # (next round: the trap on the boss)
        self.assertEqual(b.traps, [[{"storm": 30}]])

    def test_healer_heals_the_lowest(self):
        heal = S.Card("Satyr", "heal", "life", 0, value=900, tid=6)
        st = S.State([lord()], [], pips=0, hp=600, fhp=[9000], me_first=True,
                     mates=[mate("Ann", 5, "healer", [heal]), mate("Bob", 6, hp=2000)])
        b = S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
        b.side_round(0, {})
        self.assertEqual((b.hp, b.side[2].hp), (1500, 2000))

    def test_single_hits_spread_and_lost_only_when_all_down(self):
        foe = S.Foe("Ogre", 90000, spells=[("Smash", 1.0, {"pips": 0, "min": 400, "max": 400, "accuracy": 100})])
        st = S.State([], [], hp=3000, fhp=[90000], me_first=False, mates=[mate("Bob", 5, hp=3000)])
        b = S._Battle.from_state(st, sure(), [foe], S.Opts(), random.Random(2))
        for _ in range(6):
            b.foe_round()
        self.assertEqual(b.hp + b.side[1].hp, 6000 - 6 * 400)
        self.assertTrue(b.hp < 3000 and b.side[1].hp < 3000)         # (both hit)
        b.hp = 0
        self.assertFalse(b.lost())                                   # (Bob's still up)
        b.side[1].hp = 0
        self.assertTrue(b.lost())

    def test_unknown_hitter_mate_and_plan(self):
        # (a hitter mate whose hand isn't known: the generic hitter - the boss falls sooner than with me alone)
        snake = S.Card("Snake", "damage", "storm", 2, heads={"storm": 150}, tid=2)
        foes = [S.Foe("Boss", 1500, spells=[("Hit", 1.0, {"pips": 1, "min": 50, "max": 60, "accuracy": 100})])]
        alone = S.plan_round(S.State([snake], [snake] * 20, pips=2, fhp=[1500], me_first=True), sure(), foes, n=40,
                             seed=1, budget_ms=10000, horizon=30)
        st = S.State([snake], [snake] * 20, pips=2, fhp=[1500], me_first=True, mates=[mate("Bob", 5, pips=5)])
        team = S.plan_round(st, sure(), foes, n=40, seed=1, budget_ms=10000, horizon=30)
        r = lambda p: next(x for x in p["plays"] if x["name"] == "Snake")["rounds"]   # noqa: E731
        self.assertLess(r(team), r(alone))

    def test_plan_team_orders(self):
        # (Ann - a hitter mate - holds the kill; me a Snake: the team's plan gives Ann the kill)
        tempest = S.Card("Tempest", "aoe", "storm", 4, heads={"storm": 900}, tid=7)
        snake = S.Card("Snake", "damage", "storm", 2, heads={"storm": 150}, tid=2)
        foes = [biter("A", 600), biter("B", 600)]
        st = S.State([snake], [snake] * 10, pips=2, fhp=[600, 600], seat=4, me_first=True,
                     mates=[mate("Ann", 5, hand=[tempest, snake], pips=4), mate("Bob", 6, "blader")])
        tp = S.plan_team(st, sure(), foes, n=20, seed=3, budget_ms=8000)
        self.assertEqual([o["who"] for o in tp["orders"]], [0, 1])  # (Bob's hand not known: no order for it)
        ann = tp["orders"][1]
        self.assertEqual((ann["name"], ann["card"], ann["seat"]), ("Ann", "Tempest", 5))
        self.assertGreater(ann["won"], 0.9)
        self.assertTrue(any("hand isn't known" in w for w in tp["why"]))
        lines = S.team_lines(tp, foes)
        self.assertTrue(lines[1].startswith("order|1|5|Ann|0|7|aoe|all|"), lines)
        self.assertTrue(any(ln.startswith("teamnote|") for ln in lines))

    def test_recorded_hits_on_each_wizard(self):
        # (known by its hits on me only: half the rounds, 300 - with 3 mates each of us still takes them at that rate,
        # the side four times it - not my own rate shared out)
        def foe():
            return S.Foe("Ghoul", 90000, hits=[300] * 10, hit_p=0.5)
        _h, alone, _s = foe_rounds(foe())
        _h, on_me, on_side = foe_rounds(foe(), mates=[mate(nm, s, maxhp=10 ** 9) for nm, s in (("A", 5), ("B", 6),
                                                                                                ("C", 7))])
        self.assertTrue(135 < alone < 165 and 135 < on_me < 165, (alone, on_me))
        self.assertTrue(540 < on_side < 660, on_side)

    def test_a_mate_down(self):
        # (the party's 0 %: down - still in the duel, never back to full health; not known: its max)
        self.assertEqual([S.Mate(hp=v).hp for v in (0, "0", None, "", "x", float("nan"), -5, 1200)],
                         [0, 0, None, None, None, None, 0, 1200])
        foe = S.Foe("Ogre", 90000, spells=[("Smash", 1.0, {"pips": 0, "min": 400, "max": 400, "accuracy": 100})])
        st = S.State([], [], hp=3000, fhp=[90000], me_first=False, mates=[mate("Ann", 5, hp=0), mate("Bob", 6)])
        b = S._Battle.from_state(st, sure(), [foe], S.Opts(), random.Random(2))
        self.assertEqual([b._wiz(k).hp for k in b.wizards()], [3000, 0, 3000])
        self.assertEqual(b.up(), [0, 2])
        for _ in range(6):
            b.foe_round()
        self.assertEqual(b.side[1].hp, 0)                           # (Ann soaks no hit)
        self.assertEqual(b.hp + b.side[2].hp, 6000 - 6 * 400)

    def test_team_junk_never_raises(self):
        for st in (S.State([lord()], mates=[mate("", None, "x", ["junk", None])]), S.State(None, mates=[]),
                   S.State([lord()], fhp=[0], mates=[mate("A", 5)])):
            tp = S.plan_team(st, sure(), [biter()], budget_ms=30)
            self.assertIsInstance(tp["orders"], list)
            self.assertIsInstance(S.team_lines(tp, [biter()]), list)
            p = S.plan_round(st, sure(), [biter()], budget_ms=30)
            self.assertIsInstance(p["plays"], list)
        self.assertEqual(S.plan_team(S.State([lord()]), sure(), [])["why"], ["no enemies"])


class BestDecks(unittest.TestCase):
    def test_groups_by_zone(self):
        recs = [enemy_record({"spell": "Bite"}, zone="Z1"), enemy_record({"spell": "Bite"}, zone="Z1"),
                enemy_record({"spell": "Bite"}, zone="Z2"), enemy_record({"spell": "Bite"}, zone=None)]
        book = S.FoeBook(battles=recs)
        self.assertEqual(dict(book.groups["Z1"]), {("Imp", "Shaman"): 2})
        self.assertEqual(sorted(book.groups), ["Z1", "Z2"])

    def test_the_stronger_deck_first(self):
        strong = S.deck_cards({"cards": [hit("Storm Lord", 3, 1500, count=20)]})
        weak = S.deck_cards({"cards": [hit("Thunder Snake", 2, 100, count=20)]})
        groups = {("Rat", "Rat"): 5, ("Ogre",): 1}
        made = {"Rat": 900, "Ogre": 4000}
        res = S.best_decks([("a1", "Weak", weak, S.Opts()), ("b2", "Strong", strong, S.Opts())], groups,
                           lambda names: [biter(nm, made[nm]) for nm in names], S.Me("storm", 3000), n=30, seed=1)
        self.assertEqual([d["name"] for d in res["decks"]], ["Strong", "Weak"])
        self.assertEqual(res["groups"], [(("Rat", "Rat"), 5), (("Ogre",), 1)])
        best = res["decks"][0]
        self.assertGreater(best["won"], res["decks"][1]["won"] - 1e-9)
        self.assertEqual((best["groups"], best["battles"]), (2, 6))
        lines = S.deckfor_lines(res, "Z1")
        self.assertTrue(lines[0].startswith("deckfor|b2|Strong|"))
        self.assertIn("group|5|Rat,Rat", lines)
        self.assertIn("zone|Z1", lines)

    def test_same_cards_score_the_same(self):
        # (one deck in two Equipment Sets, its cards listed apart: the same numbers, seed or none - common random
        # numbers, so DeckForZone's 5-point gap is never the dice's)
        a = S.deck_cards({"cards": [hit("Storm Lord", 3, 700, count=10), hit("Thunder Snake", 2, 300, count=10)]})
        b = S.deck_cards({"cards": [hit("Thunder Snake", 2, 300, count=10), hit("Storm Lord", 3, 700, count=10)]})
        groups = {("Ghoul", "Ghoul", "Wraith"): 12, ("Ghoul",): 5}
        made = {"Ghoul": 1200, "Wraith": 2000}
        def run(decks, seed=None):
            res = S.best_decks(decks, groups, lambda names: [biter(nm, made[nm], 500, 700) for nm in names],
                               S.Me("storm", 3000), n=30, seed=seed)
            return [(d["won"], d["lost"], d["rounds"], d["hp_left"]) for d in res["decks"]]
        for seed in (None, 5):
            x, y = run([("a", "A", a, S.Opts()), ("b", "B", b, S.Opts())], seed)
            self.assertEqual(x, y)
            self.assertLess(x[0], 1.0)                              # (close fights: the dice matter)
        # (asked again - the helper every 10 minutes: the same answer, not a new roll)
        self.assertEqual(run([("a", "A", a, S.Opts())]), run([("b", "B", b, S.Opts())]))

    def test_pause_before_each_simulation_not_counted(self):
        # (vision.py's gate_wait: the gated reads go first - its time never cuts a deck off the budget)
        import time
        cards = S.deck_cards({"cards": [hit("Storm Lord", 3, 1500, count=20)]})
        groups = {("Rat",): 2, ("Ogre",): 1}
        made = {"Rat": 900, "Ogre": 4000}
        calls = []

        def pause():
            calls.append(1)
            time.sleep(0.03)
        decks = [("a", "A", cards, S.Opts()), ("b", "B", cards, S.Opts())]
        res = S.best_decks(decks, groups, lambda names: [biter(nm, made[nm]) for nm in names], S.Me("storm", 3000),
                           n=5, seed=1, budget_ms=60, pause=pause)
        self.assertEqual(len(calls), 4)                             # (2 decks x 2 groups)
        self.assertEqual([d["key"] for d in res["decks"]], ["a", "b"])
        self.assertFalse(any("not simulated in the time given" in w for w in res["why"]), res["why"])

    def test_no_groups_and_junk(self):
        res = S.best_decks([("a", "A", [], S.Opts())], {}, lambda names: [], S.Me())
        self.assertEqual(res["decks"], [])
        self.assertTrue(S.deckfor_lines(res)[0].startswith("none|no enemy group known"))
        res = S.best_decks(None, [["Rat"]], lambda names: 1 / 0, S.Me())
        self.assertTrue(any("couldn't all be simulated" in w for w in res["why"]))
        self.assertEqual(S.deckfor_lines(None), ["none|no deck to simulate"])

    def test_verdict_says_what_was_learned(self):
        cards = S.deck_cards({"cards": [hit(count=10)]})
        f, g = biter("Shaman", 2000), biter("Rat", 500)
        f.acts = {"shield": {"p": 0.2, "v": 50}}
        r = S.simulate(cards, S.Me("storm", 3000), [f, g], n=20, seed=1)
        v = S.verdict(r, cards, S.Me("storm", 3000), [f, g])
        self.assertTrue(any(n.startswith("learned from the battles recorded") and "Shaman shield" in n
                            for n in v["notes"]), v["notes"])
        self.assertTrue(any(n.startswith("not modelled:") and "Rat" in n and "Shaman" not in n for n in v["notes"]))


# ============================================================================ the bot's whole chain: enchants, the defend
# check, Tower Shield / absorb and the filler, Reshuffle and the spent pile, the support's chain
def snake():
    return S.Card("Thunder Snake", "damage", "storm", 2, heads={"storm": 150}, tid=2)


def ench(name="Epic", value=300, tc=False):
    return S.Card(name, "enchant", "", 0, value=value, tc=tc)


def tower():
    return S.Card("Tower Shield", "ward", "ice", 0, value=50, tid=60)


def absorb(pips=0, value=200):
    return S.Card("Spirit Armor", "absorb", "", pips, value=value, tid=61)


def resh():
    return S.Card("Reshuffle", "manipulation", "", 0, tid=62)


def satyr():
    return S.Card("Satyr", "heal", "life", 3, value=900, tid=6)


def stormblade():
    return S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tid=3)


def smasher(hp=9000, dmg=1000):
    return S.Foe("Smasher", hp, spells=[("Smash", 1.0, {"pips": 0, "min": dmg, "max": dmg, "accuracy": 100})])


def battle(hand, pile=(), foes=None, opts=None, seed=1, **kw):
    """a battle from a State (sure(): storm, 3000 health, never a miss; an enemy with no resist learned: x0.85)"""
    st = S.State(list(hand), list(pile), **dict({"fhp": None, "me_first": True}, **kw))
    return S._Battle.from_state(st, sure(), foes or [S.Foe("A", 9000)], opts or S.Opts(), random.Random(seed))


def names(cards):
    return [c.name for c in cards]


class Enchants(unittest.TestCase):
    """Part A: the bot's damage enchants on every hit its chain casts (Autofarmer.ahk UseHit, KillCalc.ahk HeadsDamage /
    FindLethalHit)"""

    def test_cards_read(self):
        e = S.card_of({"name": "Epic", "kind": "enchant", "value": 300})
        self.assertEqual((e.kind, e.value, e.hit, e.bot_ench), ("enchant", 300.0, False, "epic"))
        c = S.card_of({"template_id": 5}, {5: {"kind": "enchant", "value": "+275", "name": "Colossal"}})
        self.assertEqual((c.value, c.bot_ench), (275, "colossal"))
        self.assertEqual(S.card_of({"name": "Primordial", "kind": "enchant", "value": 350}).bot_ench, "")
        self.assertEqual(S.enchant_add(S.Card("Strong", "enchant")), 100)        # (no number: the bot's default)
        self.assertEqual(S.enchant_add(S.Card("Primordial", "enchant", value=350)), 0)
        self.assertEqual(S.enchant_add(None), 0)
        d = {"name": "Storm Lord", "kind": "damage", "school": "storm", "pips": 7, "value": 1000,
             "heads_text": "storm:1000", "ench_effect": "kModifyCardDamage +175"}
        h = S.card_of(d)
        self.assertEqual((h.ench, h.heads), (175.0, {"storm": 1000.0}))
        self.assertEqual(S.card_of(dict(d, kind="blade")).ench, 0.0)          # (only a hit's)
        self.assertEqual(S.card_of(dict(d, ench_effect="kModifyCardAccuracy +10")).ench, 0.0)
        self.assertEqual(lord().ench, 0.0)

    def test_least_with_an_add(self):
        b = S._Battle([], S.Me("storm"), [S.Foe("A", 900)], S.Opts(), random.Random(1))
        self.assertEqual(b.least(lord(), 0), 850)                              # (unchanged)
        self.assertAlmostEqual(b.least(lord(), 0, add=300), 1105.0)
        c = S.Card("Storm Lord", "damage", "storm", 7, heads={"storm": 1000}, ench=300)
        self.assertAlmostEqual(b.least(c, 0), 1105.0)                          # (the enchantment on it counted)
        b = S._Battle([], S.Me("storm"), [S.Foe("A", 900, resist={"fire": 0.5, "ice": 0.85, "storm": 0.85})], S.Opts(),
                      random.Random(1))
        hydra = S.Card("Hydra", "damage", "fire", 8, heads={"fire": 230, "ice": 230, "storm": 230})
        self.assertAlmostEqual(b.least(hydra, 0, add=300), 230 * 0.5 + 2 * 230 * 0.85 + 300 * 0.5)   # (the least head)
        self.assertEqual(b._add_head(hydra, 0), "fire")
        b = S._Battle([], S.Me("fire"), [S.Foe("A", 900)], S.Opts(), random.Random(1))
        b.pips, b.power = 5, 2
        meteor = S.Card("Meteor", "aoe", "fire", 0, x=True, heads={"fire": 100})
        self.assertAlmostEqual(b.least(meteor, 0, add=300), (7 * 100 + 300) * 0.85)   # (once, not a pip)

    def test_pass_one_kill_saves_the_enchant(self):
        b = battle([lord(), ench()], pips=7, fhp=[700], foes=[S.Foe("A", 900)])
        self.assertTrue(b.my_round(fresh=False))                               # (850 >= 700 x 1.15)
        self.assertEqual(names(b.hand), ["Epic"])
        self.assertEqual(b.fhp, [0])
        self.assertNotIn("Epic", b.casts)

    def test_pass_two_kill_uses_it(self):
        b = battle([lord(), ench()], pips=7, fhp=[900], foes=[S.Foe("A", 900)])
        self.assertTrue(b.my_round(fresh=False))                               # (850 < 1035 <= 1105)
        self.assertEqual((b.hand, b.fhp, b.pips, b.boosts_run), ([], [0], 0, 0))
        self.assertEqual(b.casts, {"Storm Lord": 1, "Epic": 1})

    def test_a_hit_takes_the_best_enchant(self):
        b = battle([lord(), ench("Giant", 125), ench()], pips=7, fhp=[5000], foes=[S.Foe("A", 5000)])
        self.assertTrue(b.my_round(fresh=False))
        self.assertEqual(names(b.hand), ["Giant"])
        self.assertTrue(3785 <= b.fhp[0] <= 3895, b.fhp)                     # ((1000..1130 + 300) x 0.85)
        self.assertEqual(b.casts["Epic"], 1)
        # (equal adds: EnchantList's order - Colossal before a Giant given 275)
        b = battle([ench("Giant", 275), ench("Colossal", 275)], pips=7)
        self.assertEqual(b._best_ench().name, "Colossal")

    def test_never_on_an_item_or_an_enchanted_card(self):
        wand = S.Card("Storm Lord", "damage", "storm", 7, heads={"storm": 1000}, item=True)
        b = battle([wand, ench()], pips=7, fhp=[5000], foes=[S.Foe("A", 5000)])
        self.assertTrue(b.my_round(fresh=False))
        self.assertEqual(names(b.hand), ["Epic"])
        self.assertTrue(4040 <= b.fhp[0] <= 4150, b.fhp)                     # (plain: 850..960)
        done = S.Card("Storm Lord", "damage", "storm", 7, heads={"storm": 1000}, ench=300)
        b = battle([done, ench()], pips=7, fhp=[900], foes=[S.Foe("A", 900)])
        self.assertTrue(b.my_round(fresh=False))                               # (pass 1: its own 300 counted)
        self.assertEqual((names(b.hand), b.fhp), (["Epic"], [0]))

    def test_no_enchant_on_a_hit_not_paid_for(self):
        b = battle([lord(), ench()], pips=6, fhp=[5000])
        self.assertFalse(b.my_round(fresh=False))
        self.assertEqual(names(b.hand), ["Storm Lord", "Epic"])
        # (cast itself: the hit is paid for before the enchant goes on - Autofarmer.ahk UseHit)
        b = battle([lord(), ench()], pips=6, fhp=[5000])
        self.assertFalse(b.force(b.hand[0]))
        self.assertEqual(names(b.hand), ["Epic"])
        self.assertNotIn("Epic", b.casts)

    def test_a_fizzle_loses_both(self):
        st = S.State([lord(), ench()], [], pips=7, fhp=[5000], me_first=True)
        b = S._Battle.from_state(st, S.Me("storm", 3000, accuracy=-100), [S.Foe("A", 9000)], S.Opts(),
                                 random.Random(1))
        self.assertFalse(b.my_round(fresh=False))
        self.assertEqual((b.hand, b.pips, b.fhp), ([], 7, [5000]))
        self.assertEqual(b.casts, {"Storm Lord": 1, "Epic": 1})
        self.assertEqual(sorted(names(b.spent)), ["Epic", "Storm Lord"])

    def test_enchant_draws_no_random_number(self):
        b1, b2 = [S._Battle([], S.Me("storm"), [S.Foe("A", 9000)], S.Opts(), random.Random(7)) for _ in range(2)]
        b1.hit(lord(), 1)
        b2.hit(lord(), 1, add=300)
        self.assertEqual(b1.rng.getstate(), b2.rng.getstate())
        self.assertLessEqual(abs((9000 - b2.fhp[0]) - (9000 - b1.fhp[0]) - 255), 1)     # (300 x 0.85)
        b = battle([lord(), ench()], pips=7, fhp=[5000])
        s0 = b.rng.getstate()
        b.choose()
        self.assertEqual(b.rng.getstate(), s0)

    def test_hit_puts_the_add_on_the_least_head_once(self):
        def gap(me, foe, card, per):
            b1, b2 = [S._Battle([], me, [foe], S.Opts(), random.Random(7)) for _ in range(2)]
            b1.hit(card, per)
            b2.hit(card, per, add=300)
            self.assertEqual(b1.rng.getstate(), b2.rng.getstate())
            return b2, b1.fhp[0] - b2.fhp[0]
        # (Hydra: its least head here is ice, not its first - the add goes there, x0.5)
        hydra = S.Card("Hydra", "damage", "fire", 8, heads={"fire": 230, "ice": 230, "storm": 230})
        b, d = gap(S.Me("storm"), S.Foe("A", 90000, resist={"ice": 0.5, "fire": 0.85, "storm": 0.85}), hydra, 1)
        self.assertEqual(b._add_head(hydra, 0), "ice")
        self.assertLessEqual(abs(d - 150), 1)                                  # (the first head's would be 255)
        # (an X-pip hit: the add once, not a pip - 300 x 0.85, not 7 x 300 x 0.85)
        meteor = S.Card("Meteor", "aoe", "fire", 0, x=True, heads={"fire": 100})
        _b, d = gap(S.Me("fire"), S.Foe("A", 90000), meteor, 7)
        self.assertLessEqual(abs(d - 255), 1)

    def test_value_counts_the_enchant(self):
        big = S.Card("Big", "damage", "storm", 5, heads={"storm": 1200})
        wave = S.Card("Wave", "aoe", "storm", 4, heads={"storm": 500})
        foes = [S.Foe("A", 5000), S.Foe("B", 5000)]
        b = battle([big, wave, ench()], foes=foes, pips=7)
        self.assertEqual(b.choose().name, "Wave")                              # ((500 + 300) x 0.85 x 2 > 1500 x 0.85)
        b = battle([big, wave], foes=foes, pips=7)
        self.assertEqual(b.choose().name, "Big")                               # (1020 > 850)

    def test_forced_plain_kill_keeps_the_enchant(self):
        # (force: a hit that kills without the enchant goes plain - the kill check's pass 1; a fizzle shows the Epic
        # stayed in hand)
        st = S.State([lord(), ench()], [], pips=7, fhp=[700], me_first=True)
        b = S._Battle.from_state(st, S.Me("storm", 3000, accuracy=-100), [S.Foe("A", 900)], S.Opts(), random.Random(1))
        self.assertIs(b.force(b.hand[0]), False)
        self.assertEqual(names(b.hand), ["Epic"])
        self.assertNotIn("Epic", b.casts)

    def test_discard_keeps_the_bots_enchants(self):
        b = S._Battle([], S.Me("storm"), [S.Foe("A", 900)], S.Opts(discardunused=1, discardmax=4), random.Random(1))
        b.hand = [ench(), S.Card("Freeze", "stun"), S.Card("Poison", "dot"), S.Card("Primordial", "enchant", value=350),
                  S.Card("Keen Eyes", "enchantother")]
        b.discard()
        # (every damage enchant kept - CardLearn.ahk DiscardUnused skips type enchant whatever its name: a Primordial
        # the bot never finds stays in hand as a dead card)
        self.assertEqual(names(b.hand), ["Epic", "Primordial"])
        self.assertEqual(sorted(names(b.spent)), ["Freeze", "Keen Eyes", "Poison"])

    def test_planner_carries_the_enchant(self):
        st = S.State([lord(), ench()], [snake()] * 10, pips=7, fhp=[900], me_first=True)
        p = S.plan_round(st, sure(), [S.Foe("A", 900)], n=20, seed=1, budget_ms=5000)
        best = p["plays"][0]
        self.assertEqual((best["name"], best["won"], best["rounds"]), ("Storm Lord", 1.0, 1))
        self.assertNotIn("Epic", [x["name"] for x in p["plays"]])
        self.assertTrue(any("goes on a hit" in w for w in p["why"]), p["why"])
        # (an enchant the bot never finds - a Primordial - never goes on a hit: not simulated, as before the change)
        st = S.State([lord(), S.Card("Primordial", "enchant", value=350)], [lord()] * 5, pips=7, fhp=[5000],
                     me_first=True)
        p = S.plan_round(st, sure(), [S.Foe("A", 5000)], n=10, seed=1, budget_ms=5000)
        self.assertIn("1 card in hand not tried (not simulated)", p["why"])

    def test_a_mate_uses_its_enchant(self):
        st = S.State([lord()], [], pips=0, fhp=[9000], seat=5, me_first=True,
                     mates=[mate("Ann", 4, "blader", [snake(), ench()], pips=2)])
        b = S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
        b.side_round(0, {})
        self.assertEqual(b.side[1].hand, [])
        self.assertEqual(b.casts, {"Thunder Snake": 1, "Epic": 1})
        self.assertTrue(8601 <= b.fhp[0] <= 8618, b.fhp)                     # ((150..169.5 + 300) x 0.85)

    def test_a_held_enchant_keeps_the_battle_going(self):
        # (the bot flees only with no card in hand: an enchant with no hit to go on keeps it passing - before, the Epic
        # was discarded and the battle a timeout)
        st = S.State([ench()], [], pips=0, fhp=[9000], me_first=True)
        b = S._Battle.from_state(st, sure(), [S.Foe("Rat", 9000)], S.Opts(), random.Random(1))
        self.assertEqual(b.run_from(False, None, horizon=5), "cut")
        self.assertEqual(names(b.hand), ["Epic"])


def _has_enemies():
    try:
        __import__("numpy")
        __import__("enemies")
        return True
    except Exception:  # noqa: BLE001
        return False


class Defend(unittest.TestCase):
    """Part B and C: the defend check (EnemySpells.ahk EnemyDanger / EnemyDefend), Tower Shield and absorbs as cast, the
    filler"""

    def test_opts_reads_the_chain_keys(self):
        def keys(o):
            return (o.usetower, o.useabsorb, o.defendat, o.usereshuffle)
        self.assertEqual(keys(S.Opts()), (True, True, 30.0, True))
        self.assertEqual(keys(S.Opts.of({"usetower": "0", "defendat": "50", "useabsorb": "0", "usereshuffle": "0"})),
                         (False, False, 50.0, False))
        self.assertEqual(S.Opts.of({"defendat": "x"}).defendat, 30.0)
        self.assertEqual(S.Opts.of({"defendat": "nan"}).defendat, 30.0)
        self.assertEqual(S.Opts(1, 0, 40, 15, 1, 1, 1, 1, 1, 3, True).boss, True)    # (positional calls as before)

    def test_tower_shield_halves_the_next_hit(self):
        b = battle([tower()], foes=[smasher()], pips=0)
        self.assertIs(b.force(b.hand[0]), True)
        self.assertEqual(b.shields, [(50.0, None)])
        b.foe_round()
        self.assertEqual((b.hp, b.shields), (2500, []))
        # (the enemies first: a shield cast after their hit waits for the next one)
        b = battle([tower()], foes=[smasher()], pips=0, me_first=False)
        b.foe_round()
        self.assertEqual(b.hp, 2000)
        b.force(b.hand[0])
        self.assertEqual(b.shields, [(50.0, None)])
        self.assertEqual((tower().acc, S.Card("Fire Shield", "ward", "fire", 0, value=80).tower), (100, False))
        self.assertTrue(S.card_of({"display": "Escudo", "name": "Tower Shield", "kind": "ward"}).tower)

    def test_absorb_card_soaks(self):
        b = battle([absorb(value=200)], foes=[smasher(dmg=500)])
        b.force(b.hand[0])
        b.foe_round()
        self.assertEqual((b.hp, b.absorb), (2700, 0))
        b = battle([S.Card("Spirit Armor", "absorb", "", 0, value="100/pip")], pips=3)
        b.force(b.hand[0])
        self.assertEqual((b.absorb, b.pips), (300, 0))                         # (an X-pip absorb's N a pip)

    def test_defend_tower_when_lethal(self):
        b = battle([snake(), tower()], foes=[smasher()], pips=2, hp=900, fhp=[9000])
        b._snap_danger()
        self.assertAlmostEqual(b._danger(), 1.0)
        self.assertEqual(b.choose().name, "Tower Shield")
        for o in (S.Opts(defendat=0), S.Opts(usetower=0)):
            b = battle([snake(), tower()], foes=[smasher()], pips=2, hp=900, fhp=[9000], opts=o)
            b._snap_danger()
            self.assertEqual(b.choose().name, "Thunder Snake")
        b = battle([snake(), tower()], foes=[smasher()], pips=2, hp=1100, fhp=[9000])
        b._snap_danger()
        self.assertEqual(b._danger(), 0.0)                                     # (the fast path: 1000 < 1100)
        self.assertEqual(b.choose().name, "Thunder Snake")
        b = battle([snake(), tower()], foes=[smasher()], pips=2, hp=900, fhp=[9000])
        self.assertEqual((b._danger(), b.choose().name), (0.0, "Thunder Snake"))    # (no snapshot: no defend)

    def test_defend_heals_first_under_90_percent(self):
        for pips, hp, o, want in ((3, 2400, S.Opts(), "Satyr"), (3, 2850, S.Opts(), "Tower Shield"),
                                  (2, 2400, S.Opts(), "Tower Shield"), (3, 2400, S.Opts(useheal=0), "Tower Shield")):
            b = battle([snake(), tower(), satyr()], foes=[smasher(dmg=3000)], pips=pips, hp=hp, fhp=[9000], opts=o)
            b._snap_danger()
            self.assertEqual(b.choose().name, want, (pips, hp))
        # (the 90 % is the round start's health - the planning phase's -, not what's left after the enemies went first)
        b = battle([tower(), satyr()], foes=[smasher(dmg=3000)], pips=3, hp=2850, fhp=[9000])
        b._snap_danger()
        b.hp = 2550
        self.assertEqual(b.choose().name, "Tower Shield")

    def test_defend_absorb_any_cost_filler_only_free(self):
        def pick(hand, dmg, pips=2):
            b = battle(hand, foes=[smasher(dmg=dmg)], pips=pips, hp=900, fhp=[9000])
            b._snap_danger()
            c = b.choose()
            return c.name if c is not None else None
        self.assertEqual(pick([snake(), absorb(pips=2, value=500)], 1000), "Spirit Armor")    # (the defend's)
        self.assertEqual(pick([snake(), absorb(pips=2, value=500)], 100), "Thunder Snake")    # (no danger)
        self.assertIsNone(pick([lord(), absorb(pips=2)], 100))                                # (the filler's: not free)
        self.assertEqual(pick([lord(), absorb(pips=0)], 100), "Spirit Armor")                 # (free: the filler's)

    def test_kill_check_before_defend(self):
        b = battle([lord(), tower()], foes=[smasher(hp=700)], pips=7, hp=900, fhp=[700])
        b._snap_danger()
        self.assertEqual(b.choose().name, "Storm Lord")

    def test_kill_check_before_the_heal(self):
        b = battle([lord(), satyr()], foes=[S.Foe("A", 700)], pips=7, hp=600, fhp=[700])
        self.assertEqual(b.choose().name, "Storm Lord")                        # (before: the Satyr)

    def test_danger_draws_no_random_number(self):
        b = battle([snake(), tower()], foes=[smasher()], pips=2, hp=900, fhp=[9000])
        b._snap_danger()
        s0 = b.rng.getstate()
        b._danger()
        b.choose()
        self.assertEqual(b.rng.getstate(), s0)
        cards = S.deck_cards({"cards": [hit(count=20)]})
        self.assertEqual(S.simulate(cards, S.Me("storm", 3000), [biter()], S.Opts(), n=80, seed=7),
                         S.simulate(cards, S.Me("storm", 3000), [biter()], S.Opts(defendat=0), n=80, seed=7))

    @unittest.skipUnless(_has_enemies(), "numpy / enemies.py not importable")
    def test_danger_matches_enemies_predict(self):
        import numpy as np
        import enemies

        class W:
            SP = {"Bite": {"pips": 2, "min": 300, "max": 400, "accuracy": 85, "type": "Damage"},
                  "Big": {"pips": 5, "min": 800, "max": 950, "accuracy": 80, "type": "Damage"},
                  "Wave": {"pips": 4, "min": 400, "max": 500, "accuracy": 85, "type": "AoE", "aoe": True},
                  "Hex": {"pips": 1, "type": "Curse"},
                  "Storm": {"xpips": True, "perpip": [90, 110], "accuracy": 75, "type": "Damage"}}

            def creature(self, n):
                return {"spells": list(self.SP)}

            def spell(self, s):
                return self.SP.get(s)

            def brief(self, s):
                return ""
        for k in (3, 5, 7):
            for team in (1, 2):
                for health in (500, 900, 1500, 2500):
                    eb = enemies.Battle(W(), enemies.NoCasts(), ["Ogre", "Imp"], team)
                    for e in eb.enemies:
                        e.pips = np.zeros(enemies.MAX_PIPS + 1)
                        e.pips[k] = 1.0
                    _, lethal = eb.predict(health)
                    foes = [S.Foe(n, 5000, spells=S.wiki_spells(W(), None, n)) for n in ("Ogre", "Imp")]
                    b = S._Battle([], S.Me("storm", 3000, team=team), foes, S.Opts(), random.Random(1))
                    b.fpips = [k - 1, k - 1]
                    b.hp = health
                    b._snap_danger()
                    self.assertLess(abs(b._danger() - lethal), 0.03, (k, team, health, b._danger(), lethal))

    def test_lethal_exact_at_the_edge(self):
        # (the grid's bin at hp holds hp itself: counted half - before, damage half a bin short of hp counted as a kill)
        self.assertLess(abs(S._lethal((((1.0, 600.0, 700.0),),), 650) - 0.5), 0.005)
        self.assertLess(abs(S._lethal((((2 / 3.0, 295.0, 335.0),),), 318) - 0.2833), 0.005)
        self.assertLess(abs(S._lethal((((0.5, 400.0, 500.0),), ((0.5, 400.0, 500.0),)), 900) - 0.125), 0.005)
        self.assertEqual(S._lethal((((1.0, 1000.0, 1000.0),),), 1000), 1.0)    # (a sure hit of hp: a kill)
        self.assertEqual(S._lethal((((1.0, 1004.0, 1004.0),),), 1000), 1.0)
        self.assertEqual(S._lethal((((1.0, 995.0, 995.0),),), 1000), 0.0)
        # (the defend check's flip: a Bite 295-335 with a pass beside it, 5 pips; enemies.py's predict gives 0.282 at
        # 318 health - under defendat 30: the bot casts the Snake; at 300 it's 0.58: the Tower Shield)
        sp = {"Bite": {"pips": 2, "min": 295, "max": 335, "accuracy": 100, "type": "Damage"}}

        class W:
            def creature(self, n):
                return {"spells": list(sp)}

            def spell(self, s):
                return sp.get(s)

            def brief(self, s):
                return ""
        foe = S.Foe("Ogre", 5000, spells=S.wiki_spells(W(), None, "Ogre"))
        for hp, want in ((318, "Thunder Snake"), (300, "Tower Shield")):
            b = battle([snake(), tower()], [snake()] * 5, foes=[foe], pips=2, hp=hp, fhp=[5000])
            b.fpips = [4]
            b._snap_danger()
            self.assertEqual(b.choose().name, want, (hp, b._danger()))

    def test_danger_ignores_foes_the_wiki_hasnt(self):
        for f in (S.Foe("Ghoul", 9000, hits=[2000] * 5, hit_p=1.0), S.Foe("Rat", 9000)):
            b = battle([snake(), tower()], foes=[f], pips=2, hp=900, fhp=[9000])
            b._snap_danger()
            self.assertEqual((b._danger(), b.choose().name), (0.0, "Thunder Snake"))
        self.assertEqual(S._lethal((), 900), 0.0)
        self.assertEqual(S._lethal("junk", 900), 0.0)                          # (never raises)

    def test_danger_at_the_round_start(self):
        b = battle([snake(), tower()], [snake()] * 10, foes=[smasher(dmg=900)], pips=2, hp=1500, fhp=[9000],
                   me_first=False)
        b._snap_danger()
        b.foe_round()
        self.assertEqual(b.hp, 600)
        self.assertEqual(b.choose().name, "Thunder Snake")                     # (the danger at 1500: 0)
        b.new_round()
        b._snap_danger()
        self.assertEqual(b.choose().name, "Tower Shield")                      # (at 600: 1)

    def test_planner_round_now_doesnt_defend(self):
        st = S.State([snake(), tower()], [snake()] * 10, pips=2, hp=1000, fhp=[9000], me_first=True)
        foes = [smasher(dmg=900)]
        b = S._Battle.from_state(st, sure(), foes, S.Opts(), random.Random(2))
        b.run_from(False, None, horizon=1)
        self.assertEqual(b.casts, {"Thunder Snake": 1})                        # (the bot asked the planner: no defend)
        b = S._Battle.from_state(st, sure(), foes, S.Opts(), random.Random(2))
        b.run_from(False, None, horizon=2)
        self.assertEqual(b.casts.get("Tower Shield"), 1)                       # (round 2 at 100 health)
        # (a sure kill this round still gets no defend of mine: at 900 against 1000 the danger is 1)
        st2 = S.State([snake(), tower()], [snake()] * 10, pips=2, hp=900, fhp=[9000], me_first=True)
        b = S._Battle.from_state(st2, sure(), [smasher(dmg=1000)], S.Opts(), random.Random(2))
        self.assertEqual(b.run_from(False, None, horizon=1), "lost")
        self.assertEqual(b.casts, {"Thunder Snake": 1})
        p = S.plan_round(st, sure(), foes, n=10, seed=1, budget_ms=5000)
        self.assertTrue(any(x["name"] == "Tower Shield" and x["kind"] == "ward" for x in p["plays"]), p["plays"])
        p = S.plan_round(st, sure(), foes, S.Opts(usetower=0), n=10, seed=1, budget_ms=5000)
        self.assertFalse(any(x["name"] == "Tower Shield" for x in p["plays"]))
        self.assertTrue(any("switched off" in w for w in p["why"]), p["why"])

    def test_discard_keeps_tower_and_absorb(self):
        hand = [tower(), S.Card("Fire Shield", "ward", "fire", 0, value=80), absorb()]
        b = battle([], opts=S.Opts(discardunused=1, discardmax=3))
        b.hand = list(hand)
        b.discard()
        self.assertEqual(names(b.hand), ["Tower Shield", "Spirit Armor"])
        b = battle([], opts=S.Opts(usetower=0, discardunused=1, discardmax=3))
        b.hand = list(hand)
        b.discard()
        self.assertEqual(b.hand, [])

    def test_filler_tower_instead_of_a_pass(self):
        b = battle([lord(), tower(), tower()], pips=0, fhp=[5000])
        b.my_round(fresh=False)
        b.my_round(fresh=False)
        self.assertEqual(b.shields, [(50.0, None), (50.0, None)])              # (stacked: the bot stacks them)
        self.assertEqual(names(b.hand), ["Storm Lord"])
        p = S.plan_round(S.State([lord(), tower()], [snake()] * 10, pips=0, fhp=[5000], me_first=True), sure(),
                         [S.Foe("A", 5000)], n=10, seed=1, budget_ms=5000)
        self.assertEqual(p["chain"]["name"], "Tower Shield")


class TeamChain(unittest.TestCase):
    """Part E: the support's chain in the bot's order - PartyShield (Party.ahk), the defend check for every role"""

    def test_healer_party_shield(self):
        def side(bob_hp):
            st = S.State([lord()], [], pips=0, hp=3000, fhp=[9000], me_first=True,
                         mates=[mate("Ann", 5, "healer", [tower(), tower()]), mate("Bob", 6, hp=bob_hp)])
            return S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
        b = side(900)
        b.side_round(0, {})
        self.assertEqual(b.side[2].shields, [(50.0, None)])                    # (Bob: 30 % < 2 x 40 %)
        self.assertEqual((b.shields, b.side[1].shields, b.side[1].pshield_used), ([], [], True))
        b.side_round(1, {})
        self.assertEqual(b.side[1].shields, [(50.0, None)])                    # (PartyShield went: the filler, on Ann)
        self.assertEqual(b.side[2].shields, [(50.0, None)])
        b = side(3000)
        b.side_round(0, {})
        self.assertEqual(b.shields, [(50.0, None)])                            # (nobody low: on the hitter - me)

    def test_blader_party_shield_after_its_boosts(self):
        st = S.State([lord()], [], pips=0, fhp=[9000], seat=5, me_first=True,
                     mates=[mate("Ann", 4, "blader", [stormblade(), tower()])])
        b = S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
        b.side_round(0, {})
        self.assertEqual((b.blades, b.shields), ([("Stormblade", {"storm": 35})], []))
        b.side_round(1, {})
        self.assertEqual(b.shields, [(50.0, None)])
        self.assertIs(b.side[1].pshield_used, True)
        # (a forced Tower Shield goes where PartyShield puts it - on the hitter)
        st = S.State([lord()], [], pips=0, fhp=[9000], seat=5, me_first=True,
                     mates=[mate("Ann", 4, "blader", [tower()])])
        b = S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
        b.side_round(0, {1: (0, None)})
        self.assertEqual((b.shields, b.side[1].shields, b.side[1].pshield_used), ([(50.0, None)], [], True))

    def test_defend_for_every_role(self):
        for hp, want in ((500, "Tower Shield"), (1200, "Stormblade")):
            st = S.State([lord()], [], pips=0, fhp=[9000], seat=5, me_first=True,
                         mates=[mate("Ann", 4, "blader", [stormblade(), tower()], hp=hp)])
            b = S._Battle.from_state(st, sure(), [smasher()], S.Opts(), random.Random(1))
            b._snap_danger()
            b._swap(1)
            card = b.choose_support()
            self.assertEqual(card.name, want, hp)                              # (team 2: the hit at Ann half the time)
            if hp == 500:
                self.assertIsNone(b.shield_to)                                 # (the defend's: on Ann herself)
            b._swap(0)

    def test_party_shield_gone_already(self):
        # (State / Mate pshield_used: the bot's used19 - a support's PartyShield went this battle; not given: not gone)
        hitter = S.Mate("Hit", 5, S.Me("storm", 3000), "hitter", hand=[lord()], pile=[], pips=2)

        def healer(used):
            st = S.State([stormblade(), tower()], [], pips=2, hp=3000, fhp=[9000], me_first=True, seat=4,
                         mates=[hitter], pshield_used=used)
            return S._Battle.from_state(st, S.Me("storm", 3000), [S.Foe("Boss", 9000)], S.Opts(role="healer"),
                                        random.Random(1))
        b = healer(False)
        self.assertEqual((b.choose_support().name, b.shield_to), ("Tower Shield", 1))
        b = healer(True)
        self.assertIs(b.pshield_used, True)
        self.assertEqual((b.choose_support().name, b.blade_to), ("Stormblade", 1))
        b = healer(True)
        b.force(next(c for c in b.hand if c.tower))
        self.assertEqual((b.shields, b.side[1].shields), ([(50.0, None)], []))    # (on itself)
        # (a blader mate whose PartyShield went: its chain's Tower Shield is the filler's, on itself)
        for used, mine, ann in ((False, [(50.0, None)], []), (True, [], [(50.0, None)])):
            st = S.State([lord()], [], pips=0, fhp=[9000], seat=5, me_first=True,
                         mates=[S.Mate("Ann", 4, S.Me("storm", 3000, accuracy=30), "blader", [tower()], [], 0, 0, None,
                                       pshield_used=used)])
            b = S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
            b.side_round(0, {})
            self.assertEqual((b.shields, b.side[1].shields), (mine, ann), used)
        self.assertEqual((S.State([], pshield_used="junk").pshield_used, S.Mate(pshield_used=[1]).pshield_used),
                         (False, False))

    def test_mates_defend_in_the_round_now(self):
        # (the round now: only my own defend check is off - the bot asked the planner after it declined; a mate's bot
        # runs its own chain, defend first. Ann at 900 against a sure 1000 AoE shields herself and lives)
        smash = S.Foe("Smasher", 9000, spells=[("Smash", 1.0, {"pips": 0, "min": 1000, "max": 1000, "accuracy": 100,
                                                                "type": "Damage", "aoe": True})])
        ann = S.Mate("Ann", 4, S.Me("fire", 3000), "blader", hand=[snake(), tower()], pile=[snake()] * 5, pips=2, hp=900)
        st = S.State([lord()], [snake()] * 10, pips=0, hp=3000, fhp=[9000], me_first=True, seat=5, mates=[ann])
        b = S._Battle.from_state(st, sure(), [smash], S.Opts(), random.Random(1))
        self.assertEqual(b.run_from(False, None, horizon=1), "cut")
        self.assertEqual((b.side[1].hp, b.shields, b.casts), (400, [], {"Tower Shield": 1}))

    def test_wiz_fields(self):
        for k in ("spent", "danger_hp", "pshield_used"):
            self.assertIn(k, S.WIZ_FIELDS)


class Reshuffle(unittest.TestCase):
    """Part D: Reshuffle (the filler's last) and the spent pile it puts back"""

    def test_spotted_and_never_missing(self):
        for c in (S.Card("Reshuffle", "manipulation"), S.Card("Reshuffle", "keep"),
                  S.card_of({"display": "Reshuffle", "name": "X", "kind": "manipulation"}),
                  S.card_of({"display": "Remezclar", "name": "Reshuffle", "kind": "manipulation"})):
            self.assertTrue(c.resh)
        self.assertFalse(lord().resh)
        self.assertEqual(S.Card("Reshuffle", "manipulation").acc, 100)
        for seed in range(50):
            b = S._Battle([], S.Me("storm", accuracy=0), [S.Foe("A", 900)], S.Opts(), random.Random(seed))
            b.hand = [resh()]
            self.assertIs(b.cast(b.hand[0]), True)

    def test_never_discarded(self):
        b = battle([], opts=S.Opts(discardunused=1, discardmax=3))
        b.hand = [resh()] + [S.Card("Black Mantle", "curse")] * 3
        b.discard()
        self.assertEqual((names(b.hand), len(b.spent)), (["Reshuffle"], 3))
        b = battle([], opts=S.Opts(usereshuffle=0, discardmax=4))
        b.hand = [resh()] + [S.Card("Black Mantle", "curse")] * 3
        b.discard()
        self.assertEqual(b.hand, [])
        b = battle([])
        b.hand = [S.Card("Black Mantle", "curse", tc=True)]
        b.discard()
        # (a dealt treasure card goes by the same discard rules - the simulator deals them with the main deck - and a
        # thrown-away one is used up: not spent, so no Reshuffle brings it back)
        self.assertEqual((b.hand, b.spent), ([], []))

    def test_filler_reshuffle(self):
        def pick(hand, opts=None, pips=2):
            b = battle(hand, pips=pips, fhp=[9000], opts=opts)
            s0 = b.rng.getstate()
            c = b.choose()
            self.assertEqual(b.rng.getstate(), s0)
            return c.name if c is not None else None
        self.assertEqual(pick([resh(), lord()]), "Reshuffle")
        self.assertEqual(pick([resh(), lord(), stormblade()]), "Stormblade")  # (boost first: it fits the Lord)
        self.assertEqual(pick([resh(), snake()]), "Thunder Snake")
        self.assertIsNone(pick([resh(), lord()], S.Opts(usereshuffle=0)))
        self.assertEqual(pick([resh(), lord(), tower()]), "Tower Shield")
        st = S.State([lord()], [], pips=0, fhp=[9000], seat=5, me_first=True, mates=[mate("Ann", 4, "blader", [resh()])])
        b = S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
        b._swap(1)
        self.assertEqual(b.choose_support().name, "Reshuffle")
        b._swap(0)

    def test_spent_cards_go_back(self):
        b = S._Battle([], sure(), [S.Foe("A", 90000)], S.Opts(discardunused=1), random.Random(1))
        miss = S.Card("Thunder Snake", "damage", "storm", 2, heads={"storm": 150}, acc=-200)
        tcs = S.Card("Thunder Snake", "damage", "storm", 2, heads={"storm": 150}, tc=True)
        curse = S.Card("Curse", "curse")
        r = resh()
        snakes = [snake() for _ in range(4)]
        b.hand = snakes + [miss, tcs, curse, curse, r]
        for c in snakes + [miss, tcs]:
            b.pips = 7
            b.cast(c)
        b.discard()
        b.cast(r)
        self.assertEqual(sorted(names(b.pile)), ["Curse", "Curse"] + ["Thunder Snake"] * 5)
        self.assertEqual(b.spent, [])
        self.assertFalse(any(c.tc for c in b.pile))                            # (a treasure card's used up)
        self.assertNotIn("Reshuffle", names(b.pile))                           # (one use a copy)
        b.pile = []
        b.hand = [resh()]
        b.cast(b.hand[0])
        self.assertEqual(b.pile, [])                                           # (nothing spent: nothing back)
        # (a treasure hit in /plan's hand still goes - and is used up)
        kraken = S.Card("Kraken", "damage", "storm", 3, heads={"storm": 5000}, tc=True)
        b = battle([kraken], pips=7, fhp=[9000])
        self.assertIs(b.choose(), kraken)
        b.cast(kraken)
        self.assertEqual(b.spent, [])
        # (the cards drawn before the planner's round: spent - a Reshuffle brings them back)
        st = S.State.of_deck([resh()], [snake()] * 4 + [resh()], used=3)
        b = S._Battle.from_state(st, sure(), [S.Foe("A", 9000)], S.Opts(), random.Random(1))
        self.assertEqual((len(b.pile), len(b.spent)), (1, 3))

    def _deck(self, resh_first=False):
        r = {"name": "Reshuffle", "display": "Reshuffle", "kind": "manipulation", "school": "", "pips": 0, "count": 1,
             "side": "main"}
        bolts = hit("Bolt", 1, 300, count=8)
        return S.deck_cards({"cards": [r, bolts] if resh_first else [bolts, r]})

    def test_fewer_timeouts(self):
        cards = self._deck()
        foe = biter("Tank", 4000, 50, 60)
        on = S.simulate(cards, sure(), [foe], S.Opts(), n=200, seed=1)
        off = S.simulate(cards, sure(), [foe], S.Opts(usereshuffle=0), n=200, seed=1)
        self.assertGreaterEqual(on["won"], 0.95)
        self.assertLess(on["timeout"], 0.05)
        self.assertEqual(on["casts"]["Reshuffle"], 1.0)
        # (off: today's simulator's numbers for this deck, computed before the change - it threw the Reshuffle away;
        # usereshuffle 0 does the same, with no random number in between)
        keys = ("won", "lost", "timeout", "rounds", "rounds_p90", "hp_left", "dmg_in", "first_kill", "casts")
        self.assertEqual(tuple(off[k] for k in keys), (0.0, 0.0, 1.0, None, None, None, 55, None, {"Bolt": 8.0}))

    def test_planner_lists_reshuffle(self):
        deck = [snake()] * 10 + [resh()]
        st = S.State.of_deck([resh(), snake()], deck, pips=0, fhp=[6000], me_first=True, used=9)
        p = S.plan_round(st, sure(), [S.Foe("A", 6000)], n=20, seed=1, budget_ms=5000, horizon=20)
        r = [x for x in p["plays"] if x["name"] == "Reshuffle"]
        self.assertEqual((len(r), r[0]["kind"], r[0]["chain"]), (1, "manipulation", True))
        line = next(ln for ln in S.plan_lines(p, [S.Foe("A", 6000)]) if ln.split("|")[10:11] == ["Reshuffle"])
        self.assertEqual(line.split("|")[11], "me")
        st = S.State([lord()], [], pips=0, fhp=[9000], seat=5, mates=[mate("Ann", 4, "blader", [resh()])])
        b = S._Battle.from_state(st, sure(), [S.Foe("A", 9000)], S.Opts(), random.Random(1))
        self.assertIn((0, None), S._team_cands(b, 1, b.alive()))

    def test_a_mates_reshuffle_refills_its_own_pile(self):
        st = S.State([lord()], [], pips=0, fhp=[9000], seat=5, me_first=True, mates=[mate("Ann", 4, "blader", [resh()])])
        b = S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
        b.side[1].spent = [snake()] * 3
        b.side_round(1, {})
        self.assertEqual((len(b.side[1].pile), b.side[1].spent), (3, []))
        self.assertEqual((b.pile, b.spent), ([], []))

    def test_reshuffle_deck_same_score_listed_apart(self):
        groups = {("Ghoul", "Wraith"): 3, ("Ghoul",): 2}
        made = {"Ghoul": 1500, "Wraith": 2500}

        def run(cards):
            res = S.best_decks([("a", "A", cards, S.Opts())], groups,
                               lambda nm: [biter(x, made[x], 50, 60) for x in nm], sure(), n=30, seed=2)
            return [(d["won"], d["lost"], d["rounds"], d["hp_left"]) for d in res["decks"]]
        self.assertEqual(run(self._deck()), run(self._deck(resh_first=True)))


class ZeroEffect(unittest.TestCase):
    """a deck with no damage enchant, Tower Shield, absorb, Reshuffle or heal (a treasure side or not): today's numbers
    exactly (pins computed with the simulator before the whole chain went in - common random numbers, bit-identical
    floats)"""

    def test_mixed_deck_pinned(self):
        cards = S.deck_cards({"cards": [hit(count=8), hit("Thunder Snake", 2, 150, count=6),
                                        boost("blade", "Stormblade", 35, count=4),
                                        boost("trap", "Storm Trap", 30, count=4)]})
        r = S.simulate(cards, S.Me("storm", 2500, damage=40), [biter("Ogre", 3000, 150, 200),
                                                              biter("Imp", 800, 60, 80, passes=True)], n=120, seed=11)
        self.assertEqual(tuple(r[k] for k in ("won", "lost", "timeout", "rounds", "rounds_p90", "hp_left", "dmg_in",
                                               "first_kill")), (0.5, 0.5, 0.0, 13.0, 17, 21.3, 176, 10))
        self.assertEqual(r["casts"], {"Storm Lord": 3.07, "Storm Trap": 2.55, "Stormblade": 2.28, "Thunder Snake": 0.15})

    def test_timeout_deck_pinned(self):
        cards = S.deck_cards({"cards": [hit("Thunder Snake", 2, 300, count=10),
                                        boost("blade", "Stormblade", 35, count=2)]})
        r = S.simulate(cards, S.Me("storm", 3000), [biter("Tank", 2600, 50, 60)], n=100, seed=3)
        self.assertEqual(tuple(r[k] for k in ("won", "lost", "timeout", "rounds", "rounds_p90", "hp_left", "dmg_in",
                                               "first_kill")), (0.08, 0.0, 0.92, 14.0, 15, 75.6, 54, 14.0))
        self.assertEqual(r["casts"], {"Thunder Snake": 10.0, "Stormblade": 2.0})

    def test_treasure_side_pinned(self):
        # (a treasure side of cards the bot doesn't play - dealt with the main deck, discarded as before; pins computed
        # with the simulator before the whole chain went in)
        stun = {"name": "Freeze", "display": "Freeze", "kind": "stun", "school": "ice", "pips": 0, "value": 0, "count": 3,
                "side": "treasure"}
        cards = S.deck_cards({"cards": [hit("Thunder Snake", 2, 300, count=10), boost("blade", "Stormblade", 35, count=2),
                                        stun]})
        r = S.simulate(cards, S.Me("storm", 3000), [biter("Tank", 2600, 50, 60)], n=100, seed=3)
        keys = ("won", "lost", "timeout", "rounds", "rounds_p90", "hp_left", "dmg_in", "first_kill")
        self.assertEqual(tuple(r[k] for k in keys), (0.1, 0.0, 0.9, 13.5, 16, 75.9, 54, 13.5))
        self.assertEqual(r["casts"], {"Thunder Snake": 9.97, "Stormblade": 2.0})
        cards = S.deck_cards({"cards": [hit(count=6), hit("Thunder Snake", 2, 150, count=10),
                                        boost("blade", "Stormblade", 35, count=4),
                                        {"name": "Stun", "display": "Stun", "kind": "stun", "count": 6, "side": "treasure"},
                                        {"name": "Weakness", "display": "Weakness", "kind": "weakness", "count": 4,
                                         "side": "treasure"}]})
        tank = S.Foe("Tank", 3000, "fire", spells=[(None, 0.5, None), ("Bite", 1.0, {"pips": 2, "min": 200, "max": 250,
                                                                                      "accuracy": 85, "type": "Damage"})])
        r = S.simulate(cards, S.Me("storm", 3000), [tank], n=120, seed=5)
        self.assertEqual(tuple(r[k] for k in keys), (0.9833333333333333, 0.008333333333333333, 0.008333333333333333,
                                                     17.0, 22, 43.9, 95, 17.0))
        self.assertEqual(r["casts"], {"Storm Lord": 4.12, "Stormblade": 2.69, "Thunder Snake": 2.04})
        tstun = S.Card("Stun", "stun", tc=True)
        st = S.State([lord(), snake(), tstun], [snake()] * 6 + [tstun] * 6, pips=3, fhp=[3000], me_first=True)
        p = S.plan_round(st, sure(), [tank], n=30, seed=3, budget_ms=10000)
        self.assertEqual([(x["name"], x["aim"], x["n"], round(x["score"], 9)) for x in p["plays"]],
                         [("pass", None, 30, 0.277758487), ("Thunder Snake", 0, 30, 0.275680388)])

    def test_plan_pinned(self):
        hand = [lord(), S.Card("Snake", "damage", "storm", 2, heads={"storm": 150}, tid=2), stormblade()]
        p = S.plan_round(S.State(hand, hand * 3, pips=6, fhp=[2000, 900], rnd=3), sure(),
                         [biter("A", 2400), biter("B", 1200)], n=30, seed=5, budget_ms=10000)
        self.assertEqual([(x["name"], x["aim"], x["n"], round(x["score"], 9)) for x in p["plays"]],
                         [("Stormblade", None, 30, 0.447482705), ("Snake", 0, 30, 0.367980398),
                          ("pass", None, 30, 0.352737221), ("Snake", 1, 30, 0.351109917)])


class ChainFixes(unittest.TestCase):
    """two bugs the whole chain's review found: an enemy's wiki heal played as damage on you; learn_deck switching a
    deck's absorbs off"""

    def mender(self, **d):
        spell = dict({"pips": 0, "min": 300, "max": 400, "accuracy": 100, "type": "Healing",
                      "text": "Heals 300-400 Health"}, **d)
        return S.Foe("Shaman", 5000, spells=[("Mend", 1.0, spell)])

    def test_a_wiki_heal_heals_its_side(self):
        imp = S.Foe("Imp", 2000, spells=[(None, 1.0, None)])                  # (it only passes)
        b = battle([], foes=[self.mender(), imp], fhp=[1000, 2000], me_first=False)
        b.foe_round()
        self.assertEqual((b.hp, b.dmg_in), (3000, 0))                          # (before: 300-400 off my health)
        self.assertTrue(1300 <= b.fhp[0] <= 1400, b.fhp)                       # (the weakest of its side)
        self.assertEqual(b.fhp[1], 2000)
        # (no type, a heal's words; an AoE heal's words: each of its side)
        b = battle([], foes=[self.mender(type="", text="Heals 300 to all allies", aoe=True, max=300), imp],
                   fhp=[1000, 1500], me_first=False)
        b.foe_round()
        self.assertEqual((b.hp, b.fhp), (3000, [1300, 1800]))
        # (a wiki heal is its turn: no learned act besides)
        m = self.mender()
        m.acts, m.dmg_p = {"heal": {"p": 1.0, "v": 1000}}, 0.0
        b = battle([], foes=[m], fhp=[1000], me_first=False)
        b.foe_round()
        self.assertTrue(1300 <= b.fhp[0] <= 1400, b.fhp)
        # (the danger estimate leaves it out, as the bot's does; a damage spell still hurts)
        self.assertEqual(S._foe_outcomes(self.mender(), 7, 1), ())
        b = battle([], foes=[self.mender(type="Damage", text="Deals 300-400 Storm damage")], fhp=[1000], me_first=False)
        b.foe_round()
        self.assertTrue(2600 <= b.hp <= 2700, b.hp)
        r = S.simulate(S.deck_cards({"cards": [hit(count=20)]}), sure(), [self.mender()], n=20, seed=1)
        self.assertEqual((r["dmg_in"], r["lost"]), (0, 0.0))

    def test_learn_deck_keeps_usetower_for_absorbs(self):
        armor = {"name": "Spirit Armor", "display": "Spirit Armor", "kind": "absorb", "count": 2}
        shield = {"name": "Tower Shield", "display": "Tower Shield", "kind": "ward", "count": 2}
        for cards, off in (([hit(count=4), armor], False), ([hit(count=4), shield], False), ([hit(count=4)], True)):
            L = S.learn_deck({"gid": 1, "display": "D", "sets": [1], "cards": cards})
            self.assertEqual("usetower" in L["vals"], off, cards)
            if off:
                self.assertEqual(L["vals"]["usetower"], 0)
                self.assertIn("no Tower Shields or absorbs", L["why"])


class ChainDocs(unittest.TestCase):
    def test_verdict_notes(self):
        cards = S.deck_cards({"cards": [hit(count=10),
                                        {"name": "Tower Shield", "display": "Tower Shield", "kind": "ward", "pips": 0,
                                         "count": 2, "side": "main"},
                                        {"name": "Epic", "display": "Epic", "kind": "enchant", "value": 300, "count": 2,
                                         "side": "main"}]})
        me = S.Me("storm", 3000)
        foes = [biter("Rat", 500), S.Foe("Ghoul", 900)]
        v = S.verdict(S.simulate(cards, me, foes, n=20, seed=1), cards, me, foes)
        nm = next(n for n in v["notes"] if n.startswith("not modelled:"))
        self.assertTrue("stuns" in nm and "minions" in nm, nm)
        for w in ("Tower Shield", "enchants", "Reshuffle", "absorbs"):
            self.assertNotIn(w, nm)
        self.assertTrue(any(n.startswith("defending (defendat 30%): Ghoul not on the wiki") for n in v["notes"]),
                        v["notes"])
        # (nothing to defend with, or defendat 0: no such note)
        plain = S.deck_cards({"cards": [hit(count=10)]})
        v = S.verdict(S.simulate(plain, me, foes, n=20, seed=1), plain, me, foes)
        self.assertFalse(any(n.startswith("defending") for n in v["notes"]))
        v = S.verdict(S.simulate(cards, me, foes, n=20, seed=1), cards, me, foes, S.Opts(defendat=0))
        self.assertFalse(any(n.startswith("defending") for n in v["notes"]))


if __name__ == "__main__":
    unittest.main()
