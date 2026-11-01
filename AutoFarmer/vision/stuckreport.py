r"""stuckreport.py - how often the walker got badly stuck and how much time that lost, run by run of the bot, read from
AutoFarmer's debug.log (TODO goal 2: "Measure it"). Read only, standard library only - nothing of the game's is touched.

    python vision\stuckreport.py                          debug.previous.log, then debug.log (next to the vision folder)
    python vision\stuckreport.py "D:\OneDrive\Wiz-Maxxing logs\PC1\debug.log" --episodes
    python vision\stuckreport.py debug.log --runs 1 --json

    files...        the logs to read, oldest first (several runs in one file are split at each "Started ..." line; a file
                    with none is one run)
    --runs N        only the last N runs
    --episodes      each stuck episode and each sigil that didn't start, with its time
    --json          one JSON object instead of the text

Lines are "HH:mm:ss text" with no date: a time over an hour before the line before it is taken as past midnight.

Counted per run: the walker's unstick tries ("stuck at distance .. try N") and the obstacles got round, its give-ups
("gave up after 5 tries"), teleports to the Commons (and where they arrived / didn't happen), "the same place again",
"stuck at a teleport", its "NEEDS YOU" notices by title, the puzzle code's "the walker gives up here", the dungeon runs'
back-ups and their stops (stuck / a way that didn't load), the sigils X'd, the ones that started and the ones that
didn't - each tied to the last relog before it ("Reconnect: back in the game", "in the world after a character select")
- and battle time.
Badly stuck: exact from the walker's own "badly stuck #N (kind): why" lines (v1.0.0 on); an older log's give-up lines
within 2 minutes of each other taken as one (a give-up and its Commons teleport or notice: one), said "estimated".
Time lost: exact from the walker's "stuck over - N s lost" lines (v1.0.0 on; an episode still open at the end of a run
isn't in them); an older log's estimated - each run of unstick tries from the stall before try 1 (its why: "no closer
in 4 s", "...for 15 s", "picture not moving" 1.2 s) to "got round" (else the last try's back-up, turn and walk), a give-up
on to the Commons' arrival or the notice closed (F8 - else the run's end), 3 minutes before a "no closer to the goal"
teleport, 9 s a dungeon back-up, the wait of each sigil that didn't start - battle time ("Round start" to "Out of
battle") left out. A sigil that didn't start: exact from "sigil: didn't start" (v1.0.0 on) or "sigil: still here";
likely - another X within 5 minutes with no sign of a zone change between - counted apart."""
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FARMER = os.path.dirname(HERE)
DEFAULT_FILES = [os.path.join(FARMER, "debug.previous.log"), os.path.join(FARMER, "debug.log")]

LINE = re.compile(r"^(\d\d):(\d\d):(\d\d) (.*)$")
START = re.compile(r"^Started (\S*?)\.? Game area|^Started (v\S+)")
# (the walker's own lines - Walker.ahk; the time-lost and count lines are v1.0.0's)
TRY = re.compile(r"^Walk: stuck at distance (\S+) \((.*?)\): try (\d+) - back up, turn \d+ degrees \w+, walk (\d+) ms")
GOT_ROUND = re.compile(r"^Walk: got round the obstacle at distance")
GAVE_UP = re.compile(r"^Walk: stuck: gave up after (\d+) tries")
COMMONS_GO = re.compile(r"^Walk: badly stuck \((.*)\) - teleporting to the Commons")
COMMONS_AT = re.compile(r"^Walk: at the Commons \((.*)\) - walking on from here")
COMMONS_FAIL = re.compile(r"^Walk: the teleport to the Commons didn't happen")
SAME_SPOT = re.compile(r"^Walk: badly stuck \((.*)\) where it was at (\d\d?:\d\d) too")
TP_STUCK = re.compile(r"^Walk: stuck at a teleport:")
NEEDS = re.compile(r"^Walk: NEEDS YOU - (.*?): ")
NOTE_CLOSED = re.compile(r"^Walk: notice '(.*)' closed")
FRO = re.compile(r"^Walk: going to and fro a third time in a minute - taken as stuck")
BAD = re.compile(r"^Walk: badly stuck #(\d+) \(([^)]*)\): (.*)$")
OVER = re.compile(r"^Walk: stuck over - (\d+) s lost \(([^,)]*)(?:, (\d+) tr(?:y|ies))?(?:, (.*))?\)$")
STUCK_WHY_S = re.compile(r"no closer (?:in|for) (\d+) s")
NOCLOSER = re.compile(r"no closer to the goal in (\d+) minutes? of walking")
# (sigils - Walker.ahk)
SIGIL_X = re.compile(r"^Walk: sigil: (.*) - pressed X, waiting (\d+) s")
SIGIL_STILL = re.compile(r"^Walk: sigil: still here - X again")
SIGIL_DIDNT = re.compile(r"^Walk: sigil: didn't start - still in (\S+) (\d+) s after X")
SIGIL_IN = re.compile(r"^Walk: sigil: in (\S+) (\d+) s after X")
SIGIL_DIALOG = re.compile(r"^Walk: sigil: X opened a dialogue")
SIGIL_LEAVE = re.compile(r"^Walk: sigil: leaving it")
SIGIL_BACK = re.compile(r"^Walk: sigil: back at the sigil")
SIGIL_WONT = re.compile(r"^Walk: sigil: won't start")
# (a sign the zone changed: a dungeon entered or left, the Commons, a loading screen, a dungeon run's next zone)
ZONE_SIGNS = re.compile(r"^(Walk: at the Commons|Walk: loading screen|Walk: sigil: just came out of|Backpack: a dungeon|"
                        r"Dungeons: in |Walk: sigil: in |Potions: at )")
