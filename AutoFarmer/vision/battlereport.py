"""battlereport.py - what the battle recorder wrote down (AutoFarmer\\learned\\battles\\ - vision\\battlerec.py, whose
docstring is the format), summed up. Read only, standard library only, streamed line by line.

    python vision\\battlereport.py                       the last 7 days
    python vision\\battlereport.py --days 30 --enemy "Bonestriker"
    python vision\\battlereport.py --since 2026-10-01 --school balance --zone Celestia --char 192247409141544743 --json

    --dir <folder>      learned\\battles (default: the one next to this script's folder)
    --days N | --since YYYY-MM-DD      which battles (by their start); --char, --school, --zone, --enemy narrow them
    --json              one JSON object instead of the text

Sections: totals (results, rounds, hours, rounds played by the bot vs you, per day); rounds per kill by enemy kind
(battles, kills, rounds to kill - mean, median, best -, the damage it took and dealt you per round, your win rate against
it); deaths (each lost battle's zone, enemies, the last two rounds' hits on you); the cards you cast (by the bot / by
you, damage per cast and per pip, crits, misses); the bot's rules (used, battles won when used, rounds to a win); data
quality (rounds with a hand read, with a bot post, deck known, partial records). Lines that don't parse (a torn last
line), records of an unknown kind or version and a battle id seen before are skipped and counted."""
import argparse
import collections
import datetime
import gzip
import json
import os
import re
import statistics
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DIR = os.path.join(os.path.dirname(HERE), "learned", "battles")
KNOWN_V = {1}
DAY_FILE = re.compile(r"^(\d{4}-\d\d-\d\d)(?:-\d+)?\.jsonl$")
MONTH_GZ = re.compile(r"^(\d{4}-\d\d)\.jsonl\.gz$")


# ============================================================================ reading
def files(base, d0, d1):
    """the day files and month zips that can hold battles started from day d0 to d1 (YYYY-MM-DD), oldest first"""
    out = []
    try:
        names = os.listdir(base)
    except OSError:
        return out
    for n in sorted(names):
        p = os.path.join(base, n)
        m = MONTH_GZ.match(n)
        if m and d0[:7] <= m.group(1) <= d1[:7]:
            out.append((m.group(1) + "-00", p))
        elif re.match(r"^\d{4}-\d\d$", n) and os.path.isdir(p) and d0[:7] <= n <= d1[:7]:
            for f in sorted(os.listdir(p)):
                mf = DAY_FILE.match(f)
                if mf and d0 <= mf.group(1) <= d1:
                    out.append((mf.group(1), os.path.join(p, f)))
    return sorted(out)


def battles(base, d0, d1, stats):
    """each battle record started from d0 to d1, once (a battle id seen before - a month zipped twice - skipped) - stats
    counts what was skipped"""
    lo, hi = d0.replace("-", ""), d1.replace("-", "")
    seen = set()
    for _d, path in files(base, d0, d1):
        try:
            f = gzip.open(path, "rb") if path.endswith(".gz") else open(path, "rb")
        except OSError:
            stats["unreadable files"] += 1
            continue
        with f:
            try:
                for raw in f:
                    if not raw.startswith(b'{"rec":"battle"'):
                        if raw.startswith(b'{"rec":"header"') or not raw.strip():
                            continue
                        if raw.startswith(b'{"rec":'):
                            stats["other kinds"] += 1
                            continue
                    i = raw.find(b'"id":"')
                    if i >= 0:
                        day = raw[i + 6:i + 14].decode("ascii", "replace")
                        if not (lo <= day <= hi):
                            continue
                    try:
                        o = json.loads(raw)
                    except ValueError:
                        stats["torn lines"] += 1
                        continue
                    if not isinstance(o, dict) or o.get("rec") != "battle":
                        stats["other kinds"] += 1
                        continue
                    if o.get("v") not in KNOWN_V:
                        stats["unknown versions"] += 1
                        continue
                    bid = o.get("id")
                    if isinstance(bid, str):
                        if bid in seen:
                            stats["repeated battles"] += 1
                            continue
                        seen.add(bid)
                    yield o
            except (OSError, EOFError) as e:
                stats["unreadable files"] += 1
                stats.setdefault("why", str(e))


