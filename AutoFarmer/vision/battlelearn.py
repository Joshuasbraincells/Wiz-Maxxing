"""battlelearn.py - learned plays (TODO goal 3, step 3 of learned battle play: the planner's prior): what was played in
each kind of round of the battles recorded (AutoFarmer\\learned\\battles\\ - vision\\battlerec.py's docstring is the
format) and how those battles went - kept per school and for every school together; prior() blends the two, so a school
with few battles leans on all schools' data and its own takes over as its battles grow. Pure Python (standard library):
it reads the records only (battlereport.battles) and writes learned\\battles\\plays.json (a tmp file + os.replace).

    plays = build(base)                     # one pass over the battles recorded (days back)
    f = plays.prior_fn("storm")             # f(situation) -> ({kind: -1..1}, why): battlesim.plan_round(prior=f)
    python vision\\battlelearn.py [--days 120] [--school storm] [--save] [--advice] [--dir <learned\\battles>]

THE SITUATION (a round as it's keyed - battlesim.situation gives the same fields for the round being planned)
  school; pips: mine (power pips counted 1, school pips too; not shadow) - 0-1 / 2-3 / 4-5 / 6+; alive: enemies left at
  the round's start - 1 / 2 or more; boss: one of them a boss; hit: a hit in hand I could pay for (the hand's castable
  estimate); hp: my health - under 40% / under 75% / more  ->  key "p1|a2|b0|h1|hp2" (key_of)
THE PLAY   the kind of the card I cast (the hand's kind as the record has it: damage aoe heal blade trap aura ward ...);
           pass: nothing cast; other: a kind not known here, or the card not found in the hand
THE OUTCOME (per school / "*" every school, key, play): [rounds, of them in battles won, rounds left to the battle's end
           (summed), damage that round to the enemies (summed)] - battles won, lost or fled only (left / cut / unknown
           ones are skipped: their end isn't known); a round with no hand read is skipped (its situation isn't known)
PRIOR      prior(school, key) -> {kind: {rate, n, w...}}: rate = w x the school's win rate with that play + (1 - w) x every
           school's, w = n_school / (n_school + K) (n_school: the school's rounds with that key, any play); a play the
           school never made there: every school's rate. prior_fn: each play's rate less the mean of the plays there
           (those with MIN_N rounds or more, at least two of them), / SPREAD, as -1..1 - the planner adds PRIOR_W of that
           (a nudge between near-equal plays: what usually went with winning is not what made it win).
ADVICE     the planner's advice lines (Planner.ahk, planner:1 - "Plan: would play <card> ... [tid N]") in the rounds' bot
           lines, against what was played: advice_rows / --advice (how often it agreed, and the battles' results either
           way).

FAILS SOFT: a record or round it can't read is skipped and counted (skipped); prior() of an unknown school or key is {}."""
import argparse
import collections
import datetime
import json
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DIR = os.path.join(os.path.dirname(HERE), "learned", "battles")
PLAYS_FILE = "plays.json"
V = 1
K = 20                      # w = n_school / (n_school + K): 20 rounds of a school's own in that situation weigh half
MIN_N = 5                   # a play with fewer (blended) rounds in a situation isn't compared
SPREAD = 0.25               # a win rate this far above the situation's mean: the whole nudge (+1)
DAYS = 120
SCHOOLS = ("balance", "death", "fire", "ice", "life", "myth", "storm")
KINDS = ("damage", "aoe", "heal", "ward", "blade", "trap", "aura", "bubble", "weakness", "enchant", "dot", "stun",
         "dispel", "prism", "clear", "polymorph", "keep", "absorb")
RESULTS = ("won", "lost", "fled")
PIP_KEYS = ("generic", "power", "balance", "death", "fire", "ice", "life", "myth", "storm")
ADVICE_RX = re.compile(r"\bPlan: would play (.+?) (?:at (.+?)|on all|on you|\(pass\))?\s*\(won (\d+)%")
ADVICE_TID = re.compile(r"\[tid (\d+)\]")


