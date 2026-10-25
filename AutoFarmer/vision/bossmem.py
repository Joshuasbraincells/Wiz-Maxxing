"""bossmem - READ-ONLY reader of the zone's mobs' TITLE (Boss / Elite / Normal / Easy / Minion), RANK, starting (max)
HEALTH and SCHOOL in a running Wizard101 client (WizardGraphicalClient.exe), and in a battle of every participant's health,
max health, boss flag and level - for picking the boss deck BEFORE the fight (Alt+1 only names the boss inside the battle,
too late: the game can't change the in-game deck mid-battle). navmem.py makes one per game (in a thread, like the hand's
and the quest's readers) for the vision helper's /mobs (each mob's title, rank, health, school, boss flag) and /battle.

    bm = BossMem(st, log=print)        # st: navmem's attached game (navmem._Attached); about half a second, once per game
    info, why = bm.mob(obj)            # a mob's ClientObject (navmem's objects thread) -> {title, boss, rank, health, ...}
    parts, why = bm.battle(hm)         # in a battle (hm: handmem.HandMem): [{owner, me, team, health, max_health, boss...}]

    mobs, why = navmem.NavMem().mobs()     # the zone's mobs with title, rank, health, school, boss, kind (navmem's way)
    parts, why = navmem.NavMem().battle()  # the battle's participants, each joined to its mob (name, title, rank)

    python bossmem.py [-n 1] [-i 2] [--battle SECONDS] [--duel] [--json]     readings from the command line

SAFETY. The game is opened by navmem.py's Proc - PROCESS_VM_READ | PROCESS_QUERY_INFORMATION (falling back to
PROCESS_VM_READ | PROCESS_QUERY_LIMITED_INFORMATION) and nothing else - and only read: ReadProcessMemory, plus
VirtualQueryEx / QueryWorkingSetEx and the module / toolhelp enumeration navmem.py uses. Nothing is ever written,
allocated, injected, hooked, suspended or debugged; no window is touched and no input is sent. Every class and property
offset is found by NAME in a copy of the game's code (its reflection registration: handmem.Image / questmem.class_props);
every object is checked by its vtable before it's used.

FAILS SOFT. mob() and battle() never raise: (None, why) when it can't be read; a value that can't be read for sure is
None, never a guess. The constructor raises LookupError when a reflected class or property isn't in this build (navmem
answers (None, why) then, and tries again after a while).

WHAT IS READ (build 6A9721E9-370E000, 2026-10-25 - every offset found by name each attach; the numbers are what they were):

  mob      the mob's ClientObject (navmem's objects thread: its vtable, global id and zone checked at each read)
             CoreObject.m_inactiveBehaviors (+0xE0): std::vector<SharedPointer<BehaviorInstance>> (16 bytes each)
             -> the NPCBehavior: the element whose vtable is one of NPCBehavior's (its GetType's - the type namer can't
                name it: its name is loaded too far into GetType)
             BehaviorInstance +0x48 its object (== the mob: checked), +0x58 its template - not reflected: checked (the
                object / the NPCBehaviorTemplate vtable) at each read, looked for in another build, kept once 2 mobs agree
             -> NPCBehaviorTemplate (CoreTemplate's m_behaviors list keeps no copy - its slot is empty client-side):
                m_nStartingHealth +0x78 (int), m_HideCurrentHP +0x7C (bool), m_nLevel +0x80 (the RANK), m_bossMob +0x90
                (bool: the same flag a battle's CombatParticipant.m_bossMob carries), m_mobTitle +0x94 (enum),
                m_schoolOfFocus +0xA0 / m_secondarySchoolOfFocus +0xC8 (std::string), m_maxShadowPips +0x110,
                m_minionLevel +0x128, m_fIntelligence / m_fSelfishFactor / m_nAggressiveFactor (its AI);
                m_baseEffects +0x118: std::list of StartingPipEffectInfo / StatisticEffectInfo ("CanonicalStormReduceDamage"
                - a resist looked up by level, its number isn't here); m_triggerList (the cheats) is empty client-side
  titles   m_mobTitle's options, decoded from NPCBehaviorTemplate's registration code: each option's code ends with a LEA
             of a copy of "m_mobTitle"; its name is the string just before that copy in .rdata ("Easy", "Elite", "Boss",
             "Minion") or, pooled elsewhere, the string its code loads ("Normal"); its value the store to the one stack
             slot every option writes 0..n-1 to (mov dword [rbp-9], imm32 / a zero register) -
             Easy 0, Normal 1, Elite 2, Boss 3, Minion 4; checked (Boss and Elite there, values distinct). Not decoded:
             the known table in this build only; in another no title at all (the boss from m_bossMob alone)
             (all 188 NPCBehaviorTemplates in the heap, 2026-10-25: (title, boss flag) (Easy, 0) x111 - NPCs -, (Normal,
             0) x75, (Boss, 1) x2: a Boss title always came with the boss flag)
  battle   the GUI's CombatantDataControl windows ("CombatantControl", one per participant: under handmem's root) -> the
             ClientCombatParticipant in each (by vtable; +0x760 now) - and handmem's own (SpellSelection +0x358):
             CombatParticipant m_ownerID.m_full (the mob's global id -> its ClientObject -> the above), m_templateID.m_full,
             m_isPlayer, m_teamID, m_primaryMagicSchoolID, m_playerHealth, m_maxPlayerHealth, m_HideCurrentHP, m_bossMob,
             m_mobLevel (the level its stats are figured at - 40 for a rank 9 boss against a level-40 wizard: not the
             rank), m_isMonster, m_isMinion, m_minionStartingHealth
  duel     (--duel: a cross-check) the zone object (the sigil) holding a WizardClientDuelBehavior -> DuelBehavior.m_pDuel
             +0x70 -> ClientDuel: m_flatParticipantList +0x50 (std::vector<SharedPointer<CombatParticipant>>) holds my
             participant; m_roundNum, m_duelPhase. A participant leaves the list when it's defeated
"""
import json
import os
import re
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import navmem as N                   # noqa: E402
import handmem as H                  # noqa: E402
import questmem as Q                 # noqa: E402

