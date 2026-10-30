"""battlesim.py - the battle simulator (TODO goal 3, step 2 of learned battle play), "can this deck beat it" and decks
learned from the ones set up in the game. Pure Python (numpy is not needed): it reads nothing from the game itself -
the vision helper hands it what navmem / deckmem / enemies already read (vision.py /sim and /decks).

    cards = deck_cards(deck)                       # a deckmem deck ({cards, item_cards, school...}) -> [Card]
    foes = [book.foe("Governor Nereus", wiki)]     # FoeBook: what the battle recorder saw + the wiki's creature
    r = simulate(cards, Me(school="balance", maxhp=4200, damage=95), foes, Opts(), n=400, seed=1)
    v = verdict(r, cards, me, foes)                # {word, text, best, hits...}: "can this deck beat it"
    learned = learn_decks(reading)                 # deckmem.read(kinds=True) -> one bot deck profile per in-game deck
    st = State.of_deck(hand, cards, pips=5, fhp=[2400], blades=[...], rnd=3)    # a battle in the middle (vision.py /plan)
    plan = plan_round(st, me, foes, opts, budget_ms=300, prior=plays.prior_fn("storm"))   # this round's plays, best first

    python battlesim.py --deck deck.json --foe "Governor Nereus" [--hp 4200] [--damage 95] [-n 400]   (a test run)

THE MODEL (one battle, round by round, until every enemy is dead, the wizard is, or MAX_ROUNDS)
  The wizard (Me): health, school, damage % (the game's curve - KillCalc.ahk DamageMultiplier), pierce, critical and
  block rating, level, accuracy %, incoming resist %, power pip chance. Pips: +1 each round (a power pip - worth 2 for a
  card of the wizard's school and for X-pip cards - at power_pip chance), at most 7 pips (power pips counted as 1 pip
  each). Starts at round 1 with that first pip.
  The deck (Card): the main side and the treasure cards shuffled together (the game's draw pile), the hand refilled to 7
  at each round's start; item cards (the gear's, the pet's) only with their kind known (cards.jsonl facts by template id).
  Copies: count each. No Reshuffle (the battle ends with an empty draw pile and hand: a timeout unless it's won).
  The bot's way (Opts - the deck's settings): cards it doesn't play discarded (discardunused, at most discardmax a round);
  a heal under healat %; the kill check - the cheapest hit that kills its target(s) at its least damage with the boosts
  on (killmargin % to spare); else, boost first (cardlogic 1, or 3 against a boss): a blade, trap or aura that fits a head
  of the planned hit - the hit dealing the most to the enemies left - while fewer than boostmax boosts went on since the
  last hit (0: no limit); then the planned hit once its pips are there; else a pass (pips build). Hit first (cardlogic 2,
  or 3 against mobs): the planned hit as soon as it's paid for, boosts only while waiting for pips.
  A hit: each head's least damage (heads_text - Hydra's three) to RANGE_TOP of it (the game's ranges are ~13% wide: 295-335),
  x the damage curve, x every blade on the wizard and trap on the target that fits the head's school (each used up by
  the hit), x the aura while it lasts (4 rounds), x the target's resist for that school (learned from the battles
  recorded: the game's own multiplier; else the creature's school's 15% the bot assumes - enemyresist) less pierce, a
  critical (CritChance / CritMult against the target's block); an AoE hits every enemy; a single-target hit the one with
  the most health (the bot's trap target too). Misses: accuracy (the card's, else its school's) + the wizard's accuracy;
  a missed card is gone, its pips kept (the game's fizzle).
  The enemies (Foe): health, school, resists, block; each round +1 pip (at most 7, starts with 1-3 as enemies.py does),
  a card at random - the wiki's spells weighted by the casts seen (enemies.Battle's own weights: 1 + seen, a pass's
  PASS_PRIOR; one it can't afford is a pass) - its damage the wiki's range (X-pip: per pip), its accuracy, an AoE hits
  every wizard on the team, a single-target one the wizard 1 in team; less the wizard's resist. A creature the wiki hasn't
  (yet): its hits recorded on the wizard (the battles' damage each cast) at its recorded cast rate; none recorded: a
  generic hitter (100 a pip, a cast every other round). Its blades, traps, shields and heals aren't modelled (damage only).
  Who goes first: either side, alike (the game's initiative), the same all battle.
  NOT modelled (yet): shields / wards on either side, the enemies' boosts and heals, damage over time after its first
  part, stuns, the party's other wizards (team only splits the enemies' single hits), Reshuffle, enchants (Epic...),
  the wizard's own minions. So the numbers lean optimistic against bosses that shield or heal - verdict() says so.

THE PLANNER (TODO goal 3, step 3 - vision.py /plan, Planner.ahk: advice only)
  State: a battle in the middle - the hand as dealt, the draw pile (the deck less the hand), pips, my health and each
  enemy's, the blades (by their cards' names - bot_blades turns the bot's keys into them), traps and aura on, the round,
  boosts since the last hit, who goes first; _Battle.from_state starts there and run_from plays it on: the round now
  with a play forced (force: a card at an enemy, or a pass - no pip, no draw: they're this round's), then the bot's
  chain (choose - my_round's picks) each round. plan_round tries every card that can go now (and a pass) in rollouts on
  common random numbers within a time budget and ranks them (win %, then the sooner, then health left; a rollout still
  going at the horizon valued by the enemies' health it took); a learned prior (battlelearn.Plays.prior_fn) only nudges
  near-equal plays. plan_lines is /plan's answer.

RESULTS  simulate() -> {n, won, lost, timeout (fractions), rounds (median rounds of the battles won), rounds_p90, hp_left
  (the wizard's mean health % left in won battles), dmg_in (mean damage taken a round), first_kill (median round of the
  first enemy's death), casts {card name: mean casts a battle}, why: [notes]}.

FAILS SOFT: nothing here raises out of the public functions on bad input - a card it can't read is left out (counted in
why), a foe with nothing known gets the generic hitter."""
import argparse
import collections
import json
import math
import random
import re
import statistics
import sys
import time

SCHOOLS = ("balance", "death", "fire", "ice", "life", "myth", "storm")
MAX_PIPS = 7
MAX_ROUNDS = 30
HAND = 7
RANGE_TOP = 1.13            # a hit's top as its least x this (the game's ranges: 295-335, 80-120 per pip...)
AURA_ROUNDS = 4
ENEMY_START_PIPS = (1, 2, 3)
PASS_PRIOR = 0.5            # enemies.py's
GENERIC_PER_PIP = 100       # an enemy nobody knows: 100 a pip
GENERIC_CAST = 0.5          # ... cast every other round
SCHOOL_ACC = {"balance": 85, "death": 85, "fire": 75, "ice": 80, "life": 90, "myth": 80, "storm": 70}
ENEMY_RESIST = 15           # the bot's own default (PlayerStats enemyresist): an enemy's resist to the wizard's hits
# (an enemy's block rating when nothing was learned of its crits: the wizard's own critical rating - a 75% critical
# chance at x1.25, not block 0's certain x2 every hit)
BLOCK_LIKE_ME = None
# (the kinds the simulator plays; every other card is discarded when discardunused is on, else just held)
PLAYED = ("damage", "aoe", "heal", "blade", "trap", "aura")
VERDICTS = ((0.9, "yes"), (0.65, "likely"), (0.35, "risky"), (0.0, "no"))


# ============================================================================ the bot's maths (KillCalc.ahk, Decks.ahk)
def damage_multiplier(d):
    """outgoing damage % -> multiplier, the PvE curve: linear to 150 %, then towards +200 % (KillCalc DamageMultiplier)"""
    L, k0, n0 = 2.0, 190.0, -40.0
    d = float(d or 0)
    if d <= k0 + n0:
        return 1 + d / 100
    k = math.log((100 * L) / (100 * L - k0)) / k0
    n = math.log(1 - (k0 + n0) / (100 * L)) + k * (k0 + n0)
    return 1 + L - L / math.exp(k * d - n)


def crit_mult(crit, block):
    """a critical's multiplier: 2 - 3B / (C + 3B) (Decks.ahk CritMult)"""
    if not crit or crit <= 0:
        return 1.0
    return 2 - 3 * block / (crit + 3 * block)


def crit_chance(crit, block, level=100):
    """the chance a hit is a critical: 3 L C / (3 C + B), L level / 100 at most 1 (Decks.ahk CritChance)"""
    if not crit or crit <= 0:
        return 0.0
    lf = min(1.0, level / 100.0) if level and level > 0 else 1.0
    return min(1.0, 3 * lf * crit / (3 * crit + (block or 0)))


def school_of(s):
    s = (s or "").strip().lower()
    return s if s in SCHOOLS else ""


def parse_pairs(text):
    """'fire:230,ice:230' -> {'fire': 230, 'ice': 230}; '' / '?' / junk -> {}"""
    out = {}
    for part in (text or "").split(","):
        k, _, v = part.partition(":")
        k = k.strip().lower()
        try:
            v = float(v)
        except ValueError:
            continue
        if k == "all" or k in SCHOOLS:
            out[k] = out.get(k, 0) + v
    return out


def value_of(v):
    """(number, top, per_pip) of a card's value - a number as it is, or handmem's value_text: '295-335' (295, 335),
    '100/pip' (100, None, True), '35%', '+75', '+10%' - (None, None, False) none"""
    if isinstance(v, bool) or v is None:
        return None, None, False
    if isinstance(v, (int, float)):
        return float(v), None, False
    m = re.match(r"\s*\+?(-?\d+(?:\.\d+)?)\s*(?:-\s*(\d+(?:\.\d+)?))?", str(v))
    if not m:
        return None, None, False
    lo = float(m.group(1))
    hi = float(m.group(2)) if m.group(2) else None
    return lo, (hi if hi is not None and hi > lo else None), "/pip" in str(v)


