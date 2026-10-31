"""spellplan - PURE planning for TODO goal 4, card quests and spell learning (no game, no navmem: like battlesim.py, it
imports nothing of the game's - tested offline, test_spellplan.py): the training plan file (AutoFarmer\\trainplans.txt),
what to train next with training points, which spells are new in the spellbook, what a new spell would change in a deck,
and when to track a spell quest and go back to the main quest. NOTHING HERE ACTS and nothing the bot does calls it yet:
taking spell quests, visiting trainers and editing decks need window names nobody has seen (Training.ahk's TODOs) - the
bot only reads the spellbook (/book) and logs the new spells. Its inputs are the vision helper's /book and /quests
answers (vision\\deckmem.py book_lines, vision\\questmem.py quest_lines), read back by parse_book / parse_quests.

    plan = parse_plan(open("trainplans.txt").read())   # {schools {school: [entry]}, rules [...], errors [...]}
    e, why, waiting = next_to_train(plan, "storm", known_names, level=20, tp=2)   # the plan's next spell, or None
    new, gone = new_spells(prev_book, book)            # spells in the book now that weren't (template ids)
    changes, notes = deck_changes(deck, book_cards)    # adds / swaps of a deck's main side, within its limits
    action, qid, why = pick_quest(quests, tracked_id, main_id, spell_rule(plan["rules"]))   # keep / track / back

    python spellplan.py [--plan <file>] [--school storm] [--level 20] [--tp 2] [--main <quest id>]
                        [--book book.txt | --live [--fresh [--ob]]] [--quests quests.txt] [--port 47128]
        the plan file checked (each line it can't take, and why), then - with the spellbook (a saved /book answer, or
        --live: asked of the running vision helper on 127.0.0.1, its HTTP only; --fresh reads it now - /book?fresh=1:
        the helper refuses it unless its battle recorder rules a battle out; --ob too: YOU say the wizard is out of
        battle - ob=1, the bot's own claim, the only guard then with the recorder off) -
        what it would train next and why, the plan's spells the book doesn't hold yet (their names are to be checked
        against the game's display names: a spell the wizard knows shows its own in /book), and - with the quests (a
        saved /quests answer, or --live) - the quests the plan's spellquest rules call spell quests and what pick_quest
        would do. Read only: it never sends anything to the game, and a --live ask is a GET of /book and /quests.

THE PLAN FILE (plan_path: yours, AutoFarmer\\learned\\trainplans.txt - kept by updates - when it's there, else the draft
that ships, AutoFarmer\\trainplans.txt - replaced by updates; ; starts a note, blank lines skipped, | between fields, a
field never holds one):
    school|<storm, fire, ice, life, death, myth, balance - or any: for every school>   the plan below is that school's
    train|<spell: the game's display name>|<taught by: its school>|<trainer>|<zone>|<level: the least, ? not known>|
          <cost: training points, ? not known>|<needs: spells first, + between them>|<kind: what it's for>|<checked: 1
          its name, level, cost and needs seen in the game, 0 not yet>
    spellquest|title|<regex>            a quest whose title it finds (any case) is a spell quest
    spellquest|prop|<property>|<value>  a quest whose WizQuestData property (/quests' props) has this value is one
A school's own plan is tried first, in its order, then any's - any's spells its own school teaches left out (those come
with the school, not for training points). A spell is the plan's next when the book doesn't hold it, its needs are all
known, the wizard's level reaches it; it is bought in order: one that costs more than the points there are is saved for
(nothing after it is taken), a level not reached or a need missing is passed by for the next.
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCHOOLS = ("storm", "fire", "ice", "life", "death", "myth", "balance")
# the schools a spell may be taught by (the astral ones and shadow too)
TEACHERS = SCHOOLS + ("sun", "moon", "star", "shadow")
TRAIN_FIELDS = 10       # train| and its 9 fields
# deck_changes' defaults: the kinds it looks at (handmem's), the copies of a new spell wanted, how much stronger a spell
# must be to take a weaker one's place (15%: CardLearn's learnupgrade's), the kinds that must be the deck's own school
KINDS = ("damage", "aoe", "heal", "blade", "trap", "ward", "aura", "absorb")
COPIES = {"damage": 4, "aoe": 4, "heal": 3, "blade": 2, "trap": 2, "ward": 2, "aura": 1, "absorb": 2}
MARGIN = 0.15
OWN_SCHOOL = ("damage", "aoe", "blade", "trap", "aura")
PORT = 47128            # the vision helper's (vision.py PORT)


# ============================================================================ names
def norm(name):
    """a spell's name to match by: any case, punctuation and runs of spaces as one space ("Dr. Purreau" = "dr purreau")"""
    s = (name or "").replace("’", "'").lower()
    s = re.sub(r"[^a-z0-9]+", " ", s.replace("'", ""))
    return s.strip()


