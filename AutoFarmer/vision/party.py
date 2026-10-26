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
    a follower in that zone walks there and on through.
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
    return s


def clean_peer(d):
    """the leader's state as a follower got it (its answer: each field checked again - nothing in it reaches AutoFarmer
    unchecked)"""
    d = d if isinstance(d, dict) else {}
    s = clean_state({k: str(v) for k, v in d.items() if isinstance(v, (str, int, float))})
    door = d.get('door')
    if isinstance(door, dict):
        z, to = str(door.get('zone') or ''), str(door.get('to') or '')
        s['door'] = {'zone': z if ZONE_RE.match(z) else '', 'to': to if ZONE_RE.match(to) else '',
                     **{k: _f(door.get(k)) for k in ('x', 'y', 'z', 'dx', 'dy')}}
    else:
        s['door'] = None
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
        self.trail = []                     # (t, zone, x, y, z) of the last few seconds (the door)
        self.door = None                    # {zone, x, y, z, dx, dy, at}: the last spot in the zone left, the way on
        self.battle_spot = None             # (x, y, z) where its battle started
        self.members = {}                   # leader: follower id -> state (with 'at', 'ip')
        self.leader = None                  # follower: the leader's answer (with 'at')
        self.state, self.why = 'off', ''
        self.server, self.server_key = None, None
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
        """the leader's LAN server running (on its port) only while the role is leader"""
        with self.lock:
            want = (self.cfg['bind'] or '0.0.0.0', self.cfg['port']) if self.cfg['role'] == 'leader' else None
        if want == self.server_key:
            return
        if self.server is not None:
            srv, self.server, self.server_key = self.server, None, None
            threading.Thread(target=lambda: (srv.shutdown(), srv.server_close()), daemon=True).start()
        if want is None:
            return
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
                if not ok or len(self.path) > 1024 or u.path != '/party/beat':
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

        try:
            srv = PartyServer(want, Handler)
        except OSError as e:
            with self.lock:
                self.state, self.why = 'error', f'port {want[1]} taken or blocked ({e.strerror or e})'
            self.server_key = want      # (not tried again every call - a role or port change tries again)
            self.log(f'party: the leader\'s server can\'t start on port {want[1]} ({e!r})')
            return
        self.server, self.server_key = srv, want
        threading.Thread(target=srv.serve_forever, name='party-server', daemon=True).start()
        self.log(f'party: leader - serving the party on {want[0]}:{want[1]}')

    def stop(self):
        if self.server is not None:
            srv, self.server, self.server_key = self.server, None, None
            srv.shutdown()
            srv.server_close()

    # ------------------------------------------------------------------ state
    def _me(self):
        """this wizard's state to send: AutoFarmer's fields and the memory's place, the door, the battle spot"""
        with self.lock:
            s = dict(self.ahk)
            m = self.mem
            fresh = m and time.time() - m.get('at', 0) < 3
            for k in ('zone', 'x', 'y', 'z', 'yaw'):
                s[k] = m.get(k) if fresh else (None if k != 'zone' else '')
            s['name'] = self.cfg['name']
            s['door'] = dict(self.door) if self.door else None
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
                 'hitr', 'plan', 'lasthit')} for o in others]}

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
        me = self._me()
        q = {k: ('' if v is None else v) for k, v in me.items() if k not in ('door', 'bspot')}
        q['id'] = self.id
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
        with self.lock:
            last = self.trail[-1] if self.trail else None
            if last and last[1] != r['zone']:
                # (the zone changed: the last spot in the old one, and the way it was going there - from ~1.5 s before)
                old = [p for p in self.trail if p[1] == last[1]]
                back = next((p for p in old if last[0] - p[0] <= 1.5), old[0])
                dx, dy = last[2] - back[2], last[3] - back[3]
                n = math.hypot(dx, dy) or 1.0
                self.door = {'zone': last[1], 'x': last[2], 'y': last[3], 'z': last[4], 'dx': dx / n, 'dy': dy / n,
                             'to': r['zone'], 'at': now}
                self.trail = []
            self.trail.append((now, r['zone'], x, y, z))
            self.trail = [p for p in self.trail if now - p[0] <= 4.0]
            self.mem = {'zone': r['zone'], 'x': x, 'y': y, 'z': z, 'yaw': r.get('yaw'), 'at': now}

    # ------------------------------------------------------------------ to AutoFarmer
    def lines(self):
        """party|role|state|why; me|zone|x|y|z|yaw; leader|...; member|... (one per follower, the leader's view)"""
        def num(v, d=0):
            return '' if v is None else f'{v:.{d}f}'
        now = time.time()
        with self.lock:
            role, state, why = self.cfg['role'], self.state, self.why
            m = self.mem
            out = [f'party|{role}|{state}|{why}',
                   f"me|{m.get('zone', '')}|{num(m.get('x'))}|{num(m.get('y'))}|{num(m.get('z'))}|{num(m.get('yaw'), 4)}"]
            if role == 'follower' and self.leader:
                L = self.leader
                age = round((now - L['at']) * 1000)
                dist = ''
                if L.get('zone') and L.get('zone') == m.get('zone') and L.get('x') is not None and m.get('x') is not None:
                    dist = f"{math.hypot(L['x'] - m['x'], L['y'] - m['y']):.0f}"
                d = L.get('door') or {}
                b = L.get('bspot') or (None, None, None)
                out.append('leader|' + '|'.join([
                    L.get('name') or '', L.get('zone') or '', num(L.get('x')), num(L.get('y')), num(L.get('z')),
                    num(L.get('yaw'), 4), L.get('battle', '0'), num(L.get('hp')), L.get('ready', '0'), L.get('walk', '0'),
                    str(age), dist, d.get('zone', ''), num(d.get('x')), num(d.get('y')), num(d.get('z')),
                    num(d.get('dx'), 3), num(d.get('dy'), 3), d.get('to', ''), num(b[0]), num(b[1]), num(b[2]),
                    L.get('hold') or '', L.get('brole') or '', L.get('wiz') or '', L.get('school') or '',
                    num(L.get('hits')), num(L.get('hitr')), L.get('plan') or '', L.get('lasthit') or '']))
                # (the other followers: as the leader's own rows below - walk, loading and hold where it doesn't say)
                for o in L.get('others') or []:
                    # (its age as the leader last heard it, and since that answer: a leader gone quiet takes them along)
                    oa = o.get('age')
                    out.append('member|' + '|'.join([o.get('name') or '', o.get('zone') or '', num(o.get('x')),
                               num(o.get('y')), num(o.get('z')), o.get('battle', '0'), num(o.get('hp')),
                               o.get('ready', '0'), str(oa + age) if isinstance(oa, int) else '', '', o.get('walk', '0'), '0', '',
                               o.get('brole') or '', o.get('wiz') or '', o.get('school') or '', num(o.get('hits')),
                               num(o.get('hitr')), o.get('plan') or '', o.get('lasthit') or '']))
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
                               v.get('lasthit') or '']))
        return out
