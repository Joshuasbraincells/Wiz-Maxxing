"""test_stuckreport.py - the badly-stuck count and time-lost report's checks (standard library only):
python -m unittest vision\\test_stuckreport.py"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stuckreport as R  # noqa: E402

START = "20:00:00 Started v0.9.0. Game area 0,0 1920x1080"
TRY = ("Walk: stuck at distance 40 (no closer in 4 s): try %d - back up, turn 75 degrees right, walk %d ms")


def runs(text, source="debug.log"):
    return [R.analyse(r) for r in R.split_runs(text.strip("\n").split("\n"), source)]


def one(text):
    rs = runs(text)
    assert len(rs) == 1, rs
    return rs[0]


class Splitting(unittest.TestCase):
    def test_runs_and_midnight(self):
        rs = R.split_runs([
            "23:59:50 Started v0.8.1. Game area 0,0 800x600",
            "00:00:10 Walk: something",
            "a message's own second line",
            "08:00:00 Started v0.9.0. Game area 0,0 800x600",
            "08:00:05 Walk: x"], "f")
        self.assertEqual(len(rs), 2)
        self.assertEqual(rs[0]["version"], "v0.8.1")
        self.assertEqual([t for t, m in rs[0]["lines"]], [86390, 86410])     # past midnight: a day on
        self.assertEqual(R.clock(86410), "00:00:10 +1d")
        self.assertEqual(rs[1]["version"], "v0.9.0")
        self.assertTrue(rs[1]["started"])

    def test_no_start_line(self):
        rs = R.split_runs(["10:00:00 Walk: x", "10:00:01 Walk: y"])
        self.assertEqual(len(rs), 1)
        self.assertFalse(rs[0]["started"])

    def test_small_step_back_isnt_midnight(self):
        rs = R.split_runs(["10:00:00 Walk: x", "09:59:00 Walk: y"])
        self.assertEqual([t for t, m in rs[0]["lines"]], [36000, 35940])


class OldLines(unittest.TestCase):
    def test_tries_got_round(self):
        o = one("\n".join([START,
                           "20:01:00 " + TRY % (1, 900),
                           "20:01:03 " + TRY % (2, 1800),
                           "20:01:08 Walk: got round the obstacle at distance 40 going left"]))
        self.assertEqual(o["unstick_tries"], 2)
        self.assertEqual(o["unstick_episodes"], 1)
        self.assertEqual(o["got_round"], 1)
        self.assertEqual(o["badly_stuck"], 0)
        self.assertFalse(o["exact"])
        # 4 s stall before try 1 (20:00:56) to "got round" (20:01:08)
        self.assertEqual(o["lost_estimated_seconds"], 12)
        self.assertEqual(o["episodes"][0]["how"], "got round")

    def test_tries_started_over(self):
        o = one("\n".join([START,
                           "20:01:00 " + TRY % (1, 900),
                           "20:05:00 " + TRY % (1, 900)]))
        self.assertEqual(o["unstick_episodes"], 2)
        # each: the 4 s stall, the walk 0.9 s and the back-up / turn 1.5 s
        self.assertEqual(o["lost_estimated_seconds"], round(2 * (4 + 0.9 + 1.5)))

    def test_stall_from_why(self):
        self.assertEqual(R.stall_of("walking on but no closer for 15 s - the game's memory"), 15)
        self.assertEqual(R.stall_of("picture not moving: 3% changed"), 1.2)
        self.assertEqual(R.stall_of("going to and fro a third time in a minute"), 0)
        self.assertEqual(R.stall_of("whatever"), 4)

    def test_gave_up_commons_counted_once(self):
        o = one("\n".join([START,
                           "20:01:00 " + TRY % (1, 900),
                           "20:01:10 " + TRY % (5, 3600),
                           "20:01:20 Walk: stuck: gave up after 5 tries",
                           "20:01:20 Walk: badly stuck (couldn't get round an obstacle in 5 tries) - teleporting to the "
                           "Commons (End) to start over",
                           "20:01:40 Walk: at the Commons (WizardCity/WC_Hub) - walking on from here"]))
        self.assertEqual(o["gave_up"], 1)
        self.assertEqual(o["commons_teleports"], 1)
        self.assertEqual(o["commons_arrived"], 1)
        self.assertEqual(o["badly_stuck"], 1)
        self.assertEqual(o["lost_estimated_seconds"], 44)        # 20:00:56 to the Commons at 20:01:40
        self.assertEqual(o["episodes"][0]["how"], "at the Commons")

    def test_waiting_for_you_till_the_notice_closes(self):
        o = one("\n".join([START,
                           "20:01:00 " + TRY % (1, 900),
                           "20:01:30 Walk: stuck: gave up after 5 tries",
                           "20:01:30 Walk: NEEDS YOU - Stuck: The wizard couldn't get round an obstacle (40 from the goal)",
                           "20:11:30 Walk: notice 'Stuck' closed"]))
        self.assertEqual(o["notices"], {"Stuck": 1})
        self.assertEqual(o["badly_stuck"], 1)
        self.assertEqual(o["lost_estimated_seconds"], 634)       # 20:00:56 to 20:11:30
        self.assertTrue(o["episodes"][0]["bad"])

    def test_open_at_the_end(self):
        o = one("\n".join([START,
                           "20:01:00 Walk: stuck at a teleport: the quest's way on is a teleport ... - walking off",
                           "20:01:00 Walk: NEEDS YOU - Stuck at a teleport: The quest's way on ...",
                           "20:31:00 Walk: the last minute: nothing"]))
        self.assertEqual(o["teleport_stuck"], 1)
        self.assertEqual(o["badly_stuck"], 1)
        self.assertEqual(o["episodes"][0]["how"], "open at the run's end")
        self.assertEqual(o["lost_estimated_seconds"], 1800)

    def test_battles_left_out(self):
        o = one("\n".join([START,
                           "20:01:00 Walk: stuck: gave up after 5 tries",
                           "20:01:00 Walk: NEEDS YOU - Stuck: x",
                           "20:02:00 Round start: Pass button at 1,2",
                           "20:03:00 Round start: Pass button at 1,2",
                           "20:04:00 Out of battle (spellbook visible)",
                           "20:05:00 Walk: notice 'Stuck' closed"]))
        self.assertEqual(o["battle_seconds"], 120)
        self.assertEqual(o["lost_estimated_seconds"], 240 - 120)

    def test_nocloser_commons_counts_its_minutes(self):
        o = one("\n".join([START,
                           "20:10:00 Walk: badly stuck (no closer to the goal in 3 minutes of walking) - teleporting to "
                           "the Commons (End) to start over",
                           "20:10:20 Walk: at the Commons (Krokotopia/KT_Hub) - walking on from here"]))
        self.assertEqual(o["lost_estimated_seconds"], 200)
        self.assertEqual(o["badly_stuck"], 1)

    def test_same_place_and_others(self):
        o = one("\n".join([START,
                           "20:01:00 Walk: badly stuck (couldn't get round an obstacle in 5 tries) where it was at 19:40 too "
                           "(X, 35 from the goal) - the Commons only brings it back here: walking off",
                           "20:01:00 Walk: NEEDS YOU - Stuck at the same place again: ...",
                           "20:10:00 Puzzle: the walker gives up here (no closer) - stuck at 1, 2 (300 off the goal)",
                           "20:20:00 Dungeons: no closer to step 4 in 7 s (300 away) - backing up and turning",
                           "20:21:00 Dungeons: stopped 'Rattlebones' after 2 runs - stuck 300 from step 4 (X) - no closer "
                           "after backing up 4 times",
                           "20:30:00 Dungeons: no loading screen into Y - step 7 again (try 2)",
                           "20:31:00 Dungeons: stopped 'Rattlebones' after 0 runs - the way from A into B didn't load (3 tries)",
                           "20:40:00 Walk: the teleport to the Commons didn't happen (no loading screen) - x"]))
        self.assertEqual(o["same_place"], 1)
        self.assertEqual(o["puzzle_giveups"], 1)
        self.assertEqual(o["dungeon_backups"], 1)
        self.assertEqual(o["dungeon_stops_stuck"], 1)
        self.assertEqual(o["dungeon_noload"], 1)
        self.assertEqual(o["dungeon_stops_load"], 1)
        self.assertEqual(o["commons_failed"], 1)
        self.assertEqual(o["badly_stuck"], 4)                     # same place (+ its notice), puzzle, 2 dungeon stops


class NewLines(unittest.TestCase):
    def test_exact_lines_win(self):
        o = one("\n".join([START,
                           "20:01:00 " + TRY % (1, 900),
                           "20:01:08 Walk: got round the obstacle at distance 40 going left",
                           "20:01:08 Walk: stuck over - 9 s lost (obstacle, 1 try, got round)",
                           "20:05:00 Walk: badly stuck #1 (nocloser): no closer to the goal in 3 minutes of walking",
                           "20:05:00 Walk: badly stuck (no closer to the goal in 3 minutes of walking) - teleporting to "
                           "the Commons (End) to start over",
                           "20:05:20 Walk: at the Commons (Z) - walking on from here",
                           "20:05:20 Walk: stuck over - 200 s lost (nocloser, 0 tries, at the Commons)"]))
        self.assertTrue(o["exact"])
        self.assertEqual(o["badly_stuck"], 1)
        self.assertEqual(o["badly_stuck_kinds"], {"nocloser": 1})
        self.assertEqual(o["lost_seconds"], 209)
        self.assertEqual(o["lost_exact_kinds"], {"obstacle": 9, "nocloser": 200})
        self.assertEqual(o["lost_estimated_seconds"], 12 + 200)   # the old lines' estimate kept beside it

    def test_over_line_forms(self):
        for line, n, kind in [("Walk: stuck over - 5 s lost (obstacle, 2 tries, got round)", 5, "obstacle"),
                              ("Walk: stuck over - 31 s lost (sigil, 0 tries, the sigil started - in X/Y)", 31, "sigil"),
                              ("Walk: stuck over - 7 s lost (teleport)", 7, "teleport")]:
            m = R.OVER.match(line)
            self.assertIsNotNone(m, line)
            self.assertEqual((int(m.group(1)), m.group(2)), (n, kind))


class Sigils(unittest.TestCase):
    X = "Walk: sigil: sigil prompt showing (the arrow led here) - pressed X, waiting 30 s"

    def test_still_here_after_a_relog(self):
        o = one("\n".join([START,
                           "21:41:55 Reconnect: back in the game (Celestia/CL_Hub)",
                           "21:44:00 " + self.X,
                           "21:44:30 Walk: sigil: waited 30 s - walking on",
                           "21:44:30 Walk: sigil: still here - X again when its prompt shows",
                           "21:45:00 Walk: sigil: at the goal (distance 3) and it's a sigil - pressed X, waiting 30 s",
                           "21:45:30 Walk: sigil: waited 30 s - walking on"]))
        self.assertEqual(o["sigil_x"], 2)
        self.assertEqual(o["sigil_failed"], 1)                   # the first: still here; the second's not known
        self.assertEqual(o["sigil_failed_after_relog"], 1)
        self.assertEqual(o["failed_sigils"][0]["relog_ago_seconds"], 125)
        self.assertEqual(o["relogs"], [{"at": "21:41:55", "zone": "Celestia/CL_Hub"}])
        self.assertEqual(o["lost_estimated_seconds"], 30)

    def test_x_again_soon_is_likely(self):
        o = one("\n".join([START,
                           "21:44:00 " + self.X,
                           "21:44:30 Walk: sigil: waited 30 s - walking on",
                           "21:45:00 Walk: sigil: at the goal (distance 3) and it's a sigil - pressed X, waiting 30 s"]))
        self.assertEqual(o["sigil_failed"], 0)
        self.assertEqual(o["sigil_likely"], 1)
        self.assertTrue(o["failed_sigils"][0]["likely"])

    def test_working_sigil_not_counted(self):
        o = one("\n".join([START,
                           "21:44:00 " + self.X,
                           "21:44:14 Walk: sigil: in Celestia/CL_Dungeon 12 s after X (its loading screen over) - walking on",
                           "21:46:00 " + self.X,
                           "21:46:20 Backpack: a dungeon (entered through its sigil: X) - the next full backpack is held",
                           "21:47:00 " + self.X]))
        self.assertEqual(o["sigil_started"], 1)
        self.assertEqual(o["sigil_failed"] + o["sigil_likely"], 0)

    def test_didnt_start_line_and_reset(self):
        o = one("\n".join([START,
                           "20:59:00 Reconnect: in the world after a character select (Celestia/CL_Hub) - a relog",
                           "21:00:00 " + self.X,
                           "21:00:30 Walk: sigil: didn't start - still in Celestia/CL_Hub 30 s after X, no loading screen "
                           "by the game's log (1 in a row here; a relog 1 min ago)",
                           "21:01:00 " + self.X,
                           "21:01:30 Walk: sigil: didn't start - still in Celestia/CL_Hub 30 s after X, no loading screen "
                           "by the game's log (2 in a row here; a relog 2 min ago)",
                           "21:01:30 Walk: badly stuck #1 (sigil): the sigil didn't start 2 times in a row",
                           "21:01:30 Walk: sigil: leaving it (the sigil didn't start 2 times in a row) - a Mark here",
                           "21:02:10 Walk: sigil: back at the sigil (Celestia/CL_Hub) after Home and the Recall - X again",
                           "21:02:20 " + self.X,
                           "21:02:32 Walk: sigil: in Celestia/CL_Dungeon 12 s after X (its loading screen over) - walking on",
                           "21:02:32 Walk: stuck over - 92 s lost (sigil, 0 tries, the sigil started - in Celestia/CL_Dungeon)"]))
        self.assertEqual(o["sigil_failed"], 2)
        self.assertEqual(o["sigil_failed_after_relog"], 2)
        self.assertEqual(o["sigil_started"], 1)
        self.assertEqual((o["sigil_leaves"], o["sigil_back"]), (1, 1))
        self.assertEqual(o["badly_stuck"], 1)
        self.assertEqual(o["lost_seconds"], 92)

    def test_dialogue_isnt_a_failure(self):
        o = one("\n".join([START,
                           "21:00:00 " + self.X,
                           "21:00:02 Walk: sigil: X opened a dialogue, not a dungeon - pressing Space through it",
                           "21:01:00 " + self.X]))
        self.assertEqual(o["sigil_dialogues"], 1)
        self.assertEqual(o["sigil_failed"] + o["sigil_likely"], 0)


class Output(unittest.TestCase):
    def test_files_text_json(self):
        with tempfile.TemporaryDirectory() as d:
            p1, p2 = os.path.join(d, "debug.previous.log"), os.path.join(d, "debug.log")
            with open(p1, "w", newline="\r\n") as f:
                f.write("\n".join([START, "20:01:00 Walk: stuck: gave up after 5 tries",
                                   "20:01:00 Walk: NEEDS YOU - Stuck: x", "20:02:00 Walk: notice 'Stuck' closed"]) + "\n")
            with open(p2, "w") as f:
                f.write("\n".join(["08:00:00 Started v0.9.0. Game area 0,0 1920x1080",
                                   "08:00:10 Walk: badly stuck #1 (obstacle): couldn't get round an obstacle in 5 tries",
                                   "08:00:40 Walk: stuck over - 30 s lost (obstacle, 5 tries, closer to the goal)"]) + "\n")
            rs = R.report([p1, p2])
            self.assertEqual(len(rs), 2)
            self.assertEqual([r["badly_stuck"] for r in rs], [1, 1])
            self.assertEqual([r["exact"] for r in rs], [False, True])
            t = R.total(rs)
            self.assertEqual((t["runs"], t["badly_stuck"], t["lost_seconds"], t["estimated_runs"]), (2, 2, 90, 1))
            txt = R.text(rs, episodes=True)
            self.assertIn("Badly stuck      1   (estimated - an older log)", txt)
            self.assertIn("All 2 runs", txt)
            self.assertEqual(len(R.report([p1, p2], last=1)), 1)
            self.assertEqual(R.report([os.path.join(d, "missing.log")]), [])
            # the command line: JSON on stdout
            import io
            import contextlib
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                R.main([p1, p2, "--json"])
            o = json.loads(buf.getvalue())
            self.assertEqual(o["total"]["badly_stuck"], 2)

    def test_empty(self):
        self.assertEqual(R.text([]), "no log lines read")
        self.assertEqual(R.dur(59), "59 s")
        self.assertEqual(R.dur(61), "1 min 01 s")
        self.assertEqual(R.dur(3661), "1 h 01 min")


if __name__ == "__main__":
    unittest.main()