# (others' lines - Puzzle.ahk, Dungeons.ahk, Reconnect.ahk, Autofarmer.ahk)
PUZZLE_GIVEUP = re.compile(r"^Puzzle: the walker gives up here \((.*?)\) - (.*?) at ")
DG_BACKUP = re.compile(r"^Dungeons: no closer to step (\d+) in 7 s")
DG_STOP_STUCK = re.compile(r"^Dungeons: stopped '(.*)' after \d+ runs? - stuck ")
DG_STOP_LOAD = re.compile(r"^Dungeons: stopped '(.*)' after \d+ runs? - the way from .* didn't load")
DG_NOLOAD = re.compile(r"^Dungeons: no loading screen into (\S+) - step (\d+) again")
RELOG = re.compile(r"^Reconnect: (?:back in the game|in the world after a character select) \((.*?)\)")
ROUND = re.compile(r"^Round start")
OUT = re.compile(r"^Out of battle")

GIVEUP_MERGE_S = 120     # give-up lines this close together: one badly-stuck episode (a give-up, its Commons, its notice)
SIGIL_AGAIN_S = 300      # another sigil X this soon with no zone sign between: the first likely didn't start
TRY_EXTRA_S = 1.5        # a try's back-up (0.8 s) and its turn, on top of its walk
DG_BACKUP_S = 9          # a dungeon back-up: its 7 s with no closer, the back-up, the turn and the walk on
PICTURE_STALL_S = 1.2    # "picture not moving": FastStuckTime
DEFAULT_STALL_S = 4      # a try whose why says nothing: StuckTime


# ============================================================================ reading
def read_lines(path):
    """a log's lines (bytes as UTF-8, anything else replaced - AutoHotkey writes it as the system's code page or UTF-8);
    [] when it can't be read"""
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return []
    return data.decode("utf-8", errors="replace").splitlines()


def split_runs(lines, source=""):
    """the runs in a log: [{source, version, started (bool), lines: [(t, msg)]}] - t in seconds from the run's first
    day's midnight (a time over an hour before the line before: past midnight); lines that aren't "HH:mm:ss text"
    (a message's own line breaks) left out"""
    runs, cur, prev, day = [], None, None, 0
    for raw in lines:
        m = LINE.match(raw)
        if not m:
            continue
        msg = m.group(4)
        st = START.match(msg)
        sec = int(m.group(1)) * 3600 + int(m.group(2)) * 60 + int(m.group(3))
        if st or cur is None:
            cur = {"source": source, "version": (st.group(1) or st.group(2) or "") if st else "",
                   "started": bool(st), "lines": []}
            runs.append(cur)
            prev, day = None, 0
        if prev is not None and sec + day * 86400 < prev - 3600:
            day += 1
        t = sec + day * 86400
        prev = t
        cur["lines"].append((t, msg))
    return runs


