"""Enemy spells: what each creature in a battle can cast (the Wizard101 Fandom wiki - Wizard101 Central's blocks bots),
which it most likely casts this round, and how likely the wizard is to die of it.

Data
  * A creature's page (its CreatureInfobox): school, rank, health, spell1..spell14 - the spells it's been seen casting.
    A spell's page (SpellInfobox): school, pipcost, accuracy, type, descrip1..5 (the damage: "Deals 170 - 210",
    "Deal 155 to 195", "65 to 105", "Deal 50 + 210" over rounds, "Steal 160", "100 per pip"). Read through the wiki's
    API (api.php), a creature and its spells at most once per CACHE_DAYS, kept in wiki\\cache.json (entries a parser
    older than PARSER read are read again); asked in the background - an answer meanwhile says it's still looking.
  * What each creature was seen casting - the game's own log names every caster's spell each round (the bot reads
    it: EnemySpells.ahk): wiki\\casts.json - {creature: {spell: weight, '_pass': times}}. The log's mob-only names
    ("NA Ghost-01", "Fire Elf - Mob", "Ice Bats Mob") are matched to the wiki's (clean_spell). A cast counts more the less
    likely the creature could afford it then (1 / that chance): the model's own "can't afford it, so it passes" isn't
    counted twice - and passes seen aren't counted at all (most were cards it couldn't afford).

The model (each enemy, each round)
  * Pips: unknown - a spread over 0..MAX_PIPS: at the first round 1-3 alike (mobs start with a few, as wizards do),
    then each round +1 (at most MAX_PIPS), less what it cast. A cast seen narrows it: it had at least that many.
  * Its choice: a card at random from its spells - each weighted by how often it was seen cast (+1 each, so the wiki's
    list counts before anything's seen) - or a pass (PASS_PRIOR); a card it can't afford with the pips it has is a pass
    too (so its pips build up for the big ones, as mobs' do).
  * This round: the chance of each spell, the chance it hits the wizard (its accuracy; a single-target hit is at one of
    the team's wizards, alike; one at all enemies, at each), its damage now (min..max; an X-pip spell's per pip times its
    pips; a damage-over-time's first part only), and - all enemies together, sampled - the chance their hits this round
    reach the wizard's health ('lethal')."""
import json
import os
import re
import threading
import time
import urllib.parse
import urllib.request

import numpy as np