def known_keys(book):
    """the norm keys of the spells in a book (entries with display / name, or names)"""
    out = set()
    for e in book or ():
        if isinstance(e, dict):
            for k in ("display", "name"):
                if e.get(k):
                    out.add(norm(e[k]))
        elif e:
            out.add(norm(e))
    out.discard("")
    return out


# ============================================================================ the plan file
def _num(v):
    """a level or cost: an int, None for ? or empty, False when it's neither"""
    v = (v or "").strip()
    if v in ("", "?"):
        return None
    return int(v) if re.fullmatch(r"\d{1,4}", v) else False


def parse_plan(text):
    """{schools {school: [entry]}, rules [("title", regex) | ("prop", name, value)], errors [(line no, line, why)]} of a
    plan file's text (the module's docstring). entry: {spell, key, teacher, trainer, zone, level, cost, needs [names],
    need_keys, kind, checked, line}. A line it can't take is an error (and left out) - the rest are read"""
    plan = {"schools": {}, "rules": [], "errors": []}
    school = None
    for no, raw in enumerate((text or "").splitlines(), 1):
        line = raw.split(";", 1)[0].strip()
        if not line:
            continue
        f = [x.strip() for x in line.split("|")]
        what = f[0].lower()

        def bad(why):
            plan["errors"].append((no, line, why))
        if what == "school":
            s = (f[1] if len(f) > 1 else "").lower()
            if len(f) != 2 or s not in SCHOOLS + ("any",):
                bad("school|<one of %s, or any>" % ", ".join(SCHOOLS))
                school = None
                continue
            school = s
            plan["schools"].setdefault(s, [])
        elif what == "train":
            if school is None:
                bad("a train| line before any (good) school| line")
                continue
            if len(f) != TRAIN_FIELDS:
                bad("train| takes %d fields, not %d" % (TRAIN_FIELDS - 1, len(f) - 1))
                continue
            _t, spell, teacher, trainer, zone, level, cost, needs, kind, checked = f
            teacher = teacher.lower()
            lv, co = _num(level), _num(cost)
            if not norm(spell):
                bad("no spell name")
            elif teacher not in TEACHERS:
                bad("taught by: one of %s" % ", ".join(TEACHERS))
            elif lv is False or co is False:
                bad("level and cost: a number, or ? when not known")
            elif checked not in ("0", "1"):
                bad("checked: 1 (seen in the game) or 0")
            else:
                ns = [n.strip() for n in needs.split("+") if n.strip()]
                plan["schools"][school].append({"spell": spell, "key": norm(spell), "teacher": teacher,
                                                "trainer": trainer, "zone": zone, "level": lv, "cost": co, "needs": ns,
                                                "need_keys": [norm(n) for n in ns], "kind": kind.lower(),
                                                "checked": checked == "1", "line": no})
        elif what == "spellquest":
            how = (f[1] if len(f) > 1 else "").lower()
            if how == "title" and len(f) == 3 and f[2]:
                try:
                    plan["rules"].append(("title", re.compile(f[2], re.IGNORECASE)))
                except re.error as e:
                    bad("spellquest|title: not a regex (%s)" % e)
            elif how == "prop" and len(f) == 4 and re.fullmatch(r"m_\w+", f[2]):
                plan["rules"].append(("prop", f[2], f[3]))
            else:
                bad("spellquest|title|<regex> or spellquest|prop|<m_property>|<value>")
        else:
            bad("not a school|, train| or spellquest| line")
    return plan


def plan_for(plan, school):
    """[entry] tried for a wizard of school: its own plan, then any's (less the spells its own school teaches); [] for a
    school that isn't one"""
    school = (school or "").lower()
    if school not in SCHOOLS:
        return []
    own = list(plan["schools"].get(school) or [])
    keys = {e["key"] for e in own}
    rest = [e for e in plan["schools"].get("any") or [] if e["teacher"] != school and e["key"] not in keys]
    return own + rest