BOSS_BUILD = "6A9721E9-370E000"
KNOWN = {"beh_owner": 0x48, "beh_template": 0x58, "cdc_participant": 0x760}
NEED = {"CoreObject": ("m_inactiveBehaviors", "m_globalID.m_full"),
        "NPCBehaviorTemplate": ("m_nStartingHealth", "m_nLevel", "m_bossMob", "m_mobTitle", "m_schoolOfFocus"),
        "CombatParticipant": ("m_ownerID.m_full", "m_templateID.m_full", "m_isPlayer", "m_teamID",
                              "m_primaryMagicSchoolID", "m_playerHealth", "m_maxPlayerHealth", "m_bossMob", "m_mobLevel"),
        "GameObjectTemplate": ("m_objectName", "m_displayName"),
        "WizGameObjectTemplate": ("m_primarySchoolName",),
        "DuelBehavior": ("m_pDuel",),
        "Duel": ("m_flatParticipantList", "m_roundNum", "m_duelPhase")}
VT_CLASSES = ("NPCBehavior", "NPCBehaviorTemplate", "ClientCombatParticipant", "CombatantDataControl",
              "WizardClientDuelBehavior", "ClientDuelBehavior", "DuelBehavior", "ClientDuel", "Duel")
TITLES_KNOWN = {0: "Easy", 1: "Normal", 2: "Elite", 3: "Boss", 4: "Minion"}
SCHOOLS = {"Fire", "Ice", "Storm", "Myth", "Life", "Death", "Balance", "Star", "Sun", "Moon", "Shadow", "Gardening",
           "Fishing", "Cantrips", "Castlemagic", "WhirlyBurly", ""}
SCHOOL_IDS = H.SCHOOL_IDS
RESCAN_EVERY = 5.0
# what navmem puts on each of its mobs from mob()'s info (None each when it isn't known)
FIELDS = ("title", "title_id", "rank", "health", "school", "boss", "kind")


