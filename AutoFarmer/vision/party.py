"""Party: up to 4 wizards, one per PC on the same home network - the leader quests, the followers go where it goes
(TODO goal 1). State only: where each wizard is and what it's doing - nothing one bot sends can make another press,
click, buy or type anything. Its battle part (hitter, blader, healer), its wizard's in-game name, school and hits steer
one thing: a blader's or healer's boosts go to the hitter's plate - found on its own screen by that name, among the
names the game's own log gives for its own side.

  * Each bot's helper reads its own wizard's zone and position (the game's memory, read-only) every BEAT s, and keeps
    what its AutoFarmer says (/party: in battle, health %, ready, walking, bot on, why it's holding).
  * The leader's helper serves the LAN (0.0.0.0, the party port - a server of its own: none of the helper's other
    requests can be reached from the LAN): GET /party/beat?... - a follower's state in, the leader's (and the other
    followers') out, as JSON. Only from private addresses; every field checked.
  * A follower's helper calls the leader's every BEAT s in its own thread (AutoFarmer never waits on the network).
  * The leader's "door": when it changes zone, the last spot in the zone it left and which way it was going there -
    a follower in that zone walks there and on through. Each is marked walked (it moved WALK_MIN units or more in the
    DOOR_WINDOW s before it left - its readings while zoning, navmem's 'object' ones, left out) or not (it stood still:
    End, Home, a sigil, a potion run, a friend's teleport - no door a follower can walk through); the last MAX_DOORS are
    kept with their ages, so a follower two zones behind still has the door out of its own zone (A -> B -> C: a follower
    in A walks A -> B, then B -> C). Walked or not isn't checked in the game yet: Party.ahk only logs it, and walks to
    the door all the same, unless Settings' partytpdoors is on.
  * The leader's loading flag and how long it's been in its zone go to the followers too, and port_advice() says when a
    follower should teleport to it (TODO goal 1 - the Friends list's Teleport; the AutoHotkey side decides and clicks).
  * A follower's teleport state (tp: wait - it can't follow -, stuck, porting, refused) goes to the leader, which stops
    waiting for one that can't follow.
  * The leader's battle spot: where it stood when its battle started - followers walk into the circle there.
Never sent: the game's login, anything from Credential Manager, the character's id, file paths, screenshots, gold."""
import http.client
import ipaddress
import json
import math
import random
import re
import socket
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 47140            # the leader's LAN port (a setting)
BEAT = 0.4              # how often each helper reads its wizard and (a follower) calls the leader
STALE = 10.0            # a follower not heard from this long is dropped
MAX_FOLLOWERS = 3
LOG_EVERY = 60.0        # the same party log line at most this often (s)
REBIND_JOIN = 1.0       # s a new server on the port of one still closing waits for it (in a thread of its own)...
REBIND_TRIES = 6        # ...then its bind tried this many times...
REBIND_GAP = 0.25       # ...this far apart (s): about 1.5 s in all
REBIND_RECENT = 3.0     # an old server on the port closed this recently (s): the new one's bind is waited and retried too
FRESH = 3.0             # s a reading of the wizard's place is good for (older: its zone not known - a loading screen?)
MAX_DOORS = 3           # the leader's last doors kept and sent (a follower behind by up to that many zones)
DOOR_WINDOW = 1.5       # s before a zone change its trail is looked at: the door's way on, and walked or not...
WALK_MIN = 60.0         # ...walked: this many units or more covered in it (walking is ~1000 units a second - Walker.ahk;
                        # stood still before End / Home / a sigil / a friend's teleport: 0)
WALK_SPAN_MIN = 0.3     # less trail than this (s) before the change: walked not known (None)
PORT_ZONE_AGE = 3.0     # s the leader has been in its zone before a follower should teleport to it (not mid-arrival)
LEADER_FRESH = 5.0      # s since the leader's answer: older, nothing's decided on it (as Party.ahk's 5 s)
TP_STATES = ('wait', 'stuck', 'porting', 'refused')     # a follower's tp ('' following)
MAX_PATH = 1024         # the longest request the leader's server takes (characters): a longer beat gets a 403
NAME_RE = re.compile(r"^[\w .'-]{1,24}$")
ZONE_RE = re.compile(r"^[\w/\\ .'-]{1,120}$")
HOLD_RE = re.compile(r"^[\w .,'()/-]{0,80}$")
ROLES = ('hitter', 'blader', 'healer')
SCHOOLS = ('storm', 'fire', 'myth', 'balance', 'ice', 'life', 'death')


def _f(v):
    """a finite float within reach of any zone, else None"""
    try:
        x = float(v)
    except (TypeError, ValueError):
        return None
    return x if math.isfinite(x) and abs(x) < 1e6 else None


