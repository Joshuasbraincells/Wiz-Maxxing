"""test_plan.py - the round planner's checks (battlesim.plan_round / plan_lines, vision.py /plan's plan_lines_for with
stand-in readers shaped as handmem's and bossmem's readings), the 'planner' rule of the battle recorder, and /sim and
/decks on deckmem-shaped decks whose item cards' facts are value_text strings (standard library only):
    python -m unittest test_plan          (from AutoFarmer\\vision)"""
import os
import sys
import time
import types
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import battlesim as S  # noqa: E402


def C(name, kind, pips=0, value=0, school="storm", **kw):
    return S.Card(name, kind, school, pips, value=value, **kw)


LORD = C("Storm Lord", "damage", 7, 1000, tid=101)
SNAKE = C("Thunder Snake", "damage", 2, 150, tid=102)
TEMPEST = C("Tempest", "aoe", 6, 400, tid=103)
BLADE = C("Stormblade", "blade", 0, 35, tid=104)
TRAP = C("Storm Trap", "trap", 0, 30, tid=105)
HEAL = C("Satyr", "heal", 3, 900, school="life", tid=106)
DECK = [LORD] * 4 + [SNAKE] * 6 + [TEMPEST] * 4 + [BLADE] * 4 + [TRAP] * 4 + [HEAL] * 3


def foe(name="Rat", hp=1200, lo=100, hi=150, pips=1, boss=False):
    return S.Foe(name, hp, spells=[("Bite", 1.0, {"pips": pips, "min": lo, "max": hi, "accuracy": 100})], boss=boss)


def sure_me(**kw):
    """a storm wizard whose cards never miss (70 + 30 % accuracy)"""
    kw.setdefault("accuracy", 30)
    return S.Me("storm", kw.pop("maxhp", 3000), **kw)


