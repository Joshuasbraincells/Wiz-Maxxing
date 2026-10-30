"""test_gearrank.py - the gear model (vision\\gearrank.py: stat names, an item's stats, its requirements, the score, the
swap plan, the drop log and "done", /gear's lines) on made-up items, and the vision helper's /gear (gear_lines_for, the
reader made up) - no game, no Windows:  python3 -m unittest test_gearrank   (from AutoFarmer\\vision)"""
import configparser
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import gearrank as G  # noqa: E402


def stat(name, v=None, index=None):
    f = {"m_effectName": name}
    if v is not None:
        f["m_value"] = v
    if index is not None:
        f["m_lookupIndex"] = index
    return {"type": "StatisticEffectInfo", "fields": f}


def lvl(n, op=0):
    return {"op": op, "not": False, "list": [{"type": "ReqMagicLevel", "fields": {"m_numericValue": n,
                                                                                 "m_applyNOT": False}}]}


def item(gid, slot, effects, reqs=None, tid=None, sets=(), name=None):
    return {"gid": gid, "tid": tid if tid is not None else gid, "name": name or "%s-%x" % (slot, gid), "slot": slot,
            "effects": effects, "reqs": reqs if reqs is not None else lvl(10), "sets": list(sets)}


TOTALS = {"damage": 60, "pierce": 10, "crit": 150, "block": 100, "acc": 5, "resist": 20, "hp": 3000}


class Stats(unittest.TestCase):
    def test_parse_stat(self):
        P = G.parse_stat
        self.assertEqual(P("CanonicalFireDamage"), ("damage", "fire"))
        self.assertEqual(P("CanonicalAllReduceDamage"), ("resist", "all"))
        self.assertEqual(P("CanonicalStormReduceDamage"), ("resist", "storm"))
        self.assertEqual(P("CanonicalMaxHealth"), ("health", ""))
        self.assertEqual(P("CanonicalLifeHealing"), ("outheal", "life"))
        self.assertEqual(P("CanonicalIncHealing"), ("incheal", ""))
        self.assertEqual(P("CanonicalAllArmorPiercing"), ("pierce", "all"))
        self.assertEqual(P("CanonicalDeathCriticalHit"), ("critical", "death"))
        self.assertEqual(P("CanonicalPowerPip"), ("powerpip", ""))
        self.assertEqual(P("CanonicalShadowPipRating"), ("shadowpip", ""))      # (not Shadow's "PipRating")
        self.assertEqual(P("CanonicalDamage"), ("damage", "all"))
        self.assertEqual(P("Something Odd"), ("raw", "Something Odd"))
        self.assertEqual(P(None), ("raw", ""))

    def test_slot_of(self):
        self.assertEqual(G.slot_of(["Hat", "FLAG_NoTrade"]), "hat")
        self.assertEqual(G.slot_of(["Deck", "Hat"]), "deck")
        self.assertEqual(G.slot_of(["Reagent"]), "")
        self.assertIsNone(G.slot_of(None))

    def test_item_stats(self):
        st, unk, how = G.item_stats([stat("CanonicalFireDamage", 8), stat("CanonicalFireDamage", 2),
                                     stat("CanonicalMaxHealth", index=3),
                                     {"type": "StartingPipEffectInfo", "fields": {"m_pipsGiven": 1, "m_powerPipsGiven": 0}},
                                     {"type": "ProvideSpellEffectInfo", "fields": {"m_spellName": "X", "m_numSpells": 2}},
                                     {"type": "WeirdEffectInfo", "fields": {}}])
        self.assertEqual(st["damage.fire"], 10)
        self.assertIsNone(st["health"])
        self.assertEqual(unk, ["health"])
        self.assertEqual(how["health"], "index:3")
        self.assertEqual((st["pips"], st["powerpips"], st["cards"]), (1, 0, 2))
        self.assertIn("raw.WeirdEffectInfo", st)
        self.assertEqual(G.stats_text(st, how).split(","), ["cards=2", "damage.fire=10", "health=#3", "pips=1",
                                                            "powerpips=0", "raw.WeirdEffectInfo"])
        self.assertEqual(G.item_stats(None), (None, ["effects"], {}))
        # (a lookup that knows the table: the size from it)
        st2, unk2, _h = G.item_stats([stat("CanonicalMaxHealth", index=3)], lookup=lambda n, i: 100 * i)
        self.assertEqual((st2["health"], unk2), (300, []))
        # (a value read as junk - NaN, a bool - isn't one)
        st3, unk3, _h = G.item_stats([stat("CanonicalFireDamage", float("nan"))])
        self.assertEqual(unk3, ["damage.fire"])

    def test_delta_of(self):
        d = G.delta_of({"damage.all": 3, "damage.fire": 5, "damage.ice": 9, "resist.all": 7, "resist.ice": 14,
                        "health": 200}, "fire")
        self.assertEqual((d["damage"], d["hp"]), (8, 200))
        self.assertAlmostEqual(d["resist"], 9.0)            # (7 + 14 / 7)


