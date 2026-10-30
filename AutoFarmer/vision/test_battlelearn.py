"""test_battlelearn.py - the learned plays' checks (stand-in battle records in battlerec.py's format; standard library
only):  python -m unittest test_battlelearn          (from AutoFarmer\\vision)"""
import collections
import datetime
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import battlelearn as L  # noqa: E402
import battlesim as S  # noqa: E402

_ids = collections.Counter()


def card(i, kind, ok=True, name=None, tid=None):
    return {"i": i, "slot": "Card%d" % (i + 1), "tid": tid if tid is not None else 100 + i, "name": name or kind.title(),
            "kind": kind, "school": "Storm", "pips": 2, "x": False, "ok": ok}


def rnd(n, kind="damage", pips=4, hp=2500, most=3000, ok=True, played=True, dmg=300, hand=None, lines=None, tid=None):
    """one round: a hand whose first card (kind) was played, my pips (generic), health, the damage that cast did"""
    hand = hand if hand is not None else [card(0, kind, ok, tid=tid), card(1, "damage", ok)]
    out = {"n": n, "hand": hand, "pips": {"generic": pips, "power": 0, "storm": 0, "shadow": 2}, "hp": hp, "max": most,
           "played": {"spell": hand[0]["name"], "tid": hand[0]["tid"], "hand_i": 0, "targets": [0]} if played else None,
           "casts": [{"sc": 4, "spell": hand[0]["name"], "hp": [[0, 1000, -dmg], [5, 2000, -50]]},
                     {"sc": 0, "spell": "Bite", "hp": [[4, 3000, -120]]}]}
    if lines is not None:
        out["bot"] = {"rule": "hit", "lines": lines}
    return out


def battle(rounds, school="storm", result="won", boss=False, enemies=1, day=None):
    _ids["n"] += 1
    day = day or datetime.date.today()
    parts = [{"sc": k, "side": "enemy", "name": "Foe%d" % k, "boss": boss and k == 0, "died_round": len(rounds)}
             for k in range(enemies)]
    parts += [{"sc": 4, "side": "me", "name": "Me"}, {"sc": 5, "side": "ally", "name": "Pal"}]
    return {"rec": "battle", "v": 1, "id": day.strftime("%Y%m%d") + "-120000-%d" % _ids["n"], "result": result,
            "rounds_n": len(rounds), "me": {"sc": 4, "school": school, "max0": 3000}, "parts": parts,
            "rounds": rounds}


class Situation(unittest.TestCase):
    def test_key_buckets(self):
        k = L.key_of({"pips": 5, "alive": 3, "boss": True, "hit": True, "hp": 39})
        self.assertEqual(k, "p2|a2|b1|h1|hp0")
        self.assertEqual(L.key_of({"pips": 0, "alive": 1, "boss": False, "hit": False, "hp": 75}), "p0|a1|b0|h0|hp2")
        self.assertEqual(L.key_of({"pips": 7, "alive": 1, "hp": None}), "p3|a1|b0|h0|hp?")
        self.assertIsNone(L.key_of({"pips": None}))
        self.assertIsNone(L.key_of("junk"))

    def test_round_situation(self):
        b = battle([rnd(1, pips=3, hp=1000), rnd(2), rnd(3)], enemies=2, boss=True)
        b["parts"][1]["died_round"] = 1                  # (enemy 1 died in round 1: alive at its start, gone after)
        s1 = L.round_situation(b, b["rounds"][0])
        self.assertEqual((s1["school"], s1["pips"], s1["alive"], s1["boss"], s1["hit"], s1["hp"]),
                         ("storm", 3, 2, True, True, 33))
        self.assertEqual(L.round_situation(b, b["rounds"][1])["alive"], 1)
        # (the log's Participant lines, when the round has them: who's alive at its start)
        r = rnd(2)
        r["start"] = [[0, 0, 1, 0], [1, 500, 2, 0], [4, 2500, 3, 0]]
        self.assertEqual(L.round_situation(b, r)["alive"], 1)
        self.assertFalse(L.round_situation(b, rnd(1, ok=False))["hit"])
        self.assertIsNone(L.round_situation(b, dict(rnd(1), hand=None)))

    def test_kind_played(self):
        self.assertEqual(L.kind_played(rnd(1, "blade")), "blade")
        self.assertEqual(L.kind_played(rnd(1, played=False)), "pass")
        r = rnd(1)
        r["played"]["hand_i"] = 9
        self.assertEqual(L.kind_played(r), "other")
        self.assertEqual(L.kind_played(rnd(1, "mystery")), "other")
        self.assertIsNone(L.kind_played(dict(rnd(1), hand=[])))
        # (the card was played from the last hand before the cast when there was one)
        r = rnd(1, "damage")
        r["hand_last"] = [card(0, "trap")]
        self.assertEqual(L.kind_played(r), "trap")

    def test_round_damage(self):
        b = battle([rnd(1, dmg=420)])
        self.assertEqual(L.round_damage(b, b["rounds"][0]), 420)    # (not the ally's 50, not the enemy's hit on me)