# ============================================================================ the title enum, from the code
def mob_titles(img, gt, prop="m_mobTitle", lim=0x3000):
    """{value: name} of an enum property whose options register inline after gt (NPCBehaviorTemplate's GetType): each
    option's code ends with a LEA of a copy of prop's name; its name: the identifier just before that copy in .rdata, or
    (pooled elsewhere) the identifier its code loads RIP-relative; its value: the store to the one [rbp+d8] / [rsp+d8]
    slot that every option writes and whose values are 0..n-1 (the other common slots: the name's length and capacity,
    a 1 << value bit). {} when it doesn't read that way"""
    r0, rdata = img.secs[".rdata"]
    copies = set(img.strings(prop))
    code = img.code_at(gt, lim)
    if not copies or not code:
        return {}
    leas = []
    for m in re.finditer(rb"[\x48\x4C]\x8D[\x15\x05](....)", code, re.DOTALL):
        tgt = gt + m.start() + 7 + struct.unpack("<i", m.group(1))[0]
        if tgt in copies:
            leas.append((m.start(), tgt))
    if len(leas) < 3:
        return {}

    def word_at(a):
        s = img.rdata_str(a, 40)
        return s.decode() if re.fullmatch(rb"[A-Za-z][A-Za-z0-9_]*", s or b"") and not s.startswith(b"m_") else None

    def word_before(a):
        i = a - r0 - 1                       # (the NULs before the copy, then the string before them)
        while i > 0 and rdata[i] == 0:
            i -= 1
        j = i
        while j > 0 and 0x20 <= rdata[j - 1] < 0x7F:
            j -= 1
        return word_at(r0 + j) if i - j < 40 else None

    # mov dword [rsp+d8] / [rbp+d8], imm32 (not a REX.W qword store: a string's size / capacity), or esi / r14d kept at
    # zero (mov [rsp+d8] / [rbp+d8], esi|r14d)
    store = re.compile(rb"(?<![\x48\x49\x4C\x4D])\xC7\x44\x24(.)(....)|(?<![\x48\x49\x4C\x4D])\xC7\x45(.)(....)|"
                       rb"(?<![\x48\x49\x4C\x4D])\x89\x74\x24(.)|(?<![\x48\x49\x4C\x4D])\x89\x75(.)", re.DOTALL)
    segs = []
    for (a, _), (b, tgt) in zip(leas, leas[1:]):
        seg_at = a + 7
        seg = code[seg_at:b]
        name = word_before(tgt)
        if name is None:
            for m in re.finditer(rb"(?:\x8B\x05|\x0F\xB7\x05|\x0F\xB6\x05|[\x48\x4C]\x8B\x05|\x8B[\x0D\x15\x1D])(....)",
                                 seg, re.DOTALL):
                t = gt + seg_at + m.end() + struct.unpack("<i", m.group(1))[0]
                if img.m.in_section(t, ".rdata") and rdata[t - r0 - 1] == 0 and word_at(t):
                    name = word_at(t)
                    break
        slots = {}
        for m in store.finditer(seg):
            g = m.groups()
            if g[0] is not None:
                slots.setdefault(("rsp", g[0][0]), struct.unpack("<i", g[1])[0])
            elif g[2] is not None:
                slots.setdefault(("rbp", g[2][0]), struct.unpack("<i", g[3])[0])
            elif g[4] is not None:
                slots.setdefault(("rsp", g[4][0]), 0)           # (a register kept at zero: esi / r14d)
            else:
                slots.setdefault(("rbp", g[5][0]), 0)
        segs.append((name, slots))
    # the first LEA is the property's own registration (no option before it): options are the segments with a name
    opts = [(n, s) for n, s in segs if n]
    if len(opts) < 2:
        return {}
    common = set.intersection(*(set(s) for _, s in opts))
    for slot in sorted(common, key=lambda sl: (sl[0], sl[1] - 256 if sl[1] >= 128 else sl[1])):
        vals = [s[slot] for _, s in opts]
        if sorted(vals) == list(range(len(vals))):
            return {v: n for v, (n, _) in zip(vals, opts)}
    return {}