class Requirements(unittest.TestCase):
    def test_level_and_school(self):
        M = G.meets_reqs
        self.assertEqual(M(lvl(50), 60, "fire")[0], True)
        self.assertEqual(M(lvl(50), 40, "fire")[0], False)
        self.assertIsNone(M(lvl(50), None, "fire")[0])
        sch = {"op": 0, "not": False, "list": [{"type": "ReqSchoolOfFocus", "fields": {"m_magicSchool": "Fire"}}]}
        self.assertTrue(M(sch, 10, "fire")[0])
        self.assertFalse(M(sch, 10, "ice")[0])
        self.assertIsNone(M(sch, 10, "")[0])
        notfire = {"op": 0, "not": False, "list": [{"type": "ReqSchoolOfFocus",
                                                    "fields": {"m_magicSchool": "Fire", "m_applyNOT": True}}]}
        self.assertFalse(M(notfire, 10, "fire")[0])
        self.assertTrue(M(notfire, 10, "ice")[0])

    def test_lists(self):
        M = G.meets_reqs
        self.assertEqual(M({"op": None, "not": None, "list": []}, None, ""), (True, "no requirement"))
        self.assertIsNone(M(None, 10, "fire")[0])
        badge = {"op": 0, "not": False, "list": [{"type": "ReqHasBadge", "fields": {}}]}
        self.assertIsNone(M(badge, 10, "fire")[0])
        two = {"op": 0, "not": False, "list": lvl(50)["list"] + [{"type": "ReqSchoolOfFocus",
                                                                  "fields": {"m_magicSchool": "Ice"}}]}
        self.assertFalse(M(two, 60, "fire")[0])                    # (AND: one fails)
        self.assertTrue(M(two, 60, "ice")[0])
        two_or = dict(two, op=1)
        self.assertIsNone(M(two_or, 60, "fire")[0])                # (another op, mixed: not known)
        self.assertTrue(M(two_or, 60, "ice")[0])                   # (all agree: sure)
        self.assertFalse(M(dict(lvl(50), **{"not": True}), 60, "fire")[0])
        self.assertEqual(G.level_req(two), 50)
        self.assertEqual(G.reqs_text(two), "level>=50,school=ice")
        self.assertEqual(G.reqs_text(badge), "?ReqHasBadge")
        self.assertEqual(G.reqs_text(None), "?")


class Score(unittest.TestCase):
    def test_more_is_better(self):
        s0 = G.score(TOTALS, "hitter", "fire", 100)
        for k, v in (("damage", 10), ("pierce", 5), ("crit", 50), ("acc", 5), ("resist", 5), ("hp", 300)):
            t = dict(TOTALS)
            t[k] += v
            self.assertGreater(G.score(t, "hitter", "fire", 100), s0, k)

    def test_roles(self):
        t = dict(TOTALS, heal=20)
        self.assertEqual(G.score(t, "hitter", "fire"), G.score(TOTALS, "hitter", "fire"))   # (a hitter's heal weight 0)
        self.assertGreater(G.score(t, "healer", "life"), G.score(TOTALS, "healer", "life"))
        # (gearweights: a hitter who cares for health only)
        w = G.parse_weights("off:0,def:1, junk , pip=0")
        self.assertEqual(w, {"off": 0.0, "def": 1.0, "pip": 0.0})
        t2 = dict(TOTALS, damage=200)
        self.assertAlmostEqual(G.score(t2, "hitter", "fire", weights=w), G.score(TOTALS, "hitter", "fire", weights=w))

    def test_capped_resist_and_junk(self):
        self.assertTrue(G.score({"resist": 500, "hp": 100}, "blader", ""))
        self.assertTrue(G.score({}, "nobody", "nowhere") is not None)