# ============================================================================ what to train next
def next_to_train(plan, school, known, level=None, tp=None, skip=()):
    """(entry, why, waiting) - the plan's next spell for a wizard of school (plan_for's order) that known (the
    spellbook: entries or names) doesn't hold: its needs all known and its level reached (a level not known - the
    wizard's or the plan's - doesn't stop it: why says so); in order - one that costs more than tp (a cost not known: 1)
    is saved for: (None, why, waiting). tp None: not known (why says so). skip: names passed by (tried, failed).
    waiting: [(spell, why)] of those passed by. (None, why, waiting) when there's none to train"""
    have = known_keys(known)
    skips = {norm(s) for s in skip or ()}
    waiting = []
    if (school or "").lower() not in SCHOOLS:
        return None, "the wizard's school isn't known", waiting
    todo = plan_for(plan, school)
    if not todo:
        return None, "no plan for %s (nor for any school)" % school, waiting
    for e in todo:
        if e["key"] in have:
            continue
        if e["key"] in skips:
            waiting.append((e["spell"], "passed by (tried before)"))
            continue
        miss = [n for n, k in zip(e["needs"], e["need_keys"]) if k not in have]
        if miss:
            waiting.append((e["spell"], "needs " + ", ".join(miss) + " first"))
            continue
        if e["level"] is not None and level is not None and level < e["level"]:
            waiting.append((e["spell"], "level %d (the wizard's %d)" % (e["level"], level)))
            continue
        cost = e["cost"] if e["cost"] is not None else 1
        if tp is not None and tp < cost:
            return None, "saving for %s: %d training point%s, %d there" % (e["spell"], cost, "" if cost == 1 else "s",
                                                                           tp), waiting
        notes = []
        if e["level"] is None:
            notes.append("its level isn't in the plan")
        elif level is None:
            notes.append("the wizard's level isn't known")
        if e["cost"] is None:
            notes.append("its cost isn't in the plan (1 taken)")
        if tp is None:
            notes.append("the training points aren't known")
        if not e["checked"]:
            notes.append("the plan's line not checked in the game yet")
        why = "%s (%s, %s in %s)%s" % (e["spell"], e["teacher"], e["trainer"] or "its trainer", e["zone"] or "?",
                                       (" - " + "; ".join(notes)) if notes else "")
        return e, why, waiting
    return None, "every spell of the plan is known" if not waiting else "nothing to train yet", waiting


# ============================================================================ new spells
def _tids(book):
    out = []
    for e in book or ():
        t = e.get("template_id") if isinstance(e, dict) else e
        if t is not None and t != "":
            out.append(int(t))
    return out


def new_spells(prev, book):
    """(new, gone): the entries of book (or template ids) whose template id prev (entries or ids) doesn't hold - in
    book's order -, and the template ids prev holds that book doesn't (sorted)"""
    was, now = set(_tids(prev)), set(_tids(book))
    new = [e for e in book or () if (e.get("template_id") if isinstance(e, dict) else e) not in (None, "")
           and int(e.get("template_id") if isinstance(e, dict) else e) not in was]
    return new, sorted(was - now)


# ============================================================================ a deck's changes
def strength(card):
    """a card's number to compare cards of a kind by: its value (handmem's - a number), else its value_text's ("295-335"
    the middle, "35%", "+35", "+35%"); None when neither tells (an X-pip "N/pip", nothing read)"""
    v = card.get("value")
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        return float(v)
    for t in (v, card.get("value_text")):
        if not isinstance(t, str):
            continue
        t = t.strip()
        m = re.fullmatch(r"(\d+(?:\.\d+)?)\s*-\s*(\d+(?:\.\d+)?)", t)
        if m:
            return (float(m.group(1)) + float(m.group(2))) / 2
        m = re.fullmatch(r"\+?(\d+(?:\.\d+)?)%?", t)
        if m:
            return float(m.group(1))
    return None


def _school(c):
    return (c.get("school") or "").lower()