def fits(boosts, school):
    """the % a boost ({school: %}, 'all') adds to a head of school - 0 none"""
    return boosts.get(school, boosts.get("all", 0)) if boosts else 0


# ============================================================================ the cards
class Card:
    """one card the wizard can draw: name, kind (PLAYED or another of handmem's KINDS), school, pips, x (X-pip), value
    (a hit's least damage, a heal's amount, a boost's %), heads {school: least damage} (a hit's), boosts {school: %} (a
    blade's, trap's, aura's), acc (its accuracy %), tc / item"""
    __slots__ = ("name", "tid", "kind", "school", "pips", "x", "value", "heads", "boosts", "acc", "tc", "item", "top")

    def __init__(self, name, kind, school="", pips=0, x=False, value=0, heads=None, boosts=None, acc=None, tid=None,
                 tc=False, item=False, top=None):
        self.name, self.kind, self.school, self.tid = name or "?", kind or "", school_of(school), tid
        num, rtop, per = value_of(value)
        self.pips, self.x, self.value = int(pips or 0), bool(x) or per, num or 0.0
        # (a hit's range top as a multiple of its least: the card's own '295-335', else RANGE_TOP)
        rtop = top if top is not None else rtop
        self.top = (rtop / self.value) if rtop and self.value > 0 and rtop > self.value else RANGE_TOP
        self.heads = dict(heads or {})
        if self.kind in ("damage", "aoe") and not self.heads and self.value > 0:
            self.heads = {self.school or "balance": self.value}
        self.boosts = dict(boosts or {})
        if self.kind in ("blade", "trap", "aura") and not self.boosts and self.value > 0:
            self.boosts = {self.school or "all": self.value}
        self.acc = acc if acc else SCHOOL_ACC.get(self.school, 85)
        self.tc, self.item = bool(tc), bool(item)

    @property
    def hit(self):
        return self.kind in ("damage", "aoe") and bool(self.heads)

    def __repr__(self):
        return "Card(%s %s %dp)" % (self.name, self.kind, self.pips)


def card_of(c, facts=None):
    """a Card from a deckmem / handmem card dict (kind, school, pips, x_pips, value, heads_text, boosts_text...) - its
    template's facts (cards.jsonl's: kind, value - handmem's value_text there, heads, boosts, acc) fill what it lacks.
    None: no kind known"""
    f = (facts or {}).get(c.get("template_id") or c.get("tid")) or {}
    kind = c.get("kind") or f.get("kind")
    if not kind:
        return None
    heads = parse_pairs(c.get("heads_text") or f.get("heads") or "")
    boosts = parse_pairs(c.get("boosts_text") or f.get("boosts") or "")
    value = c.get("value") if c.get("value") is not None else f.get("value")
    # (the range's top: the card's value_text, else the fact's)
    _lo, top, _per = value_of(c.get("value_text") if c.get("value_text") else f.get("value"))
    return Card(c.get("display") or c.get("name") or f.get("display") or f.get("name"), kind,
                c.get("school") or f.get("school"), c.get("pips") if c.get("pips") is not None else f.get("pips"),
                c.get("x_pips") if c.get("x_pips") is not None else f.get("x"), value, heads, boosts,
                c.get("accuracy") or f.get("acc"), c.get("template_id") or c.get("tid"),
                tc=c.get("side") == "treasure", item=bool(c.get("item")), top=top)


def deck_cards(deck, facts=None, why=None):
    """[Card] of a deckmem deck: each main / treasure card count times, its item cards whose kind facts know (count
    times); why (a list) gets what was left out"""
    out, left = [], 0
    for c in (deck or {}).get("cards") or []:
        card = card_of(c, facts)
        if card is None:
            left += int(c.get("count") or 1)
            continue
        out.extend(_copies(card, c.get("count")))
    for c in (deck or {}).get("item_cards") or []:
        card = card_of(dict(c, item=True), facts)
        if card is None:
            left += int(c.get("count") or 1)
            continue
        out.extend(_copies(card, c.get("count")))
    if left and why is not None:
        why.append("%d card%s with no kind known left out" % (left, "" if left == 1 else "s"))
    return out


def _copies(card, n):
    try:
        n = max(1, min(int(n or 1), 60))
    except (TypeError, ValueError):
        n = 1
    return [card] * n


def load_facts(path):
    """{template id: fact} of cards.jsonl (the battle recorder's - the last line per tid wins); {} none"""
    out = {}
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                try:
                    o = json.loads(line)
                except ValueError:
                    continue
                if o.get("rec") == "card" and o.get("tid") is not None:
                    if o.get("full") is False and o["tid"] in out:
                        continue
                    out[o["tid"]] = o
    except OSError:
        pass
    return out


# ============================================================================ the wizard and the settings
class Me:
    """the wizard: school, maxhp (hp: its health at the start, default maxhp), damage %, pierce %, crit / block rating,
    level, accuracy % (added to a card's), resist % (incoming damage less), power_pip (chance a round), team (wizards on
    the side - the enemies' single hits split among them)"""

    def __init__(self, school="", maxhp=3000, hp=None, damage=0, pierce=0, crit=0, block=0, level=100, accuracy=0,
                 resist=0, power_pip=0.4, team=1):
        self.school = school_of(school)
        self.maxhp = max(1, int(maxhp or 3000))
        self.hp = int(hp) if hp else self.maxhp
        self.damage, self.pierce, self.crit, self.block = float(damage or 0), float(pierce or 0), float(crit or 0), \
            float(block or 0)
        self.level, self.accuracy, self.resist = int(level or 100), float(accuracy or 0), float(resist or 0)
        self.power_pip = min(1.0, max(0.0, float(power_pip if power_pip is not None else 0.4)))
        self.team = max(1, int(team or 1))


class Opts:
    """the bot's settings that shape a round (a deck's own - Decks.ahk DeckKeys - else the Settings'): cardlogic (1 boost
    first, 2 hit first, 3 boss: boost first, mobs: hit first), boostmax (0 no limit), healat %, killmargin %, useblades,
    usetraps, useaura, useheal, usehit (False: no hits - a support), discardunused, discardmax, boss (the fight is a boss's
    - cardlogic 3)"""
    KEYS = ("cardlogic", "boostmax", "healat", "killmargin", "useblades", "usetraps", "useaura", "useheal",
            "discardunused", "discardmax")

    def __init__(self, cardlogic=1, boostmax=0, healat=40, killmargin=15, useblades=1, usetraps=1, useaura=1, useheal=1,
                 discardunused=1, discardmax=3, boss=False, usehit=True):
        self.cardlogic, self.boostmax, self.healat, self.killmargin = int(cardlogic), int(boostmax), float(healat), \
            float(killmargin)
        self.useblades, self.usetraps, self.useaura, self.useheal = bool(useblades), bool(usetraps), bool(useaura), \
            bool(useheal)
        self.discardunused, self.discardmax, self.boss, self.usehit = bool(discardunused), int(discardmax), bool(boss), \
            bool(usehit)

    @classmethod
    def of(cls, vals, boss=False):
        """from {key: value} (a deck's vals / the settings) - unknown keys ignored, bad numbers the default"""
        kw = {}
        for k in cls.KEYS:
            if k in (vals or {}):
                try:
                    kw[k] = float(vals[k])
                except (TypeError, ValueError):
                    pass
        return cls(boss=boss, **kw)

    @property
    def boost_first(self):
        return self.cardlogic == 1 or (self.cardlogic == 3 and self.boss)


# ============================================================================ the enemies
class Foe:
    """an enemy: name, maxhp, school, resist {school: damage multiplier} (learned: the game's own; 'all' a fallback),
    block (rating; learned block chance as block_p), spells [(name or None for a pass, weight, data {pips, xpips, min, max,
    perpip, accuracy, aoe})] - the wiki's; hits [damage...] recorded on the wizard and hit_p (the chance a round it hit
    the wizard - the party's share already in it) when the wiki has none; boss; src (what it's known from)"""

    def __init__(self, name, maxhp, school="", resist=None, block=0, spells=None, hits=None, hit_p=None, boss=False,
                 src=""):
        self.name, self.maxhp, self.school = name or "?", max(1, int(maxhp or 1)), school_of(school)
        self.resist = dict(resist or {})
        self.block = float(block or 0)
        self.spells = list(spells or [])
        self.hits = [h for h in (hits or []) if h and h > 0]
        self.hit_p = hit_p
        self.block_p = None
        self.crit_p = None      # the game's own critical chance against it (learned: the log's finalCrit), None unknown
        self.boss, self.src = bool(boss), src

    def block_for(self, me):
        """its block rating: its own when known (above 0), else the wizard's critical rating (BLOCK_LIKE_ME)"""
        return self.block if self.block > 0 else (me.crit if BLOCK_LIKE_ME is None else BLOCK_LIKE_ME)

    def resist_mult(self, school, pierce=0):
        """the damage multiplier for a head of school, less pierce (a resist only: pierce never turns it into a boost)"""
        m = self.resist.get(school)
        if m is None:
            m = self.resist.get("all")
        if m is None:
            m = 1 - ENEMY_RESIST / 100.0 if (school and school == self.school) or not self.resist else 1.0
        r = 1 - m
        if r > 0:
            r = max(0.0, r - pierce / 100.0)
        return 1 - r