class Plan(unittest.TestCase):
    def test_better_hat_planned(self):
        worn = [item(0x10, "hat", [stat("CanonicalFireDamage", 8)]), item(0x11, "deck", None)]
        bag = [item(0x20, "hat", [stat("CanonicalFireDamage", 12)]), item(0x21, "hat", [stat("CanonicalFireDamage", 9)]),
               item(0x22, "deck", None), item(0x23, "pet", None)]
        r = G.swap_plan(worn, bag, TOTALS, "fire", 60)
        self.assertEqual(len(r["plan"]), 1)
        p = r["plan"][0]
        self.assertEqual((p["slot"], p["gid"], p["worn_gid"], p["basis"], p["held"]), ("hat", 0x20, 0x10, "stats", False))
        self.assertIn("damage +4", p["why"])
        v = {j["gid"]: j["verdict"] for j in r["judged"]}
        self.assertEqual(v, {0x20: "better", 0x21: "not better"})       # (decks and pets never judged)

    def test_margin(self):
        worn = [item(0x10, "hat", [stat("CanonicalFireDamage", 8)])]
        bag = [item(0x20, "hat", [stat("CanonicalFireDamage", 9)])]
        self.assertEqual(G.swap_plan(worn, bag, TOTALS, "fire", 60, margin=50)["plan"], [])
        self.assertEqual(len(G.swap_plan(worn, bag, TOTALS, "fire", 60, margin=0.1)["plan"]), 1)

    def test_cant_wear_unknown_and_sets(self):
        worn = [item(0x10, "robe", [stat("CanonicalMaxHealth", 100)], sets=[2])]
        bag = [item(0x20, "robe", [stat("CanonicalMaxHealth", 900)], reqs=lvl(150)),
               item(0x21, "robe", [stat("CanonicalMaxHealth", 900)], reqs={"op": 0, "not": False,
                                                                           "list": [{"type": "ReqHasBadge", "fields": {}}]}),
               item(0x22, "robe", [stat("CanonicalMaxHealth", 900)], sets=[1]),
               item(0x23, "robe", [stat("CanonicalMaxHealth", 500)])]
        r = G.swap_plan(worn, bag, TOTALS, "fire", 100)
        v = {j["gid"]: j["verdict"] for j in r["judged"]}
        self.assertEqual(v, {0x20: "can't wear", 0x21: "unknown", 0x22: "in a set", 0x23: "better"})
        p = r["plan"][0]
        self.assertEqual((p["gid"], p["held"]), (0x23, True))             # (the worn robe's in set 2)
        self.assertIn("Equipment Set 2", p["why"])
        r2 = G.swap_plan(worn, bag, TOTALS, "fire", 100, allow_sets=True)
        self.assertEqual((r2["plan"][0]["gid"], r2["plan"][0]["held"]), (0x22, False))   # (gearsets:1: set pieces too)

    def test_level_basis_when_sizes_unknown(self):
        worn = [item(0x10, "shoes", [stat("CanonicalFireDamage", index=2)], reqs=lvl(50))]
        bag = [item(0x20, "shoes", [stat("CanonicalFireDamage", index=4)], reqs=lvl(80)),
               item(0x21, "shoes", [stat("CanonicalFireDamage", index=1)], reqs=lvl(40)),
               item(0x22, "shoes", [stat("CanonicalFireDamage", index=1)], reqs={"op": None, "not": None, "list": []})]
        r = G.swap_plan(worn, bag, TOTALS, "fire", 90)
        v = {j["gid"]: (j["verdict"], j["basis"]) for j in r["judged"]}
        self.assertEqual(v[0x20], ("better", "level"))
        self.assertEqual(v[0x21], ("not better", "level"))
        self.assertEqual(v[0x22], ("unknown", None))                      # (no level to go by)
        self.assertEqual((r["plan"][0]["gid"], r["plan"][0]["delta"]), (0x20, 30.0))

    def test_stats_basis_beats_level_and_empty_slot(self):
        worn = [item(0x10, "ring", [stat("CanonicalFireDamage", 2)])]
        bag = [item(0x20, "ring", [stat("CanonicalFireDamage", 6)]),
               item(0x21, "ring", [stat("CanonicalFireDamage", index=9)], reqs=lvl(55)),
               item(0x30, "amulet", [stat("CanonicalMaxHealth", 50)])]
        r = G.swap_plan(worn, bag, TOTALS, "fire", 60)
        got = {p["slot"]: (p["gid"], p["basis"]) for p in r["plan"]}
        self.assertEqual(got["ring"], (0x20, "stats"))
        self.assertEqual(got["amulet"], (0x30, "empty"))                 # (nothing worn there)
        self.assertNotIn("deck", got)

    def test_no_level_note(self):
        r = G.swap_plan([], [item(0x20, "hat", [stat("CanonicalFireDamage", 1)])], TOTALS, "fire", None)
        self.assertEqual(r["judged"][0]["verdict"], "unknown")
        self.assertTrue(any("level" in n for n in r["notes"]))