def school_of(s):
    s = (s or "").strip().lower() if isinstance(s, str) else ""
    return s if s in SCHOOLS else ""


def _num(v):
    return v if isinstance(v, (int, float)) and not isinstance(v, bool) else None


# ============================================================================ a round's situation and play
def key_of(sit):
    """the situation's key "p<0-3>|a<1-2>|b<0-1>|h<0-1>|hp<0-2>" - None when its pips aren't known"""
    if not isinstance(sit, dict):
        return None
    pips = _num(sit.get("pips"))
    if pips is None:
        return None
    pb = 0 if pips < 2 else 1 if pips < 4 else 2 if pips < 6 else 3
    alive = _num(sit.get("alive")) or 0
    hp = _num(sit.get("hp"))
    hb = "?" if hp is None else (0 if hp < 40 else 1 if hp < 75 else 2)
    return "p%d|a%d|b%d|h%d|hp%s" % (pb, 2 if alive >= 2 else 1, 1 if sit.get("boss") else 0, 1 if sit.get("hit") else 0,
                                     hb)


def round_hand(rd):
    """the hand the round's card was played from: the last settled one before the cast (hand_last), else the first"""
    h = rd.get("hand_last") or rd.get("hand")
    return h if isinstance(h, list) else None


def round_situation(b, rd):
    """the situation of record b's round rd (the fields battlesim.situation gives) - None: no hand read in it"""
    hand = round_hand(rd)
    if not hand:
        return None
    me = b.get("me") or {}
    pips = None
    pp = rd.get("pips")
    if isinstance(pp, dict):
        vals = [_num(pp.get(k)) for k in PIP_KEYS]
        if any(v is not None for v in vals):
            pips = sum(v for v in vals if v is not None)
    elif isinstance(rd.get("pips_log"), list) and len(rd["pips_log"]) >= 2:
        pips = sum(v for v in rd["pips_log"][:2] if _num(v) is not None)
    enemies = [p for p in b.get("parts") or [] if isinstance(p, dict) and p.get("side") == "enemy"]
    n = _num(rd.get("n")) or 0
    start = rd.get("start")
    if isinstance(start, list) and start:
        alive_sc = {s[0] for s in start if isinstance(s, list) and len(s) >= 2 and _num(s[0]) is not None
                    and 0 <= s[0] <= 3 and (_num(s[1]) or 0) > 0}
        alive = [p for p in enemies if p.get("sc") in alive_sc]
        n_alive = len(alive_sc)
    else:
        alive = [p for p in enemies if (p.get("died_round") is None or (_num(p.get("died_round")) or 0) >= n)
                 and (p.get("out_round") is None or (_num(p.get("out_round")) or 0) >= n)
                 and (_num(p.get("joined")) or 0) <= n]
        n_alive = len(alive)
    hp, most = _num(rd.get("hp")), _num(rd.get("max")) or _num(me.get("max0"))
    return {"school": school_of(me.get("school")), "pips": pips, "alive": n_alive,
            "boss": any(p.get("boss") for p in alive),
            "hit": any(isinstance(c, dict) and c.get("kind") in ("damage", "aoe") and c.get("ok") is True for c in hand),
            "hp": int(round(100.0 * hp / most)) if hp is not None and most else None}


def kind_played(rd):
    """the kind of card round rd's play was ('pass' nothing cast, 'other' not known) - None: no hand read in it"""
    hand = round_hand(rd)
    if not hand:
        return None
    pl = rd.get("played")
    if not isinstance(pl, dict) or pl.get("pass") or not pl.get("spell"):
        return "pass"
    hi = pl.get("hand_i")
    if not isinstance(hi, int) or isinstance(hi, bool) or not 0 <= hi < len(hand) or not isinstance(hand[hi], dict):
        return "other"
    k = str(hand[hi].get("kind") or "").lower()
    return k if k in KINDS else "other"