def _flag(v):
    return '1' if str(v) == '1' else '0'


def clean_state(q):
    """a wizard's state from a request's fields - only these, each checked (a wrong one: blank)"""
    s = {}
    name = (q.get('name') or '').strip()
    s['name'] = name if NAME_RE.match(name) else ''
    zone = (q.get('zone') or '').strip()
    s['zone'] = zone if ZONE_RE.match(zone) else ''
    for k in ('x', 'y', 'z', 'yaw'):
        s[k] = _f(q.get(k))
    for k in ('battle', 'ready', 'walk', 'bot', 'loading'):
        s[k] = _flag(q.get(k))
    hp = _f(q.get('hp'))
    s['hp'] = None if hp is None or not 0 <= hp <= 100 else round(hp)
    hold = (q.get('hold') or '').strip()
    s['hold'] = hold if HOLD_RE.match(hold) else ''
    # (its battle part, its wizard's in-game name, its school, its hits and the log's round of the last - a blader's or
    # healer's boosts go to the hitter's plate, found on its own screen by that name among its own side's in the log)
    brole = str(q.get('brole') or '').strip()
    s['brole'] = brole if brole in ROLES else ''
    wiz = str(q.get('wiz') or '').strip()
    s['wiz'] = wiz if NAME_RE.match(wiz) else ''
    sch = str(q.get('school') or '').strip().lower()
    s['school'] = sch if sch in SCHOOLS else ''
    for k in ('hits', 'hitr'):
        v = _f(q.get(k))
        s[k] = int(v) if v is not None and 0 <= v < 1e6 else None
    # (the hitter's planned hit's schools - its supports boost for them - and its last hit's: a support's blades that fit
    # none of those stay on it; the seven schools only, each once)
    for k in ('plan', 'lasthit'):
        seen = []
        for p in str(q.get(k) or '').lower().split(','):
            p = p.strip()
            if p in SCHOOLS and p not in seen:
                seen.append(p)
        s[k] = ','.join(seen)
    # (a follower's teleport state - TODO goal 1: '' following; wait - it can't follow (the leader went where no door it
    # walked through leads from here, or its door didn't take it); stuck - five stuck tries on the way; porting - the
    # Friends list's teleport under way; refused - the game said no. And why, as the leader's hold is checked)
    tp = str(q.get('tp') or '').strip()
    s['tp'] = tp if tp in TP_STATES else ''
    tpwhy = str(q.get('tpwhy') or '').strip()
    s['tpwhy'] = tpwhy if s['tp'] and HOLD_RE.match(tpwhy) else ''
    # (the party's hit round - TODO goal 3, v0.9.0: the hitter's planned hit's round in its game's log, the earliest it can
    # go out - its supports time their blades and traps to it, Party.ahk PartyHitHold -, and each wizard's seat in the
    # battle: its subcircle 4-7, the cast order of our side. None: not said - an older bot, no hit planned)
    v = _f(q.get('hitat'))
    s['hitat'] = int(v) if v is not None and v == int(v) and 1 <= v <= 99 else None
    v = _f(q.get('seat'))
    s['seat'] = int(v) if v is not None and v == int(v) and 4 <= v <= 7 else None
    return s


def _walked(v):
    """a door's walked flag as sent (True / 1 / '1', False / 0 / '0'), else None (not known - an older helper)"""
    if v is True or v is False:
        return v
    if str(v) in ('1', '0'):
        return str(v) == '1'
    return None


def _ms(v):
    """an age in ms as sent: a whole number from 0 up to ~11 days, else None. (Not _f: its 1e6 - a zone's reach - is 16.7
    minutes in ms: a leader that long in its zone, or a door that old, read as no age - "an older version" - and the
    teleport advice never came)"""
    if isinstance(v, bool):
        return None
    try:
        x = float(v)
    except (TypeError, ValueError):
        return None
    return int(x) if math.isfinite(x) and 0 <= x < 1e9 else None


def clean_door(door):
    """one of the leader's doors as a follower got it, each field checked: {zone, to, x, y, z, dx, dy, walked, age} or
    None (not a door)"""
    if not isinstance(door, dict):
        return None
    z, to = str(door.get('zone') or ''), str(door.get('to') or '')
    # (fullmatch: a trailing newline - which $ lets by - would break the lines AutoHotkey reads)
    d = {'zone': z if ZONE_RE.fullmatch(z) else '', 'to': to if ZONE_RE.fullmatch(to) else '',
         **{k: _f(door.get(k)) for k in ('x', 'y', 'z', 'dx', 'dy')}}
    d['walked'], d['age'] = _walked(door.get('walked')), _ms(door.get('age'))
    return d