def parse_template(raw, lo, NB, titles, string_at=None):
    """{title, title_id, boss, kind, rank, health, hide_hp, school, school2, max_shadow_pips, minion_level, ai} of an
    NPCBehaviorTemplate's bytes raw (read from its +lo; NB its reflected {property: offset}; titles the m_mobTitle
    names; string_at(property) its std::string, or None) - each value in its sane range, else None (never a guess):
    title 0..15 (its name from titles - "" none known for that value: None), rank 0..200, health 1..10,000,000, flags 0/1,
    school one of the game's. kind: what the deck goes by - "boss" when the game's own boss flag is set (or the title is
    Boss), else the title in lower case ("elite", "normal", "easy", "minion"), "normal" with no title but the boss flag
    clear, None not known"""
    def at(k, n):
        i = NB[k] - lo if k in NB else -1
        return i if 0 <= i and i + n <= len(raw) else None

    def i32(k):
        i = at(k, 4)
        return struct.unpack_from("<i", raw, i)[0] if i is not None else None

    def u8(k):
        i = at(k, 1)
        return raw[i] if i is not None else None

    def f32(k):
        i = at(k, 4)
        if i is None:
            return None
        v = struct.unpack_from("<f", raw, i)[0]
        return round(v, 3) if v == v and abs(v) < 1e9 else None

    s = string_at or (lambda k: None)
    title_id, boss, rank, health, hide = i32("m_mobTitle"), u8("m_bossMob"), i32("m_nLevel"), i32("m_nStartingHealth"), \
        u8("m_HideCurrentHP")
    school, school2 = s("m_schoolOfFocus"), s("m_secondarySchoolOfFocus")
    ok_title = title_id is not None and 0 <= title_id < 16
    info = {"title_id": title_id if ok_title else None,
            "title": (titles.get(title_id) if ok_title else None),
            "boss": bool(boss) if boss in (0, 1) else None,
            "rank": rank if rank is not None and 0 <= rank <= 200 else None,
            "health": health if health is not None and 0 < health <= 10000000 else None,
            "hide_hp": bool(hide) if hide in (0, 1) else None,
            "school": school if school in SCHOOLS else None,
            "school2": school2 if school2 in SCHOOLS else None,
            "max_shadow_pips": i32("m_maxShadowPips"), "minion_level": i32("m_minionLevel"),
            "ai": {"intelligence": f32("m_fIntelligence"), "selfish": f32("m_fSelfishFactor"),
                   "aggressive": i32("m_nAggressiveFactor")}}
    t_name = info["title"]
    info["kind"] = ("boss" if info["boss"] or t_name == "Boss" else (t_name or "").lower() or
                    ("normal" if info["boss"] is False else None))
    return info