def deck_changes(deck, book_cards, policy=None):
    """(changes, notes) - what the new spells would change in a deck's MAIN side (deckmem's deck: school, limits
    {max_spells, school_max_copies, generic_max_copies}, cards [{template_id, name, display, school, kind, value,
    value_text, side, count, max_copies}]): each book card (book_cards: /book?kinds=1's - template_id, name, display,
    school, kind, value / value_text, max_copies) of policy's kinds that isn't in it - the kinds that hit or boost (
    OWN_SCHOOL) only of the deck's school - is added (copies: policy's for its kind, within its template's max copies
    and the deck's school / generic max copies) while there's room; with none, it takes the place of the weakest card
    of its kind (and school, for OWN_SCHOOL's) when it is MARGIN stronger (strength - both known): all that card's
    copies out, as many of the new one in as fit. Treasure and item cards are never touched, nor a card of another
    kind, nor one whose strength isn't known. The deck's size or copy limits not known: nothing changed (said).
    changes: [{op (add / remove), template_id, name, kind, count, why}] - in order; notes: [why] of what wasn't.
    policy: {kinds, copies {kind: n}, want (template ids: only these - None every book card), margin, swap (False:
    never take a card's place)}"""
    pol = dict(policy or {})
    kinds = tuple(pol.get("kinds") or KINDS)
    copies = dict(COPIES, **(pol.get("copies") or {}))
    margin = pol.get("margin", MARGIN)
    want = pol.get("want")
    want = None if want is None else {int(t) for t in want}
    swap = pol.get("swap", True)
    changes, notes = [], []
    L = deck.get("limits") or {}
    sch = (deck.get("school") or "").lower()
    main = [dict(c) for c in deck.get("cards") or [] if c.get("side") == "main" and c.get("template_id") is not None]
    if L.get("max_spells") is None or any(L.get(k) is None for k in ("school_max_copies", "generic_max_copies")):
        return changes, ["the deck's size or copy limits weren't read - nothing changed"]
    have = {int(c["template_id"]) for c in main}
    room = L["max_spells"] - sum(int(c.get("count") or 0) for c in main)

    def label(c):
        return c.get("display") or c.get("name") or str(c.get("template_id"))
    cands = []
    for c in book_cards or ():
        if c.get("template_id") is None:
            continue
        tid = int(c["template_id"])
        if tid in have or (want is not None and tid not in want):
            continue
        k = c.get("kind")
        if k not in kinds:
            if want is not None:
                notes.append("%s: a %s - not a kind put in decks here" % (label(c), k or "card of no kind read"))
            continue
        if k in OWN_SCHOOL and (not sch or _school(c) != sch):
            notes.append("%s: a %s %s - only the deck's own school's (%s) go in" % (label(c), _school(c) or "?", k,
                                                                                   sch or "not known"))
            continue
        cands.append(c)
    # (the strongest first - those whose strength isn't known last, in the book's order)
    cands.sort(key=lambda c: (strength(c) is None, -(strength(c) or 0.0)))
    for c in cands:
        tid, k = int(c["template_id"]), c["kind"]
        caps = [copies.get(k, 1), L["school_max_copies"] if _school(c) == sch else L["generic_max_copies"]]
        if c.get("max_copies"):
            caps.append(int(c["max_copies"]))
        n = max(0, min(caps))
        if n <= 0:
            notes.append("%s: no copy allowed in this deck" % label(c))
            continue
        if room >= n:
            changes.append({"op": "add", "template_id": tid, "name": label(c), "kind": k, "count": n,
                            "why": "a %s not in the deck (room for %d)" % (k, room)})
            room -= n
            main.append(dict(c, count=n, side="main"))
            continue
        same = [m for m in main if m.get("kind") == k and (k not in OWN_SCHOOL or _school(m) == sch)
                and int(m["template_id"]) != tid]
        s_new = strength(c)
        known = [m for m in same if strength(m) is not None]
        weakest = min(known, key=strength) if known and len(known) == len(same) else None
        if not swap or weakest is None or s_new is None or s_new < strength(weakest) * (1 + margin):
            why = ("no room (%d free)" % room if not swap or not same else
                   "its strength isn't known" if s_new is None else
                   "a card of its kind with no strength read" if weakest is None else
                   "not %d%% stronger than %s (%g against %g)" % (round(margin * 100), label(weakest), s_new,
                                                                   strength(weakest)))
            if room > 0 and not same:
                changes.append({"op": "add", "template_id": tid, "name": label(c), "kind": k, "count": room,
                                "why": "a %s not in the deck (room for %d of %d)" % (k, room, n)})
                main.append(dict(c, count=room, side="main"))
                room = 0
                continue
            notes.append("%s: not added - %s" % (label(c), why))
            continue
        out_n = int(weakest.get("count") or 0)
        put = min(n, out_n + room)
        changes.append({"op": "remove", "template_id": int(weakest["template_id"]), "name": label(weakest), "kind": k,
                        "count": out_n, "why": "the weakest %s (%g) - %s is stronger (%g)" % (k, strength(weakest),
                                                                                           label(c), s_new)})
        changes.append({"op": "add", "template_id": tid, "name": label(c), "kind": k, "count": put,
                        "why": "in place of %s" % label(weakest)})
        main.remove(weakest)
        main.append(dict(c, count=put, side="main"))
        room += out_n - put
    return changes, notes