def clock(t):
    """seconds from the run's first midnight as HH:MM:SS (a day later: +1d)"""
    t = int(t)
    d, t = divmod(t, 86400)
    return "%02d:%02d:%02d%s" % (t // 3600, t // 60 % 60, t % 60, " +%dd" % d if d else "")


# ============================================================================ the sums
def battles_in(lines):
    """battle time spans [(t0, t1)]: the first "Round start" to "Out of battle" (one still on at the end: to the last line)"""
    spans, on = [], None
    for t, msg in lines:
        if on is None and ROUND.match(msg):
            on = t
        elif on is not None and OUT.match(msg):
            spans.append((on, t))
            on = None
    if on is not None and lines:
        spans.append((on, lines[-1][0]))
    return spans


def outside(t0, t1, spans):
    """seconds from t0 to t1 with the battle spans left out (0 when t1 <= t0)"""
    if t1 <= t0:
        return 0.0
    total = t1 - t0
    for a, b in spans:
        lo, hi = max(a, t0), min(b, t1)
        if hi > lo:
            total -= hi - lo
    return max(0.0, total)


def stall_of(why):
    """the time with no progress before an unstick try, by its why"""
    m = STUCK_WHY_S.search(why)
    if m:
        return float(m.group(1))
    if "picture not moving" in why:
        return PICTURE_STALL_S
    if "to and fro" in why:
        return 0.0
    return float(DEFAULT_STALL_S)


def analyse(run):
    """one run summed up (a dict - see the docstring)"""
    lines = run["lines"]
    spans = battles_in(lines)
    t_first = lines[0][0] if lines else 0
    t_last = lines[-1][0] if lines else 0
    o = {"source": run["source"], "version": run["version"], "started": run["started"],
         "start": clock(t_first), "end": clock(t_last), "seconds": t_last - t_first,
         "battle_seconds": round(sum(b - a for a, b in spans)), "unstick_tries": 0, "unstick_episodes": 0,
         "got_round": 0, "fro_stuck": 0, "gave_up": 0, "commons_teleports": 0, "commons_arrived": 0,
         "commons_failed": 0, "same_place": 0, "teleport_stuck": 0, "notices": {}, "puzzle_giveups": 0,
         "dungeon_backups": 0, "dungeon_stops_stuck": 0, "dungeon_stops_load": 0, "dungeon_noload": 0,
         "sigil_x": 0, "sigil_started": 0, "sigil_failed": 0, "sigil_failed_after_relog": 0, "sigil_likely": 0,
         "sigil_dialogues": 0, "sigil_leaves": 0, "sigil_back": 0, "sigil_gave_up": 0, "relogs": [],
         "badly_stuck_exact": 0, "badly_stuck_kinds": {}, "badly_stuck_estimated": 0, "lost_exact_seconds": 0,
         "lost_exact_kinds": {}, "lost_estimated_seconds": 0, "episodes": [], "failed_sigils": []}
    giveups = []            # the give-up lines' times (old format count)
    ep = None               # the unstick episode under way {t0, last, tries, bad, why}
    pending = None          # the last sigil X {t, why, wait, still, didnt, started, zone, dialog}
    exact_lines = False

    def close_ep(end, how):
        nonlocal ep
        if ep is None:
            return
        lost = outside(ep["t0"], max(end, ep["t0"]), spans)
        o["episodes"].append({"from": clock(ep["t0"]), "to": clock(end), "tries": ep["tries"], "bad": ep["bad"],
                              "lost": round(lost), "how": how, "why": ep["why"]})
        o["lost_estimated_seconds"] += lost
        ep = None

    def settle_sigil(p, t_next=None):
        """a sigil X decided: started, didn't (exact / likely) or not known"""
        if p is None or p["dialog"]:
            return
        how = "didn't start" if p["didnt"] else "still here" if p["still"] else ""
        likely = False
        if not how and not p["started"] and not p["zone"] and t_next is not None and t_next - p["t"] <= SIGIL_AGAIN_S:
            how, likely = "X again within %d min, no zone change seen" % (SIGIL_AGAIN_S // 60), True
        if p["started"]:
            o["sigil_started"] += 1
        if not how:
            return
        rl = last_relog_before(p["t"])
        ago = None if rl is None else p["t"] - rl
        o["failed_sigils"].append({"at": clock(p["t"]), "how": how, "likely": likely, "why": p["why"],
                                   "relog_ago_seconds": None if ago is None else round(ago)})
        if likely:
            o["sigil_likely"] += 1
        else:
            o["sigil_failed"] += 1
            if ago is not None and ago <= 1800:
                o["sigil_failed_after_relog"] += 1
        o["lost_estimated_seconds"] += p["wait"]

    relog_times = []

    def last_relog_before(t):
        best = None
        for r in relog_times:
            if r <= t:
                best = r
        return best

    for t, msg in lines:
        if not msg.startswith(("Walk: ", "Puzzle: ", "Dungeons: ", "Reconnect: ", "Backpack: ", "Potions: ")):
            continue
        m = BAD.match(msg)
        if m:
            exact_lines = True
            o["badly_stuck_exact"] += 1
            k = m.group(2)
            o["badly_stuck_kinds"][k] = o["badly_stuck_kinds"].get(k, 0) + 1
            continue
        m = OVER.match(msg)
        if m:
            exact_lines = True
            o["lost_exact_seconds"] += int(m.group(1))
            k = m.group(2)
            o["lost_exact_kinds"][k] = o["lost_exact_kinds"].get(k, 0) + int(m.group(1))
            continue
        m = TRY.match(msg)
        if m:
            n, walk = int(m.group(3)), int(m.group(4)) / 1000.0
            o["unstick_tries"] += 1
            if ep is not None and n == 1:
                close_ep(ep["last"], "tries started over (got closer)")
            if ep is None:
                o["unstick_episodes"] += 1
                ep = {"t0": t - stall_of(m.group(2)), "last": t, "tries": 0, "bad": False, "why": m.group(2)}
            ep["tries"] += 1
            ep["last"] = t + walk + TRY_EXTRA_S
            continue
        if GOT_ROUND.match(msg):
            o["got_round"] += 1
            if ep is not None and not ep["bad"]:
                close_ep(t, "got round")
            continue
        if FRO.match(msg):
            o["fro_stuck"] += 1
            continue
        if GAVE_UP.match(msg):
            o["gave_up"] += 1
            giveups.append(t)
            if ep is None:
                ep = {"t0": t, "last": t, "tries": 0, "bad": True, "why": "gave up"}
            ep["bad"] = True
            continue
        m = SAME_SPOT.match(msg)
        if m:
            o["same_place"] += 1
            giveups.append(t)
            if ep is not None:
                ep["bad"] = True
            continue
        m = COMMONS_GO.match(msg)
        if m:
            o["commons_teleports"] += 1
            giveups.append(t)
            nc = NOCLOSER.search(m.group(1))
            if ep is None:
                back = int(nc.group(1)) * 60 if nc else 0
                ep = {"t0": t - back, "last": t, "tries": 0, "bad": True, "why": m.group(1)}
            ep["bad"] = True
            continue
        if COMMONS_AT.match(msg):
            o["commons_arrived"] += 1
            close_ep(t, "at the Commons")
            if pending is not None:
                pending["zone"] = True
            continue
        if COMMONS_FAIL.match(msg):
            o["commons_failed"] += 1
            continue
        if TP_STUCK.match(msg):
            o["teleport_stuck"] += 1
            giveups.append(t)
            if ep is None:
                ep = {"t0": t, "last": t, "tries": 0, "bad": True, "why": "stuck at a teleport"}
            ep["bad"] = True
            continue
        m = NEEDS.match(msg)
        if m:
            title = m.group(1)
            o["notices"][title] = o["notices"].get(title, 0) + 1
            if title.lower().startswith("stuck") or "won't start" in title:
                giveups.append(t)
                if ep is not None:
                    ep["bad"] = True
            continue
        m = NOTE_CLOSED.match(msg)
        if m:
            if ep is not None and ep["bad"]:
                close_ep(t, "the notice closed (%s)" % m.group(1))
            continue
        m = PUZZLE_GIVEUP.match(msg)
        if m:
            o["puzzle_giveups"] += 1
            giveups.append(t)
            continue
        if DG_BACKUP.match(msg):
            o["dungeon_backups"] += 1
            o["lost_estimated_seconds"] += outside(t - DG_BACKUP_S + 2, t + 2, spans)
            continue
        if DG_STOP_STUCK.match(msg):
            o["dungeon_stops_stuck"] += 1
            giveups.append(t)
            continue
        if DG_STOP_LOAD.match(msg):
            o["dungeon_stops_load"] += 1
            giveups.append(t)
            continue
        if DG_NOLOAD.match(msg):
            o["dungeon_noload"] += 1
            continue
        m = RELOG.match(msg)
        if m:
            relog_times.append(t)
            o["relogs"].append({"at": clock(t), "zone": m.group(1)})
            continue
        m = SIGIL_X.match(msg)
        if m:
            o["sigil_x"] += 1
            settle_sigil(pending, t)
            pending = {"t": t, "why": m.group(1), "wait": int(m.group(2)), "still": False, "didnt": False,
                       "started": False, "zone": "just came out of" in m.group(1), "dialog": False}
            continue
        if SIGIL_STILL.match(msg):
            if pending is not None:
                pending["still"] = True
            continue
        if SIGIL_DIDNT.match(msg):
            if pending is not None:
                pending["didnt"] = True
            continue
        if SIGIL_IN.match(msg):
            if pending is not None:
                pending["started"] = True
            continue
        if SIGIL_DIALOG.match(msg):
            o["sigil_dialogues"] += 1
            if pending is not None:
                pending["dialog"] = True
            continue
        if SIGIL_LEAVE.match(msg):
            o["sigil_leaves"] += 1
            continue
        if SIGIL_BACK.match(msg):
            o["sigil_back"] += 1
            continue
        if SIGIL_WONT.match(msg):
            o["sigil_gave_up"] += 1
            giveups.append(t)
            continue
        if ZONE_SIGNS.match(msg) and pending is not None:
            pending["zone"] = True
    settle_sigil(pending)
    if ep is not None:
        close_ep(t_last if ep["bad"] else ep["last"], "open at the run's end" if ep["bad"] else "the run's end")
    # (the old lines' badly stuck: give-ups within GIVEUP_MERGE_S of the one before - one episode)
    prev = None
    for g in giveups:
        if prev is None or g - prev > GIVEUP_MERGE_S:
            o["badly_stuck_estimated"] += 1
        prev = g
    o["lost_estimated_seconds"] = round(o["lost_estimated_seconds"])
    o["exact"] = exact_lines
    o["badly_stuck"] = o["badly_stuck_exact"] if exact_lines else o["badly_stuck_estimated"]
    o["lost_seconds"] = o["lost_exact_seconds"] if exact_lines else o["lost_estimated_seconds"]
    return o


def total(results):
    """the runs added up (the counts, both badly-stuck and time-lost figures - each run's own pick - and the time)"""
    keys = ["seconds", "battle_seconds", "unstick_tries", "unstick_episodes", "got_round", "gave_up",
            "commons_teleports", "commons_arrived", "commons_failed", "same_place", "teleport_stuck", "puzzle_giveups",
            "dungeon_backups", "dungeon_stops_stuck", "dungeon_stops_load", "sigil_x", "sigil_started", "sigil_failed",
            "sigil_failed_after_relog", "sigil_likely", "sigil_leaves", "sigil_back", "sigil_gave_up", "badly_stuck",
            "lost_seconds"]
    t = {k: sum(r[k] for r in results) for k in keys}
    t["runs"] = len(results)
    t["estimated_runs"] = sum(1 for r in results if not r["exact"])
    t["relogs"] = sum(len(r["relogs"]) for r in results)
    return t


# ============================================================================ the text
def dur(s):
    s = int(round(s))
    if s < 60:
        return "%d s" % s
    if s < 3600:
        return "%d min %02d s" % (s // 60, s % 60)
    return "%d h %02d min" % (s // 3600, s // 60 % 60)


def text(results, episodes=False):
    out = []
    for i, r in enumerate(results, 1):
        head = "%s - run %d: %s at %s, %s (battles %s)" % (
            os.path.basename(r["source"]) or "?", i,
            ("started " + r["version"]) if r["started"] and r["version"] else "started" if r["started"] else
            "no start line", r["start"], dur(r["seconds"]), dur(r["battle_seconds"]))
        out.append(head)
        how = ("exact - the walker's own lines" if r["exact"] else "estimated - an older log"
               if r["badly_stuck"] or r["lost_seconds"] else "none seen")
        out.append("  Badly stuck      %d   (%s)%s" % (
            r["badly_stuck"], how,
            ": " + ", ".join("%s %d" % kv for kv in sorted(r["badly_stuck_kinds"].items())) if r["exact"] else ""))
        out.append("  Time lost        %s   (%s)%s" % (
            dur(r["lost_seconds"]), how,
            "; estimated from the older lines: " + dur(r["lost_estimated_seconds"]) if r["exact"] else ""))
        out.append("  Unstick tries    %d in %d episodes, %d got round; to and fro taken as stuck %d" % (
            r["unstick_tries"], r["unstick_episodes"], r["got_round"], r["fro_stuck"]))
        out.append("  Gave up          %d   Commons %d (arrived %d, didn't happen %d)   same place again %d   "
                   "stuck at a teleport %d" % (r["gave_up"], r["commons_teleports"], r["commons_arrived"],
                                               r["commons_failed"], r["same_place"], r["teleport_stuck"]))
        if r["notices"]:
            out.append("  Notices          " + ", ".join("%s %d" % kv for kv in sorted(r["notices"].items())))
        if r["puzzle_giveups"]:
            out.append("  Puzzle give-ups  %d" % r["puzzle_giveups"])
        if r["dungeon_backups"] or r["dungeon_stops_stuck"] or r["dungeon_stops_load"] or r["dungeon_noload"]:
            out.append("  Dungeon runs     back-ups %d, loads that didn't come %d, stopped stuck %d, stopped not "
                       "loading %d" % (r["dungeon_backups"], r["dungeon_noload"], r["dungeon_stops_stuck"],
                                       r["dungeon_stops_load"]))
        if r["sigil_x"]:
            out.append("  Sigils           X %d, started %d (seen), didn't start %d (%d within 30 min of a relog), "
                       "likely didn't %d; left and came back %d of %d, given up %d" % (
                           r["sigil_x"], r["sigil_started"], r["sigil_failed"], r["sigil_failed_after_relog"],
                           r["sigil_likely"], r["sigil_back"], r["sigil_leaves"], r["sigil_gave_up"]))
        if r["relogs"]:
            out.append("  Relogs           " + ", ".join("%s (%s)" % (x["at"], x["zone"]) for x in r["relogs"]))
        if episodes:
            for e in r["episodes"]:
                out.append("    %s-%s  %s lost, %d tr%s%s - %s (%s)" % (
                    e["from"], e["to"], dur(e["lost"]), e["tries"], "y" if e["tries"] == 1 else "ies",
                    ", badly stuck" if e["bad"] else "", e["how"], e["why"]))
            for s in r["failed_sigils"]:
                out.append("    %s  sigil %s%s: %s%s" % (
                    s["at"], "likely " if s["likely"] else "", s["how"], s["why"],
                    "" if s["relog_ago_seconds"] is None else " - a relog %s before" % dur(s["relog_ago_seconds"])))
    if len(results) > 1:
        t = total(results)
        out.append("All %d runs: %s (battles %s) - badly stuck %d, time lost %s%s; sigils X %d, didn't start %d "
                   "(%d after a relog), likely %d" % (
                       t["runs"], dur(t["seconds"]), dur(t["battle_seconds"]), t["badly_stuck"],
                       dur(t["lost_seconds"]),
                       " (%d run%s estimated)" % (t["estimated_runs"], "" if t["estimated_runs"] == 1 else "s")
                       if t["estimated_runs"] else "", t["sigil_x"], t["sigil_failed"],
                       t["sigil_failed_after_relog"], t["sigil_likely"]))
    if not results:
        out.append("no log lines read")
    return "\n".join(out)


def report(paths, last=0):
    """[analyse(run)] for every run in the files, oldest first (the last `last` runs when last > 0)"""
    results = []
    for p in paths:
        for run in split_runs(read_lines(p), p):
            if run["lines"]:
                results.append(analyse(run))
    return results[-last:] if last > 0 else results


def main(argv=None):
    ap = argparse.ArgumentParser(description="the walker's badly-stuck count and time lost, per run (read only)")
    ap.add_argument("files", nargs="*", help="debug logs, oldest first (default: debug.previous.log, debug.log)")
    ap.add_argument("--runs", type=int, default=0, help="only the last N runs")
    ap.add_argument("--episodes", action="store_true", help="each stuck episode and failed sigil")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    paths = a.files or [p for p in DEFAULT_FILES if os.path.exists(p)]
    results = report(paths, a.runs)
    if a.json:
        print(json.dumps({"files": paths, "runs": results, "total": total(results)}, ensure_ascii=True))
    else:
        print(text(results, a.episodes))
    return 0


if __name__ == "__main__":
    sys.exit(main())