# ============================================================================ the reader
class BossMem:
    """the zone's mobs' title / rank / health / school, and the battle's participants - see the top. Not thread-safe:
    call it under navmem's lock (as handmem / questmem)"""

    def __init__(self, st, log=None):
        self.log = log or (lambda msg: None)
        t0 = time.perf_counter()
        self.st, self.p, self.build = st, st.p, st.m.build
        img = H.Image(st)
        props = {c: Q.class_props(img, c) for c in set(NEED) | set(VT_CLASSES)}
        self.P = {c: {k: v[0] for k, v in props[c][0].items()} for c in props}
        missing = [c + "." + k for c, ks in NEED.items() for k in ks if k not in self.P[c]]
        if missing:
            raise LookupError("reflected properties not found in this build (%s): %s" % (self.build, ", ".join(missing)))
        self.vt = {c: set(props[c][2]) for c in VT_CLASSES}
        none = [c for c in ("NPCBehavior", "NPCBehaviorTemplate", "ClientCombatParticipant") if not self.vt[c]]
        if none:
            raise LookupError("reflected classes not found in this build (%s): %s" % (self.build, ", ".join(none)))
        titles = mob_titles(img, props["NPCBehaviorTemplate"][1])
        if {"Boss", "Elite"} <= set(titles.values()) and len(set(titles.values())) == len(titles):
            self.titles, self.how_titles = titles, "decoded from the code"
        elif self.build == BOSS_BUILD:
            self.titles, self.how_titles = dict(TITLES_KNOWN), "the known table (the code didn't decode: %r)" % (titles,)
        else:
            self.titles, self.how_titles = {}, "unknown (the code didn't decode: %r) - boss by m_bossMob only" % (titles,)
        del img, props
        self.o = {}                  # places found and kept (the non-reflected ones)
        self._cand = {}              # key -> {offset: {objects}} waiting for a second object
        self._next = {}
        self.cache = {}              # NPCBehaviorTemplate address -> (its vtable, its info)
        self.mismatch = set()        # templates whose title and boss flag disagree (logged once)
        self.attach_s = time.perf_counter() - t0
        self.log("bossmem: ready in %.2f s - titles %s (%s)" % (self.attach_s, self.titles, self.how_titles))

    # ------------------------------------------------------------------ small readers
    def u64(self, a):
        b = self.p.try_read(a, 8) if N.ptr_ok(a) else None
        return struct.unpack("<Q", b)[0] if b else 0

    def vec(self, a, limit=128):
        """the objects of a std::vector<SharedPointer<T>> at a (begin, end: 16-byte elements)"""
        b = self.p.try_read(a, 16) if N.ptr_ok(a) else None
        if not b:
            return []
        x, y = struct.unpack("<QQ", b)
        if not (N.ptr_ok(x) and x <= y <= x + 16 * limit and (y - x) % 16 == 0):
            return []
        raw = self.p.try_read(x, y - x) or b""
        return [struct.unpack_from("<Q", raw, i)[0] for i in range(0, len(raw) - 7, 16)]

    def _due(self, key):
        now = time.monotonic()
        if now < self._next.get(key, 0):
            return False
        if len(self._next) > 2000:
            self._next.clear()
        self._next[key] = now + RESCAN_EVERY
        return True

    def _place(self, key, base, size, ok):
        """(the value at base + the place kept for key - KNOWN's first - when ok(value), the offset if not kept yet): in
        another build looked for in base's first size bytes (at most every RESCAN_EVERY s per object) and kept once two
        different objects agree"""
        off = self.o.get(key, KNOWN[key])
        v = self.u64(base + off)
        if ok(v):
            return v, None
        if self.build == BOSS_BUILD or not self._due(key + "%x" % base):
            return 0, None
        raw = self.p.try_read(base, size) or b""
        for i in range(0, len(raw) - 7, 8):
            v = struct.unpack_from("<Q", raw, i)[0]
            if ok(v):
                seen = self._cand.setdefault(key, {}).setdefault(i, set())
                seen.add(base)
                if len(seen) >= 2:
                    self.o[key] = i
                    self._cand.pop(key, None)
                    self.log("bossmem: %s found at +%#x" % (key, i))
                return v, i
        return 0, None

    # ------------------------------------------------------------------ a mob
    def npc_template(self, obj):
        """(the NPCBehaviorTemplate of the mob obj, why): its NPCBehavior among CoreObject.m_inactiveBehaviors (by
        vtable), whose object is obj and whose template is an NPCBehaviorTemplate (by vtable)"""
        beh = [b for b in self.vec(obj + self.P["CoreObject"]["m_inactiveBehaviors"]) if self.u64(b) in self.vt["NPCBehavior"]]
        if not beh:
            return 0, "no NPCBehavior"
        b = beh[0]
        owner, _ = self._place("beh_owner", b, 0x100, lambda v: v == obj)
        if owner != obj:
            return 0, "its NPCBehavior isn't the mob's"
        t, _ = self._place("beh_template", b, 0x100, lambda v: N.ptr_ok(v) and self.u64(v) in self.vt["NPCBehaviorTemplate"])
        return (t, "") if t else (0, "no NPCBehaviorTemplate")

    def template_info(self, t):
        """parse_template of an NPCBehaviorTemplate (kept per template: they don't change while the game runs - its
        vtable checked each time)"""
        vt = self.u64(t)
        hit = self.cache.get(t)
        if hit and hit[0] == vt:
            return hit[1]
        NB = self.P["NPCBehaviorTemplate"]
        lo = min(NB.values())
        hi = max(NB.values()) + 8
        raw = self.p.stable(t + lo, hi - lo)          # (read until two reads agree)
        info = parse_template(raw, lo, NB, self.titles,
                              lambda k: self.p.try_string(t + NB[k]) if k in NB else None)
        # (the kind the deck goes by: the game's own boss flag first - the battle's CombatParticipant carries it too)
        t_name = info["title"]
        if info["boss"] is not None and t_name is not None and info["boss"] != (t_name == "Boss") and t not in self.mismatch:
            self.mismatch.add(t)
            self.log("bossmem: template %#x title %s but boss flag %s" % (t, t_name, info["boss"]))
        if len(self.cache) > 5000:
            self.cache.clear()
        self.cache[t] = (vt, info)
        return info

    def mob(self, obj):
        """(info, why) of the mob ClientObject obj: template_info plus the game object template's name and school.
        Never raises"""
        try:
            t, why = self.npc_template(obj)
            if not t:
                return None, why
            info = dict(self.template_info(t))
            tpl = self.u64(obj + N.DATA["co_template"])
            if N.ptr_ok(tpl) and (self.st.tn.of(tpl) or "").endswith("Template"):
                info["template"] = self.p.try_string(tpl + self.P["GameObjectTemplate"]["m_objectName"])
                info["display_key"] = self.p.try_string(tpl + self.P["GameObjectTemplate"]["m_displayName"])
                ts = self.p.try_string(tpl + self.P["WizGameObjectTemplate"]["m_primarySchoolName"])
                info["template_school"] = ts
                if info["school"] in (None, "") and ts in SCHOOLS:
                    info["school"] = ts
            return info, ""
        except Exception as e:  # noqa: BLE001 - never into the caller
            return None, "the mob couldn't be read (%r)" % (e,)

    # ------------------------------------------------------------------ a battle
    def participant(self, c):
        """{owner, template_id, player, team, school_id, school, health, max_health, hide_hp, boss, mob_level, monster,
        minion, minion_health} of a ClientCombatParticipant c (checked by vtable), or None"""
        if not (N.ptr_ok(c) and self.u64(c) in self.vt["ClientCombatParticipant"]):
            return None
        CP = self.P["CombatParticipant"]
        hi = max(CP.values()) + 8
        raw = self.p.try_read(c, hi)
        if not raw:
            return None
        i32 = lambda k: struct.unpack_from("<i", raw, CP[k])[0] if k in CP else None    # noqa: E731
        u8 = lambda k: raw[CP[k]] if k in CP else None                                     # noqa: E731
        q = lambda k: struct.unpack_from("<Q", raw, CP[k])[0] if k in CP else None        # noqa: E731
        tid = q("m_templateID.m_full")
        hp, most = i32("m_playerHealth"), i32("m_maxPlayerHealth")
        return {"addr": c, "owner": q("m_ownerID.m_full"), "template_id": tid & 0xFFFFFFFF if tid else None,
                "player": bool(u8("m_isPlayer")), "team": i32("m_teamID"), "school_id": i32("m_primaryMagicSchoolID") & 0xFFFFFFFF,
                "school": SCHOOL_IDS.get(i32("m_primaryMagicSchoolID") & 0xFFFFFFFF, ""),
                "health": hp if hp is not None and -100000 <= hp <= 10000000 else None,
                "max_health": most if most is not None and 0 < most <= 10000000 else None,
                "hide_hp": bool(u8("m_HideCurrentHP")), "boss": bool(u8("m_bossMob")), "mob_level": i32("m_mobLevel"),
                "monster": bool(u8("m_isMonster")), "minion": bool(u8("m_isMinion")),
                "minion_health": i32("m_minionStartingHealth")}

    def combatant_windows(self, hm):
        """the GUI's CombatantDataControl windows under handmem's root (one per participant)"""
        root = hm.root()
        if not root or not self.vt["CombatantDataControl"]:
            return []
        out, stack = [], [(root, 0)]
        while stack and len(out) < 32:
            w, d = stack.pop()
            if hm._vt(w) in self.vt["CombatantDataControl"]:
                out.append(w)
                continue
            if d < 8:
                stack.extend((k, d + 1) for k in hm.kids(w))
        return out

    def battle(self, hm):
        """([participant + {me, shown, window, source}], why) - every participant the battle's GUI shows (its
        CombatantDataControl windows) and mine (handmem's) - in a battle's planning phase only: ([], why) out of a battle
        (the spell selection window keeps the wizard's participant out of a battle too - 2026-10-25: so the planning
        window has to show, and the battle's own windows have to hold a participant). Never raises"""
        try:
            pp, ss, hand = hm.windows()
            mine, _ = hm.participant(ss) if ss else (0, None)
            if not mine:
                return [], "not in a battle"
            if not (pp and hm.flags(pp) & 1):
                return [], "not in a battle's planning phase"
            seen, out = set(), []
            for w in self.combatant_windows(hm):
                c, _ = self._place("cdc_participant", w, 0x1000,
                                   lambda v: N.ptr_ok(v) and self.u64(v) in self.vt["ClientCombatParticipant"])
                if not c or c in seen:
                    continue
                r = self.participant(c)
                if r:
                    seen.add(c)
                    r.update(me=c == mine, shown=bool(hm.flags(w) & 1), window=hm.wname(w), source="window")
                    out.append(r)
            if not out:
                return [], "no participant in the battle's windows (not in a battle?)"
            if mine not in seen:
                r = self.participant(mine)
                if r:
                    r.update(me=True, shown=None, window=None, source="handmem")
                    out.append(r)
            return out, ""
        except Exception as e:  # noqa: BLE001
            return [], "the battle couldn't be read (%r)" % (e,)

    def duel(self, objs, mine=0):
        """(the ClientDuel holding my participant, [its participants]) from the zone's objects: the one (the sigil) whose
        behaviors hold a WizardClientDuelBehavior with an m_pDuel - a cross-check of battle(). (0, []) none"""
        dv = self.vt["WizardClientDuelBehavior"] | self.vt["ClientDuelBehavior"] | self.vt["DuelBehavior"]
        D = self.P["Duel"]
        for obj in objs:
            for b in self.vec(obj + self.P["CoreObject"]["m_inactiveBehaviors"]):
                if self.u64(b) in dv:
                    d = self.u64(b + self.P["DuelBehavior"]["m_pDuel"])
                    if N.ptr_ok(d) and self.u64(d) in self.vt["ClientDuel"] | self.vt["Duel"]:
                        parts = self.vec(d + D["m_flatParticipantList"])
                        if not mine or mine in parts:
                            return d, parts
        return 0, []