def wiki_spells(wiki, casts, name):
    """[(spell or None, weight, data)] - enemies.Battle._choices' weights for creature name (the wiki's spells, 1 + its
    casts seen, scaled to the same total; a pass PASS_PRIOR) - [] the wiki hasn't it (yet)"""
    try:
        c = wiki.creature(name) if wiki is not None else None
    except Exception:  # noqa: BLE001 - nothing known then
        c = None
    if not c or c.get("missing") or not c.get("spells"):
        return []
    try:
        import enemies
        seen = {}
        for k, v in (casts.counts(name) if casts is not None else {}).items():
            if k != "_pass":
                s = enemies.clean_spell(k, c["spells"])
                seen[s] = seen.get(s, 0) + v
    except Exception:  # noqa: BLE001
        seen = {}
    spells = list(dict.fromkeys(c["spells"]))
    raw = [1.0 + seen.get(s, 0) for s in spells]
    scale = len(spells) / sum(raw) if raw else 1.0
    out = [(None, PASS_PRIOR, None)]
    for s, r in zip(spells, raw):
        try:
            d = wiki.spell(s) or {}
        except Exception:  # noqa: BLE001
            d = {}
        out.append((s, r * scale, {} if d.get("missing") else d))
    return out


class FoeBook:
    """what the battle recorder saw of each enemy (learned\\battles\\ - battlereport.py reads them), by its name:
    {name: {n (battles), max, school, rank, boss, res {school: [multipliers]}, crits, blocked, hits [damage on me],
    casts, rounds}}. Read once (days back); foe() builds a Foe from it and the wiki"""

    def __init__(self, base=None, days=120, battles=None):
        self.by = {}
        self.why = ""
        bad, err = 0, None
        try:
            if battles is None:
                battles = self._read(base, days)
            for b in battles:
                # (an odd record - a part's max "?" - skips that battle, not the rest: the iteration goes on, and so
                # does whatever else reads the same pass - vision.py _plan_load's learned plays)
                try:
                    self._add(b)
                except Exception as e:  # noqa: BLE001 - that battle only
                    bad, err = bad + 1, err or e
        except Exception as e:  # noqa: BLE001 - what was read so far
            self.why = "the battles couldn't all be read (%r)" % (e,)
        if bad:
            self.why = "; ".join(w for w in (self.why, "%d battle%s couldn't be read (%r)" % (
                bad, "" if bad == 1 else "s", err)) if w)

    @staticmethod
    def _read(base, days):
        import datetime
        import battlereport
        base = base or battlereport.DEFAULT_DIR
        d1 = datetime.date.today()
        d0 = d1 - datetime.timedelta(days=days)
        # (battlereport counts torn lines, other kinds... into it: a Counter, so a torn line costs nothing)
        stats = collections.Counter()
        return battlereport.battles(base, d0.isoformat(), d1.isoformat(), stats)

    def _add(self, b):
        parts = {p.get("sc"): p for p in b.get("parts") or [] if isinstance(p, dict)}
        me = b.get("me") or {}
        msc, mschool = me.get("sc"), school_of(me.get("school"))
        foes = {sc: p for sc, p in parts.items() if p.get("side") == "enemy" and p.get("name")}
        for p in foes.values():
            e = self.by.setdefault(p["name"], {"n": 0, "max": None, "school": "", "rank": None, "boss": False, "res": {},
                                                "crits": 0, "blocked": 0, "hits": [], "hits_n": 0, "casts": 0,
                                                "rounds": 0, "crit_p": []})
            e["n"] += 1
            if p.get("max"):
                e["max"] = max(e["max"] or 0, int(p["max"]))
            e["school"] = school_of(p.get("school")) or e["school"]
            e["rank"] = p.get("rank") or e["rank"]
            e["boss"] = e["boss"] or bool(p.get("boss"))
        for rd in b.get("rounds") or []:
            hand = rd.get("hand") or []
            played = rd.get("played") or {}
            pschool = mschool
            hi = played.get("hand_i")
            if isinstance(hi, int) and 0 <= hi < len(hand):
                pschool = school_of(hand[hi].get("school")) or mschool
            alive = set()
            for c in rd.get("casts") or []:
                sc = c.get("sc")
                if sc in foes:
                    alive.add(sc)
                    e = self.by[foes[sc]["name"]]
                    if not c.get("pass") and c.get("spell"):
                        e["casts"] += 1
                        for h in c.get("hp") or []:
                            if len(h) >= 3 and h[0] == msc and isinstance(h[2], (int, float)) and h[2] < 0:
                                e["hits_n"] += 1
                                if len(e["hits"]) < 400:
                                    e["hits"].append(-h[2])
                elif sc == msc and msc is not None:
                    for r in c.get("res") or []:
                        if len(r) >= 3 and r[0] in foes and isinstance(r[2], (int, float)) and pschool:
                            lst = self.by[foes[r[0]]["name"]]["res"].setdefault(pschool, [])
                            if len(lst) < 200:
                                lst.append(float(r[2]))
                    tgt = (played.get("targets") or [None])[0]
                    # (the game's own critical chance against it: GetCritParams' finalCrit - 0-1, or a % over 1)
                    cp = c.get("crit_p")
                    if isinstance(cp, list) and len(cp) >= 4 and isinstance(cp[3], (int, float)) and tgt in foes:
                        lst = self.by[foes[tgt]["name"]]["crit_p"]
                        if len(lst) < 200:
                            lst.append(cp[3] / 100.0 if cp[3] > 1 else float(cp[3]))
                    for cr in c.get("crit") or []:
                        name = foes[tgt]["name"] if tgt in foes else (foes[next(iter(foes))]["name"] if len(foes) == 1
                                                                       else None)
                        if name and len(cr) >= 3:
                            self.by[name]["crits"] += 1
                            self.by[name]["blocked"] += 1 if cr[2] else 0
            for sc in alive:
                self.by[foes[sc]["name"]]["rounds"] += 1

    def foe(self, name, wiki=None, casts=None, hp=None, school=None, boss=None):
        """a Foe for creature name: its max health (hp given: the game's memory's), school, resists and block from the
        battles recorded, its spells from the wiki - or its recorded hits; nothing known: the generic hitter"""
        e = self.by.get(name) or {}
        c = None
        try:
            c = wiki.creature(name) if wiki is not None else None
        except Exception:  # noqa: BLE001
            c = None
        if c and c.get("missing"):
            c = None
        maxhp = hp or e.get("max") or (c or {}).get("health")
        src = []
        if hp:
            src.append("health: the game's memory")
        elif e.get("max"):
            src.append("health: %d battle%s recorded" % (e["n"], "" if e["n"] == 1 else "s"))
        elif (c or {}).get("health"):
            src.append("health: the wiki")
        res = {s: statistics.median(v) for s, v in (e.get("res") or {}).items() if v}
        block_p = (e["blocked"] / e["crits"]) if e.get("crits") else None
        spells = wiki_spells(wiki, casts, name)
        hits, hit_p = None, None
        if spells:
            src.append("spells: the wiki")
        elif e.get("hits") and e.get("rounds"):
            hits = list(e["hits"])
            hit_p = min(1.0, e["hits_n"] / float(e["rounds"]))
            src.append("hits: %d recorded in %d rounds" % (e["hits_n"], e["rounds"]))
        else:
            src.append("hits: not known (a generic hitter)")
        f = Foe(name, maxhp or 1000, school or e.get("school") or (c or {}).get("school"), res, 0, spells, hits,
                hit_p, boss if boss is not None else e.get("boss", False), "; ".join(src))
        f.block_p = block_p
        if e.get("crit_p"):
            f.crit_p = min(1.0, max(0.0, statistics.median(e["crit_p"])))
        if not maxhp:
            f.src = "health: not known (1000 assumed); " + f.src
        return f


# ============================================================================ a battle in the middle
class State:
    """a battle in the middle - the round the planner looks at (vision.py /plan builds it from the game's memory and the
    bot's own bookkeeping):
      hand        [Card] as dealt now, left to right (the bot's discards this round already made)
      pile        [Card] the draw pile: the deck less the hand (of_deck) - its order not known: shuffled each rollout
      used        cards drawn from the pile before this round besides the hand (taken off it; None: round - 1, about one
                  a round - a shuffled pile's mix is the same whatever is taken off, only its size counts)
      pips, power my pips now, power pips counted 1 (as _Battle's), and how many of them are power pips
      hp          my health now (None: Me's)
      fhp         each enemy's health now, in foes' order (None for one: its max)
      blades      [(name, {school: %})] on me - one of each name (identical blades don't stack): the cards' names (the
                  bot's own keys through bot_blades, so a copy in hand of one on matches it)
      traps       [[{school: %}] for each enemy] on it
      aura        ({school: %}, rounds left - this one counted) or None
      round       the battle's round (1 the first); boosts_run the boosts cast since my last hit (boostmax counts them)
      me_first    True / False: my side casts first (the game's initiative); None not known (a coin each rollout)
      fpips       each enemy's pips now, or None (not known: 1-3 as at a battle's start)
    Never raises on junk: a value it can't read is the default"""

    def __init__(self, hand, pile=None, pips=0, power=0, hp=None, fhp=None, blades=None, traps=None, aura=None, rnd=1,
                 boosts_run=0, me_first=None, fpips=None, used=None):
        self.hand = [c for c in (hand or []) if isinstance(c, Card)]
        self.pile = [c for c in (pile or []) if isinstance(c, Card)]
        self.pips, self.power = _int(pips), _int(power)
        self.hp = _int(hp) or None
        self.fhp = [None if h is None else _int(h) for h in (fhp or [])]
        self.blades = [(str(n), dict(b)) for n, b in (blades or []) if isinstance(b, dict)]
        self.traps = [[dict(t) for t in ts if isinstance(t, dict)] for ts in (traps or [])]
        self.aura = (dict(aura[0]), _int(aura[1])) if aura and isinstance(aura[0], dict) and _int(aura[1]) > 0 else None
        self.round = max(1, _int(rnd) or 1)
        self.boosts_run = _int(boosts_run)
        self.me_first = None if me_first is None else bool(me_first)
        self.fpips = [None if x is None else _int(x) for x in fpips] if isinstance(fpips, (list, tuple)) and fpips else None
        self.used = max(0, self.round - 1) if used is None else max(0, _int(used))

    @classmethod
    def of_deck(cls, hand, deck, **kw):
        """the State with its pile the deck's cards ([Card] - deck_cards) less the hand's: each hand card takes one copy
        of its template id (else its name) out - one the deck hasn't (a pet's card) takes nothing"""
        pile = list(deck or [])
        for c in hand or []:
            k = next((j for j, d in enumerate(pile) if c.tid is not None and d.tid == c.tid), None)
            if k is None:
                k = next((j for j, d in enumerate(pile) if d.name == c.name and d.kind == c.kind), None)
            if k is not None:
                pile.pop(k)
        return cls(hand, pile, **kw)