def enemies(b):
    return [p for p in b.get("parts") or [] if p.get("side") == "enemy"]


def kind_of(p):
    return p.get("obj") or p.get("name") or ("wizard " + (p.get("name_h") or "?"))


def wanted(b, a):
    if a.char and str(b.get("char") or "") != a.char:
        return False
    if a.school and ((b.get("me") or {}).get("school") or "").lower() != a.school.lower():
        return False
    if a.zone and a.zone.lower() not in (b.get("zone") or "").lower():
        return False
    if a.enemy:
        e = a.enemy.lower()
        if not any(e in (p.get("name") or "").lower() or e in (p.get("obj") or "").lower() for p in enemies(b)):
            return False
    return True


# ============================================================================ the sums
class Report:
    def __init__(self):
        self.n = 0
        self.results = collections.Counter()
        self.rounds = 0
        self.secs = 0.0
        self.who = collections.Counter()
        self.days = collections.defaultdict(collections.Counter)
        self.kinds = {}
        self.deaths = []
        self.cards = {}
        self.rules = {}
        self.q = collections.Counter()

    def add(self, b):
        self.n += 1
        res = b.get("result") or "unknown"
        self.results[res] += 1
        rs = b.get("rounds") or []
        self.rounds += len(rs)
        self.secs += b.get("dur_s") or 0.0
        day = (b.get("t0") or "")[:10]
        self.days[day]["battles"] += 1
        self.days[day][res] += 1
        for w, ns in (b.get("who") or {}).items():
            self.who[w] += len(ns)
        me = (b.get("me") or {}).get("sc")
        won = res == "won"
        names = {p["sc"]: p.get("name") or p.get("obj") or p.get("name_h") for p in b.get("parts") or []}
        # (each enemy kind: kills, rounds to kill, damage taken and dealt to me per round)
        dmg_to, dmg_by = collections.Counter(), collections.Counter()
        for r in rs:
            for c in r.get("casts") or []:
                for e in c.get("hp") or []:
                    if e[0] is None or e[2] >= 0:
                        continue
                    dmg_to[e[0]] += -e[2]
                    if e[0] == me:
                        dmg_by[c["sc"]] += -e[2]
        seen_kinds = set()
        for p in enemies(b):
            k = kind_of(p)
            K = self.kinds.setdefault(k, {"battles": 0, "won": 0, "kills": 0, "to_kill": [], "took": 0, "dealt": 0,
                                          "rounds_in": 0, "rank": p.get("rank"), "title": p.get("title"),
                                          "school": p.get("school"), "name": p.get("name")})
            if k not in seen_kinds:
                seen_kinds.add(k)
                K["battles"] += 1
                K["won"] += 1 if won else 0
            joined = p.get("joined") or 1
            last = p.get("out_round") or b.get("rounds_n") or len(rs)
            K["rounds_in"] += max(1, last - joined + 1)
            if p.get("died_round") is not None:
                K["kills"] += 1
                K["to_kill"].append(p["died_round"] - joined + 1)
            K["took"] += dmg_to.get(p["sc"], 0)
            K["dealt"] += dmg_by.get(p["sc"], 0)
            for f in ("rank", "title", "school", "name"):
                K[f] = K[f] if K[f] is not None else p.get(f)
        # (deaths)
        if res == "lost":
            hits = []
            for r in rs[-2:]:
                for c in r.get("casts") or []:
                    for e in c.get("hp") or []:
                        if e[0] == me and e[2] < 0:
                            hits.append({"round": r.get("n"), "caster": names.get(c["sc"]) or c["sc"],
                                         "spell": c.get("spell"), "damage": -e[2], "before": e[1]})
            self.deaths.append({"id": b.get("id"), "zone": b.get("zone"),
                                "enemies": [p.get("name") or p.get("obj") for p in enemies(b)], "hits": hits,
                                "killed_by": (b.get("me") or {}).get("killed_by")})
        # (my cards)
        rules_here = set()
        for r in rs:
            w = r.get("who")
            bot = r.get("bot")
            if bot:
                rules_here.add(bot.get("rule"))
            self.q["rounds"] += 1
            self.q["hand"] += 1 if r.get("hand") else 0
            self.q["post"] += 1 if bot else 0
            for c in r.get("casts") or []:
                if c.get("sc") != me or c.get("pet") or not c.get("spell"):
                    continue
                C = self.cards.setdefault(c["spell"], {"bot": 0, "user": 0, "other": 0, "dmg": 0, "dmg_casts": 0,
                                                       "per_pip": [], "crits": 0, "missed": 0, "casts": 0})
                C["casts"] += 1
                C[w if w in ("bot", "user") else "other"] += 1
                d = sum(-e[2] for e in c.get("hp") or [] if e[0] is not None and e[0] != me and e[2] < 0)
                if d:
                    C["dmg"] += d
                    C["dmg_casts"] += 1
                    cost = (c.get("pips") or [0])[0]
                    if cost:
                        C["per_pip"].append(d / cost)
                    if c.get("crit"):
                        C["crits"] += 1
                if c.get("missed"):
                    C["missed"] += 1
        for rule in rules_here:
            R = self.rules.setdefault(rule, {"rounds": 0, "battles": 0, "won": 0, "rounds_to_win": []})
            R["battles"] += 1
            if won:
                R["won"] += 1
                R["rounds_to_win"].append(b.get("rounds_n") or len(rs))
        for r in rs:
            if r.get("bot"):
                self.rules[r["bot"].get("rule")]["rounds"] += 1
        self.q["deck"] += 1 if (b.get("deck") or {}).get("src") == "mem" else 0
        self.q["partial"] += 1 if b.get("partial") else 0

    def out(self):
        def mean(x):
            return round(statistics.mean(x), 2) if x else None

        def med(x):
            return statistics.median(x) if x else None

        kinds = []
        for k, K in sorted(self.kinds.items(), key=lambda kv: -kv[1]["battles"]):
            kinds.append({"kind": k, "name": K["name"], "rank": K["rank"], "title": K["title"], "school": K["school"],
                          "battles": K["battles"], "kills": K["kills"], "rounds_to_kill_mean": mean(K["to_kill"]),
                          "rounds_to_kill_median": med(K["to_kill"]),
                          "rounds_to_kill_best": min(K["to_kill"]) if K["to_kill"] else None,
                          "took_per_round": round(K["took"] / K["rounds_in"], 1) if K["rounds_in"] else None,
                          "dealt_you_per_round": round(K["dealt"] / K["rounds_in"], 1) if K["rounds_in"] else None,
                          "win_rate": round(K["won"] / K["battles"], 3) if K["battles"] else None})
        cards = []
        for s, C in sorted(self.cards.items(), key=lambda kv: -kv[1]["casts"]):
            cards.append({"spell": s, "casts": C["casts"], "by_bot": C["bot"], "by_you": C["user"],
                          "dmg_per_cast": round(C["dmg"] / C["dmg_casts"], 1) if C["dmg_casts"] else None,
                          "dmg_per_pip": mean(C["per_pip"]),
                          "crit_rate": round(C["crits"] / C["dmg_casts"], 3) if C["dmg_casts"] else None,
                          "missed": C["missed"]})
        rules = []
        for k, R in sorted(self.rules.items(), key=lambda kv: -kv[1]["rounds"]):
            rules.append({"rule": k, "rounds": R["rounds"], "battles": R["battles"], "won": R["won"],
                          "rounds_to_win_mean": mean(R["rounds_to_win"])})
        q = self.q
        return {"totals": {"battles": self.n, "results": dict(self.results), "rounds": self.rounds,
                           "hours": round(self.secs / 3600.0, 2), "rounds_by": dict(self.who),
                           "per_day": {d: dict(c) for d, c in sorted(self.days.items())}},
                "enemies": kinds, "deaths": self.deaths, "cards": cards, "rules": rules,
                "quality": {"rounds": q["rounds"],
                            "hand_read_pct": round(100.0 * q["hand"] / q["rounds"], 1) if q["rounds"] else None,
                            "bot_post_pct": round(100.0 * q["post"] / q["rounds"], 1) if q["rounds"] else None,
                            "deck_known_pct": round(100.0 * q["deck"] / self.n, 1) if self.n else None,
                            "partial": q["partial"]}}