def round_damage(b, rd):
    """the damage my casts did to the enemies in round rd (the log's ModifyHealth on them)"""
    me = b.get("me") or {}
    msc = me.get("sc")
    foes = {p.get("sc") for p in b.get("parts") or [] if isinstance(p, dict) and p.get("side") == "enemy"}
    total = 0
    for c in rd.get("casts") or []:
        if not isinstance(c, dict) or c.get("sc") != msc or msc is None:
            continue
        for h in c.get("hp") or []:
            if isinstance(h, list) and len(h) >= 3 and h[0] in foes and _num(h[2]) is not None and h[2] < 0:
                total += -h[2]
    return total


# ============================================================================ the plays learned
class Plays:
    """{school ("*" every school): {key: {kind: [rounds, won, rounds left, damage]}}} - see the docstring"""

    def __init__(self):
        self.by = {}
        self.battles = 0
        self.rounds = 0
        self.skipped = collections.Counter()
        self.made = ""

    def add(self, b):
        """battle record b's rounds counted - how many (0: none usable; never raises)"""
        try:
            res = b.get("result")
            if res not in RESULTS:
                self.skipped["battles %s" % (res or "with no result")] += 1
                return 0
            school = school_of((b.get("me") or {}).get("school"))
            won = 1 if res == "won" else 0
            rounds = [rd for rd in b.get("rounds") or [] if isinstance(rd, dict)]
            last = _num(b.get("rounds_n")) or len(rounds)
            used = 0
            for rd in rounds:
                try:
                    sit = round_situation(b, rd)
                    kind = kind_played(rd)
                    key = key_of(sit) if sit is not None else None
                    if key is None or kind is None:
                        self.skipped["rounds with no hand or pips read"] += 1
                        continue
                    left = max(1, int(last - (_num(rd.get("n")) or last) + 1))
                    dmg = round_damage(b, rd)
                    for sch in ([school] if school else []) + ["*"]:
                        cell = self.by.setdefault(sch, {}).setdefault(key, {}).setdefault(kind, [0, 0, 0, 0])
                        cell[0] += 1
                        cell[1] += won
                        cell[2] += left
                        cell[3] += dmg
                    used += 1
                except Exception:  # noqa: BLE001 - this round only
                    self.skipped["rounds that couldn't be read"] += 1
            if used:
                self.battles += 1
                self.rounds += used
            return used
        except Exception:  # noqa: BLE001 - this battle only
            self.skipped["battles that couldn't be read"] += 1
            return 0

    # ---------------------------------------------------------------- the prior
    def prior(self, school, key):
        """{kind: {rate (blended win rate), n (blended rounds), w (the school's weight), n_school (the school's rounds of
        that play), n_all, rounds (mean rounds left), dmg (mean damage that round)}} for school's situation key"""
        school = school_of(school)
        mine = self.by.get(school, {}).get(key, {}) if school else {}
        pool = self.by.get("*", {}).get(key, {})
        n_s = sum(v[0] for v in mine.values())
        w = n_s / float(n_s + K) if n_s else 0.0
        out = {}
        for kind in set(mine) | set(pool):
            a, p = mine.get(kind), pool.get(kind)
            ra = a[1] / float(a[0]) if a and a[0] else None
            rp = p[1] / float(p[0]) if p and p[0] else None
            if ra is None and rp is None:
                continue
            if ra is None:
                rate, wk = rp, 0.0
            elif rp is None:
                rate, wk = ra, 1.0
            else:
                rate, wk = w * ra + (1 - w) * rp, w
            na, npl = (a[0] if a else 0), (p[0] if p else 0)
            src = a if wk >= 0.5 and a else p or a
            out[kind] = {"rate": rate, "n": wk * na + (1 - wk) * npl, "w": wk, "n_school": na, "n_all": npl,
                         "rounds": src[2] / float(src[0]) if src and src[0] else None,
                         "dmg": src[3] / float(src[0]) if src and src[0] else None}
        return out

    def prior_fn(self, school):
        """f(situation) -> ({kind: -1..1}, why) for battlesim.plan_round: each play's blended win rate there less the
        mean of the plays there (MIN_N rounds or more, two plays at least), / SPREAD; ({}, '') nothing to compare"""
        school = school_of(school)

        def f(sit):
            key = key_of(sit)
            if key is None:
                return {}, ""
            p = {k: v for k, v in self.prior(school, key).items() if v["n"] >= MIN_N}
            if len(p) < 2:
                return {}, ""
            mean = sum(v["rate"] for v in p.values()) / len(p)
            bonus = {k: max(-1.0, min(1.0, (v["rate"] - mean) / SPREAD)) for k, v in p.items()}
            w = max(v["w"] for v in p.values())
            why = "learned plays (%s, %s; %s): %s" % (
                school or "every school", key, ("your school's own %d%%" % round(100 * w)) if w else "every school's",
                ", ".join("%s won %d%% of %d" % (k, round(100 * v["rate"]), round(v["n"]))
                          for k, v in sorted(p.items(), key=lambda kv: -kv[1]["rate"])))
            return bonus, why
        return f

    # ---------------------------------------------------------------- the file
    def to_json(self):
        return {"rec": "plays", "v": V, "made": self.made, "battles": self.battles, "rounds": self.rounds, "k": K,
                "skipped": dict(self.skipped), "by": self.by}

    @classmethod
    def from_json(cls, o):
        p = cls()
        if not isinstance(o, dict) or o.get("rec") != "plays" or o.get("v") != V:
            return p
        for sch, keys in (o.get("by") or {}).items():
            if not isinstance(keys, dict):
                continue
            for key, kinds in keys.items():
                if not isinstance(kinds, dict):
                    continue
                for kind, cell in kinds.items():
                    if isinstance(cell, list) and len(cell) == 4 and all(_num(x) is not None for x in cell):
                        p.by.setdefault(sch, {}).setdefault(key, {})[kind] = list(cell)
        p.battles, p.rounds, p.made = int(o.get("battles") or 0), int(o.get("rounds") or 0), str(o.get("made") or "")
        return p

    def save(self, path):
        """written whole: a tmp file next to it, then os.replace - True when it was"""
        try:
            tmp = path + ".tmp"
            with open(tmp, "w", encoding="ascii") as f:
                json.dump(self.to_json(), f, separators=(",", ":"), sort_keys=True)
            os.replace(tmp, path)
            return True
        except (OSError, TypeError, ValueError):
            return False

    @classmethod
    def load(cls, path):
        """the plays saved at path - an empty Plays when there are none or the file can't be read"""
        try:
            with open(path, encoding="ascii") as f:
                return cls.from_json(json.load(f))
        except (OSError, ValueError, UnicodeDecodeError):
            return cls()

    def lines(self, school=None):
        """the table as text lines: school | situation | play | rounds | won % | rounds left | damage"""
        out = ["%d battles, %d rounds learned%s" % (self.battles, self.rounds, (" (made %s)" % self.made) if self.made else "")]
        for sch in sorted(self.by):
            if school and sch not in (school, "*"):
                continue
            for key in sorted(self.by[sch]):
                for kind, c in sorted(self.by[sch][key].items(), key=lambda kv: -kv[1][0]):
                    out.append("%-8s %-22s %-9s %5d rounds  won %3d%%  %4.1f rounds left  %6.0f damage" % (
                        sch, key, kind, c[0], round(100.0 * c[1] / c[0]), c[2] / float(c[0]), c[3] / float(c[0])))
        for k, v in sorted(self.skipped.items()):
            out.append("skipped: %d %s" % (v, k))
        return out