def bot_blades(blades, cards):
    """the blades on as the bot counts them (vision.py /plan's blades=: KillCalc.ahk AppliedBlades' keys - BoostKey's
    "storm/blade", "blade3", "elementalblade"..., "@tc" / "@item" after it a treasure or item card's copy, "+" a
    sharpened cast) in the simulator's names, which are its cards' (a blade on is one of each name - _Battle.cast,
    pick_boost, _plannable): the deck's own plain cast named as the blade card of cards (the hand, then the draw pile -
    not a treasure or item card) that boosts the same schools, the nearest % of them; so another copy of it in hand is
    'on already' and never stacks in the rollouts - the bot's used flags never cast it plain again while it's on
    (Autofarmer.ahk UseBlade's Use2; sharpened only with a Sharpen, which the simulator doesn't play). A sharpened cast
    or a treasure / item card's copy keeps the bot's key - no card has it: the bot counts it on top of the deck's plain
    one and still casts that (KillCalc.ahk AddBoost, BoostCopyCanGo - the user, 2026-10-24); (the simulator's names
    don't tell a hand card's copies apart: a treasure / item card's in hand goes as the deck's does). A key no card fits
    keeps it too. [(name, {school: %})] in blades' order; never raises (junk as it came)"""
    def schools(b):
        s = {k for k, v in b.items() if isinstance(v, (int, float)) and v > 0}
        return frozenset(SCHOOLS) if "all" in s else frozenset(s)

    def pct(b):
        return max([v for v in b.values() if isinstance(v, (int, float))] or [0])
    out = []
    try:
        own = [c for c in cards or [] if isinstance(c, Card) and c.kind == "blade" and not c.tc and not c.item]
    except TypeError:
        own = []
    for nb in blades or []:
        try:
            n, b = nb
        except (TypeError, ValueError):
            out.append(nb)
            continue
        try:
            m = re.match(r"(.*?)(@[a-z]+)?(\+)?$", str(n))
            fit = [c for c in own if schools(c.boosts) == schools(b)] if b and not (m.group(2) or m.group(3)) else []
            if fit:
                n = min(fit, key=lambda c: abs(pct(c.boosts) - pct(b))).name
        except Exception:  # noqa: BLE001 - that one as it came
            pass
        out.append((n, b))
    return out


def _int(v, d=0):
    try:
        return int(float(v))
    except (TypeError, ValueError, OverflowError):
        return d