# ============================================================================ spell quests
def spell_rule(rules):
    """is_spell(quest) from a plan's spellquest rules: True when a rule finds its title, or its props hold a rule's
    value (as /quests writes it: bools 1/0); no rules: never"""
    rules = list(rules or ())

    def is_spell(q):
        for r in rules:
            if r[0] == "title" and r[1].search(q.get("title") or ""):
                return True
            if r[0] == "prop":
                v = (q.get("props") or {}).get(r[1])
                if v is not None and str(v).strip() == r[2]:
                    return True
        return False
    return is_spell


def _done(q):
    goals = q.get("goals") or []
    return bool(goals) and all(g.get("status") == "COMPLETE" for g in goals)


def pick_quest(quests, tracked_id, main_id, is_spell):
    """(action, quest id, why) - "keep" (nothing to change: a spell quest is tracked, or none is open and the main one
    is - or isn't known), "track" (an open spell quest - the first by id - while another is tracked: remember
    tracked_id as the main quest, track this one), "back" (no spell quest open and main_id, still among the quests,
    isn't tracked: track it again). quests: /quests' rows ({id, title, tracked, goals [{status}], props})"""
    by_id = {q.get("id"): q for q in quests or ()}
    cur = by_id.get(tracked_id)
    if cur is not None and is_spell(cur):
        return "keep", tracked_id, "a spell quest is tracked (%s)" % (cur.get("title") or tracked_id)
    spell = sorted((q for q in quests or () if is_spell(q) and not _done(q)), key=lambda q: q.get("id") or 0)
    if spell:
        q = spell[0]
        return "track", q.get("id"), "spell quest %s is open - track it%s" % (
            q.get("title") or q.get("id"), " (then back to %s)" % ((cur or {}).get("title") or tracked_id)
            if tracked_id is not None else "")
    if main_id is not None and main_id != tracked_id and main_id in by_id:
        return "back", main_id, "no spell quest open - back to %s" % (by_id[main_id].get("title") or main_id)
    return "keep", tracked_id, "no spell quest open"


# ============================================================================ the helper's answers read back
def _fields(line):
    return line.rstrip("\r\n").split("|")


def _int(v):
    v = (v or "").strip()
    return int(v) if re.fullmatch(r"-?\d+", v) else None


def _flag(v):
    v = (v or "").strip()
    return None if v == "" else v == "1"


def parse_book(text):
    """{spells [entry], treasure [entry], n, tc_n, player_gid, ms, why, none} of a /book answer (deckmem.book_lines):
    entry {template_id, name, display, school, type, pips, x_pips, retired, tier_group, kind, value_text} (treasure:
    count for x_pips / retired / tier_group). none: the none| line's why (None when there's none)"""
    out = {"spells": [], "treasure": [], "n": None, "tc_n": None, "player_gid": "", "ms": None, "why": "", "none": None}
    for line in (text or "").splitlines():
        f = _fields(line)
        if f[0] == "none":
            out["none"] = "|".join(f[1:]).strip() or "none"
        elif f[0] == "book" and len(f) >= 12:
            out["spells"].append({"template_id": _int(f[1]), "name": f[2], "display": f[3], "school": f[4],
                                  "type": f[5], "pips": _int(f[6]), "x_pips": _flag(f[7]), "retired": _flag(f[8]),
                                  "tier_group": _int(f[9]), "kind": f[10] or None, "value_text": f[11] or None})
        elif f[0] == "tcbook" and len(f) >= 10:
            out["treasure"].append({"template_id": _int(f[1]), "count": _int(f[2]), "name": f[3], "display": f[4],
                                    "school": f[5], "type": f[6], "pips": _int(f[7]), "kind": f[8] or None,
                                    "value_text": f[9] or None})
        elif f[0] == "books" and len(f) >= 6:
            out.update(n=_int(f[1]), tc_n=_int(f[2]), player_gid=f[3].strip(), why="|".join(f[5:]).strip())
            try:
                out["ms"] = float(f[4])
            except ValueError:
                out["ms"] = None
    return out