def text(o, skipped, d0, d1):
    T = o["totals"]
    L = ["Battles %s .. %s: %d - %s; %d rounds, %.2f h in battle; rounds played: %s" % (
        d0, d1, T["battles"], ", ".join("%s %d" % kv for kv in sorted(T["results"].items())) or "none", T["rounds"],
        T["hours"], ", ".join("%s %d" % kv for kv in sorted(T["rounds_by"].items())) or "none")]
    for d, c in T["per_day"].items():
        L.append("  %s  %3d battles  %s" % (d, c.get("battles", 0), ", ".join("%s %d" % (k, v) for k, v in sorted(c.items())
                                                                                if k != "battles")))
    L.append("")
    L.append("Rounds per kill by enemy kind (kind, rank / title / school: battles, kills, rounds to kill mean / median / "
             "best, damage it took and dealt you per round, your win rate)")
    for k in o["enemies"]:
        L.append("  %-34s %-26s %3d battles %4d kills  %s / %s / %s rounds  took %s, dealt you %s a round  won %s%%" % (
            k["kind"][:34], ("%s %s %s" % (k["rank"], k["title"] or "", k["school"] or "")).strip()[:26], k["battles"],
            k["kills"], k["rounds_to_kill_mean"], k["rounds_to_kill_median"], k["rounds_to_kill_best"],
            k["took_per_round"], k["dealt_you_per_round"],
            None if k["win_rate"] is None else round(100 * k["win_rate"], 1)))
    L.append("")
    L.append("Deaths: %d" % len(o["deaths"]))
    for dd in o["deaths"]:
        L.append("  %s  %s  vs %s" % (dd["id"], dd["zone"], ", ".join(str(x) for x in dd["enemies"])))
        for h in dd["hits"]:
            L.append("      round %s: %s - %s for %d (health before %d)" % (h["round"], h["caster"], h["spell"],
                                                                         h["damage"], h["before"]))
    L.append("")
    L.append("Your cards (casts, by the bot / by you, damage a cast, a pip, crit rate, misses)")
    for c in o["cards"]:
        L.append("  %-28s %4d  %4d / %-4d  %s a cast, %s a pip, crits %s, missed %d" % (
            c["spell"][:28], c["casts"], c["by_bot"], c["by_you"], c["dmg_per_cast"], c["dmg_per_pip"], c["crit_rate"],
            c["missed"]))
    L.append("")
    L.append("The bot's rules (rounds, battles used in, won, rounds to a win)")
    for r in o["rules"]:
        L.append("  %-16s %5d rounds %4d battles %4d won  %s rounds to win" % (r["rule"], r["rounds"], r["battles"],
                                                                             r["won"], r["rounds_to_win_mean"]))
    q = o["quality"]
    L.append("")
    L.append("Data: %d rounds - a hand read %s%%, a bot post %s%%; the deck known in %s%% of battles; %d partial; "
             "skipped: %s" % (q["rounds"], q["hand_read_pct"], q["bot_post_pct"], q["deck_known_pct"], q["partial"],
                              ", ".join("%s %s" % kv for kv in sorted(skipped.items())) or "nothing"))
    return "\n".join(L)


def main(argv=None):
    ap = argparse.ArgumentParser(description="the battle recorder's records summed up (read only)")
    ap.add_argument("--dir", default=DEFAULT_DIR)
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--days", type=int, default=7)
    g.add_argument("--since")
    ap.add_argument("--until")
    ap.add_argument("--char")
    ap.add_argument("--school")
    ap.add_argument("--zone")
    ap.add_argument("--enemy")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    today = datetime.date.today()
    d1 = a.until or today.isoformat()
    d0 = a.since or (today - datetime.timedelta(days=max(1, a.days) - 1)).isoformat()
    t0 = time.perf_counter()
    skipped = collections.Counter()
    R = Report()
    for b in battles(a.dir, d0, d1, skipped):
        if wanted(b, a):
            R.add(b)
    o = R.out()
    o["skipped"] = dict(skipped)
    o["range"] = [d0, d1]
    o["seconds"] = round(time.perf_counter() - t0, 3)
    if a.json:
        print(json.dumps(o, ensure_ascii=True))
    else:
        print(text(o, skipped, d0, d1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
