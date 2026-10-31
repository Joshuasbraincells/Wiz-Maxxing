"""petplan - the PURE decisions of goal 6, "Perfect pets" (TODO.md): which talents you want (AutoFarmer\\pets.txt's want:
line, as the bot passes it - /pets?want=), whether a pet has them all, which pets to keep out of Quick Sell, the pair of
parents covering the most of them, the best snack and when to stop - no memory, no game, no input: every function takes
pets as petmem.PetMem.read gives them ({gid, where, level, talents [names] or None, derby...}) and is tested on stand-ins
(test_petplan.py).

    want = parse_wanted("Spell-Proof, Spell-Defying, Mighty, Pain-Giver, Pain-Bringer")
    has_all(pet, want)          # True / False / None (its talents not read)
    missing(pet, want)          # the wanted talents it lacks ([] none; None not read)
    keepers(pets, want, hatching_on)   # {gid: why} - the pets Quick Sell must not sell
    pick_parents(pets, want)    # (gid a, gid b, [talents covered], [talents still missing]) or None
    best_snack(snacks, pet)     # the snack to feed (gold-bought, never a Crowns one) or None
    stop_reason(...)            # why training / hatching stops now, "" to go on
    pets_answer(r, why, want_text, hatch)   # /pets' lines: petmem.pet_lines + want| + keep|

Talents are matched by name, case, spaces and dashes not counted ("pain giver" is Pain-Giver). A pet's derby talents
count too once they're read. A pet whose talents aren't read (petmem's talents None - not confirmed in the game yet, so
every pet for now) is KEPT: Quick Sell can't tell it from a perfect one (fails safe).

Used by: vision.py /pets (keep| lines - QuickSell.ahk QsPetGuard leaves the Pet group out while a pet to keep is in the
backpack). Not used yet (steps 9-11 need the game's windows first - TODO.md goal 6): pick_parents and best_snack (the
hatchery and the snack shop), stop_reason (the pet game's loop)."""
import re

import petmem as PM

FULL_LEVEL = 6          # Mega: the level a pet's last talent shows by (assumed - one talent at each of Teen ... Mega;
                        # to check in the game) - a pet below it may still show a wanted talent
WANT_CAP = 20           # wanted talents at most


def norm(name):
    """a talent's name for matching: lower case, letters and digits only ("Spell-Proof" -> "spellproof")"""
    return re.sub(r"[^a-z0-9]", "", str(name or "").lower())


def parse_wanted(text):
    """[names] of a wanted-talents text - commas, semicolons, | or line breaks between them; the same talent once (by
    norm), in the order given, WANT_CAP at most; [] none"""
    out, seen = [], set()
    for part in re.split(r"[,;|\r\n]+", str(text or "")):
        nm = re.sub(r"\s+", " ", part).strip()
        if nm and norm(nm) and norm(nm) not in seen:
            seen.add(norm(nm))
            out.append(nm)
    return out[:WANT_CAP]


def talents_of(pet):
    """{norm: name} of a pet's talents and derby talents (those read); None when its talents aren't read"""
    tal = (pet or {}).get("talents")
    if tal is None:
        return None
    out = {norm(t): t for t in tal if norm(t)}
    for t in (pet or {}).get("derby") or []:
        if norm(t):
            out.setdefault(norm(t), t)
    return out


def missing(pet, wanted):
    """the wanted talents the pet lacks, as wanted names them ([] it has every one); None its talents not read"""
    have = talents_of(pet)
    if have is None:
        return None
    return [w for w in wanted if norm(w) not in have]


def has_all(pet, wanted):
    """True: the pet has every wanted talent; False: one or more missing; None: its talents not read, or nothing wanted"""
    if not wanted:
        return None
    m = missing(pet, wanted)
    return None if m is None else not m


def covered(pets, wanted):
    """the wanted talents (as wanted names them) one or more of pets has - the talents not read count as none"""
    have = set()
    for p in pets:
        have |= set(talents_of(p) or {})
    return [w for w in wanted if norm(w) in have]


def pick_parents(pets, wanted, min_level=1):
    """(gid a, gid b, [wanted talents the pair covers], [those still missing]) - the two pets (talents read, level
    min_level or more - the hatchery's own rule isn't known yet) covering the most wanted talents between them; ties to
    the pair with more wanted talents counted on each (two parents with the same one pass it on more surely - an
    assumption), then the higher levels, then the lower gids. None: fewer than two such pets, or nothing wanted"""
    if not wanted:
        return None
    cand = [p for p in pets or [] if talents_of(p) is not None and (p.get("level") or 0) >= min_level and p.get("gid")]
    best = None
    for i, a in enumerate(cand):
        for b in cand[i + 1:]:
            cov = covered([a, b], wanted)
            each = len(covered([a], wanted)) + len(covered([b], wanted))
            key = (len(cov), each, (a.get("level") or 0) + (b.get("level") or 0), -min(a["gid"], b["gid"]))
            if best is None or key > best[0]:
                best = (key, a, b, cov)
    if best is None:
        return None
    _key, a, b, cov = best
    lo, hi = sorted((a["gid"], b["gid"]))
    return lo, hi, cov, [w for w in wanted if w not in cov]