class PlanRound(unittest.TestCase):
    def test_kill_now_beats_boosting(self):
        st = S.State.of_deck([LORD, BLADE, TRAP, SNAKE], DECK, pips=7, fhp=[900], rnd=4, me_first=True)
        p = S.plan_round(st, sure_me(damage=60), [foe()], seed=1)
        best = p["plays"][0]
        self.assertEqual((best["name"], best["kind"], best["aim"]), ("Storm Lord", "damage", 0))
        self.assertGreater(best["kill"], 0.95)
        self.assertEqual(best["rounds"], 1)
        self.assertTrue(best["chain"])                # (the bot's own kill check picks it too)
        self.assertIn("ends it this round", best["why"])

    def test_blade_then_hit_beats_a_weak_hit(self):
        # (6 pips, no power pips: Storm Lord next round - with a blade now it kills (1000 x 2 x 1.35 x 0.85 = 2295);
        # Thunder Snake now spends the pips it needs: the Lord two rounds later)
        st = S.State.of_deck([LORD, BLADE, SNAKE], DECK, pips=6, fhp=[2200], rnd=3, me_first=True)
        p = S.plan_round(st, sure_me(damage=100, power_pip=0), [foe("Boss", 2200, 50, 80, boss=True)],
                         S.Opts(cardlogic=2, boss=True), seed=2, budget_ms=2000)
        by = {pl["name"]: pl for pl in p["plays"]}
        self.assertEqual(p["plays"][0]["name"], "Stormblade")
        self.assertGreater(by["Stormblade"]["score"], by["Thunder Snake"]["score"])
        self.assertEqual(by["Stormblade"]["rounds"], 2)
        self.assertGreater(by["Thunder Snake"]["rounds"], 2)

    def test_heal_when_the_next_hit_kills(self):
        st = S.State.of_deck([HEAL, SNAKE], DECK, pips=4, hp=400, fhp=[5000], rnd=5, me_first=False)
        p = S.plan_round(st, sure_me(), [foe("Brute", 5000, 500, 600)], seed=3)
        self.assertEqual(p["plays"][0]["kind"], "heal")
        snake = next(pl for pl in p["plays"] if pl["name"] == "Thunder Snake")
        self.assertGreater(snake["lost"], 0.9)

    def test_pass_when_nothing_is_payable(self):
        st = S.State.of_deck([LORD, TEMPEST], DECK, pips=2, fhp=[900], rnd=2)
        p = S.plan_round(st, sure_me(), [foe()], seed=4)
        self.assertEqual([pl["kind"] for pl in p["plays"]], ["pass"])
        self.assertTrue(any("not paid for" in w for w in p["why"]))
        self.assertTrue(S.plan_lines(p, [foe()])[0].startswith("plan|-1|||pass|"))

    def test_single_target_tried_at_each_enemy(self):
        st = S.State.of_deck([SNAKE, TRAP, TEMPEST, BLADE], DECK, pips=6, fhp=[500, 900, 0], rnd=2)
        p = S.plan_round(st, sure_me(), [foe("A", 900), foe("B", 900), foe("C", 900)], seed=5)
        aims = sorted(pl["aim"] for pl in p["plays"] if pl["name"] == "Thunder Snake")
        self.assertEqual(aims, [0, 1])                # (the dead one isn't a target)
        self.assertEqual([pl["aim"] for pl in p["plays"] if pl["name"] == "Tempest"], [None])

    def test_copies_and_switched_off_once(self):
        st = S.State.of_deck([SNAKE, SNAKE, BLADE], DECK, pips=4, fhp=[900], rnd=2)
        p = S.plan_round(st, sure_me(), [foe()], S.Opts(useblades=0), seed=6)
        self.assertEqual(sorted(pl["name"] for pl in p["plays"]), ["Thunder Snake", "pass"])
        self.assertTrue(any("switched off" in w for w in p["why"]))

    def test_same_seed_same_answer(self):
        st = S.State.of_deck([LORD, BLADE, TRAP, SNAKE, TEMPEST], DECK, pips=5, fhp=[2000, 1500], rnd=2)
        foes = [foe("A", 2000), foe("B", 1500)]
        a = S.plan_round(st, sure_me(), foes, n=40, seed=9, budget_ms=5000)
        b = S.plan_round(st, sure_me(), foes, n=40, seed=9, budget_ms=5000)
        strip = lambda p: [(x["name"], x["aim"], x["n"], x["won"], round(x["score"], 9)) for x in p["plays"]]  # noqa: E731
        self.assertEqual(strip(a), strip(b))
        self.assertEqual(S.plan_lines(a, foes), S.plan_lines(b, foes))

    def test_within_budget(self):
        hand = [LORD, BLADE, TRAP, SNAKE, TEMPEST, HEAL, C("Storm Shark", "damage", 3, 300, tid=107)]
        st = S.State.of_deck(hand, DECK, pips=7, hp=1500, fhp=[2000, 1500, 1800, 2500], rnd=3)
        foes = [foe("E%d" % i, 2500) for i in range(4)]
        t = time.perf_counter()
        p = S.plan_round(st, sure_me(), foes, n=2000, budget_ms=60, seed=1)
        ms = (time.perf_counter() - t) * 1000
        self.assertTrue(p["plays"])
        self.assertLess(ms, 60 + 150)                 # (one round robin past the budget at most)
        self.assertTrue(any("in the time given" in w for w in p["why"]))

    def test_prior_nudges_and_is_quoted(self):
        st = S.State.of_deck([BLADE, TRAP], DECK, pips=3, fhp=[5000], rnd=2)
        foes = [foe("Boss", 5000, boss=True)]
        seen = {}

        def prior(sit):
            seen.update(sit)
            return {"trap": 1.0, "blade": -1.0}, "learned: traps won here"
        p = S.plan_round(st, sure_me(), foes, n=30, seed=1, budget_ms=5000, prior=prior)
        self.assertEqual(p["learned"], "learned: traps won here")
        self.assertEqual((seen["school"], seen["pips"], seen["alive"], seen["boss"], seen["hit"]), ("storm", 3, 1, True,
                                                                                                    False))
        by = {pl["kind"]: pl for pl in p["plays"]}
        self.assertAlmostEqual(by["trap"]["bonus"], S.PRIOR_W)
        self.assertAlmostEqual(by["blade"]["bonus"], -S.PRIOR_W)
        self.assertIn("learned +", by["trap"]["why"])
        self.assertTrue(any(ln.startswith("learned|") for ln in S.plan_lines(p, foes)))

    def test_junk_never_raises(self):
        for st, me, foes in ((None, S.Me(), [foe()]), (S.State(None), S.Me(), [foe()]), (S.State([LORD]), S.Me(), []),
                             (S.State(["x", None], pips="abc", fhp=["?"], blades=[(1, "x")], aura=("x", "y"),
                                      traps="junk", rnd=float("inf")), S.Me(), [foe()]),
                             (S.State([LORD], fhp=[0]), S.Me(), [foe()])):
            p = S.plan_round(st, me, foes, budget_ms=20)
            self.assertIsInstance(p["plays"], list)
            lines = S.plan_lines(p, foes)
            self.assertTrue(lines and all(isinstance(ln, str) for ln in lines))
        self.assertEqual(S.plan_lines(S.plan_round(S.State([LORD]), S.Me(), []), [])[0], "none|no enemies")
        self.assertEqual(S.plan_lines(None, []), ["none|nothing to plan"])