API = 'https://wizard101.fandom.com/api.php'
AGENT = 'Wiz-Maxxing/0.36 (a personal Wizard101 helper; reads creature and spell infoboxes, cached for a month)'
CACHE_DAYS = 30
PARSER = 2              # the cache's entries read by an older parser than this are read again
MAX_PIPS = 7            # a mob's pips at most (power pips not counted apart)
START_PIPS = (1, 2, 3)  # at a battle's first round: one of these, alike
PASS_PRIOR = 0.5        # a pass's weight (each spell's is 1 + its weight seen)
SAMPLES = 4000          # the lethal chance: this many sampled rounds
DAMAGE_TYPES = ('damage', 'steal', 'damage over time', 'dot', 'aoe', 'drain', '')
WORDS = {'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5}


def _num(s):
    m = re.search(r'\d+', s or '')
    return int(m.group()) if m else None


def _split_top(body):
    """a template's body split at its own '|'s - not those inside a {{template}} or [[link]] in it"""
    parts, depth, cur, i = [], 0, [], 0
    while i < len(body):
        two = body[i:i + 2]
        if two in ('{{', '[['):
            depth += 1
            cur.append(two)
            i += 2
            continue
        if two in ('}}', ']]') and depth > 0:
            depth -= 1
            cur.append(two)
            i += 2
            continue
        if body[i] == '|' and depth == 0:
            parts.append(''.join(cur))
            cur = []
        else:
            cur.append(body[i])
        i += 1
    parts.append(''.join(cur))
    return parts


def _clean(v):
    """a field's value as text: links' words, no comments, line breaks or templates"""
    v = re.sub(r'<!--.*?-->', '', v, flags=re.S)
    v = re.sub(r'<br\s*/?>', ' ', v, flags=re.I)
    v = re.sub(r'\{\{.*?\}\}', '', v, flags=re.S)
    v = re.sub(r'\[\[(?:[^|\]]*\|)?([^\]]*)\]\]', r'\1', v)
    return re.sub(r'\s+', ' ', v).strip()


def parse_infobox(text, name):
    """{field: value} of the {{name ...}} template in a page's wikitext (None when it has none) - its fields split at
    its own '|'s (two on a line, an empty one before another, all right)"""
    i = text.find('{{' + name)
    if i < 0:
        return None
    depth, j = 0, i
    while j < len(text):
        if text.startswith('{{', j):
            depth += 1
            j += 2
            continue
        if text.startswith('}}', j):
            depth -= 1
            j += 2
            if depth == 0:
                break
            continue
        j += 1
    body = text[i + 2 + len(name):j - 2]
    out = {}
    for part in _split_top(body)[1:]:
        if '=' not in part:
            continue
        k, v = part.split('=', 1)
        k = k.strip().lower()
        if re.fullmatch(r'[a-z0-9_]+', k):
            out[k] = _clean(v)
    return out


def spell_info(box):
    """a SpellInfobox's fields as {school, pips, xpips, accuracy, type, min, max, perpip, dot, aoe, est, text} - min/max
    the damage it does at once (None: none known); perpip (min, max) for an X-pip spell"""
    text = ' '.join(box.get(f'descrip{k}', '') for k in range(1, 6))
    text = re.sub(r'\s+', ' ', text).strip()
    acc = _num(box.get('accuracy') or box.get('accurac1y'))
    pips_text = box.get('pipcost', '')
    xpips = bool(re.search(r'\bX\b', pips_text))
    kind = box.get('type', '').lower()
    lo = hi = perpip = None
    dot = est = False
    over = re.search(r'\b(?:over|for)\s+(\d+|one|two|three|four|five)\s+rounds?', text, re.I)
    m = re.search(r'(\d+)\s*(?:-\s*(\d+)\s*)?(?:damage\s*)?per pip', text, re.I)
    if m:
        perpip = (int(m.group(1)), int(m.group(2) or m.group(1)))
    elif re.search(r'(\d+)\s*\+\s*(\d+)', text):
        # (an initial hit and more over rounds: the first round's part now)
        m = re.search(r'(\d+)\s*\+\s*(\d+)', text)
        lo = hi = int(m.group(1))
        dot = True
    elif over:
        # (all of it over rounds, none now)
        lo = hi = 0
        dot = True
    else:
        m = re.search(r'(\d+)\s*(?:-|to|–)\s*(\d+)', text)
        if m:
            lo, hi = int(m.group(1)), int(m.group(2))
        else:
            m = re.search(r'\b(?:Deals?|Steals?)\s+(\d+)', text, re.I) or re.match(r'\s*(\d+)\b(?!\s*%)', text)
            if m:
                lo = hi = int(m.group(1))
    # (a damage or steal spell whose text has no numbers the wiki's way: about 100 a pip - marked an estimate)
    if lo is None and perpip is None and ('damage' in kind or 'steal' in kind):
        if xpips:
            perpip, est = (85, 105), True
        elif _num(pips_text):
            lo, hi, est = 85 * _num(pips_text), 105 * _num(pips_text), True
    return {'school': box.get('school', ''), 'pips': None if xpips else _num(pips_text), 'xpips': xpips,
            'accuracy': acc if acc else 100, 'type': box.get('type', ''), 'min': lo, 'max': hi, 'perpip': perpip,
            'dot': dot, 'est': est, 'aoe': bool(re.search(r'\ball enem|\ball targets|to all\b', text, re.I)), 'text': text}


def creature_info(box):
    spells = [box.get(f'spell{k}', '') for k in range(1, 15)]
    return {'school': box.get('school', ''), 'rank': _num(box.get('rank')), 'health': _num(box.get('heal')),
            'spells': [s for s in spells if s and not re.search(r'[{}<>#|\[\]]', s)]}


def clean_spell(raw, known=()):
    """the game log's spell name as the wiki's: '' for none (a pass); its mob-only dress taken off ("NA ", " - Mob",
    " Mob", "-01"); one of known (the creature's wiki spells) if its letters are the same, or one holds the other"""
    s = (raw or '').strip()
    if not s or s.lower() in ('none', '_pass'):
        return ''
    s = re.sub(r'^NA\s+', '', s)
    s = re.sub(r'\s*-\s*\d+$', '', s)
    s = re.sub(r'\s*-?\s*\bMob\b\s*$', '', s, flags=re.I).strip()
    key = re.sub(r'[^a-z]', '', s.lower())
    best = None
    for k in known:
        kk = re.sub(r'[^a-z]', '', re.sub(r'\(.*?\)', '', k).lower())
        if kk == key:
            return k
        if len(kk) >= 4 and len(key) >= 4 and (kk in key or key in kk) and best is None:
            best = k
    return best or s


class Wiki:
    """creature and spell data from the wiki - cached; looked up in the background (fetch: for tests)"""

    def __init__(self, folder, log=print, fetch=None):
        self.folder, self.log = folder, log
        self.file = os.path.join(folder, 'cache.json')
        self.lock = threading.Lock()
        self.fetch = fetch or self._fetch
        self.pending, self.failed = set(), {}
        try:
            with open(self.file, encoding='utf-8') as f:
                self.data = json.load(f)
        except (OSError, ValueError):
            self.data = {}
        self.data.setdefault('creatures', {})
        self.data.setdefault('spells', {})
        self.queue, self.wake = [], threading.Event()
        threading.Thread(target=self._run, daemon=True).start()

    @staticmethod
    def _fetch(titles):
        """{asked title: (page title, wikitext or None)} for up to 50 titles, redirects followed. An error answer (the
        wiki busy, read-only...) raises - tried again later, not taken as 'no such page'"""
        q = urllib.parse.urlencode({'action': 'query', 'prop': 'revisions', 'rvprop': 'content', 'rvslots': 'main',
                                    'format': 'json', 'redirects': 1, 'maxlag': 5, 'titles': '|'.join(titles)})
        req = urllib.request.Request(API + '?' + q, headers={'User-Agent': AGENT})
        with urllib.request.urlopen(req, timeout=10) as r:
            d = json.loads(r.read().decode('utf-8'))
        if 'error' in d or 'query' not in d:
            raise RuntimeError(f"the wiki answered {d.get('error') or 'nothing'}")
        qd = d['query']
        back = {}
        for k in ('normalized', 'redirects'):
            for x in qd.get(k, []):
                back[x['to']] = back.get(x['from'], x['from'])
        out = {}
        for p in qd.get('pages', {}).values():
            revs = p.get('revisions') or []
            text = revs[0].get('slots', {}).get('main', {}).get('*') if revs else None
            asked = back.get(p['title'], p['title'])
            out[asked] = (p['title'], text)
        return out

    def _save(self):
        try:
            os.makedirs(self.folder, exist_ok=True)
            tmp = self.file + '.tmp'
            with open(tmp, 'w', encoding='utf-8') as f:
                json.dump(self.data, f, indent=1, sort_keys=True)
            os.replace(tmp, self.file)
        except OSError as e:
            self.log(f'enemies: the wiki cache can\'t be written ({e!r})')

    @staticmethod
    def _fresh(entry):
        return (entry is not None and entry.get('parser', 1) >= PARSER
                and time.time() - entry.get('at', 0) < CACHE_DAYS * 86400)

    def creature(self, name):
        """its data, or None (asked for in the background - 'missing' in it when the wiki has no such creature)"""
        with self.lock:
            c = self.data['creatures'].get(name)
            if self._fresh(c):
                return c
            if name and name not in self.pending and time.time() - self.failed.get(name, 0) > 300:
                self.pending.add(name)
                self.queue.append(name)
                self.wake.set()
            return c if c and c.get('parser', 1) >= PARSER else None

    def spell(self, title):
        with self.lock:
            return self.data['spells'].get(title)

    def _run(self):
        while True:
            self.wake.wait()
            self.wake.clear()
            while True:
                with self.lock:
                    if not self.queue:
                        break
                    name = self.queue.pop(0)
                try:
                    self._lookup(name)
                except Exception as e:  # noqa: BLE001 - offline, the wiki down: tried again in 5 minutes
                    with self.lock:
                        self.failed[name] = time.time()
                    self.log(f'enemies: {name} not looked up on the wiki ({e!r})')
                finally:
                    with self.lock:
                        self.pending.discard(name)
                time.sleep(0.5)

    def _lookup(self, name):
        """the creature's page - its own title, else "(Creature)" / "(Monster)" after it - then its spells' pages
        (a spell's own title, else "(Spell)" after it)"""
        box, title = None, None
        for t in (name, name + ' (Creature)', name + ' (Monster)'):
            page, text = self.fetch([t]).get(t, (t, None))
            box = parse_infobox(text or '', 'CreatureInfobox')
            if box is not None:
                title = page
                break
        if box is None:
            with self.lock:
                self.data['creatures'][name] = {'missing': True, 'at': time.time(), 'parser': PARSER}
                self._save()
            self.log(f'enemies: {name} - no creature page on the wiki')
            return
        c = creature_info(box)
        c.update(title=title, at=time.time(), parser=PARSER)
        want = list(dict.fromkeys(s for s in c['spells'] if not self._fresh(self.data['spells'].get(s))))
        got = {}
        for i in range(0, len(want), 40):
            got.update(self.fetch(want[i:i + 40]))
        boxes, again = {}, []
        for s in want:
            page, text = got.get(s, (s, None))
            sb = parse_infobox(text or '', 'SpellInfobox')
            if sb is None:
                again.append(s)
            else:
                boxes[s] = sb
        if again:
            more = self.fetch([s + ' (Spell)' for s in again])
            for s in again:
                page, text = more.get(s + ' (Spell)', (None, None))
                boxes[s] = parse_infobox(text or '', 'SpellInfobox')
        with self.lock:
            for s in want:
                sb = boxes.get(s)
                self.data['spells'][s] = (dict(spell_info(sb), at=time.time(), parser=PARSER) if isinstance(sb, dict)
                                          else {'missing': True, 'at': time.time(), 'parser': PARSER})
            self.data['creatures'][name] = c
            self._save()
        self.log(f"enemies: {name} - {c['school']}, rank {c['rank']}, {c['health']} health, casts "
                 + ', '.join(f"{s} ({self.brief(s)})" for s in c['spells']))

    def brief(self, s):
        d = self.data['spells'].get(s) or {}
        if d.get('missing'):
            return '?'
        if d.get('perpip'):
            dmg = f"{d['perpip'][0]}-{d['perpip'][1]} a pip"
        elif d.get('max'):
            dmg = f"{d['min']}-{d['max']}"
        else:
            dmg = d.get('type', '')
        return f"{'X' if d.get('xpips') else d.get('pips')} pips, {dmg}"


class Casts:
    """what each creature was seen casting: {creature: {spell: weight, '_pass': times}} in wiki\\casts.json"""

    def __init__(self, folder, log=print):
        self.file, self.log, self.lock = os.path.join(folder, 'casts.json'), log, threading.Lock()
        try:
            with open(self.file, encoding='utf-8') as f:
                self.data = json.load(f)
        except (OSError, ValueError):
            self.data = {}

    def counts(self, creature):
        with self.lock:
            return dict(self.data.get(creature, {}))

    def add(self, creature, spell, weight=1.0):
        """one cast seen ('' or None: a pass - kept, not used as a weight), counted weight"""
        spell = spell or '_pass'
        with self.lock:
            d = self.data.setdefault(creature, {})
            d[spell] = round(d.get(spell, 0) + (1 if spell == '_pass' else weight), 3)
            try:
                os.makedirs(os.path.dirname(self.file), exist_ok=True)
                tmp = self.file + '.tmp'
                with open(tmp, 'w', encoding='utf-8') as f:
                    json.dump(self.data, f, indent=1, sort_keys=True)
                os.replace(tmp, self.file)
            except OSError as e:
                self.log(f'enemies: casts.json can\'t be written ({e!r})')


class NoCasts:
    """no casts seen (the plain model: a cast's weight is worked out from it)"""

    @staticmethod
    def counts(creature):
        return {}


class Enemy:
    """one enemy in this battle: its pips' spread (index k: the chance it has k pips)"""

    def __init__(self, name):
        self.name = name
        self.pips = np.zeros(MAX_PIPS + 1)
        for k in START_PIPS:
            self.pips[k] = 1.0 / len(START_PIPS)


class Battle:
    """the enemies of the battle going on, and their spreads; step() to the round, then predict()"""

    def __init__(self, wiki, casts, names, team=1):
        """team: the wizards on your side - a single-target hit is at one of them, alike"""
        self.wiki, self.casts = wiki, casts
        self.enemies = [Enemy(n) for n in names]
        self.round, self.team = 1, max(1, team)

    def _choices(self, e):
        """[(spell or None for a pass, its weight, its data)] - its spells, each weighted 1 + its casts seen (the log's
        names matched to the wiki's), and a pass"""
        c = self.wiki.creature(e.name)
        out = [(None, PASS_PRIOR, None)]
        if c and not c.get('missing'):
            seen = self._seen(e.name, c['spells'])
            spells = list(dict.fromkeys(c['spells']))
            raw = [1.0 + seen.get(s, 0) for s in spells]
            # (the casts seen say which spells it favours, not how often it passes: the weights kept to the same total
            # as before any were seen - a pass's share stays PASS_PRIOR's)
            scale = len(spells) / sum(raw) if raw else 1.0
            for s, r in zip(spells, raw):
                d = self.wiki.spell(s) or {}
                if d.get('missing'):
                    d = {}
                out.append((s, r * scale, d))
        return out

    def _seen(self, name, spells):
        """{spell: its casts seen, weighed} for creature name - the log's names matched to the wiki's (spells)"""
        seen = {}
        for k, v in self.casts.counts(name).items():
            if k != '_pass':
                s = clean_spell(k, spells)
                seen[s] = seen.get(s, 0) + v
        return seen

    def _deck(self, e, dist):
        """[(spell or 'pass', its chance this round, brief, its casts seen - weighed)]: every spell the wiki has for it,
        and a pass, likeliest first; [] for a creature the wiki hasn't (yet)"""
        c = self.wiki.creature(e.name)
        if not c or c.get('missing'):
            return []
        seen = self._seen(e.name, c['spells'])
        rows = [(s, dist.get(s, 0.0), self.wiki.brief(s), seen.get(s, 0.0)) for s in dict.fromkeys(c['spells'])]
        rows.append(('pass', dist.get(None, 0.0), '', float(self.casts.counts(e.name).get('_pass', 0))))
        return sorted(rows, key=lambda r: -r[1])

    @staticmethod
    def _cost(d):
        if not d:
            return 0
        if d.get('xpips'):
            return 1
        return d.get('pips') or 0

    def _by_pips(self, e, pips):
        """[(pips k, spell or None, chance, its data)] - what it does at each pip level of the spread pips (a card it
        can't afford there: a pass)"""
        ch = self._choices(e)
        tot = sum(w for _, w, _ in ch)
        out = []
        for k in range(MAX_PIPS + 1):
            if pips[k] <= 0:
                continue
            for s, w, d in ch:
                if s is not None and self._cost(d) > k:
                    s, d = None, None
                out.append((k, s, pips[k] * w / tot, d))
        return out

    def _cast_dist(self, e, pips):
        """{spell or None: chance} for this enemy with pips spread pips; and its spread after"""
        dist, after = {}, np.zeros(MAX_PIPS + 1)
        for k, s, p, d in self._by_pips(e, pips):
            dist[s] = dist.get(s, 0.0) + p
            # (an X-pip spell takes them all)
            after[0 if (d and d.get('xpips')) else k - self._cost(d)] += p
        return dist, after

    def step(self, rnd, seen_by_round=None):
        """on to round rnd: each enemy's spread moved on a round per round since (+1 pip, then its cast - the one
        seen, {round: {enemy index: spell}}, narrowing it)"""
        seen_by_round = seen_by_round or {}
        while self.round < rnd:
            seen = seen_by_round.get(self.round, {})
            for i, e in enumerate(self.enemies):
                p = e.pips
                if i in seen:
                    d = (self.wiki.spell(seen[i]) or {}) if seen[i] else {}
                    c = self._cost(d)
                    q = np.zeros(MAX_PIPS + 1)
                    for k in range(MAX_PIPS + 1):
                        if k >= c and p[k] > 0:
                            q[0 if d.get('xpips') else k - c] += p[k]
                    if q.sum() > 0:
                        p = q / q.sum()
                    else:
                        # (it cast what the spread says it couldn't afford - power pips, a boss: it had about that
                        # many, and spent them)
                        p = np.zeros(MAX_PIPS + 1)
                        p[0] = 1.0
                else:
                    _, p = self._cast_dist(e, p)
                # (then the next round's pip)
                e.pips = np.concatenate([[0.0], p[:-2], [p[-2] + p[-1]]])
            self.round += 1

    def afford(self, index, cost):
        """the chance enemy index has cost pips or more now"""
        return float(self.enemies[index].pips[cost:].sum()) if cost > 0 else 1.0

    def predict(self, health=None):
        """[{name, pips, top: [(spell, chance, brief)], hit: chance it hits the wizard, max: its biggest hit, deck: all
        its spells (_deck)}], and the chance all their hits this round together reach health ('lethal'; None without
        health)"""
        rng = np.random.default_rng(12345)
        out, sampled = [], []
        for e in self.enemies:
            dist, _ = self._cast_dist(e, e.pips)
            top = sorted(dist.items(), key=lambda x: -x[1])
            hit, big, outcomes = 0.0, 0, []
            for k, s, p, d in self._by_pips(e, e.pips):
                if not s or not d or str(d.get('type', '')).lower() not in DAMAGE_TYPES:
                    continue
                if d.get('perpip'):
                    lo, hi = d['perpip'][0] * k, d['perpip'][1] * k
                elif d.get('max'):
                    lo, hi = d['min'] or d['max'], d['max']
                else:
                    continue
                acc = (d.get('accuracy') or 100) / 100.0 * (1.0 if d.get('aoe') else 1.0 / self.team)
                hit += p * acc
                big = max(big, hi)
                outcomes.append((p * acc, lo, hi))
            out.append({'name': e.name, 'pips': float(np.dot(np.arange(MAX_PIPS + 1), e.pips)),
                        'top': [(s or 'pass', p, self.wiki.brief(s) if s else '') for s, p in top[:3]],
                        'hit': hit, 'max': big, 'known': bool(self.wiki.creature(e.name)), 'deck': self._deck(e, dist)})
            sampled.append(outcomes)
        lethal = None
        if health:
            total = np.zeros(SAMPLES)
            for outcomes in sampled:
                u = rng.random(SAMPLES)
                acc = 0.0
                for p, lo, hi in outcomes:
                    pick = (u >= acc) & (u < acc + p)
                    total[pick] += rng.uniform(lo, hi, int(pick.sum()))
                    acc += p
            lethal = float((total >= health).mean())
        return out, lethal