class Drops(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="gearrank_")

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def reading(self, bag, worn=(), extra_gids=()):
        return {"bag": list(bag), "worn": list(worn), "bag_gids": [b["gid"] for b in bag] + list(extra_gids)}

    def test_catalogue_and_slots(self):
        text = "; a note\r\nWaterworks|Celestia|link|hat, robe,boots|||\r\nDarkmoor|Darkmoor||hat,wand,junk|z1,z2||Malistaire\r\n"
        cat = G.catalogue(text)
        self.assertEqual([d["name"] for d in cat], ["Waterworks", "Darkmoor"])
        self.assertEqual(cat[0]["slots"], ["hat", "robe", "shoes"])
        self.assertEqual(cat[1]["slots"], ["hat", "weapon"])
        self.assertEqual(cat[1]["zones"], ["z1", "z2"])
        self.assertEqual(G.catalogue_for("Waterworks 2026-10-30", cat)["name"], "Waterworks")
        self.assertIsNone(G.catalogue_for("Tower of the Helephant", cat))
        self.assertEqual(G.run_file('a/b:c*"d'), "a-b-c-d")

    def test_run_end_drops_dry_and_done(self):
        book = G.DropBook(self.dir)
        hat0 = item(0x10, "hat", [], tid=100)
        start = [item(0x50, "robe", [], tid=500)]
        # (no mark yet: nothing counted, the backpack kept)
        out = book.run_end("Waterworks", self.reading(start, [hat0]), [], ["hat"], 3, "t0")
        self.assertFalse(out["marked"])
        self.assertEqual((out["new"], out["runs"], out["dry"]), ([], 1, 1))
        # (run 2: a hat and a reagent dropped - the hat logged; it's in the plan: an upgrade)
        new_hat = item(0x60, "hat", [], tid=600, name="Hat-WW")
        rd = self.reading(start + [new_hat], [hat0], extra_gids=[0x61])
        out = book.run_end("Waterworks", rd, [{"gid": 0x60}], ["hat"], 3, "t1")
        self.assertTrue(out["marked"])
        self.assertEqual([it["gid"] for it in out["new"]], [0x60])
        self.assertEqual((out["dry"], out["done"]), (0, False))
        drops = book.load_drops("Waterworks")
        self.assertEqual(drops[600]["count"], 1)
        self.assertEqual(drops[600]["first"], "t1")
        # (run 3: nothing new; the hat put on (worn now - a drop's template): an upgrade, and every slot it drops is
        # worn from its drops: done)
        worn_now = [dict(new_hat, where="worn")]
        rd3 = self.reading(start, worn_now, extra_gids=[0x61])
        out = book.run_end("Waterworks", rd3, [], ["hat"], 3, "t2")
        self.assertEqual((out["new"], out["dry"], out["done"]), ([], 0, True))
        self.assertIn("worn with its own drop", out["why"])
        # (the state file is an .ini Dungeons.ahk reads)
        cp = configparser.ConfigParser()
        cp.read(book.path("Waterworks", ".state"), encoding="utf-8")
        self.assertEqual((cp["run"]["runs"], cp["run"]["done"], cp["run"]["worn"]), ("3", "1", "hat:600"))
        with open(book.path("Waterworks", ".txt"), "rb") as f:
            data = f.read()
        self.assertIn(b"\r\n600|Hat-WW|hat||t1|1\r\n", data)

    def test_dry_runs_end_it(self):
        book = G.DropBook(self.dir)
        rd = self.reading([item(0x50, "robe", [], tid=500)])
        book.mark("Hades", rd, "t0")
        for k in range(1, 4):
            out = book.run_end("Hades", rd, [], [], 3, "t%d" % k)
        self.assertEqual((out["dry"], out["done"]), (3, True))
        self.assertIn("3 runs with no upgrade", out["why"])
        self.assertEqual(G.done_check(["hat", "robe"], [], {}, 1, 30),
                         (False, "hat, robe not worn from its drops yet, 1 of 30 dry runs"))