class FromStateLines(unittest.TestCase):
    def test_plan_line_fields(self):
        st = S.State.of_deck([SNAKE, TEMPEST, BLADE], DECK, pips=6, fhp=[400, 900], rnd=2)
        foes = [foe("A", 900), foe("B", 900)]
        p = S.plan_round(st, sure_me(), foes, seed=1)
        lines = S.plan_lines(p, foes, ids=[(2, "Card3", 102), (4, "Card5", 103), (5, "Card6", 104)])
        f = lines[0].split("|")
        self.assertEqual(f[0], "plan")
        self.assertEqual(len(f), 15)
        names = {"Thunder Snake": ("2", "Card3", "102"), "Tempest": ("4", "Card5", "103"),
                 "Stormblade": ("5", "Card6", "104"), "pass": ("-1", "", "")}
        self.assertEqual(tuple(f[1:4]), names[f[10]])
        for ln in lines:
            g = ln.split("|")
            if g[0] in ("plan", "alt", "chain"):
                self.assertEqual(len(g), 15)
                if g[4] == "aoe":
                    self.assertEqual((g[5], g[11]), ("all", "all"))
                elif g[4] == "damage":
                    self.assertIn(g[11], ("A", "B"))


def planner_text(ans, ms=300):
    """Planner.ahk PlannerText / PlannerAt, line for line (AHK's arrays count from 1: f[11] here is f[10]) - the advice
    line it logs from /plan's answer"""
    best = chain = None
    learned = ""
    for ln in ans:
        f = [""] + ln.split("|")
        if f[1] == "plan" and len(f) - 1 >= 15:
            best = f
        elif f[1] == "chain" and len(f) - 1 >= 15:
            chain = f
        elif f[1] == "learned":
            learned = ln[8:]

    def at(f):
        return " on all" if f[6] == "all" else (" at " + f[12]) if f[6] != "" else (" on you" if f[12] == "me" else "")
    t = "Plan: would play " + best[11] + at(best) + " (won " + best[7] + "%" + (
        (" in " + best[8] + " rounds") if best[8] != "" else "") + ", " + best[13] + " tries; " + best[10] + ")"
    if chain:
        t += " - your settings' way: " + chain[11] + at(chain) + " (won " + chain[7] + "%)"
    if best[4] != "":
        t += " [tid " + best[4] + "]"
    t += " - advice only (planner:1, %d ms)" % ms
    return t + ((" - " + learned[:150]) if learned else "")


class AdviceLine(unittest.TestCase):
    def test_round_trip_to_the_recorder(self):
        # (plan_lines -> the line Planner.ahk logs -> what battlelearn reads back from the round's bot lines)
        import battlelearn
        import battlerec
        cases = [([LORD, BLADE], [900], "Storm Lord", 101), ([TEMPEST, SNAKE], [300, 300], "Tempest", 103),
                 ([LORD, TEMPEST], [900], "pass", None)]
        for hand, fhp, want, tid in cases:
            pips = 2 if want == "pass" else 7
            st = S.State.of_deck(hand, DECK, pips=pips, fhp=fhp, rnd=3, me_first=True)
            foes = [foe("E%d" % k, 900) for k in range(len(fhp))]
            p = S.plan_round(st, sure_me(damage=60), foes, seed=1, budget_ms=2000)
            ids = [(k, "Card%d" % (k + 1), c.tid) for k, c in enumerate(st.hand)]
            line = "  " + planner_text(S.plan_lines(p, foes, ids))
            self.assertEqual(battlerec.classify([[0, line]])[0], "other", line)     # (advice never decides a round)
            rows = battlelearn.advice_rows({"result": "won", "rounds": [
                {"n": 3, "bot": {"lines": [[10, line]]},
                 "played": None if want == "pass" else {"spell": want, "tid": tid}}]})
            self.assertEqual((rows[0]["advised"], rows[0]["tid"], rows[0]["same"]), (want, tid, True), line)


# ============================================================================ vision.py /plan (plan_lines_for)
def hand_card(slot, x, name, kind, school="Storm", pips=0, value=None, vtext="", tid=0, heads="", boosts="", xp=False,
              acc=None, treasure=False, item=False):
    """a card as handmem's reading has it (HandMem.read's cards)"""
    return {"slot": slot, "x": x, "shown": True, "name": name, "display": name, "school": school, "type": (kind or "").title(),
            "pips": pips, "x_pips": xp, "shadow_pips": 0, "castable": True, "treasure": treasure, "item_card": item,
            "enchantment": "", "accuracy": acc, "value": value, "value_text": vtext, "kind": kind, "dot": None,
            "school_pips": {}, "template_id": tid, "text": "", "heads_text": heads, "boosts_text": boosts}