def door_from(zone, doors):
    """the leader's door out of zone: the latest of its doors (oldest first) left from there - the way its path went on
    from zone the last time it was in it; None when none was (or zone isn't known)"""
    if not zone:
        return None
    for d in reversed(doors or []):
        if isinstance(d, dict) and d.get('zone') == zone:
            return d
    return None


def walked_before(trail):
    """how the wizard left a zone, from its trail there [(t, zone, x, y, z) ...], oldest first: (walked, moved, span, back)
    - walked True when it covered WALK_MIN units or more in the last DOOR_WINDOW s (walking through a door), False when it
    didn't (it stood still: a teleport - End, Home, a sigil, a potion run, a friend's), None when there's too little of its
    trail to tell (under WALK_SPAN_MIN s); moved the units covered, span the s looked at, back the trail point the door's
    way on is measured from"""
    if not trail:
        return None, 0.0, 0.0, None
    last = trail[-1]
    win = [p for p in trail if last[0] - p[0] <= DOOR_WINDOW]
    # (readings far apart - a slow read -: the one before too)
    if len(win) < 2 and len(trail) >= 2:
        win = trail[-2:]
    span = last[0] - win[0][0]
    moved = sum(math.hypot(b[2] - a[2], b[3] - a[3]) for a, b in zip(win, win[1:]))
    if span < WALK_SPAN_MIN:
        return None, moved, span, win[0]
    return moved >= WALK_MIN, moved, span, win[0]


def still_for(trail, tol=1.0):
    """how long (s) the wizard's place hadn't moved (more than tol units) at the end of its trail [(t, zone, x, y, ...)]:
    0.0 when its last reading had moved. (For the log: a door walked through whose last readings stood still - the game
    keeping the old zone into the loading screen, its place frozen, with a body - is how WALK_MIN / DOOR_WINDOW would go
    wrong)"""
    if not trail:
        return 0.0
    last = trail[-1]
    t0 = last[0]
    for p in reversed(trail[:-1]):
        if math.hypot(p[2] - last[2], p[3] - last[3]) > tol:
            break
        t0 = p[0]
    return last[0] - t0


def port_advice(me_zone, leader, now):
    """should a follower teleport to its leader now (the Friends list's Teleport - TODO goal 1)? ('1', why) or ('0', why).
    me_zone: the follower's own zone ('' not known); leader: its view of the leader (Party.leader: zone, loading, zage -
    ms in its zone as sent -, doors, at - when heard), now: time.time(). Yes only when the leader's been heard from in
    LEADER_FRESH s, its zone is known and isn't the follower's, it isn't loading, it's been there PORT_ZONE_AGE s or more
    (not mid-arrival - or about to go on), and no door it walked through leads on from the follower's zone (one whose
    walked isn't known - an older leader's helper - counts as walked: tried as ever). Pure: Party.ahk decides (the setting,
    the game in front, you not playing, a try at most once a minute...) and clicks. why: words for the log and the status
    - no |"""
    if not isinstance(leader, dict) or not leader:
        return '0', 'the leader not heard from'
    heard = now - (leader.get('at') or 0)
    if heard > LEADER_FRESH:
        return '0', f'the leader not heard from in {heard:.0f} s'
    lz = leader.get('zone') or ''
    if not lz:
        return '0', "the leader's zone isn't known (loading?)"
    if not me_zone:
        return '0', "this wizard's zone isn't known (loading?)"
    if lz == me_zone:
        return '0', 'in the same zone'
    if str(leader.get('loading')) == '1':
        return '0', 'the leader is loading'
    zage = leader.get('zage')
    if zage is None:
        return '0', "the leader's helper doesn't say how long it's been in its zone (an older version)"
    zage += max(0.0, heard) * 1000
    if zage < PORT_ZONE_AGE * 1000:
        return '0', f'the leader only just got to {lz} ({zage / 1000:.0f} s ago)'
    d = door_from(me_zone, leader.get('doors'))
    if d is not None and d.get('walked') is not False:
        return '0', f"a door the leader walked through leads on from here (to {d.get('to') or '?'})"
    if d is not None:
        return '1', f"the leader teleported from here (to {d.get('to') or '?'}) and is in {lz} - no door to walk through"
    return '1', f'the leader is in {lz} - no door it walked through leads there from here'