class Learn(unittest.TestCase):
    def test_counted_per_school_and_pooled(self):
        p = L.Plays()
        self.assertEqual(p.add(battle([rnd(1, "blade"), rnd(2, "damage")], "storm", "won")), 2)
        self.assertEqual(p.add(battle([rnd(1, "blade")], "fire", "lost")), 1)
        self.assertEqual(p.add(battle([rnd(1, "blade")], "fire", "cut")), 0)      # (its end isn't known)
        self.assertEqual(p.add({"rec": "battle", "result": "won", "rounds": "junk"}), 0)
        self.assertEqual(p.add(None), 0)
        self.assertEqual((p.battles, p.rounds), (2, 3))
        key = L.key_of({"pips": 4, "alive": 1, "boss": False, "hit": True, "hp": 83})
        self.assertEqual(p.by["storm"][key]["blade"][:2], [1, 1])
        self.assertEqual(p.by["fire"][key]["blade"][:2], [1, 0])
        self.assertEqual(p.by["*"][key]["blade"][:2], [2, 1])
        self.assertEqual(p.by["storm"][key]["blade"][2], 2)      # (2 rounds left to the end at round 1 of 2)
        self.assertTrue(p.skipped)

    def test_school_takes_over_at_the_threshold(self):
        key = L.key_of({"pips": 4, "alive": 1, "boss": False, "hit": True, "hp": 83})
        p = L.Plays()
        # (every school: traps win 20 % of 100 rounds; storm alone none yet)
        for k in range(100):
            p.add(battle([rnd(1, "trap")], "fire", "won" if k % 5 == 0 else "lost"))
        none = p.prior("storm", key)["trap"]
        self.assertAlmostEqual(none["rate"], 0.2)
        self.assertEqual(none["w"], 0.0)
        # (storm's own: K rounds, all won - weighed half)
        for _ in range(L.K):
            p.add(battle([rnd(1, "trap")], "storm", "won"))
        half = p.prior("storm", key)["trap"]
        self.assertAlmostEqual(half["w"], 0.5)
        pooled = (20 + L.K) / float(100 + L.K)
        self.assertAlmostEqual(half["rate"], 0.5 * 1.0 + 0.5 * pooled)
        # (many more of its own: its own rate nearly all)
        for _ in range(20 * L.K):
            p.add(battle([rnd(1, "trap")], "storm", "won"))
        most = p.prior("storm", key)["trap"]
        self.assertGreater(most["w"], 0.95)
        self.assertGreater(most["rate"], 0.95)
        # (an unknown school: every school's)
        self.assertEqual(p.prior("", key)["trap"]["w"], 0.0)
        self.assertEqual(p.prior("storm", "p9|nope"), {})

    def test_prior_fn(self):
        sit = {"school": "storm", "pips": 4, "alive": 1, "boss": False, "hit": True, "hp": 83}
        p = L.Plays()
        for k in range(30):
            p.add(battle([rnd(1, "trap")], "storm", "won" if k % 10 else "lost"))     # 90 %
            p.add(battle([rnd(1, "blade")], "storm", "won" if k % 2 else "lost"))     # 50 %
        p.add(battle([rnd(1, "aura")], "storm", "won"))                                 # (1 round: not compared)
        bonus, why = p.prior_fn("storm")(sit)
        self.assertEqual(sorted(bonus), ["blade", "trap"])
        self.assertAlmostEqual(bonus["trap"], 0.8)        # (0.9 - 0.7) / 0.25
        self.assertAlmostEqual(bonus["blade"], -0.8)
        self.assertIn("trap won 90% of 30", why)
        self.assertIn("storm", why)
        self.assertEqual(p.prior_fn("storm")({"pips": None}), ({}, ""))
        self.assertEqual(L.Plays().prior_fn("storm")(sit), ({}, ""))

    def test_save_and_load(self):
        p = L.Plays()
        p.add(battle([rnd(1, "blade"), rnd(2, "pass", played=False)]))
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, L.PLAYS_FILE)
            self.assertTrue(p.save(path))
            self.assertFalse(os.path.exists(path + ".tmp"))
            q = L.Plays.load(path)
            self.assertEqual((q.by, q.battles, q.rounds), (p.by, 1, 2))
            with open(path, "w") as f:
                f.write('{"rec":"plays","v":1,"by":{"storm":{"k":{"blade":[1,"x",0,0]}}}')
            self.assertEqual(L.Plays.load(path).by, {})
            self.assertEqual(L.Plays.load(os.path.join(d, "none.json")).by, {})
            self.assertFalse(p.save(os.path.join(d, "no", "such", "dir", "p.json")))
        self.assertTrue(any("blade" in ln for ln in p.lines()))

    def test_build_from_files_with_a_torn_line(self):
        today = datetime.date.today()
        with tempfile.TemporaryDirectory() as base:
            folder = os.path.join(base, today.strftime("%Y-%m"))
            os.makedirs(folder)
            b1 = json.dumps(battle([rnd(1, "blade"), rnd(2)]), separators=(",", ":"))
            b2 = json.dumps(battle([rnd(1, "trap")]), separators=(",", ":"))
            b3 = json.dumps(battle([rnd(1, "aura")], result="lost"), separators=(",", ":"))
            with open(os.path.join(folder, today.isoformat() + ".jsonl"), "w") as f:
                f.write('{"rec":"header","v":1}\n' + b1 + "\n" + b2[:50] + "\n" + b3 + "\n")
            asked = []
            p = L.build(base, days=2, pause=lambda: asked.append(1) and False)
        self.assertEqual((p.battles, p.rounds), (2, 3))
        self.assertEqual(len(asked), 2)
        self.assertTrue(p.made)
        self.assertEqual(L.build(battles=iter([1, None, {"result": "won"}])).battles, 0)

    def test_planner_takes_the_prior(self):
        # (the learned plays nudge battlesim.plan_round: its situation's key is the records')
        p = L.Plays()
        for k in range(40):
            p.add(battle([rnd(1, "trap", pips=3, hp=3000, ok=False)], "storm", "won"))
            p.add(battle([rnd(1, "blade", pips=3, hp=3000, ok=False)], "storm", "lost" if k % 4 else "won"))
        blade = S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35})
        trap = S.Card("Storm Trap", "trap", "storm", 0, boosts={"storm": 30})
        lord = S.Card("Storm Lord", "damage", "storm", 7, heads={"storm": 1000})
        st = S.State.of_deck([blade, trap, lord], [lord] * 8, pips=3, fhp=[6000], rnd=2)
        plan = S.plan_round(st, S.Me("storm", 3000), [S.Foe("Boss", 6000)], n=20, seed=1, budget_ms=5000,
                            prior=p.prior_fn("storm"))
        self.assertIn("learned plays (storm, p1|a1|b0|h0|hp2", plan["learned"])
        by = {x["kind"]: x for x in plan["plays"]}
        self.assertAlmostEqual(by["trap"]["bonus"], S.PRIOR_W)
        self.assertAlmostEqual(by["blade"]["bonus"], -S.PRIOR_W)
        self.assertEqual(by["pass"]["bonus"], 0.0)