# ============================================================================ reading the records
def read(base=None, days=DAYS, stats=None):
    """the battle records of the last days (battlereport.battles: a torn line or an unknown record skipped and counted
    in stats - a Counter)"""
    import battlereport
    d1 = datetime.date.today()
    d0 = d1 - datetime.timedelta(days=days)
    return battlereport.battles(base or DEFAULT_DIR, d0.isoformat(), d1.isoformat(),
                                stats if stats is not None else collections.Counter())


def build(base=None, days=DAYS, battles=None, pause=None):
    """Plays of the battles recorded (or the battles given) - pause: a callable asked before each battle; True: wait
    50 ms and ask again (vision.py: a gated request in flight - the bot's reads go first). Never raises"""
    p = Plays()
    try:
        for b in (read(base, days) if battles is None else battles):
            waited = 0
            while pause is not None and waited < 200 and pause():
                time.sleep(0.05)
                waited += 1
            p.add(b)
    except Exception:  # noqa: BLE001 - what was read so far
        p.skipped["the battles couldn't all be read"] += 1
    p.made = time.strftime("%Y-%m-%d %H:%M:%S")
    return p


# ============================================================================ the planner's advice, against what was played
def advice_rows(b):
    """[{n, advised (the card's name), tid, played (the spell cast; None a pass), same (True / False / None not known),
    result}] - the rounds of record b whose bot lines hold the planner's advice"""
    out = []
    for rd in b.get("rounds") or []:
        if not isinstance(rd, dict):
            continue
        lines = ((rd.get("bot") or {}).get("lines")) or []
        adv = None
        for ln in lines:
            t = ln[1] if isinstance(ln, list) and len(ln) >= 2 else ln
            m = ADVICE_RX.search(t) if isinstance(t, str) else None
            if m:
                tm = ADVICE_TID.search(t)
                adv = {"name": m.group(1).strip(), "tid": int(tm.group(1)) if tm else None, "won_p": int(m.group(3))}
        if adv is None:
            continue
        pl = rd.get("played") if isinstance(rd.get("played"), dict) else None
        spell = None if pl is None or pl.get("pass") else pl.get("spell")
        if adv["name"].lower() == "pass":
            same = spell is None
        elif spell is None:
            same = False
        elif adv["tid"] is not None and pl.get("tid") is not None:
            same = adv["tid"] == pl.get("tid")
        else:
            same = adv["name"].lower() == str(spell).lower() or None
        out.append({"n": rd.get("n"), "advised": adv["name"], "tid": adv["tid"], "won_p": adv["won_p"],
                    "played": spell, "same": same, "result": b.get("result")})
    return out