# ============================================================================ one battle
class _Battle:
    def __init__(self, cards, me, foes, opts, rng):
        self.me, self.opts, self.rng = me, opts, rng
        self.pile = list(cards)
        rng.shuffle(self.pile)
        self.hand = []
        self.hp = me.hp
        self.fhp = [f.maxhp for f in foes]
        self.foes = foes
        self.pips = 0           # pips (power pips counted as 1)
        self.power = 0          # of which power pips
        self.fpips = [rng.choice(ENEMY_START_PIPS) for _ in foes]
        self.blades = []        # [(name, {school: %})] on the wizard - one of each name (the game doesn't stack
                                # identical blades; traps it does)
        self.traps = [[] for _ in foes]
        self.aura = None        # ({school: %}, rounds left)
        self.boosts_run = 0     # boosts since the last hit
        self.casts = {}
        self.dmg_in = 0
        self.first_kill = None
        self.plan = None
        self.aim = None         # (the planner's: the enemy a single-target hit or trap of this round's forced play goes at)
        self.round0 = 1         # (from_state: the battle's round the state is in)
        self.me_first = None
        self.rounds_run = 0

    # ---------------------------------------------------------------- helpers
    def alive(self):
        return [i for i, h in enumerate(self.fhp) if h > 0]

    def pay(self, card):
        """(can pay, pips it spends) - an X-pip card spends them all (a power pip worth 2); a school card counts power
        pips double"""
        if card.x:
            return self.pips > 0, self.pips
        if card.pips <= 0:
            return True, 0
        doubled = card.school == self.me.school and card.school != ""
        worth = self.pips + (self.power if doubled else 0)
        return worth >= card.pips, card.pips

    def spend(self, card):
        if card.x:
            self.pips = self.power = 0
            return
        need = card.pips
        doubled = card.school == self.me.school and card.school != ""
        if doubled:
            use_p = min(self.power, need // 2)
            self.power -= use_p
            self.pips -= use_p
            need -= 2 * use_p
        take = min(self.pips - self.power, need)
        self.pips -= take
        need -= take
        if need > 0:
            use_p = min(self.power, need)
            self.power -= use_p
            self.pips -= use_p

    def pip_value(self, card):
        """an X-pip card's pips' worth (power pips 2)"""
        return self.pips + self.power

    def least(self, card, i, boosts=True):
        """the card's least damage to enemy i with the boosts on (no critical, the low end) - the kill check's"""
        per = self.pip_value(card) if card.x else 1
        total = 0.0
        for sch, v in card.heads.items():
            m = damage_multiplier(self.me.damage)
            if boosts:
                for _n, b in self.blades:
                    m *= 1 + fits(b, sch) / 100.0
                for t in self.traps[i]:
                    m *= 1 + fits(t, sch) / 100.0
                if self.aura:
                    m *= 1 + fits(self.aura[0], sch) / 100.0
            m *= self.foes[i].resist_mult(sch, self.me.pierce)
            total += v * per * m
        return total

    def targets(self, card):
        """the enemies card hits: an AoE every one left; else the planner's aim (alive), else the one with the most
        health (the bot's trap target too)"""
        al = self.alive()
        if card.kind == "aoe":
            return al
        if self.aim is not None and self.aim in al:
            return [self.aim]
        return [max(al, key=lambda i: self.fhp[i])] if al else []

    def value(self, card):
        """what a hit deals to the enemies left (the plan's measure), capped at their health"""
        return sum(min(self.fhp[i], self.least(card, i)) for i in self.targets(card))

    # ---------------------------------------------------------------- my round
    def draw(self):
        while len(self.hand) < HAND and self.pile:
            self.hand.append(self.pile.pop())

    def discard(self):
        if not self.opts.discardunused:
            return
        n = 0
        keep = []
        hit_schools = {s for c in self.hand + self.pile if c.hit for s in c.heads}
        for c in self.hand:
            useless = c.kind not in PLAYED or (c.kind in ("damage", "aoe") and (not c.hit or not self.opts.usehit)) \
                or (c.kind == "heal" and not self.opts.useheal) \
                or (c.kind == "blade" and (not self.opts.useblades or not any(fits(c.boosts, s) for s in hit_schools))) \
                or (c.kind == "trap" and (not self.opts.usetraps or not any(fits(c.boosts, s) for s in hit_schools))) \
                or (c.kind == "aura" and not self.opts.useaura)
            if useless and n < self.opts.discardmax:
                n += 1
                continue
            keep.append(c)
        self.hand = keep

    def cast(self, card):
        self.hand.remove(card)
        self.casts[card.name] = self.casts.get(card.name, 0) + 1
        ok, _ = self.pay(card)
        if not ok:
            return False
        acc = min(100.0, card.acc + self.me.accuracy)
        if self.rng.random() * 100 >= acc:
            return False        # fizzled: the card's gone, the pips kept
        per = self.pip_value(card) if card.x else 1
        self.spend(card)
        if card.kind == "heal":
            self.hp = min(self.me.maxhp, self.hp + card.value)
        elif card.kind == "blade":
            if all(n != card.name for n, _b in self.blades):
                self.blades.append((card.name, card.boosts))
            self.boosts_run += 1
        elif card.kind == "trap":
            t = self.targets(Card("", "damage", heads={"balance": 1}))
            if t:
                self.traps[t[0]].append(card.boosts)
            self.boosts_run += 1
        elif card.kind == "aura":
            self.aura = (card.boosts, AURA_ROUNDS)
            self.boosts_run += 1
        elif card.hit:
            self.hit(card, per)
        return True

    def hit(self, card, per):
        used_blades = set()
        for i in self.targets(card):
            f = self.foes[i]
            total = 0.0
            used_traps = set()
            for sch, v in card.heads.items():
                d = v * per * self.rng.uniform(1.0, card.top) * damage_multiplier(self.me.damage)
                for k, (_n, b) in enumerate(self.blades):
                    if fits(b, sch):
                        d *= 1 + fits(b, sch) / 100.0
                        used_blades.add(k)
                for k, t in enumerate(self.traps[i]):
                    if fits(t, sch):
                        d *= 1 + fits(t, sch) / 100.0
                        used_traps.add(k)
                if self.aura:
                    d *= 1 + fits(self.aura[0], sch) / 100.0
                d *= f.resist_mult(sch, self.me.pierce)
                total += d
            # (a critical: the game's own chance against it when learned - the log's finalCrit, blocks already in it -
            # else the model's with its block; its multiplier the model's)
            blk = f.block_for(self.me)
            if f.crit_p is not None:
                crit = self.rng.random() < f.crit_p
            else:
                crit = self.rng.random() < crit_chance(self.me.crit, blk, self.me.level) and not (
                    f.block_p is not None and self.rng.random() < f.block_p)
            if crit:
                total *= crit_mult(self.me.crit, blk)
            self.traps[i] = [t for k, t in enumerate(self.traps[i]) if k not in used_traps]
            before = self.fhp[i]
            self.fhp[i] = max(0, self.fhp[i] - int(total))
            if before > 0 and self.fhp[i] == 0 and self.first_kill is None:
                self.first_kill = self.round
        self.blades = [b for k, b in enumerate(self.blades) if k not in used_blades]
        self.boosts_run = 0

    def my_round(self, fresh=True):
        """the bot's round: the draw and its discards (fresh - False: the hand as dealt, the bot's own discards made: the
        planner's round now), then the card its chain picks (choose) cast - False nothing cast"""
        if fresh:
            self.draw()
            self.discard()
        card = self.choose()
        return self.cast(card) if card is not None else False

    def choose(self):
        """the card the bot's chain plays now - Autofarmer.ahk's order: a heal under healat %, the kill check, then the
        planned hit and its boosts (boost first or hit first), a payable hit with nothing better coming - None a pass.
        Draws no random number (the planner asks it what the bot would play)"""
        o = self.opts
        # (a heal under healat %)
        if o.useheal and self.hp < self.me.maxhp * o.healat / 100.0:
            heals = [c for c in self.hand if c.kind == "heal" and self.pay(c)[0]]
            if heals:
                return max(heals, key=lambda c: c.value)
        hits = [c for c in self.hand if c.hit and o.usehit]
        payable = [c for c in hits if self.pay(c)[0]]
        # (the kill check: the cheapest hit that kills its target(s) at its least, killmargin to spare)
        margin = 1 + o.killmargin / 100.0
        kills = [c for c in payable if self.targets(c) and
                 all(self.least(c, i) >= self.fhp[i] * margin for i in self.targets(c))
                 and (c.kind == "aoe" or len(self.alive()) == 1)]
        if kills:
            return min(kills, key=lambda c: (c.pips if not c.x else MAX_PIPS, -self.value(c)))
        # (the planned hit: the one dealing the most to the enemies left)
        plan = max(hits, key=self.value) if hits else None
        boost = self.pick_boost(plan)
        can_boost = boost is not None and (o.boostmax <= 0 or self.boosts_run < o.boostmax)
        plan_paid = plan is not None and self.pay(plan)[0]
        if o.boost_first:
            if can_boost:
                return boost
            if plan_paid:
                return plan
        else:
            if plan_paid:
                return plan
            if can_boost:
                return boost
        # (nothing: with no hit in hand, any hit to be had - the best payable)
        if payable and not plan_paid and not can_boost:
            best = max(payable, key=self.value)
            if not self.hand_has_better(best):
                return best
        return None

    def hand_has_better(self, best):
        """a hit in hand worth waiting for: the plan not paid yet but within reach of pips (a pass builds them)"""
        return any(c.hit and not self.pay(c)[0] and self.value(c) > 1.5 * self.value(best) for c in self.hand)

    def pick_boost(self, plan):
        """a blade, trap or aura in hand that fits a head of the planned hit (the biggest %), payable - None"""
        if plan is None:
            return None
        o = self.opts
        best, best_pct = None, 0
        for c in self.hand:
            if c.kind == "blade" and not o.useblades or c.kind == "trap" and not o.usetraps \
                    or c.kind == "aura" and (not o.useaura or self.aura) or c.kind not in ("blade", "trap", "aura"):
                continue
            # (that blade's on already: another copy adds nothing)
            if c.kind == "blade" and any(n == c.name for n, _b in self.blades):
                continue
            pct = max((fits(c.boosts, s) for s in plan.heads), default=0)
            if pct > best_pct and self.pay(c)[0]:
                best, best_pct = c, pct
        return best

    # ---------------------------------------------------------------- the enemies' round
    def foe_round(self):
        me = self.me
        for i in self.alive():
            f = self.foes[i]
            self.fpips[i] = min(MAX_PIPS, self.fpips[i] + 1)
            dmg = 0.0
            if f.spells:
                dmg = self.foe_spell(i, f)
            elif f.hits and f.hit_p is not None:
                # (its hits recorded on the wizard, at the rate they came - the party's share already in it)
                if self.rng.random() < f.hit_p:
                    dmg = self.rng.choice(f.hits)
            elif self.rng.random() < GENERIC_CAST:
                # (the generic hitter: 100 a pip, all its pips, at one wizard of the team)
                dmg = GENERIC_PER_PIP * max(1, self.fpips[i]) * self.rng.uniform(0.85, 1.15)
                self.fpips[i] = 0
                if self.rng.random() >= 1.0 / me.team:
                    dmg = 0.0
            if dmg > 0:
                dmg *= max(0.0, 1 - me.resist / 100.0)
                self.hp -= int(dmg)
                self.dmg_in += int(dmg)
                if self.hp <= 0:
                    return

    def foe_spell(self, i, f):
        total = sum(w for _s, w, _d in f.spells)
        r = self.rng.random() * total
        for s, w, d in f.spells:
            r -= w
            if r <= 0:
                break
        if s is None or not d:
            return 0.0
        cost = MAX_PIPS if d.get("xpips") else int(d.get("pips") or 0)
        if d.get("xpips"):
            cost = max(1, self.fpips[i])
        if cost > self.fpips[i]:
            return 0.0          # (can't afford it: a pass, its pips build)
        self.fpips[i] -= cost
        if self.rng.random() * 100 >= float(d.get("accuracy") or 100):
            return 0.0
        if d.get("perpip"):
            lo, hi = d["perpip"]
            dmg = self.rng.uniform(lo, hi) * cost
        elif d.get("max"):
            dmg = self.rng.uniform(d.get("min") or d["max"], d["max"])
        else:
            return 0.0
        if not d.get("aoe") and self.rng.random() >= 1.0 / self.me.team:
            return 0.0
        return dmg

    # ---------------------------------------------------------------- the battle
    def run(self, me_first):
        for self.round in range(1, MAX_ROUNDS + 1):
            self.pips = min(MAX_PIPS, self.pips + 1)
            if self.rng.random() < self.me.power_pip:
                self.power = min(self.pips, self.power + 1)
            order = (self.my_round, self.foe_round) if me_first else (self.foe_round, self.my_round)
            for step in order:
                step()
                if self.hp <= 0:
                    return "lost"
                if not self.alive():
                    return "won"
            if self.aura:
                self.aura = (self.aura[0], self.aura[1] - 1) if self.aura[1] > 1 else None
            if not self.hand and not self.pile:
                return "timeout"
        return "timeout"

    # ---------------------------------------------------------------- a battle in the middle (the planner's)
    @classmethod
    def from_state(cls, st, me, foes, opts, rng):
        """a battle started from State st (the round now) instead of round 1 with a shuffled deck: its hand as dealt, its
        draw pile shuffled (the cards drawn before it - st.used - taken off), pips, health (mine and each enemy's),
        blades, traps, aura, boosts since my last hit; the enemies' pips st.fpips (not known: 1-3 as a battle's start);
        who goes first st.me_first (not known: a coin - for a whole rollout, as the game's initiative). The random
        numbers it draws come first and are the same for every play the planner tries (one rng a rollout)"""
        b = cls([], me, foes, opts, rng)        # (no cards: nothing shuffled; the enemies' starting pips drawn)
        b.pile = list(st.pile)
        rng.shuffle(b.pile)
        if st.used:
            del b.pile[:min(len(b.pile), st.used)]
        b.hand = list(st.hand)
        b.hp = int(st.hp) if st.hp else me.hp
        fhp = list(st.fhp or [])
        b.fhp = [max(0, int(fhp[i])) if i < len(fhp) and fhp[i] is not None else f.maxhp for i, f in enumerate(foes)]
        b.pips = max(0, min(MAX_PIPS, int(st.pips or 0)))
        b.power = max(0, min(b.pips, int(st.power or 0)))
        if st.fpips:
            b.fpips = [max(0, min(MAX_PIPS, int(st.fpips[i]))) if i < len(st.fpips) and st.fpips[i] is not None
                       else b.fpips[i] for i in range(len(foes))]
        b.blades = []
        for n, bb in st.blades or []:
            if all(n != m for m, _b in b.blades):
                b.blades.append((n, dict(bb)))
        b.traps = [[dict(t) for t in (st.traps[i] if st.traps and i < len(st.traps) else [])] for i in range(len(foes))]
        b.aura = (dict(st.aura[0]), int(st.aura[1])) if st.aura and st.aura[1] and int(st.aura[1]) > 0 else None
        b.boosts_run = int(st.boosts_run or 0)
        b.round0 = max(1, int(st.round or 1))
        b.me_first = bool(st.me_first) if st.me_first is not None else rng.random() < 0.5
        return b

    def force(self, card, aim=None):
        """this round's play forced: card (one of the hand) cast at enemy aim (a single-target hit's or trap's - None:
        the bot's own pick, the most health); None a pass. As cast: False nothing went out"""
        if card is None:
            return False
        self.aim = aim
        try:
            return self.cast(card)
        finally:
            self.aim = None

    def run_from(self, play=False, aim=None, horizon=MAX_ROUNDS):
        """the battle on from from_state's round: the round now as dealt (no pip, no draw: the hand and pips are this
        round's) - play: the card cast in it (one of self.hand; None a pass; False the bot's chain: choose), aim its enemy
        - then the bot's chain each round (my_round). 'won' / 'lost' / 'timeout' (the cards ran out) / 'cut' (horizon
        rounds and nothing decided); rounds_run the rounds it took (1: decided this round)"""
        self.round = self.round0
        for k in range(max(1, int(horizon))):
            if k:
                self.round += 1
                self.pips = min(MAX_PIPS, self.pips + 1)
                if self.rng.random() < self.me.power_pip:
                    self.power = min(self.pips, self.power + 1)
            self.rounds_run = k + 1
            if k:
                mine = self.my_round
            elif play is False:
                mine = lambda: self.my_round(fresh=False)    # noqa: E731
            else:
                mine = lambda: self.force(play, aim)          # noqa: E731
            order = (mine, self.foe_round) if self.me_first else (self.foe_round, mine)
            for step in order:
                step()
                if self.hp <= 0:
                    return "lost"
                if not self.alive():
                    return "won"
            if self.aura:
                self.aura = (self.aura[0], self.aura[1] - 1) if self.aura[1] > 1 else None
            if not self.hand and not self.pile:
                return "timeout"
        return "cut"


def simulate(cards, me, foes, opts=None, n=400, seed=None):
    """n battles of the deck's cards (deck_cards) against foes - see the docstring's RESULTS. Never raises"""
    out = {"n": 0, "won": 0.0, "lost": 0.0, "timeout": 0.0, "rounds": None, "rounds_p90": None, "hp_left": None,
           "dmg_in": None, "first_kill": None, "casts": {}, "why": []}
    try:
        opts = opts or Opts(boss=any(f.boss for f in foes))
        if not foes:
            out["why"].append("no enemies")
            return out
        if not any(c.hit for c in cards):
            out["why"].append("no hit in the deck")
        rng = random.Random(seed)
        res = {"won": 0, "lost": 0, "timeout": 0}
        rounds, hp_left, dmg_in, fk, casts = [], [], [], [], {}
        n = max(1, min(int(n), 5000))
        for _ in range(n):
            b = _Battle(cards, me, foes, opts, rng)
            r = b.run(rng.random() < 0.5)
            res[r] += 1
            if r == "won":
                rounds.append(b.round)
                hp_left.append(100.0 * max(0, b.hp) / me.maxhp)
            dmg_in.append(b.dmg_in / max(1, b.round))
            if b.first_kill:
                fk.append(b.first_kill)
            for k, v in b.casts.items():
                casts[k] = casts.get(k, 0) + v
        out.update(n=n, won=res["won"] / n, lost=res["lost"] / n, timeout=res["timeout"] / n,
                   rounds=statistics.median(rounds) if rounds else None,
                   rounds_p90=sorted(rounds)[int(0.9 * (len(rounds) - 1))] if rounds else None,
                   hp_left=round(statistics.mean(hp_left), 1) if hp_left else None,
                   dmg_in=round(statistics.mean(dmg_in)) if dmg_in else None,
                   first_kill=statistics.median(fk) if fk else None,
                   casts={k: round(v / n, 2) for k, v in sorted(casts.items(), key=lambda kv: -kv[1])})
    except Exception as e:  # noqa: BLE001 - the result as far as it got
        out["why"].append("the simulation failed (%r)" % (e,))
    return out


# ============================================================================ the planner (the round's plays, tried)
PLAN_N = 100                # rollouts a play at most
PLAN_HORIZON = 10           # rounds a rollout looks ahead (one still going then is valued by the enemies' health left)
PLAN_HORIZON_BOSS = 20      # ... against a boss (a longer fight)
PLAN_BUDGET_MS = 300        # the time the rollouts may take (the bot's round waits on them)
PLAN_PRUNE = (24, 48)       # after this many rollouts each, the worse half of the plays (5 or more) stop
PRIOR_W = 0.05              # a learned play's nudge at most (a sure win scores about 1): it only tips near-equal plays


def situation(state, me, foes):
    """the round now as learned plays key it (battlelearn.key_of): {school, pips (mine, power counted 1), alive
    (enemies left), boss (one of them a boss), hit (a hit in hand I can pay for), hp (my health %)} - the fields a
    battle record gives for its rounds (battlelearn.round_situation)"""
    b = _Battle.from_state(state, me, foes, Opts(), random.Random(0))
    alive = b.alive()
    return {"school": me.school, "pips": b.pips, "alive": len(alive), "boss": any(foes[i].boss for i in alive),
            "hit": any(c.hit and b.pay(c)[0] for c in b.hand), "hp": int(round(100.0 * max(0, b.hp) / me.maxhp))}


def _plannable(c, o, b):
    """'' card c is a play to try now, else why not: a kind the simulator doesn't play, switched off, a blade of its
    name already on, an aura up"""
    if c.kind not in PLAYED or (c.kind in ("damage", "aoe") and not c.hit):
        return "not simulated"
    if (c.hit and not o.usehit) or (c.kind == "heal" and not o.useheal) or (c.kind == "blade" and not o.useblades) \
            or (c.kind == "trap" and not o.usetraps) or (c.kind == "aura" and not o.useaura):
        return "switched off"
    if c.kind == "blade" and any(n == c.name for n, _b in b.blades):
        return "on already"
    if c.kind == "aura" and b.aura:
        return "on already"
    # (a heal with my health high: wasted - and in the simulator it would only free a hand slot for the next draw)
    if c.kind == "heal" and b.me.maxhp - b.hp < c.value / 2.0:
        return "health high"
    return ""


def _rollout(r, b, total0, horizon):
    """(result, rounds, my health %, value) of one rollout - plan_round's docstring has the value"""
    dealt = max(0.0, min(1.0, 1 - sum(max(0, h) for h in b.fhp) / total0))
    hp = max(0.0, min(1.0, b.hp / float(b.me.maxhp)))
    if r == "won":
        v = 1 + 0.2 * (1 - (b.rounds_run - 1) / float(horizon)) + 0.05 * hp
    elif r == "lost":
        v = 0.05 * dealt
    else:
        v = 0.7 * dealt * (0.5 + 0.5 * hp)
    return r, b.rounds_run, 100.0 * hp, v


def plan_round(state, me, foes, opts=None, n=PLAN_N, horizon=None, budget_ms=PLAN_BUDGET_MS, seed=None,
               prior=None):
    """the plays for the round now (State), best first. Tried: every card in hand that can go now - a kind the simulator
    plays (PLAYED), paid for, not switched off in opts, not a blade already on, an aura while one's up or a heal that
    half goes to waste (my health high); copies once - a single-target hit or a trap at each enemy left, anything else
    once; and a pass. Each in up to n rollouts (from_state, then run_from: this round with that play, then the bot's
    chain - choose - till the battle's decided or horizon rounds - None: PLAN_HORIZON, PLAN_HORIZON_BOSS with a boss
    among foes), every play on the same random numbers (rollout k's rng is the same for each: the gaps are the plays',
    not luck's), round robin till budget_ms is spent (always one round of them; the worse half dropped at PLAN_PRUNE -
    the bot's own pick and the pass kept). A rollout's value: won 1 + up to 0.2 the sooner + up to 0.05 my health left; lost
    0.05 x the share of the enemies' health it took; cut at the horizon or out of cards 0.7 x that share x (0.5 + half
    my health left). prior: a callable (battlelearn.Plays.prior_fn) situation(...) -> ({kind: -1..1}, why) - x PRIOR_W
    added to each play of that kind.
    -> {plays: [{i (in state.hand; None the pass), name, tid, kind ('pass'), aim (the enemy's index in foes; None not
    aimed), n (rollouts), won, lost, kill (won this very round) - shares -, rounds (median rounds of the won: 1 this
    one), hp_left (my health % in the won), value, bonus, score, chain (the bot's own pick, as the simulator plays your
    settings), why}], chain (that play, None not known), n (the best's rollouts), ms, why [notes], learned (the prior's
    why)}. Never raises: what it got to, its failure in why"""
    t0 = time.perf_counter()
    out = {"plays": [], "chain": None, "n": 0, "ms": 0, "why": [], "learned": ""}
    try:
        foes = list(foes or [])
        opts = opts or Opts(boss=any(f.boss for f in foes))
        if not foes:
            out["why"].append("no enemies")
            return out
        if horizon is None:
            horizon = PLAN_HORIZON_BOSS if any(f.boss for f in foes) else PLAN_HORIZON
        horizon = max(1, min(int(horizon), MAX_ROUNDS))
        probe = _Battle.from_state(state, me, foes, opts, random.Random(0))
        alive = probe.alive()
        if not alive:
            out["why"].append("no enemy left")
            return out
        cands, seen, rep, left = [(None, None)], {}, {}, collections.Counter()
        for i, c in enumerate(probe.hand):
            no = _plannable(c, opts, probe) or ("" if probe.pay(c)[0] else "not paid for")
            if no:
                left[no] += 1
                continue
            key = (c.name, c.kind, c.school, c.pips, c.x, c.value, tuple(sorted(c.heads.items())),
                   tuple(sorted(c.boosts.items())))
            if key in seen:
                rep[i] = seen[key]
                continue
            seen[key] = rep[i] = i
            if (c.hit and c.kind != "aoe") or c.kind == "trap":
                cands.extend((i, a) for a in alive)
            else:
                cands.append((i, None))
        for why, k in sorted(left.items()):
            out["why"].append("%d card%s in hand not tried (%s)" % (k, "" if k == 1 else "s", why))
        # (the bot's own pick - the simulator's chain on your settings: its play among them)
        ch = _Battle.from_state(state, me, foes, opts, random.Random(1))
        pick = ch.choose()
        chain = (None, None)
        if pick is not None:
            pi = next((j for j, c in enumerate(ch.hand) if c is pick), None)
            if pi is not None:
                aim = None
                if (pick.hit and pick.kind != "aoe") or pick.kind == "trap":
                    t = ch.targets(pick if pick.hit else Card("", "damage", heads={"balance": 1}))
                    aim = t[0] if t else None
                chain = (rep.get(pi, pi), aim)
                if chain not in cands:
                    cands.append(chain)
        if state.me_first is None:
            out["why"].append("who goes first isn't known - each way in half the rollouts")
        if not state.pile:
            out["why"].append("no draw pile known - the rollouts play the hand only")
        total0 = float(sum(probe.fhp[i] for i in alive)) or 1.0
        base = seed if seed is not None else random.randrange(1 << 30)
        acc = {c: [] for c in cands}
        active = list(cands)
        deadline = t0 + max(1.0, float(budget_ms)) / 1000.0
        n = max(1, min(int(n), 2000))
        k = 0
        while k < n and active:
            rs = (int(base) * 1000003 + k) & 0xFFFFFFFFFFFF
            for cand in active:
                b = _Battle.from_state(state, me, foes, opts, random.Random(rs))
                i, aim = cand
                r = b.run_from(None if i is None else b.hand[i], aim, horizon)
                acc[cand].append(_rollout(r, b, total0, horizon))
            k += 1
            if time.perf_counter() >= deadline:
                if k < n:
                    out["why"].append("%d rollouts a play in the time given (%d ms)" % (k, budget_ms))
                break
            if k in PLAN_PRUNE and len(active) >= 5:
                ranked = sorted(active, key=lambda c: -statistics.mean(x[3] for x in acc[c]))
                keep = set(ranked[:max(4, (len(ranked) + 1) // 2)]) | {chain, (None, None)}
                active = [c for c in active if c in keep]
        bonus = {}
        if prior is not None:
            try:
                got = prior(situation(state, me, foes)) or ({}, "")
                bonus, out["learned"] = dict(got[0] or {}), str(got[1] or "")
            except Exception as e:  # noqa: BLE001 - planned without it
                out["why"].append("the learned plays couldn't be asked (%r)" % (e,))
        for cand in cands:
            rs = acc[cand]
            if not rs:
                continue
            i, aim = cand
            c = probe.hand[i] if i is not None else None
            kind = c.kind if c is not None else "pass"
            won = [x for x in rs if x[0] == "won"]
            try:
                bn = PRIOR_W * max(-1.0, min(1.0, float(bonus.get(kind) or 0)))
            except (TypeError, ValueError):
                bn = 0.0
            value = statistics.mean(x[3] for x in rs)
            p = {"i": i, "name": c.name if c is not None else "pass", "tid": c.tid if c is not None else None,
                 "kind": kind, "aim": aim, "n": len(rs), "won": len(won) / float(len(rs)),
                 "lost": sum(1 for x in rs if x[0] == "lost") / float(len(rs)),
                 "kill": sum(1 for x in won if x[1] == 1) / float(len(rs)),
                 "rounds": statistics.median(x[1] for x in won) if won else None,
                 "hp_left": statistics.mean(x[2] for x in won) if won else None, "value": value, "bonus": bn,
                 "score": value + bn, "chain": cand == chain}
            p["why"] = _plan_why(p)
            out["plays"].append(p)
        out["plays"].sort(key=lambda p: (-round(p["score"], 9), not p["chain"], p["kind"] == "pass"))
        out["chain"] = next((p for p in out["plays"] if p["chain"]), None)
        out["n"] = out["plays"][0]["n"] if out["plays"] else 0
        if out["plays"] and not any(p["won"] for p in out["plays"]):
            out["why"].append("no play wins within %d rounds - each valued by the enemies' health it takes" % horizon)
    except Exception as e:  # noqa: BLE001 - the plan as far as it got
        out["why"].append("the plan failed (%r)" % (e,))
    out["ms"] = int(round((time.perf_counter() - t0) * 1000))
    return out


def _plan_why(p):
    """a play's reasons in a few words"""
    parts = []
    if p["kill"] >= 0.05:
        parts.append("ends it this round in %d%%" % round(100 * p["kill"]))
    if p["lost"] >= 0.05:
        parts.append("lost in %d%%" % round(100 * p["lost"]))
    if p["chain"]:
        parts.append("your settings' way")
    if p["bonus"]:
        parts.append("learned %+.3f" % p["bonus"])
    return ", ".join(parts) or ("%d rollouts" % p["n"])


def plan_lines(plan, foes, ids=None, top=3):
    """/plan's answer of a plan_round result: plan|i|slot|tid|kind|target|won %|rounds|score|why|name|target's name|n|
    hp left %|kill % for the best play, alt|... (the same fields) for the next top - 1, chain|... for the bot's own pick
    when it isn't the best, learned|why, note|text (plan's why); one none|why when nothing was planned. i: the card's
    place in the game's hand (ids[i] = (place, slot, tid) maps plan_round's i - state.hand's - to the game's; -1 the
    pass); target: the enemy's index in foes ('' the pass, a heal, blade or aura - on me -; 'all' an AoE)"""
    def cell(v):
        return "" if v is None else str(v).replace("|", "/").replace("\n", " ")

    def line(tag, p):
        i = p["i"]
        if i is None:
            gi, slot, tid = -1, "", ""
        elif ids and i < len(ids):
            gi, slot, tid = ids[i]
        else:
            gi, slot, tid = i, "", p.get("tid")
        if p["kind"] == "aoe":
            tgt, tname = "all", "all"
        elif p["aim"] is not None and 0 <= p["aim"] < len(foes):
            tgt, tname = str(p["aim"]), foes[p["aim"]].name
        else:
            tgt, tname = "", ("me" if p["kind"] in ("heal", "blade", "aura") else "")
        return "|".join([tag, str(gi), cell(slot), cell(tid), cell(p["kind"]), tgt, str(int(round(100 * p["won"]))),
                         "" if p["rounds"] is None else _n(p["rounds"]), "%.3f" % p["score"], cell(p["why"]),
                         cell(p["name"]), cell(tname), str(p["n"]),
                         "" if p["hp_left"] is None else str(int(round(p["hp_left"]))), str(int(round(100 * p["kill"])))])
    plays = (plan or {}).get("plays") or []
    if not plays:
        return ["none|" + cell("; ".join((plan or {}).get("why") or []) or "nothing to plan")]
    out = [line("plan", plays[0])] + [line("alt", p) for p in plays[1:max(1, int(top))]]
    ch = (plan or {}).get("chain")
    if ch is not None and ch is not plays[0]:
        out.append(line("chain", ch))
    if plan.get("learned"):
        out.append("learned|" + cell(plan["learned"]))
    for w in plan.get("why") or []:
        out.append("note|" + cell(w))
    return out


# ============================================================================ can this deck beat it
def best_hit(cards, me, foe, opts=None):
    """(name, damage, boosts) - the deck's strongest hit on foe at its least with every blade and trap the deck holds
    that fits it (each kind once - Decks.ahk DeckDamage's way), its resist and your pierce, no critical; (None, 0, [])
    no hit"""
    opts = opts or Opts()
    best = (None, 0.0, [])
    for c in {id(c): c for c in cards if c.hit}.values():
        per = MAX_PIPS if c.x else 1
        total, used = 0.0, set()
        for sch, v in c.heads.items():
            m = damage_multiplier(me.damage) * foe.resist_mult(sch, me.pierce)
            for b in {(x.name, x.kind): x for x in cards if x.kind in ("blade", "trap", "aura")}.values():
                if (b.kind == "blade" and not opts.useblades) or (b.kind == "trap" and not opts.usetraps) \
                        or (b.kind == "aura" and not opts.useaura):
                    continue
                pct = fits(b.boosts, sch)
                if pct:
                    m *= 1 + pct / 100.0
                    used.add(b.name)
            total += v * per * m
        if total > best[1]:
            best = (c.name, total, sorted(used))
    return best


def verdict(res, cards, me, foes, opts=None):
    """{word (yes / likely / risky / no / unknown), text, win, best [name, damage, boosts], hits {foe: best hits to kill
    it}, notes} - "can this deck beat it" from a simulate() result and the deck's best hit"""
    out = {"word": "unknown", "text": "", "win": res.get("won"), "best": None, "hits": {}, "notes": list(res.get("why")
                                                                                                         or [])}
    try:
        if not res.get("n"):
            out["text"] = "not simulated: " + ("; ".join(out["notes"]) or "nothing to go on")
            return out
        win = res["won"]
        out["word"] = next(w for t, w in VERDICTS if win >= t)
        parts = []
        for f in {(f.name, f.maxhp): f for f in foes}.values():
            name, dmg, boosts = best_hit(cards, me, f, opts)
            if name:
                out["best"] = [name, int(dmg), boosts]
                out["hits"][f.name] = math.ceil(f.maxhp / dmg) if dmg > 0 else None
                parts.append("%s%s %d health: %s at its best %d%s - %s hit%s" % (
                    f.name, (" x%d" % len([g for g in foes if g.name == f.name])) if len(
                        [g for g in foes if g.name == f.name]) > 1 else "", f.maxhp, name, dmg, (" with " + ", ".join(boosts)) if boosts else "",
                    out["hits"][f.name], "" if out["hits"][f.name] == 1 else "s"))
            else:
                parts.append("%s %d health: no hit in the deck" % (f.name, f.maxhp))
        if any(f.crit_p is None for f in foes):
            out["notes"].append("an enemy's critical chance isn't known from the battles recorded - its block taken "
                                "as your critical rating (75%% critical chance at x%.2f)" % crit_mult(me.crit, me.crit)
                                if me.crit > 0 else "no critical rating given - no criticals")
        if any(f.spells == [] and not f.hits for f in foes):
            out["notes"].append("an enemy's spells aren't known (a generic hitter assumed)")
        out["notes"].append("shields, enemy heals and boosts aren't modelled - against a boss that shields or heals "
                            "it's optimistic")
        rounds = ("about %s rounds" % _n(res["rounds"])) if res.get("rounds") else "no win"
        out["text"] = "%s: %d%% won, %d%% lost, %d%% ran out (%s; %d battles) - %s" % (
            out["word"], round(100 * win), round(100 * res["lost"]), round(100 * res["timeout"]), rounds, res["n"],
            "; ".join(parts))
    except Exception as e:  # noqa: BLE001
        out["text"] = "the verdict failed (%r)" % (e,)
    return out


def _n(v):
    return ("%d" % v) if float(v).is_integer() else ("%.1f" % v)


# ============================================================================ decks learned from the game
def deck_kinds(deck, facts=None):
    """{kind: copies} of a deckmem deck's cards (main, treasure, the item cards facts know) and the names of special ones
    ({tower, reshuffle, hits [(name, pips, value, aoe)]})"""
    kinds, hits = {}, []
    tower = reshuffle = 0
    for c in list((deck or {}).get("cards") or []) + [dict(c, item=True) for c in (deck or {}).get("item_cards") or []]:
        n = int(c.get("count") or 1)
        name = (c.get("display") or c.get("name") or "")
        if re.search(r"tower\s*shield", name, re.I):
            tower += n
        if re.search(r"reshuffle", name, re.I):
            reshuffle += n
        card = card_of(c, facts)
        if card is None:
            kinds["?"] = kinds.get("?", 0) + n
            continue
        kinds[card.kind] = kinds.get(card.kind, 0) + n
        if card.hit:
            hits.append((card.name, card.pips if not card.x else -1, int(sum(card.heads.values())), card.kind == "aoe", n))
    return kinds, {"tower": tower, "reshuffle": reshuffle, "hits": hits}


def learn_deck(deck, facts=None, n_decks=1):
    """one in-game deck -> a bot deck profile's fields: {gid, name, school, eqset, when [..], vals {key: value}, why} -
    the settings that fit its cards: no blades / traps / auras / heals / Tower Shield / Reshuffle in it: that use off (a
    deck that has them: left to your Settings); its card logic (boost first with 4+ boosts and a big single hit, hit
    first with mostly AoEs and few boosts); what it's for: a boss deck (big single hits and boosts, few AoEs), else
    anything else and collect goals (the only deck: anything else). Never a setting it can't tell"""
    kinds, sp = deck_kinds(deck, facts)
    vals, why = {}, []
    blades, traps = kinds.get("blade", 0), kinds.get("trap", 0)
    auras, heals = kinds.get("aura", 0), kinds.get("heal", 0)
    bubbles = kinds.get("bubble", 0)
    for key, n, what in (("useblades", blades, "blades"), ("usetraps", traps, "traps"), ("useaura", auras, "auras"),
                         ("usebubble", bubbles, "bubbles"), ("useheal", heals, "heals"),
                         ("usetower", sp["tower"], "Tower Shields"), ("usereshuffle", sp["reshuffle"], "Reshuffles")):
        if n == 0:
            vals[key] = 0
            why.append("no %s" % what)
    hits = sp["hits"]
    aoe = sum(h[4] for h in hits if h[3])
    single = sum(h[4] for h in hits if not h[3])
    big = [h for h in hits if not h[3] and (h[1] >= 6 or h[1] < 0)]
    boosts = blades + traps + auras
    if boosts >= 4 and big:
        vals["cardlogic"] = 1
        why.append("%d boosts and a big hit (%s): boost first" % (boosts, big[0][0]))
    elif aoe > single and boosts <= 2:
        vals["cardlogic"] = 2
        why.append("mostly AoEs, %d boost%s: hit first" % (boosts, "" if boosts == 1 else "s"))
    if not hits:
        vals["usehit1"] = vals["usehit2"] = vals["usehit3"] = vals["usehit4"] = 0
        why.append("no hits: a support deck")
    if n_decks <= 1:
        when = ["default"]
    elif big and boosts >= 4 and aoe <= single:
        when = ["boss"]
        why.append("for bosses: big single hits and boosts")
    else:
        when = ["default", "collect"]
    sets = (deck or {}).get("sets") or []
    name = (deck or {}).get("display") or (deck or {}).get("object_name") or "Game deck"
    name = re.sub(r"[^\x20-\x7E]|\|", "", str(name)).strip()[:30] or "Game deck"
    return {"gid": "%x" % deck["gid"] if isinstance((deck or {}).get("gid"), int) else str((deck or {}).get("gid") or ""),
            "name": name, "school": school_of((deck or {}).get("school")) or "any",
            "eqset": sets[0] if sets and 1 <= sets[0] <= 9 else 0, "when": when, "vals": vals,
            "kinds": kinds, "why": "; ".join(why) or "nothing to set: your Settings"}


def learn_decks(reading, facts=None):
    """[learn_deck(...)] of every deck in a deckmem reading that's in an Equipment Set (a set puts it on: the bot can
    use it) - the equipped one too when it's in none (eqset 0: picked, not put on)"""
    decks = [d for d in (reading or {}).get("decks") or [] if d.get("sets") or d.get("equipped")]
    return [learn_deck(d, facts, len(decks)) for d in decks]


def learn_lines(learned):
    """/decks' learn lines: learn|gid|name|school|eqset|when|k=v,k=v|why"""
    out = []
    for L in learned:
        out.append("|".join(["learn", L["gid"], L["name"], L["school"], str(L["eqset"]), ",".join(L["when"]),
                             ",".join("%s=%s" % kv for kv in sorted(L["vals"].items())),
                             L["why"].replace("|", "/")]))
    return out


def sim_lines(res, ver, foes):
    """/sim's answer: sim|won %|lost %|timeout %|rounds|rounds p90|hp left %|damage in a round|first kill|n,
    verdict|word|text, foe|name|health|school|resist (school:mult,...)|block chance|src, cast|name|per battle, note|text"""
    def pc(v):
        return "" if v is None else str(round(100 * v))

    def f(v):
        return "" if v is None else _n(v)
    out = ["|".join(["sim", pc(res.get("won")), pc(res.get("lost")), pc(res.get("timeout")), f(res.get("rounds")),
                     f(res.get("rounds_p90")), f(res.get("hp_left")), f(res.get("dmg_in")), f(res.get("first_kill")),
                     str(res.get("n") or 0)]),
           "|".join(["verdict", ver.get("word") or "unknown", (ver.get("text") or "").replace("|", "/")])]
    for fo in foes:
        out.append("|".join(["foe", fo.name.replace("|", "/"), str(fo.maxhp), fo.school,
                             ",".join("%s:%.2f" % kv for kv in sorted(fo.resist.items())),
                             "" if fo.block_p is None else "%.2f" % fo.block_p, fo.src.replace("|", "/")]))
    for k, v in list((res.get("casts") or {}).items())[:12]:
        out.append("cast|%s|%s" % (k.replace("|", "/"), v))
    for n in ver.get("notes") or []:
        out.append("note|" + n.replace("|", "/"))
    return out


# ============================================================================ the command line
def main(argv=None):
    ap = argparse.ArgumentParser(description="simulate a deck against enemies (a test run)")
    ap.add_argument("--deck", required=True, help="a JSON file: a deckmem deck ({cards: [...]}) or a reading ({decks})")
    ap.add_argument("--foe", action="append", default=[], help="an enemy: name[:health[:school]] (again for more)")
    ap.add_argument("--school", default="")
    ap.add_argument("--hp", type=int, default=3000)
    ap.add_argument("--damage", type=float, default=0)
    ap.add_argument("--pierce", type=float, default=0)
    ap.add_argument("--crit", type=float, default=0)
    ap.add_argument("--resist", type=float, default=0)
    ap.add_argument("-n", type=int, default=400)
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--learn", action="store_true", help="the deck profiles learned from a reading instead")
    a = ap.parse_args(argv)
    with open(a.deck, encoding="utf-8") as fh:
        data = json.load(fh)
    if a.learn:
        print("\n".join(learn_lines(learn_decks(data))))
        return 0
    deck = data
    if "decks" in data:
        deck = next((d for d in data["decks"] if d.get("equipped")), (data["decks"] or [{}])[0])
    why = []
    cards = deck_cards(deck, why=why)
    me = Me(a.school or deck.get("school"), a.hp, damage=a.damage, pierce=a.pierce, crit=a.crit, resist=a.resist)
    book = FoeBook(battles=[])
    foes = []
    for spec in a.foe or ["Enemy:2000"]:
        name, _, rest = spec.partition(":")
        hp, _, sch = rest.partition(":")
        foes.append(book.foe(name, hp=int(hp) if hp.isdigit() else None, school=sch or None))
    res = simulate(cards, me, foes, n=a.n, seed=a.seed)
    res["why"] = why + res["why"]
    print("\n".join(sim_lines(res, verdict(res, cards, me, foes), foes)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