def keepers(pets, wanted, hatching_on=False):
    """{gid: why} - the pets Quick Sell must not sell, wherever they are (QuickSell.ahk looks at the backpack's):
      - its talents not read (petmem's talents None) while talents are wanted: "talents not read - kept to be safe"
      - every wanted talent: "has every wanted talent (...)" - lock it in the game
      - hatching on: every pet below FULL_LEVEL ("in training: ..." - a hatchling's talents show as it's trained, so
        none is ruled out before Mega), and the pair pick_parents chooses ("a parent: ...")
    {} when nothing is wanted and hatching is off (the bot sells pets as before)"""
    out = {}
    if not wanted and not hatching_on:
        return out
    for p in pets or []:
        gid = p.get("gid")
        if not gid:
            continue
        if wanted and talents_of(p) is None:
            out[gid] = "talents not read - kept to be safe"
        elif wanted and has_all(p, wanted):
            out[gid] = "has every wanted talent (%s)" % ", ".join(wanted)
        elif hatching_on and wanted and (p.get("level") or 0) < FULL_LEVEL:
            out[gid] = "in training (%s): %s so far - its other talents still to show" % (
                PM.level_name(p.get("level")) or "level unknown", ", ".join(covered([p], wanted)) or "none wanted")
        elif hatching_on and not wanted:
            out[gid] = "hatching on, no talents wanted - every pet kept"
    pair = pick_parents(pets, wanted) if hatching_on else None
    if pair:
        for g in pair[:2]:
            out.setdefault(g, "a parent: the pair covering %s" % (", ".join(pair[2]) or "none of the wanted talents"))
    return out


def best_snack(snacks, pet):
    """the snack to feed the pet: never a Crowns one (crowns True - or not known: None), the pet's liked categories first
    (pet's likes: [categories]), then the most XP, then the lowest rank (the cheaper snack spent first); None when none
    may be fed. snacks: [{name, xp, category, crowns, rank}] - the snack bag's reading (petmem doesn't read it yet:
    step 10, its fields seen in the game first)"""
    likes = {norm(c) for c in (pet or {}).get("likes") or []}
    ok = [s for s in snacks or [] if s.get("crowns") is False and isinstance(s.get("xp"), (int, float))]
    if not ok:
        return None
    return max(ok, key=lambda s: (norm(s.get("category")) in likes if likes else False, s["xp"],
                                  -(s.get("rank") or 0)))


def stop_reason(pet, wanted, target_level=None, gold=None, gold_floor=None, energy=None, energy_cost=1):
    """why a pet's training or hatching stops now - "" to go on:
      every wanted talent (has_all), the target level reached (target_level 1-7), gold under the floor kept (gold_floor:
      snacks and hatching are paid in gold only - never Crowns), not enough energy for one more game (energy_cost); a
      value not read (None) never stops it by itself - the caller asks again"""
    if wanted and has_all(pet, wanted):
        return "it has every wanted talent (%s)" % ", ".join(wanted)
    lv = (pet or {}).get("level")
    if target_level and isinstance(lv, int) and lv >= target_level:
        return "it's %s - the target (%s)" % (PM.level_name(lv) or lv, PM.level_name(target_level) or target_level)
    if gold_floor is not None and gold is not None and gold < gold_floor:
        return "gold %s is under the %s kept" % (gold, gold_floor)
    if energy is not None and energy < energy_cost:
        return "out of pet energy (%s)" % energy
    return ""


def keep_lines(pets, wanted, hatching_on=False):
    """want|n|names|hatch (1/0), then keep|gid hex|where|why - one a pet keepers() keeps"""
    out = ["want|%d|%s|%d" % (len(wanted), PM._f(", ".join(wanted)), 1 if hatching_on else 0)]
    by_gid = {p.get("gid"): p for p in pets or []}
    for gid, why in keepers(pets, wanted, hatching_on).items():
        out.append("keep|%x|%s|%s" % (gid, PM._f((by_gid.get(gid) or {}).get("where")), PM._f(why)))
    return out


def pets_answer(r, why, want_text="", hatch=False):
    """/pets' answer: petmem.pet_lines of the reading, then keep_lines (want|n|names|hatch, keep|gid hex|where|why) when
    the pets were read - one none|<why> when they weren't"""
    lines = PM.pet_lines(r, why)
    if not r:
        return lines
    return lines + keep_lines(r.get("pets") or [], parse_wanted(want_text), bool(hatch))