def parse_quests(text):
    """{quests [{id, title, tracked, goals [{gid, type, status, count, total, text, mob, item, npc, place, name_key}],
    props {name: value}, title_key}], n, tracked, why, none} of a /quests answer (questmem.quest_lines)"""
    out = {"quests": [], "n": None, "tracked": None, "why": "", "none": None}
    by_id = {}
    for line in (text or "").splitlines():
        f = _fields(line)
        if f[0] == "none":
            out["none"] = "|".join(f[1:]).strip() or "none"
        elif f[0] == "quest" and len(f) >= 8:
            props = {}
            for kv in f[7].split(","):
                k, eq, v = kv.partition("=")
                if eq and k.strip():
                    props[k.strip()] = v.strip()
            q = {"id": _int(f[1]), "title": f[2], "tracked": f[3] == "1", "goals": [], "title_key": f[6],
                 "props": props}
            out["quests"].append(q)
            by_id[q["id"]] = q
        elif f[0] == "goal" and len(f) >= 13:
            q = by_id.get(_int(f[1]))
            if q is not None:
                q["goals"].append({"gid": _int(f[2]), "type": f[3], "status": f[4], "count": _int(f[5]),
                                   "total": _int(f[6]), "text": f[7], "mob": f[8], "item": f[9], "npc": f[10],
                                   "place": f[11], "name_key": f[12]})
        elif f[0] == "quests" and len(f) >= 5:
            out.update(n=_int(f[1]), tracked=_int(f[2]), why="|".join(f[4:]).strip())
    return out


# ============================================================================ the command line
def ask_helper(path, port=PORT, timeout=15.0, opener=None):
    """(the running vision helper's answer to GET path, "") or (None, why) - 127.0.0.1 only, no proxy"""
    import urllib.request
    try:
        op = opener or urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with op.open("http://127.0.0.1:%d%s" % (port, path), timeout=timeout) as r:
            return r.read().decode("utf-8", "replace"), ""
    except Exception as e:  # noqa: BLE001 - said
        return None, "the vision helper didn't answer %s (%s) - is the bot running?" % (path, e)


def report(plan, school, level=None, tp=None, book=None, quests=None, main_id=None):
    """the command line's lines for a parsed plan, a parse_book reading (or None) and a parse_quests one (or None)"""
    out = []
    n_school = {s: len(v) for s, v in plan["schools"].items()}
    out.append("plan: %s; %d spell-quest rule(s); %d line(s) not taken" % (
        ", ".join("%s %d" % kv for kv in sorted(n_school.items())) or "no school", len(plan["rules"]),
        len(plan["errors"])))
    for no, line, why in plan["errors"]:
        out.append("  line %d: %s  <- %s" % (no, line, why))
    mine = (school or "").lower() in SCHOOLS
    pool = plan_for(plan, school) if mine else [e for v in plan["schools"].values() for e in v]
    if mine:
        out.append("the plan for %s, in order: %s" % (school.lower(), ", ".join(e["spell"] for e in pool) or "nothing"))
    unchecked = list(dict.fromkeys(e["spell"] for e in pool if not e["checked"]))
    if unchecked:
        out.append("not checked in the game yet (checked 0): %d - %s" % (len(unchecked), ", ".join(unchecked)))
    if book is not None:
        if book.get("none"):
            out.append("book: not read - %s" % book["none"])
        else:
            spells = book["spells"]
            have = known_keys(spells)
            out.append("book: %d spells known%s" % (len(spells), " (wizard %s)" % book["player_gid"]
                                                    if book.get("player_gid") else ""))
            todo = plan_for(plan, school)
            known_plan = [e["spell"] for e in todo if e["key"] in have]
            not_yet = [e["spell"] for e in todo if e["key"] not in have]
            if known_plan:
                out.append("  the plan's spells known: " + ", ".join(known_plan))
            if not_yet:
                out.append("  the plan's spells not in the book (check each name against the game's - the trainer's "
                           "window, or /book once learned): " + ", ".join(not_yet))
            e, why, waiting = next_to_train(plan, school, spells, level, tp)
            out.append("next to train: %s" % why)
            for sp, w in waiting:
                out.append("  passed by: %s - %s" % (sp, w))
    if quests is not None:
        if quests.get("none"):
            out.append("quests: not read - %s" % quests["none"])
        else:
            is_spell = spell_rule(plan["rules"])
            spell = [q for q in quests["quests"] if is_spell(q)]
            out.append("quests: %d (tracked %s); spell quests by the plan's rules: %s" % (
                len(quests["quests"]), quests.get("tracked"),
                ", ".join("%s [%s]" % (q["title"] or "?", q["id"]) for q in spell) or
                ("none" if plan["rules"] else "none - the plan has no spellquest| rule yet")))
            action, qid, why = pick_quest(quests["quests"], quests.get("tracked"), main_id, is_spell)
            out.append("pick_quest: %s %s - %s" % (action, qid, why))
    return out