def clean_peer(d):
    """the leader's state as a follower got it (its answer: each field checked again - nothing in it reaches AutoFarmer
    unchecked)"""
    d = d if isinstance(d, dict) else {}
    s = clean_state({k: str(v) for k, v in d.items() if isinstance(v, (str, int, float))})
    s['door'] = clean_door(d.get('door'))
    # (its last doors, oldest first, with their ages and walked - an older leader's helper sends only the last: that one,
    # walked and age not known)
    doors = d.get('doors')
    if isinstance(doors, list):
        s['doors'] = [c for c in (clean_door(x) for x in doors[-MAX_DOORS:]) if c is not None]
    else:
        s['doors'] = [s['door']] if s['door'] else []
    # (ms it's been in its zone - None not known: an older helper, or its zone isn't read)
    s['zage'] = _ms(d.get('zage'))
    b = d.get('bspot')
    s['bspot'] = tuple(_f(v) for v in b[:3]) if isinstance(b, (list, tuple)) and len(b) >= 3 else None
    return s


class PartyServer(ThreadingHTTPServer):
    """the leader's LAN server: its port its own (no address reuse - on Windows that lets a second server share it)"""
    allow_reuse_address = False
    daemon_threads = True

    def server_bind(self):
        if hasattr(socket, 'SO_EXCLUSIVEADDRUSE'):
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()