def reading(cards, health=2500, most=3000, pips=None, settled=True):
    pp = {"generic": 3, "power": 2, "balance": 0, "death": 0, "fire": 0, "ice": 0, "life": 0, "myth": 0, "storm": 0,
          "shadow": 0}
    pp.update(pips or {})
    return {"in_battle": True, "planning": True, "settled": settled, "state": "hand" if settled else "changing",
            "why": "" if settled else "hand changing", "ms": 3.0,
            "me": {"health": health, "max_health": most, "school": "storm", "pips": pp}, "cards": cards}


def parts(*enemies, team=2):
    """a battle as bossmem / navmem's battle reading has it: me first, then the enemies (name, health, max, boss)"""
    out = [{"me": True, "team": 1, "player": True, "health": 2500, "max_health": 3000, "boss": False, "name": "",
            "mob": None, "owner": 1, "box": None, "root": None}]
    for k, (name, hp, most, boss) in enumerate(enemies):
        out.append({"me": False, "team": team, "player": False, "health": hp, "max_health": most, "boss": boss,
                    "name": name, "mob": {"title": "Undead", "school": "Death", "rank": 4}, "owner": 100 + k,
                    "box": (100 + 200 * k, 10, 180 + 200 * k, 40), "root": (0, 0, 1000, 600)})
    return out


HAND = [hand_card("Card1", 10, "Storm Lord", "damage", pips=7, value=1000, vtext="1000-1130", tid=101,
                  heads="storm:1000"),
        hand_card("Card2", 60, "Stormblade", "blade", value=35, vtext="35%", tid=104, boosts="storm:35"),
        hand_card("Card3", 110, "Storm Trap", "trap", value=30, vtext="30%", tid=105, boosts="storm:30"),
        hand_card("Card4", 160, "Thunder Snake", "damage", pips=2, value=150, vtext="150-170", tid=102,
                  heads="storm:150")]


def deckmem_deck(item_tid=None):
    """the worn deck as deckmem.read(kinds=True) has it: main cards with their kinds, item cards with no kind at all"""
    def dc(name, kind, pips, value, vtext, tid, count, heads="", boosts="", side="main"):
        return {"template_id": tid, "name": name, "display": name, "school": "Storm", "type": kind.title(), "pips": pips,
                "x_pips": False, "shadow_pips": 0, "school_pips": {}, "count": count, "enchantment_id": 0, "side": side,
                "known": True, "tc_flag": False, "max_copies": 4, "kind": kind, "value": value, "value_text": vtext,
                "heads_text": heads, "boosts_text": boosts}
    d = {"gid": 0xABC, "where": "equipped", "equipped": True, "sets": [1], "template_id": 1, "object_name": "Deck",
         "display": "Storm Deck", "school": "Storm", "limits": {}, "main_n": 22, "treasure_n": 0, "excluded": [],
         "item_n": 1, "ok": True, "why": "",
         "cards": [dc("Storm Lord", "damage", 7, 1000, "1000-1130", 101, 4, heads="storm:1000"),
                   dc("Thunder Snake", "damage", 2, 150, "150-170", 102, 6, heads="storm:150"),
                   dc("Stormblade", "blade", 0, 35, "35%", 104, 4, boosts="storm:35"),
                   dc("Storm Trap", "trap", 0, 30, "30%", 105, 4, boosts="storm:30"),
                   dc("Tempest", "aoe", 6, 400, "400-460", 103, 4, heads="storm:400")],
         "item_cards": []}
    if item_tid:
        d["item_cards"] = [{"name": "Lightning Strike", "template_id": item_tid, "count": 2, "display": "Lightning Strike",
                            "from": "Wand"}]
    return d


# (cards.jsonl's facts: the recorder writes handmem's value_text there - strings, not numbers)
FACTS = {777: {"rec": "card", "v": 1, "tid": 777, "name": "Lightning Strike", "display": "Lightning Strike",
               "school": "Storm", "kind": "damage", "pips": 0, "x": False, "value": "95-115", "heads": "storm:95",
               "boosts": None, "acc": 70, "full": True},
         888: {"rec": "card", "v": 1, "tid": 888, "name": "Pet Blade", "display": "Pet Blade", "school": "Storm",
               "kind": "blade", "pips": 0, "x": False, "value": "+20%", "heads": None, "boosts": "storm:20",
               "full": True}}