def plan_path(root=None):
    """the plan file: yours - learned\\trainplans.txt, kept by updates - when there is one, else the draft that ships
    with the bot (AutoFarmer\\trainplans.txt, replaced by updates: puzzles_known.txt's way)"""
    root = root or os.path.join(HERE, "..")
    mine = os.path.join(root, "learned", "trainplans.txt")
    return mine if os.path.isfile(mine) else os.path.join(root, "trainplans.txt")


def _main(argv=None):
    ap = argparse.ArgumentParser(description="the training plan checked, and what it would train / which quest it would "
                                             "track - read only (nothing is sent to the game)")
    ap.add_argument("--plan", default="", help="the plan file (else learned\\trainplans.txt, else trainplans.txt)")
    ap.add_argument("--school", default="", help="the wizard's school")
    ap.add_argument("--level", type=int, default=None, help="the wizard's level")
    ap.add_argument("--tp", type=int, default=None, help="training points there")
    ap.add_argument("--main", type=int, default=None, help="the main quest's id (pick_quest's way back)")
    ap.add_argument("--book", default="", help="a saved /book answer")
    ap.add_argument("--quests", default="", help="a saved /quests answer")
    ap.add_argument("--live", action="store_true", help="ask the running vision helper for /book and /quests")
    ap.add_argument("--fresh", action="store_true", help="with --live: the spellbook read now (refused by the helper "
                    "unless its battle recorder rules a battle out)")
    ap.add_argument("--ob", action="store_true", help="with --fresh: you say the wizard is out of battle (ob=1 - with "
                    "the battle recorder off, nothing else keeps the read out of a battle)")
    ap.add_argument("--port", type=int, default=PORT, help="the vision helper's port")
    a = ap.parse_args(argv)
    path = a.plan or plan_path()
    try:
        with open(path, encoding="utf-8-sig") as f:
            plan = parse_plan(f.read())
    except OSError as e:
        print("the plan file can't be read (%s)" % e)
        return 2
    print("plan file: %s" % os.path.abspath(path))
    book = quests = None
    if a.book:
        with open(a.book, encoding="utf-8-sig") as f:
            book = parse_book(f.read())
    if a.quests:
        with open(a.quests, encoding="utf-8-sig") as f:
            quests = parse_quests(f.read())
    if a.live:
        if book is None:
            # (ob=1 only when you say so - --ob: it's the bot's claim that its own battle check passed, and with the
            # battle recorder off it's the helper's only guard against a read in a battle)
            text, why = ask_helper(("/book?fresh=1&ob=1" if a.ob else "/book?fresh=1") if a.fresh else "/book", a.port)
            book = parse_book(text) if text is not None else {"none": why}
            if a.fresh and not a.ob and "recorder" in (book.get("none") or ""):
                book["none"] += " - add --ob if the wizard is out of battle"
        if quests is None:
            text, why = ask_helper("/quests", a.port)
            quests = parse_quests(text) if text is not None else {"none": why}
    print("\n".join(report(plan, a.school, a.level, a.tp, book, quests, a.main)))
    return 0


if __name__ == "__main__":
    sys.exit(_main())