def advice_summary(battles):
    """{rounds, same, differ, unknown, won_same (battles won among the rounds it agreed), won_differ} over battles"""
    s = collections.Counter()
    for b in battles:
        for r in advice_rows(b):
            s["rounds"] += 1
            tag = "same" if r["same"] is True else "differ" if r["same"] is False else "unknown"
            s[tag] += 1
            if r["result"] == "won" and tag != "unknown":
                s["won_" + tag] += 1
    return dict(s)


# ============================================================================ the command line
def main(argv=None):
    ap = argparse.ArgumentParser(description="the plays learned from the battles recorded (read only; --save writes "
                                             "learned\\battles\\plays.json)")
    ap.add_argument("--dir", default=DEFAULT_DIR, help="learned\\battles (default: the one next to vision\\)")
    ap.add_argument("--days", type=int, default=DAYS)
    ap.add_argument("--school", default="", help="only this school's rows (and every school's)")
    ap.add_argument("--save", action="store_true", help="write plays.json (the helper makes it itself too)")
    ap.add_argument("--advice", action="store_true", help="the planner's advice (planner:1) against what was played")
    a = ap.parse_args(argv)
    if a.advice:
        s = advice_summary(read(a.dir, a.days))
        n = s.get("rounds", 0)
        print("%d rounds with the planner's advice" % n)
        if n:
            for tag, what in (("same", "the card played was the one advised"), ("differ", "another was played"),
                              ("unknown", "not known (names only, no template id)")):
                k = s.get(tag, 0)
                won = s.get("won_" + tag)
                print("  %4d  %s%s" % (k, what, (" - %d%% of them in battles won" % round(100.0 * won / k))
                                       if k and won is not None and tag != "unknown" else ""))
        return 0
    p = build(a.dir, a.days)
    print("\n".join(p.lines(school_of(a.school) or None)))
    if a.save:
        path = os.path.join(a.dir, PLAYS_FILE)
        print(("saved: " if p.save(path) else "couldn't be saved: ") + path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