class PlanLinesFor(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            import vision
        except ImportError as e:                          # (numpy / Pillow: the helper's own needs)
            raise unittest.SkipTest("vision.py can't be imported here (%s)" % e)
        cls.V = vision
        cls.log = vision.log
        vision.log = lambda *a, **kw: None                # (nothing into vision\vision.log from the tests)

    @classmethod
    def tearDownClass(cls):
        cls.V.log = cls.log

    def ctx(self, decks=True, plays=None, facts=None):
        return {"book": S.FoeBook(battles=[]), "facts": FACTS if facts is None else facts, "plays": plays, "wiki": None,
                "casts": None, "decks": {"decks": [deckmem_deck(777)]} if decks else None}

    def ask(self, q, hand=None, battle=None, ctx=None, rd=None):
        cr = lambda: (rd if rd is not None else reading(HAND if hand is None else hand), "")          # noqa: E731
        br = lambda: (parts(("Bonestriker", 700, 2400, False)) if battle is None else battle, "")  # noqa: E731
        return self.V.plan_lines_for(q, cr, br, ctx if ctx is not None else self.ctx())

    def test_lethal_hit_with_slot_tid_and_target(self):
        out = self.ask({"seed": "1", "budget": "2000", "acc": "30", "first": "1"})
        f = out[0].split("|")
        self.assertEqual(f[0], "plan", out)
        self.assertEqual((f[1], f[2], f[3], f[4], f[5], f[10], f[11]),
                         ("0", "Card1", "101", "damage", "0", "Storm Lord", "Bonestriker"))
        self.assertTrue(any(ln.startswith("foe|0|Bonestriker|700|2400|0|0.1400") for ln in out), out)
        planned = next(ln for ln in out if ln.startswith("planned|")).split("|")
        self.assertGreater(int(planned[1]), 0)

    def test_not_settled_and_not_read(self):
        out = self.V.plan_lines_for({}, lambda: (reading(HAND, settled=False), ""), lambda: ([], ""), self.ctx())
        self.assertEqual(out, ["none|hand changing"])
        out = self.V.plan_lines_for({}, lambda: (None, "the game is not running"), lambda: ([], ""), self.ctx())
        self.assertEqual(out, ["none|the game is not running"])
        out = self.V.plan_lines_for({}, lambda: (reading([]), ""), lambda: ([], ""), self.ctx())
        self.assertEqual(out, ["none|no card in hand"])
        # (the hand changing - the bot's discards just made: asked again within the budget, then planned)
        reads = [reading(HAND, settled=False), reading(HAND, settled=False), reading(HAND)]
        out = self.V.plan_lines_for({"budget": "2000"}, lambda: (reads.pop(0) if len(reads) > 1 else reads[0], ""),
                                    lambda: (parts(("Rat", 500, 900, False)), ""), self.ctx())
        self.assertTrue(out[0].startswith("plan|"), out)

    def test_enemies_from_the_bot_when_memory_has_none(self):
        out = self.V.plan_lines_for({"foes": "Rat~1200~storm~0~300|~~~", "seed": "1", "budget": "2000"},
                                    lambda: (reading(HAND), ""), lambda: (None, "the game can't be read"), self.ctx())
        self.assertTrue(out[0].startswith("plan|"), out)
        self.assertTrue(any(ln.startswith("foe|0|Rat|300|1200|0|") for ln in out), out)
        self.assertTrue(any("as the bot named them" in ln for ln in out))
        out = self.V.plan_lines_for({}, lambda: (reading(HAND), ""), lambda: (None, "the game can't be read"),
                                    self.ctx())
        self.assertEqual(out, ["none|no enemies (the game can't be read)"])

    def test_bot_bookkeeping_reaches_the_state(self):
        got = {}
        real = S.plan_round

        def spy(state, me, foes, opts=None, **kw):
            got.update(state=state, me=me, foes=foes, opts=opts, kw=kw)
            return real(state, me, foes, opts, **kw)
        q = {"blades": "storm/blade~storm~35|blade3~all~25|junk~~", "traps": "storm/trap~storm~30|trap3~all~30",
             "trapmax": "2400", "aura": "storm~25~3", "boostrun": "2", "round": "6", "first": "0",
             "vals": "cardlogic:2,boostmax:3,useheal:0", "damage": "80", "crit": "500", "budget": "2000", "seed": "1"}
        battle = parts(("Imp", 3000, 3000, False), ("Bonestriker", 1500, 2400, True), ("Imp", 900, 3000, False))
        with mock.patch.object(S, "plan_round", spy):
            out = self.ask(q, battle=battle)
        self.assertTrue(out[0].startswith("plan|"), out)
        st, me, opts = got["state"], got["me"], got["opts"]
        self.assertEqual(st.blades, [("storm/blade", {"storm": 35.0}), ("blade3", {"all": 25.0})])
        self.assertEqual(st.traps, [[], [{"storm": 30.0}, {"all": 30.0}], []])   # (on the one whose most is 2400)
        self.assertEqual(st.aura, ({"storm": 25.0}, 3))
        self.assertEqual((st.boosts_run, st.round, st.me_first), (2, 6, False))
        self.assertEqual((st.pips, st.power, st.hp, st.fhp), (5, 2, 2500, [3000, 1500, 900]))
        self.assertEqual((me.school, me.maxhp, me.damage, me.crit), ("storm", 3000, 80, 500))
        self.assertEqual((opts.cardlogic, opts.boostmax, opts.useheal, opts.boss), (2, 3, False, True))
        self.assertEqual([f.name for f in got["foes"]], ["Imp", "Bonestriker", "Imp"])
        # (the draw pile: the worn deck - its wand's item cards known from cards.jsonl's value_text facts - less the hand)
        names = sorted(c.name for c in st.pile)
        self.assertEqual(names.count("Lightning Strike"), 2)
        self.assertEqual(names.count("Storm Lord"), 3)
        self.assertEqual(names.count("Tempest"), 4)
        # (traps with no trapmax match: on the enemy with the most health now)
        with mock.patch.object(S, "plan_round", spy):
            self.ask(dict(q, trapmax="9999"), battle=battle)
        self.assertEqual([len(t) for t in got["state"].traps], [2, 0, 0])

    def test_no_deck_read_and_cards_with_no_kind(self):
        hand = HAND + [hand_card("Card5", 210, "Mystery", None, tid=999),
                       hand_card("PetCard", 300, "Pet Blade", None, tid=888)]
        out = self.ask({"seed": "1", "budget": "2000"}, hand=hand, ctx=self.ctx(decks=False))
        self.assertTrue(out[0].startswith("plan|"), out)
        self.assertTrue(any("1 card in hand with no kind known left out" in ln for ln in out), out)
        self.assertTrue(any("the deck isn't read" in ln for ln in out))
        # (the pet's blade - its kind from cards.jsonl - is the hand's 6th card: i 5 in the game's hand)
        alts = [ln.split("|") for ln in out if ln.split("|")[0] in ("plan", "alt", "chain")]
        self.assertFalse(any(a[1] == "4" for a in alts))

    def test_learned_prior_passed(self):
        got = {}
        real = S.plan_round

        def spy(state, me, foes, opts=None, **kw):
            got.update(kw)
            return real(state, me, foes, opts, **kw)

        class Plays:
            rounds = 10

            def prior_fn(self, school):
                got["school"] = school
                return lambda sit: ({"blade": 1.0}, "learned: blades")
        with mock.patch.object(S, "plan_round", spy):
            out = self.ask({"seed": "1", "budget": "2000"}, ctx=self.ctx(plays=Plays()))
        self.assertEqual(got["school"], "storm")
        self.assertIsNotNone(got["prior"])
        self.assertIn("learned|learned: blades", out)
        with mock.patch.object(S, "plan_round", spy):
            self.ask({"seed": "1"}, ctx=self.ctx(plays=None))
        self.assertIsNone(got["prior"])

    def test_within_budget_and_junk(self):
        t = time.perf_counter()
        out = self.ask({"budget": "120", "n": "5000"})
        ms = (time.perf_counter() - t) * 1000
        self.assertTrue(out[0].startswith("plan|"), out)
        self.assertLess(ms, 120 + 150)
        for q in ({"budget": "abc", "round": "x", "blades": "~~~|||", "traps": "junk", "aura": "a~b~c", "n": "-4",
                   "first": "maybe", "vals": ":,::,a:b", "hp": "nan", "damage": "inf", "deck": "zz", "seed": "q"},
                  {"budget": "0"}, {"foes": "~" * 50}):
            out = self.ask(q)
            self.assertTrue(out and (out[0].startswith("plan|") or out[0].startswith("none|")), (q, out))
        bad = self.V.plan_lines_for({}, lambda: 1 / 0, lambda: ([], ""), self.ctx())
        self.assertTrue(bad[0].startswith("none|the plan failed (ZeroDivisionError"))
        weird = reading([{"name": "x", "kind": "damage", "value": "?", "heads_text": "?", "pips": "seven"}, None, 5])
        out = self.ask({"budget": "300"}, rd=weird)
        self.assertTrue(out[0].startswith(("plan|", "none|")), out)


class Book(unittest.TestCase):
    """plan_book: the battles recorded read in a thread (pausing while a gated request is in flight) - /plan never waits"""

    def test_read_in_a_thread(self):
        try:
            import vision as V
        except ImportError as e:
            self.skipTest("vision.py can't be imported here (%s)" % e)
        import datetime
        import json
        import tempfile
        today = datetime.date.today()
        rec = {"rec": "battle", "v": 1, "id": today.strftime("%Y%m%d") + "-120000-1", "result": "won", "rounds_n": 1,
               "me": {"sc": 4, "school": "storm"}, "parts": [{"sc": 0, "side": "enemy", "name": "Foe1", "max": 900}],
               "rounds": [{"n": 1, "hand": [{"i": 0, "kind": "damage", "ok": True, "name": "Bolt", "tid": 1}],
                           "pips": {"generic": 3}, "hp": 3000, "max": 3000,
                           "played": {"spell": "Bolt", "tid": 1, "hand_i": 0}}]}
        keep_sim, keep_plan, keep_log = dict(V.SIM), dict(V.PLAN), V.log
        with tempfile.TemporaryDirectory() as root:
            folder = os.path.join(root, "learned", "battles", today.strftime("%Y-%m"))
            os.makedirs(folder)
            with open(os.path.join(folder, today.isoformat() + ".jsonl"), "w") as f:
                # (compact, as the recorder writes them - battlereport skips a line not starting {"rec":"battle")
                f.write('{"rec":"header","v":1}\n' + json.dumps(rec, separators=(",", ":")) + "\n{torn\n")
            try:
                V.log = lambda *a, **kw: None
                V.SIM.update(book=None, facts=None, at=0.0)
                V.PLAN.update(plays=None, at=0.0, thread=None)
                with mock.patch.object(V, "ROOT", root):
                    V.GATE.enter()                    # (a gated request in flight: the reading waits for it)
                    try:
                        first = V.plan_book()
                    finally:
                        V.GATE.leave()
                    self.assertIn("still being read", first["why"])
                    self.assertEqual(first["book"].by, {})
                    V.PLAN["thread"].join(15)
                    c = V.plan_book()
                self.assertEqual(c["why"], "")
                self.assertIn("Foe1", c["book"].by)
                self.assertEqual((c["plays"].battles, c["plays"].rounds), (1, 1))
                self.assertTrue(os.path.exists(os.path.join(root, "learned", "battles", "plays.json")))
            finally:
                V.log = keep_log
                V.SIM.clear()
                V.SIM.update(keep_sim)
                V.PLAN.clear()
                V.PLAN.update(keep_plan)


class Route(unittest.TestCase):
    """/plan on a local server (127.0.0.1, any free port), its game reader a stand-in: 200 and lines, never a 500"""

    def test_plan_route(self):
        try:
            import vision as V
        except ImportError as e:
            self.skipTest("vision.py can't be imported here (%s)" % e)
        import tempfile
        import threading
        import urllib.error
        import urllib.request
        from http.server import ThreadingHTTPServer

        class FakeNav:
            broken = False

            def cards(self, want_effects=True, wait=0.5):
                if FakeNav.broken:
                    raise RuntimeError("the reader fell over")
                return reading(HAND), ""

            def battle(self, wait=0.5):
                return parts(("Bonestriker", 700, 2400, False)), ""
        ctx = {"book": S.FoeBook(battles=[]), "facts": FACTS, "plays": None, "why": ""}
        keep = (V.nav_reader, V.LOG)
        with tempfile.TemporaryDirectory() as d, \
                mock.patch.object(V, "plan_book", lambda: dict(ctx)), \
                mock.patch.object(V, "enemy_state", lambda: (None, None)), \
                mock.patch.object(V, "decks_reading", lambda fresh, out=False: ({"decks": [deckmem_deck(777)]}, "")):
            V.nav_reader, V.LOG = (lambda: FakeNav()), os.path.join(d, "vision.log")
            srv = ThreadingHTTPServer(("127.0.0.1", 0), V.Handler)
            th = threading.Thread(target=srv.serve_forever, daemon=True)
            th.start()
            try:
                def get(path):
                    try:
                        with urllib.request.urlopen("http://127.0.0.1:%d%s" % (srv.server_address[1], path),
                                                    timeout=10) as r:
                            return r.status, r.read().decode().split("\n")
                    except urllib.error.HTTPError as e:
                        return e.code, e.read().decode().split("\n")
                code, ln = get("/plan?school=storm&round=3&budget=300&seed=1&acc=30&blades=storm%2Fblade~storm~35")
                self.assertEqual(code, 200)
                self.assertTrue(ln[0].startswith("plan|0|Card1|101|damage|0|"), ln)
                self.assertTrue(any(x.startswith("planned|") for x in ln))
                FakeNav.broken = True
                code, ln = get("/plan")
                self.assertEqual(code, 200)
                self.assertTrue(ln[0].startswith("none|the plan failed (RuntimeError"), ln)
            finally:
                srv.shutdown()
                srv.server_close()
                V.nav_reader, V.LOG = keep
        self.assertIn("/plan", V.GATED)
        self.assertEqual(V.GATE.n, 0)


# ============================================================================ the recorder's 'planner' rule
class PlannerRule(unittest.TestCase):
    def test_rule_and_settings_key(self):
        import battlerec
        self.assertIn("planner", battlerec.SETTINGS_KEYS)
        self.assertGreaterEqual(battlerec.RULE_V, 2)
        # (advice only - planner:1 - never decides a round: the round is the bot's own rule's)
        advice = [[0, "  Plan: would play Storm Lord at Bonestriker (won 92% in 3 rounds, 100 tries) - advice only"],
                  [5, "  UseBlade storm/blade: found=1"]]
        self.assertEqual(battlerec.classify(advice)[0], "blade")
        # (a card the planner itself cast - planner:2, not built yet - is its rule, before the boosts and hits)
        played = [[0, "  planner: Storm Lord cast at Bonestriker (won 92%)"], [5, "  UseHit hit3: found=1"]]
        self.assertEqual(battlerec.classify(played)[0], "planner")
        kill = [[0, "  kill check: 700/2400 -> hit3"], [3, "  UseHit hit3: found=1"],
                [4, "  planner: Storm Lord cast at Bonestriker"]]
        self.assertEqual(battlerec.classify(kill)[0], "kill")


# ============================================================================ /sim and /decks on deckmem-shaped decks
class SimOnGameDecks(unittest.TestCase):
    """the critic's note (v0.9.0): DeckBeat's /sim and DeckLearnGame's /decks on decks as deckmem reads them, whose item
    cards (a wand's, a pet's) have no kind of their own - only cards.jsonl's facts, where value is a value_text string"""

    @classmethod
    def setUpClass(cls):
        try:
            import vision
        except ImportError as e:
            raise unittest.SkipTest("vision.py can't be imported here (%s)" % e)
        cls.V = vision

    def reading(self):
        d = deckmem_deck(777)
        d["item_cards"].append({"name": "Pet Blade", "template_id": 888, "count": 1, "display": "Pet Blade",
                                "from": "Pet"})
        spare = dict(deckmem_deck(), gid=0xDEF, equipped=False, where="backpack", sets=[2], display="Spare")
        return {"decks": [d, spare], "equipped": 0xABC, "why": "", "read_at": time.monotonic()}

    def test_sim_lines_for_with_item_card_facts(self):
        class Wiki:
            def creature(self, name):
                return {"missing": True}
        with mock.patch.object(self.V, "decks_reading", lambda fresh, out=False: (self.reading(), "")), \
                mock.patch.object(self.V, "sim_book", lambda: (S.FoeBook(battles=[]), FACTS)), \
                mock.patch.object(self.V, "enemy_state", lambda: (Wiki(), None)):
            out = self.V.sim_lines_for({"foes": "Governor Nereus~9000~ice~1", "n": "60", "hp": "4000", "damage": "90",
                                        "vals": "cardlogic:1,boostmax:0"})
            spare = self.V.sim_lines_for({"foes": "Rat~500", "deck": "def", "n": "20"})
        self.assertTrue(out[0].startswith("sim|"), out)
        self.assertTrue(any(ln.startswith("verdict|") for ln in out))
        self.assertIn("deck|abc|Storm Deck", out)
        self.assertFalse(any("simulation failed" in ln for ln in out), out)
        self.assertFalse(any("no kind known" in ln for ln in out), out)      # (both item cards known from the facts)
        self.assertTrue(spare[0].startswith("sim|"), spare)
        self.assertIn("deck|def|Spare", spare)

    def test_decks_lines_learns_decks_with_item_cards(self):
        fake = types.ModuleType("deckmem")
        fake.deck_lines = lambda r: ["decks|%d" % len(r.get("decks") or [])]
        saved = sys.modules.get("deckmem")
        sys.modules["deckmem"] = fake
        try:
            with mock.patch.object(self.V, "decks_reading", lambda fresh, out=False: (self.reading(), "")), \
                    mock.patch.object(self.V, "sim_book", lambda: (S.FoeBook(battles=[]), FACTS)):
                out = self.V.decks_lines(False)
        finally:
            if saved is None:
                sys.modules.pop("deckmem", None)
            else:
                sys.modules["deckmem"] = saved
        self.assertEqual(out[0], "decks|2")
        learn = [ln for ln in out if ln.startswith("learn|")]
        self.assertEqual(len(learn), 2, out)
        self.assertTrue(learn[0].startswith("learn|abc|Storm Deck|storm|1|"))
        self.assertFalse(any(ln.startswith("nolearn|") for ln in out), out)
        self.assertTrue(out[-1].startswith("deckage|"))
        # (the item cards counted by their facts' kinds: 4 + 6 + 4 main hits + 2 wand hits; 4 + 1 blades)
        import battlesim
        kinds, _sp = battlesim.deck_kinds(self.reading()["decks"][0], FACTS)
        self.assertEqual((kinds["damage"], kinds["blade"], kinds.get("?", 0)), (12, 5, 0))


if __name__ == "__main__":
    unittest.main()