class Party:
    """this PC's part of the party. reader(): the game's memory now - {'zone', 'pos', 'yaw'} or None"""

    def __init__(self, reader, log=print):
        self.reader, self.log = reader, log
        self.lock = threading.Lock()
        self.cfg = {'role': 'off', 'name': '', 'leader': '', 'port': PORT, 'bind': ''}
        self.ahk = {}                       # what AutoFarmer said last (clean_state)
        self.ahk_at = 0.0
        self.mem = {}                       # zone, x, y, z, yaw, at - read here
        self.trail = []                     # (t, zone, x, y, z, zoning) of the last few seconds (the door) - zoning:
                                            # navmem's 'object' reading (the wizard has no body)
        self.door = None                    # {zone, x, y, z, dx, dy, to, walked, at}: the last spot in the zone left,
                                            # the way on
        self.doors = []                     # the last MAX_DOORS of those, oldest first (self.door the last)
        self.zone_at = 0.0                  # when its zone last changed (its first reading there)
        self.battle_spot = None             # (x, y, z) where its battle started
        self.members = {}                   # leader: follower id -> state (with 'at', 'ip')
        self.leader = None                  # follower: the leader's answer (with 'at')
        self.state, self.why = 'off', ''
        self.server, self.server_key = None, None
        # (the server's lifecycle: one change at a time; the old servers still closing, by port - {port: [(thread, when
        # it closed or None)]}; which change a background bind belongs to)
        self.srv_lock = threading.RLock()
        self.closing = {}
        self.srv_gen = 0
        self.fails, self.next_beat = 0, 0.0
        self.id = '%08x' % random.getrandbits(32)
        self._said = {}                     # a log line -> (when it was last written, how many times it came since)
        threading.Thread(target=self._loop, name='party', daemon=True).start()

    def _log_once(self, msg, every=LOG_EVERY):
        """msg into the log - the same line again at most every `every` s, with how many times it came in between (a
        fault that repeats every beat: 2026-10-25's "'tuple' object has no attribute 'get'", 3 a second all evening)"""
        now = time.time()
        at, n = self._said.get(msg, (None, 0))
        if at is not None and now - at < every:
            self._said[msg] = (at, n + 1)
            return
        if len(self._said) > 50:
            self._said.clear()
        self._said[msg] = (now, 0)
        self.log(msg + (f' (and {n} times more in the last {every:.0f} s)' if n else ''))

    # ------------------------------------------------------------------ from AutoFarmer
    def update(self, q):
        """/party from AutoFarmer: its settings and state; the lines it shows (see vision.py's /party)"""
        role = q.get('role', 'off')
        role = role if role in ('off', 'leader', 'follower') else 'off'
        port = int(_f(q.get('port')) or PORT)
        port = port if 1024 <= port <= 65535 else PORT
        with self.lock:
            self.cfg.update(role=role, port=port, leader=(q.get('leader') or '').strip()[:64],
                            name=clean_state(q)['name'], bind=q.get('bind', '') if q.get('bind') == '127.0.0.1' else '')
            self.ahk, self.ahk_at = clean_state(q), time.time()
            if self.ahk['battle'] == '1' and self.battle_spot is None and self.mem.get('x') is not None:
                self.battle_spot = (self.mem['x'], self.mem['y'], self.mem['z'])
            elif self.ahk['battle'] != '1':
                self.battle_spot = None
        self._serve()
        return self.lines()

    def _serve(self):
        """the leader's LAN server running (on its port) only while the role is leader. A change of the server wanted
        closes the old one in a thread (/party isn't held up: its shutdown takes up to half a second); a new one on the
        same port as one still closing - or just closed - is bound in a thread too, once the old one's gone (2026-10-26
        22:18:11: bound before the old socket was closed - "port 47140 taken or blocked")"""
        with self.lock:
            want = (self.cfg['bind'] or '0.0.0.0', self.cfg['port']) if self.cfg['role'] == 'leader' else None
        with self.srv_lock:
            if want == self.server_key:
                return
            self.srv_gen += 1
            gen = self.srv_gen
            if self.server is not None:
                srv, old = self.server, self.server_key
                self.server = None
                self._close_later(srv, old[1] if old else None)
            # (set now: a failure isn't tried again every call - a role or port change tries again)
            self.server_key = want
            if want is None:
                return
            if not self._closing_on(want[1]):
                self._start(want, gen, 1)
                return
        threading.Thread(target=self._start, args=(want, gen, REBIND_TRIES, True), name='party-bind', daemon=True).start()

    def _close_later(self, srv, port):
        """srv shut down and its socket closed in a thread (noted under its port till REBIND_RECENT s after)"""
        rec = [None, None]                  # the thread, when it had closed

        def close():
            try:
                srv.shutdown()
            except Exception:  # noqa: BLE001 - closed all the same
                pass
            try:
                srv.server_close()
            except OSError:
                pass
            rec[1] = time.monotonic()
        rec[0] = threading.Thread(target=close, name='party-close', daemon=True)
        if port is not None:
            self.closing.setdefault(port, []).append(rec)
        rec[0].start()

    def _closing_on(self, port):
        """the old servers on port still closing or closed under REBIND_RECENT s ago (the others forgotten)"""
        now = time.monotonic()
        for p in list(self.closing):
            keep = [r for r in self.closing[p] if r[1] is None or now - r[1] < REBIND_RECENT]
            if keep:
                self.closing[p] = keep
            else:
                del self.closing[p]
        return list(self.closing.get(port, ()))

    def _start(self, want, gen, tries, wait_old=False):
        """the leader's server bound on want - tries times REBIND_GAP s apart; wait_old: first the old ones on its port
        waited for (REBIND_JOIN s each at most). Not when the server wanted has changed meanwhile (gen)"""
        if wait_old:
            with self.srv_lock:
                old = self._closing_on(want[1])
            for rec in old:
                if rec[0] is not None and rec[0] is not threading.current_thread():
                    rec[0].join(REBIND_JOIN)
        err = None
        for i in range(max(1, tries)):
            with self.srv_lock:
                if gen != self.srv_gen:
                    return                  # (another change since: that one's own)
                try:
                    srv = PartyServer(want, self._handler())
                except OSError as e:
                    err = e
                else:
                    self.server = srv
                    threading.Thread(target=srv.serve_forever, name='party-server', daemon=True).start()
                    self.log(f'party: leader - serving the party on {want[0]}:{want[1]}'
                             + (f' (bound at try {i + 1})' if i else ''))
                    return
            if i + 1 < tries:
                time.sleep(REBIND_GAP)
        with self.srv_lock:
            if gen != self.srv_gen:
                return
            with self.lock:
                self.state, self.why = 'error', f'port {want[1]} taken or blocked ({err.strerror or err})'
            self.log(f'party: the leader\'s server can\'t start on port {want[1]} ({err!r})'
                     + (f' - {tries} tries' if tries > 1 else ''))

    def _handler(self):
        """the leader's server's request handler (GET /party/beat only, from private addresses)"""
        party = self

        class Handler(BaseHTTPRequestHandler):
            timeout = 3

            def log_message(self, *a):
                pass

            def do_GET(self):
                ip = self.client_address[0]
                try:
                    a = ipaddress.ip_address(ip)
                    ok = a.is_private or a.is_loopback or a.is_link_local
                except ValueError:
                    ok = False
                u = urllib.parse.urlparse(self.path)
                if not ok or len(self.path) > MAX_PATH or u.path != '/party/beat':
                    self.send_response(403)
                    self.end_headers()
                    return
                q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query).items()}
                body = json.dumps(party.beat_in(q, ip)).encode('utf-8')
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        return Handler

    def stop(self):
        with self.srv_lock:
            # (a bind still waiting in its thread: not made now)
            self.srv_gen += 1
            srv, self.server, self.server_key = self.server, None, None
        if srv is not None:
            srv.shutdown()
            srv.server_close()

    # ------------------------------------------------------------------ state
    def _me(self):
        """this wizard's state to send: AutoFarmer's fields and the memory's place, the door (the last - as older helpers
        read it), the doors (the last MAX_DOORS, oldest first, each with its age in ms - the PCs' clocks differ - and
        walked), how long it's been in its zone (zage, ms - None while its zone isn't read), the battle spot"""
        with self.lock:
            now = time.time()
            s = dict(self.ahk)
            m = self.mem
            fresh = bool(m) and now - m.get('at', 0) < FRESH
            for k in ('zone', 'x', 'y', 'z', 'yaw'):
                s[k] = m.get(k) if fresh else (None if k != 'zone' else '')
            s['name'] = self.cfg['name']
            s['door'] = dict(self.door) if self.door else None
            s['doors'] = [dict({k: d.get(k) for k in ('zone', 'x', 'y', 'z', 'dx', 'dy', 'to', 'walked')},
                               age=max(0, round((now - d['at']) * 1000))) for d in self.doors]
            s['zage'] = max(0, round((now - self.zone_at) * 1000)) if fresh and self.zone_at else None
            s['bspot'] = self.battle_spot
        return s

    def beat_in(self, q, ip):
        """the leader's side of a follower's beat: it noted; the leader's state and the others' back"""
        fid = re.sub(r'[^0-9a-f]', '', q.get('id', ''))[:16]
        s = clean_state(q)
        now = time.time()
        with self.lock:
            if fid and (fid in self.members or len(self.members) < MAX_FOLLOWERS):
                s.update(at=now, ip=ip)
                self.members[fid] = s
            others = [dict(v, age=round((now - v['at']) * 1000)) for k, v in self.members.items() if k != fid]
        me = self._me()
        return {'v': 1, 'leader': me, 'others': [{k: o.get(k) for k in
                ('name', 'zone', 'x', 'y', 'z', 'battle', 'hp', 'ready', 'walk', 'age', 'brole', 'wiz', 'school', 'hits',
                 'hitr', 'plan', 'lasthit', 'tp', 'tpwhy', 'hitat', 'seat')} for o in others]}

    def _beat_out(self):
        """a follower's beat to the leader (its own thread); a failure backs off and says why"""
        with self.lock:
            host, port = self.cfg['leader'], self.cfg['port']
        if not host:
            with self.lock:
                self.state, self.why = 'error', "no leader address (tray menu: Party...)"
            return
        if re.fullmatch(r'[\d.]+', host):
            try:
                if not ipaddress.ip_address(host).is_private:
                    with self.lock:
                        self.state, self.why = 'error', 'the leader address isn\'t a home-network one'
                    return
            except ValueError:
                with self.lock:
                    self.state, self.why = 'error', 'the leader address isn\'t an address'
                return
        q = self._beat_query()
        try:
            c = http.client.HTTPConnection(host, port, timeout=1.5)
            c.request('GET', '/party/beat?' + urllib.parse.urlencode(q))
            r = c.getresponse()
            body = r.read(16384)
            c.close()
            if r.status != 200:
                raise OSError(f'the leader answered {r.status}')
            d = json.loads(body.decode('utf-8'))
            if not isinstance(d, dict):
                raise ValueError('not an object')
            with self.lock:
                others = []
                got = d.get('others') if isinstance(d.get('others'), list) else []
                for o in got[:MAX_FOLLOWERS]:
                    if isinstance(o, dict):
                        c = clean_state({k: str(v) for k, v in o.items() if isinstance(v, (str, int, float))})
                        age = _f(o.get('age'))
                        c['age'] = int(age) if age is not None and 0 <= age < 1e6 else ''
                        others.append(c)
                self.leader = dict(clean_peer(d.get('leader')), at=time.time(), others=others)
                self.state, self.why, self.fails = 'following', '', 0
        except socket.timeout:
            self._fail('no answer - is that PC\'s bot the leader, and its firewall letting Python in (Private networks)?')
        except ConnectionRefusedError:
            self._fail('refused - that PC\'s bot isn\'t set to Leader, or the port is wrong')
        except OSError as e:
            self._fail(f'can\'t reach it ({e.strerror or e})')
        except (ValueError, http.client.HTTPException):
            self._fail('its answer couldn\'t be read')

    def _beat_query(self):
        """a follower's beat's fields: its state (_me - its tp and tpwhy too) and its id; not its doors, battle spot or
        zone's age (the leader's to send - a list in a query would only make it longer: the leader's server takes
        MAX_PATH characters). Longer than that - a 120-character zone of backslashes, an 80-character hold and why of
        commas and apostrophes, 3 characters each in the URL: ~1300 - its why, then its hold, left out till it fits (~840
        without them, the hit round's hitat and seat in; the leader answered 403 to the whole beat, and the follower went
        'unreachable'). Still over: the seat, then hitat (the hit round not said: its supports cast as ever)"""
        q = {k: ('' if v is None else v) for k, v in self._me().items() if k not in ('door', 'doors', 'bspot', 'zage')}
        q['id'] = self.id
        for k in ('tpwhy', 'hold', 'seat', 'hitat'):
            if len('/party/beat?' + urllib.parse.urlencode(q)) <= MAX_PATH:
                break
            q[k] = ''
        return q

    def _fail(self, why):
        with self.lock:
            self.fails += 1
            self.state, self.why = 'unreachable', why
            self.next_beat = time.time() + min(5.0, 0.5 * 2 ** min(self.fails, 4))

    def _loop(self):
        while True:
            t0 = time.time()
            try:
                self._read()
                with self.lock:
                    role = self.cfg['role']
                    for k in [k for k, v in self.members.items() if t0 - v['at'] > STALE]:
                        self.members.pop(k, None)
                    if role == 'leader' and self.server is not None:
                        self.state, self.why = 'serving', ''
                    elif role == 'off':
                        self.state, self.why = 'off', ''
                if role == 'follower' and t0 >= self.next_beat:
                    self._beat_out()
            except Exception as e:  # noqa: BLE001 - one bad beat mustn't end the thread (said once a minute)
                self._log_once(f'party: {e!r}')
            time.sleep(max(0.05, BEAT - (time.time() - t0)))

    def _read(self):
        """the wizard's zone and place (only while the party's on); the door when the zone changes"""
        with self.lock:
            if self.cfg['role'] == 'off':
                return
        r = self.reader()
        # (a reader answering navmem's (reading, why) pair: its reading)
        if isinstance(r, tuple):
            r = r[0] if r else None
        if not isinstance(r, dict) or not r.get('zone') or r.get('pos') is None:
            return
        now = time.time()
        x, y, z = r['pos'][:3]
        # (navmem's reading from the ClientObject's own copy of its place - it has no body: zoning. The game can keep the
        # old zone a while into the loading screen - Dungeons.ahk: "still in the zone it's leaving" -, its place frozen
        # at the doorway: that isn't standing still)
        zoning = r.get('source') == 'object'
        said = None
        with self.lock:
            last = self.trail[-1] if self.trail else None
            if last and last[1] != r['zone']:
                # (the zone changed: the last spot in the old one, and the way it was going there - from ~1.5 s before;
                # walked or not - it stood still: a teleport, no door a follower can walk through. Both from its readings
                # with a body: 1.5 s of frozen zoning reads made a door walked through a teleport, and its way on none.
                # All of them zoning: all, as before)
                old = [p for p in self.trail if p[1] == last[1]]
                body = [p for p in old if not (len(p) > 5 and p[5])] or old
                walked, moved, span, back = walked_before(body)
                nz, still = len(old) - len(body), still_for(old)
                dx, dy = last[2] - back[2], last[3] - back[3]
                n = math.hypot(dx, dy) or 1.0
                self.door = {'zone': last[1], 'x': last[2], 'y': last[3], 'z': last[4], 'dx': dx / n, 'dy': dy / n,
                             'to': r['zone'], 'walked': walked, 'at': now}
                self.doors = (self.doors + [self.door])[-MAX_DOORS:]
                self.trail = []
                said = (f'party: {last[1]} -> {r["zone"]}: '
                        + ('walked through a door' if walked else 'a teleport (it stood still)' if walked is False
                           else 'walked or not not known (too little of its trail)')
                        + f' - moved {moved:.0f} in the last {span:.1f} s'
                        + (f', still for the last {still:.1f} s' if still >= BEAT else '')
                        + (f' ({nz} zoning reads left out)' if nz else ''))
            if last is None or last[1] != r['zone']:
                self.zone_at = now
            self.trail.append((now, r['zone'], x, y, z, zoning))
            self.trail = [p for p in self.trail if now - p[0] <= 4.0]
            self.mem = {'zone': r['zone'], 'x': x, 'y': y, 'z': z, 'yaw': r.get('yaw'), 'at': now}
        if said:
            # (one line a zone change - how the doors are told apart, to check in the game: WALK_MIN, DOOR_WINDOW - and
            # whether its last readings in the old zone stand still with a body: "still for")
            self.log(said)

    # ------------------------------------------------------------------ to AutoFarmer
    def lines(self):
        """party|role|state|why; me|zone|x|y|z|yaw; leader|...; member|... (one per follower, the leader's view).
        AutoHotkey's fields (Party.ahk PartyTick - f[1] the line's kind): the leader's 2-31 as ever, then 32 loading,
        33 dwalk (the door below walked: 1, 0, '' not known), 34 zage (ms in its zone), 35 dage (the door's age, ms), 36
        port, 37 its why (port_advice), 38 hitat, 39 seat (the party's hit round - v0.9.0); a member's 2-21 as ever, then 22
        tp, 23 tpwhy, 24 hitat, 25 seat. The door (14-20): the leader's latest out of this wizard's zone (door_from), else
        its last as before. Old bots read only the fields they know (and pad the ones they don't: blank)"""
        def num(v, d=0):
            return '' if v is None else f'{v:.{d}f}'
        now = time.time()
        with self.lock:
            role, state, why = self.cfg['role'], self.state, self.why
            # (this wizard's place as last read - not when that's FRESH s old: a loading screen, its zone not known - as
            # _me sends it to the leader)
            m = self.mem if self.mem and now - self.mem.get('at', 0) < FRESH else {}
            out = [f'party|{role}|{state}|{why}',
                   f"me|{m.get('zone', '')}|{num(m.get('x'))}|{num(m.get('y'))}|{num(m.get('z'))}|{num(m.get('yaw'), 4)}"]
            if role == 'follower' and self.leader:
                L = self.leader
                age = round((now - L['at']) * 1000)
                dist = ''
                if L.get('zone') and L.get('zone') == m.get('zone') and L.get('x') is not None and m.get('x') is not None:
                    dist = f"{math.hypot(L['x'] - m['x'], L['y'] - m['y']):.0f}"
                doors = L.get('doors') or []
                d = door_from(m.get('zone'), doors) or (doors[-1] if doors else None) or L.get('door') or {}
                b = L.get('bspot') or (None, None, None)
                walked = d.get('walked')
                port, pwhy = port_advice(m.get('zone') or '', L, now)
                out.append('leader|' + '|'.join([
                    L.get('name') or '', L.get('zone') or '', num(L.get('x')), num(L.get('y')), num(L.get('z')),
                    num(L.get('yaw'), 4), L.get('battle', '0'), num(L.get('hp')), L.get('ready', '0'), L.get('walk', '0'),
                    str(age), dist, d.get('zone', ''), num(d.get('x')), num(d.get('y')), num(d.get('z')),
                    num(d.get('dx'), 3), num(d.get('dy'), 3), d.get('to', ''), num(b[0]), num(b[1]), num(b[2]),
                    L.get('hold') or '', L.get('brole') or '', L.get('wiz') or '', L.get('school') or '',
                    num(L.get('hits')), num(L.get('hitr')), L.get('plan') or '', L.get('lasthit') or '',
                    # (32-37: its loading flag; the door's walked, the leader's time in its zone and the door's age - each
                    # as sent and since that answer -; the teleport advice)
                    L.get('loading', '0'), '' if walked is None else ('1' if walked else '0'),
                    '' if L.get('zage') is None else str(L['zage'] + age),
                    '' if d.get('age') is None else str(d['age'] + age), port, pwhy.replace('|', '/'),
                    # (38-39: the hit round - its planned hit's log round, its seat)
                    num(L.get('hitat')), num(L.get('seat'))]))
                # (the other followers: as the leader's own rows below - walk, loading and hold where it doesn't say)
                for o in L.get('others') or []:
                    # (its age as the leader last heard it, and since that answer: a leader gone quiet takes them along)
                    oa = o.get('age')
                    out.append('member|' + '|'.join([o.get('name') or '', o.get('zone') or '', num(o.get('x')),
                               num(o.get('y')), num(o.get('z')), o.get('battle', '0'), num(o.get('hp')),
                               o.get('ready', '0'), str(oa + age) if isinstance(oa, int) else '', '', o.get('walk', '0'), '0', '',
                               o.get('brole') or '', o.get('wiz') or '', o.get('school') or '', num(o.get('hits')),
                               num(o.get('hitr')), o.get('plan') or '', o.get('lasthit') or '', o.get('tp') or '',
                               o.get('tpwhy') or '', num(o.get('hitat')), num(o.get('seat'))]))
            elif role == 'leader':
                for v in self.members.values():
                    dist = ''
                    if v.get('zone') and v['zone'] == m.get('zone') and v.get('x') is not None and m.get('x') is not None:
                        dist = f"{math.hypot(v['x'] - m['x'], v['y'] - m['y']):.0f}"
                    out.append('member|' + '|'.join([v.get('name') or '', v.get('zone') or '', num(v.get('x')),
                               num(v.get('y')), num(v.get('z')), v.get('battle', '0'), num(v.get('hp')),
                               v.get('ready', '0'), str(round((now - v['at']) * 1000)), dist, v.get('walk', '0'),
                               v.get('loading', '0'), v.get('hold') or '', v.get('brole') or '', v.get('wiz') or '',
                               v.get('school') or '', num(v.get('hits')), num(v.get('hitr')), v.get('plan') or '',
                               v.get('lasthit') or '', v.get('tp') or '', v.get('tpwhy') or '', num(v.get('hitat')),
                               num(v.get('seat'))]))
        return out