class Advice(unittest.TestCase):
    """the planner's advice (Planner.ahk, planner:1) in the rounds' bot lines, against what was played"""
    LINE = ("  Plan: would play Storm Lord at Bonestriker (won 92% in 3 rounds, 100 tries; ends it this round in 64%)"
            " - your settings' way: Stormblade on you (won 85%) [tid 101] - advice only (planner:1, 342 ms)")

    def test_rows_and_summary(self):
        same = rnd(1, "damage", tid=101, lines=[[0, "Round start"], [40, self.LINE]])
        other = rnd(2, "blade", tid=104, lines=[[40, self.LINE]])
        aoe = rnd(3, "aoe", tid=103, lines=[[40, "  Plan: would play Tempest on all (won 70% in 4 rounds, 80 tries;"
                                                    " lost in 6%) - your settings' way too [tid 103] - advice only"]])
        passed = rnd(4, played=False, lines=[[40, "  Plan: would play pass (won 40%, 100 tries; 100 rollouts)"]])
        none = rnd(5, lines=[[0, "  UseHit hit1: found=1"]])
        b = battle([same, other, aoe, passed, none])
        rows = L.advice_rows(b)
        self.assertEqual([(r["n"], r["advised"], r["tid"], r["same"]) for r in rows],
                         [(1, "Storm Lord", 101, True), (2, "Storm Lord", 101, False), (3, "Tempest", 103, True),
                          (4, "pass", None, True)])
        self.assertEqual(rows[0]["won_p"], 92)
        s = L.advice_summary([b, battle([other], result="lost")])
        self.assertEqual((s["rounds"], s["same"], s["differ"], s["won_same"], s["won_differ"]), (5, 3, 2, 3, 1))
        # (no tid in the line: by name - the log's spell name)
        named = rnd(1, "damage", lines=[[0, "  Plan: would play Damage at X (won 50%, 10 tries; 10 rollouts)"]])
        self.assertTrue(L.advice_rows(battle([named]))[0]["same"])


if __name__ == "__main__":
    unittest.main()