class Answer(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="gearrank_")

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def reading(self):
        worn = [item(0x10, "hat", [stat("CanonicalFireDamage", 8)], tid=1), dict(item(0x11, "deck", None), slot="deck")]
        bag = [item(0x20, "hat", [stat("CanonicalFireDamage", 12)], tid=2, name="Hat-New")]
        return {"worn": worn, "bag": bag, "bag_gids": [0x20, 0x99], "bag_size": 2, "level": 70, "sets_ok": True}

    def q(self, **kw):
        q = {k: str(v) for k, v in TOTALS.items()}
        q.update(school="fire")
        q.update(kw)
        return q

    def test_lines(self):
        lines = G.answer(self.reading(), "", self.q())
        kinds = [ln.split("|")[0] for ln in lines]
        self.assertEqual(kinds[:2], ["gear", "stats"])
        self.assertEqual(kinds.count("worn"), 2)
        g = lines[0].split("|")
        self.assertEqual(g[1:8], ["2", "1", "2", "70", "fire", "hitter", "1"])
        plan = [ln for ln in lines if ln.startswith("plan|")]
        self.assertEqual(len(plan), 1)
        f = plan[0].split("|")
        self.assertEqual(f[1:4] + f[5:6] + f[8:10], ["hat", "20", "2", "10", "stats", "0"])
        it = next(ln for ln in lines if ln.startswith("item|")).split("|")
        self.assertEqual(len(it), 15)
        self.assertEqual(it[6], "better")
        self.assertEqual(lines[1], "stats|60|10|150|100|5|20|3000|0|70")

    def test_run_mark_then_end(self):
        r = self.reading()
        lines = G.answer(r, "", self.q(run="Waterworks 1", mark="1"), self.dir, "", when="t0")
        self.assertTrue(any(ln.startswith("run|Waterworks 1|0|0||0|marked") for ln in lines))
        r2 = self.reading()
        r2["bag"].append(item(0x30, "robe", [stat("CanonicalMaxHealth", 300)], tid=3, name="Robe-WW"))
        r2["bag_gids"].append(0x30)
        known = "Waterworks|Celestia||hat,robe,shoes|||\r\n"
        lines = G.answer(r2, "", self.q(run="Waterworks 1", end="1", stopafter="5"), self.dir, known, when="t1")
        drop = [ln for ln in lines if ln.startswith("drop|")]
        self.assertEqual(drop, ["drop|3|Robe-WW|robe||1|t1"])
        run = next(ln for ln in lines if ln.startswith("run|")).split("|")
        self.assertEqual(run[1:6], ["Waterworks 1", "1", "0", "5", "0"])
        self.assertIn("hat, robe, shoes not worn", run[6])                 # (the catalogue's slots)
        self.assertEqual(run[7:9], ["1", "1"])

    def test_soft(self):
        self.assertEqual(G.answer(None, "the game is not running", {}), ["none|the game is not running"])
        lines = G.answer(self.reading(), "", {"level": "x", "margin": "y", "hp": "z", "role": "boss"})
        self.assertEqual(lines[0].split("|")[4:7], ["70", "", "hitter"])
        self.assertTrue(any("school isn't known" in ln for ln in lines))
        self.assertTrue(G.answer({"worn": "junk"}, "", {})[0].startswith("none|the gear plan failed"))


class VisionRoute(unittest.TestCase):
    """the helper's /gear: gear_lines_for with the reader made up (vision.py's nav_reader, ROOT and log put back)"""

    def setUp(self):
        import vision as V
        self.V = V
        self.keep = (V.nav_reader, V.ROOT, V.log)
        self.dir = tempfile.mkdtemp(prefix="gearroute_")
        os.makedirs(os.path.join(self.dir, "resources"))
        with open(os.path.join(self.dir, "resources", "dungeons_known.txt"), "w", encoding="utf-8") as f:
            f.write("Hades|Aquila||hat|||\n")
        self.logged = []
        V.log = lambda text, *a, **kw: self.logged.append(text)
        V.ROOT = self.dir

    def tearDown(self):
        self.V.nav_reader, self.V.ROOT, self.V.log = self.keep
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_route(self):
        V = self.V
        r = Answer.reading(self)

        class Nav:
            def gear(self, wait=0.3):
                return r, ""
        V.nav_reader = lambda: Nav()
        lines = V.gear_lines_for({"run": "Hades", "mark": "1", "school": "fire"})
        self.assertTrue(lines[0].startswith("gear|"))
        self.assertTrue(os.path.isfile(os.path.join(self.dir, "learned", "drops", "Hades.state")))
        self.assertTrue(self.logged and self.logged[-1].startswith("/gear (memory): gear|"))

        class Broken:
            def gear(self, wait=0.3):
                raise RuntimeError("boom")
        V.nav_reader = lambda: Broken()
        self.assertTrue(V.gear_lines_for({})[0].startswith("none|the gear couldn't be read"))


if __name__ == "__main__":
    unittest.main()