# ============================================================================ command line
def _zone_objects(st):
    """every object of the game's zone (navmem's way: the ones holding its ClientZone at +0x130), live ones only"""
    gc = st.gameclient()
    cz = st.zone_ptr(gc) if N.ptr_ok(gc) else 0
    if not cz:
        return []
    found, _ = st.scan_objects(cz)
    return [o for o in found if st.is_client_object(o)]


def _main():
    import argparse
    ap = argparse.ArgumentParser(description="read-only: the zone's mobs' title, rank, health and school; the battle")
    ap.add_argument("-n", type=int, default=1)
    ap.add_argument("-i", type=float, default=2.0)
    ap.add_argument("--battle", type=float, default=0, help="wait up to this many s for a battle (read only) and show it")
    ap.add_argument("--duel", action="store_true", help="in a battle: also the duel's own list (a heap look, ~1 s)")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    nm = N.NavMem(log=lambda m: None)
    r, why = nm.read(wait=30)
    if r is None:
        print("ERR", why)
        return
    t0 = time.perf_counter()
    with nm.lock:
        bm = BossMem(nm.st, log=print)
    print("zone %s - reader made in %.2f s" % (r["zone"], time.perf_counter() - t0))
    for k in range(a.n):
        t1 = time.time()
        mobs, why = nm.mobs()
        while not mobs and time.time() - t1 < 60:
            time.sleep(1)
            mobs, why = nm.mobs()
        r, _ = nm.read(wait=5)
        me = r["pos"] if r else None
        with nm.lock:
            objs = dict(nm._objs)
            t2 = time.perf_counter()
            rows = []
            for obj, (gid, name, tname, vt) in objs.items():
                info, w = bm.mob(obj)
                pos = next((m["pos"] for m in mobs or [] if m["gid"] == gid), None)
                rows.append({"name": name, "gid": gid, "dist": round(((pos[0] - me[0]) ** 2 + (pos[1] - me[1]) ** 2) ** 0.5)
                             if pos and me else None, "info": info, "why": w})
            ms = (time.perf_counter() - t2) * 1000
        print("-- %d mobs (%s) read in %.1f ms" % (len(rows), why or "ok", ms))
        for row in sorted(rows, key=lambda x: (x["dist"] is None, x["dist"] or 0)):
            i = row["info"]
            if a.json:
                print(json.dumps({k: v for k, v in row.items()}, default=str))
            elif i:
                print("   %-26s %-6s rank %-3s health %-6s %-7s%s  boss flag %s  %s  dist %s  gid %#x" % (
                    row["name"], i["title"], i["rank"], i["health"], i["school"],
                    "/" + i["school2"] if i.get("school2") else "", i["boss"], i.get("template"), row["dist"], row["gid"]))
            else:
                print("   %-26s - %s" % (row["name"], row["why"]))
        if k + 1 < a.n:
            time.sleep(a.i)
    if a.battle:
        t1 = time.time()
        while time.time() - t1 < a.battle:
            nm.mobs()
            hr, hwhy = nm.cards(want_effects=False, wait=5)
            if hr and hr.get("in_battle") and nm._hand is not None:
                with nm.lock:
                    t2 = time.perf_counter()
                    parts, why = bm.battle(nm._hand)
                    ms = (time.perf_counter() - t2) * 1000
                    by_gid = {gid: obj for obj, (gid, *_rest) in nm._objs.items()}
                    print("-- battle: %d participants (%s) read in %.1f ms" % (len(parts), why or "ok", ms))
                    for pt in parts:
                        mob = by_gid.get(pt["owner"])
                        info = bm.mob(mob)[0] if mob else None
                        name = nm._objs[mob][1] if mob else ""
                        print("   %-4s %-24s team %s %-7s hp %s/%s boss %s level %s monster %s minion %s %s | %s" % (
                            "ME" if pt["me"] else "", name, pt["team"], pt["school"], pt["health"], pt["max_health"],
                            pt["boss"], pt["mob_level"], pt["monster"], pt["minion"], pt["window"] or pt["source"],
                            "%s rank %s health %s" % (info["title"], info["rank"], info["health"]) if info else "-"))
                    mine = next((pt["addr"] for pt in parts if pt["me"]), 0)
                if a.duel:
                    objs = _zone_objects(nm.st)
                    with nm.lock:
                        d, dp = bm.duel(objs, mine)
                        print("-- duel %#x: %d participants, round %s - the same as the windows' %s" % (
                            d, len(dp), struct.unpack("<i", nm.st.p.read(d + bm.P["Duel"]["m_roundNum"], 4))[0] if d else None,
                            sorted(dp) == sorted(pt["addr"] for pt in parts)))
                break
            time.sleep(3)
        else:
            print("-- no battle in %.0f s" % a.battle)
    nm.close()


if __name__ == "__main__":
    _main()
