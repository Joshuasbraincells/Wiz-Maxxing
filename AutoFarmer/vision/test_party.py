"""test_party.py - the party link's checks (standard library only):  python -m unittest test_party  (in AutoFarmer\\vision)

The leader's doors (walked or a teleport, the last three with their ages), its loading flag and time in its zone, the
teleport advice (port_advice), a follower's teleport state (tp), and the lines AutoHotkey reads (Party.ahk PartyTick:
f[1] the line's kind - the fields it knew before stay where they were). No network, no thread: a stand-in reader and
clock, and Party's background loop switched off."""
import json
import os
import sys
import unittest
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import party as P  # noqa: E402


class Clock:
    """party.time stood in for: time() and monotonic() as set, sleep() moves it on"""

    def __init__(self, t=1000.0):
        self.t = t

    def time(self):
        return self.t

    def monotonic(self):
        return self.t

    def sleep(self, s):
        self.t += s


class Quiet(P.Party):
    """a Party whose background loop does nothing (the tests call _read, beat_in and lines themselves)"""

    def _loop(self):
        return


def ahk_fields(line, n=37):
    """a line as Party.ahk splits it: f[1] its kind, a field it doesn't have blank (1-based: f[k] is out[k])"""
    f = line.split('|')
    while len(f) < n:
        f.append('')
    return [None] + f


class PartyCase(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self._time = P.time
        P.time = self.clock
        self.logged = []

    def tearDown(self):
        P.time = self._time

    def make(self, role):
        """a Party with a stand-in reader (self.reading[party]) - its role set straight in (update() would start the
        leader's LAN server)"""
        box = {'r': None}
        p = Quiet(lambda: box['r'], log=self.logged.append)
        p.box = box
        p.cfg['role'] = role
        return p

    def at(self, p, zone, x, y, z=0.0, source='body'):
        """one reading of p's wizard (zone, place - navmem's source: 'body', or 'object' while zoning), then the clock on
        0.4 s"""
        p.box['r'] = {'zone': zone, 'pos': (x, y, z), 'yaw': 0.0, 'source': source}
        p._read()
        self.clock.t += 0.4

    def walk(self, p, zone, x0, y0, vx, vy, secs=2.0):
        """p walking in zone from (x0, y0) at (vx, vy) units a second, read every 0.4 s"""
        for i in range(int(round(secs / 0.4)) + 1):
            self.at(p, zone, x0 + vx * 0.4 * i, y0 + vy * 0.4 * i)

    def stand(self, p, zone, x, y, secs=2.0):
        for _ in range(int(round(secs / 0.4)) + 1):
            self.at(p, zone, x, y)

    def follow(self, leader, follower):
        """the follower's beat to the leader, its answer through JSON as on the network (_beat_out's own handling)"""
        d = json.loads(json.dumps(leader.beat_in({'id': follower.id, **follower._beat_query()}, '192.168.1.20')))
        follower.leader = dict(P.clean_peer(d.get('leader')), at=self.clock.t, others=[])
        return d


class Doors(PartyCase):
    def test_walked_door(self):
        L = self.make('leader')
        self.walk(L, 'WizardCity/WC_Ravenwood', 0, 0, 400, 0)
        self.at(L, 'WizardCity/WC_Commons', 5000, 5000)
        d = L.door
        self.assertEqual((d['zone'], d['to'], d['walked']), ('WizardCity/WC_Ravenwood', 'WizardCity/WC_Commons', True))
        self.assertAlmostEqual(d['x'], 800.0)              # its last spot in the zone it left
        self.assertAlmostEqual(d['dx'], 1.0)               # and the way it was going
        self.assertAlmostEqual(d['dy'], 0.0)
        self.assertEqual(L.doors, [d])
        self.assertIn('walked through a door', self.logged[-1])

    def test_teleport_standing_still(self):
        # (End / Home / a sigil / a friend's teleport: it stood still before the zone changed - before, this made a door
        # with no way on (dx = dy = 0) that a follower walked to and pushed into forever)
        L = self.make('leader')
        self.stand(L, 'WizardCity/WC_Ravenwood', 100, 100)
        self.at(L, 'WizardCity/WC_Commons', 0, 0)
        d = L.door
        self.assertIs(d['walked'], False)
        self.assertEqual((d['x'], d['y'], d['dx'], d['dy']), (100, 100, 0.0, 0.0))
        self.assertIn('a teleport', self.logged[-1])

    def test_zoning_reads_left_out(self):
        # (walked 2 s at 1000 a second, then 1.6 s of readings still in the old zone, frozen at the doorway, from the
        # ClientObject's own copy - no body: zoning -, then the new zone: a door walked through, its way on the way it
        # went - it was "a teleport", its way on none, and a follower refused the door)
        L = self.make('leader')
        self.walk(L, 'A', 0, 0, 1000, 0)
        for _ in range(4):
            self.at(L, 'A', 2000, 0, source='object')
        self.at(L, 'B', 0, 0)
        d = L.door
        self.assertIs(d['walked'], True)
        self.assertEqual((d['x'], d['y']), (2000, 0))              # its last spot in A, as before
        self.assertAlmostEqual(d['dx'], 1.0)
        self.assertIn('walked through a door', self.logged[-1])
        self.assertIn('4 zoning reads left out', self.logged[-1])
        self.assertIn('still for the last 1.6 s', self.logged[-1])

    def test_all_zoning_reads_kept(self):
        # (nothing but zoning reads in the zone left: those, as before - here it stood still)
        L = self.make('leader')
        self.stand(L, 'A', 5, 5)
        L.trail = [p[:5] + (True,) for p in L.trail]
        self.at(L, 'B', 0, 0)
        self.assertIs(L.door['walked'], False)
        self.assertNotIn('zoning reads left out', self.logged[-1])

    def test_still_for(self):
        trail = [(0.0, 'A', 0, 0, 0), (0.4, 'A', 400, 0, 0), (0.8, 'A', 400.5, 0, 0), (1.2, 'A', 400, 0, 0)]
        self.assertAlmostEqual(P.still_for(trail), 0.8)
        self.assertEqual(P.still_for(trail[:2]), 0.0)
        self.assertEqual(P.still_for([]), 0.0)

    def test_too_little_trail(self):
        L = self.make('leader')
        self.at(L, 'A', 0, 0)
        self.at(L, 'B', 900, 0)
        self.assertIsNone(L.door['walked'])

    def test_slow_reads(self):
        # (readings 2 s apart - a slow read: the one before is looked at)
        w, moved, span, back = P.walked_before([(0.0, 'A', 0, 0, 0), (2.0, 'A', 1500, 0, 0)])
        self.assertIs(w, True)
        self.assertEqual((moved, span, back[2]), (1500, 2.0, 0))
        self.assertIs(P.walked_before([(0.0, 'A', 5, 5, 0), (2.0, 'A', 5, 5, 0)])[0], False)
        self.assertEqual(P.walked_before([]), (None, 0.0, 0.0, None))

    def test_last_three_kept(self):
        L = self.make('leader')
        for i, (a, b) in enumerate([('A', 'B'), ('B', 'C'), ('C', 'D'), ('D', 'E')]):
            self.walk(L, a, 0, 0, 0, 500)
            self.at(L, b, 0, 0)
        self.assertEqual([(d['zone'], d['to']) for d in L.doors], [('B', 'C'), ('C', 'D'), ('D', 'E')])
        self.assertIs(L.door, L.doors[-1])

    def test_door_from_latest(self):
        doors = [{'zone': 'A', 'to': 'B'}, {'zone': 'B', 'to': 'A'}, {'zone': 'A', 'to': 'C'}]
        self.assertEqual(P.door_from('A', doors)['to'], 'C')        # where its path went on the last time it was there
        self.assertEqual(P.door_from('B', doors)['to'], 'A')
        self.assertIsNone(P.door_from('D', doors))
        self.assertIsNone(P.door_from('', doors))
        self.assertIsNone(P.door_from('A', None))

    def test_zone_age_and_doors_sent(self):
        L = self.make('leader')
        self.walk(L, 'A', 0, 0, 500, 0)
        t_in = self.clock.t
        self.at(L, 'B', 0, 0)
        self.stand(L, 'B', 0, 0, secs=2.0)
        me = L._me()
        self.assertEqual(me['zage'], round((self.clock.t - t_in) * 1000))   # since its first reading in B
        self.assertEqual(len(me['doors']), 1)
        self.assertNotIn('at', me['doors'][0])                     # an age, not the leader's clock
        self.assertEqual(me['doors'][0]['age'], me['zage'])
        self.assertIs(me['doors'][0]['walked'], True)
        json.dumps(me)                                             # the answer is JSON
        # (its zone not read for FRESH s - a loading screen: no zone, no zone age)
        self.clock.t += P.FRESH + 1
        me = L._me()
        self.assertEqual((me['zone'], me['zage']), ('', None))


class Advice(PartyCase):
    def leader(self, **kw):
        L = {'zone': 'C', 'loading': '0', 'zage': 10000, 'doors': [], 'at': self.clock.t}
        L.update(kw)
        return L

    def test_teleport_when_no_door(self):
        port, why = P.port_advice('A', self.leader(), self.clock.t)
        self.assertEqual(port, '1')
        self.assertIn('no door', why)
        self.assertNotIn('|', why)

    def test_teleported_from_here(self):
        L = self.leader(doors=[{'zone': 'A', 'to': 'C', 'walked': False}])
        port, why = P.port_advice('A', L, self.clock.t)
        self.assertEqual(port, '1')
        self.assertIn('teleported', why)

    def test_not_when(self):
        t = self.clock.t
        cases = [
            ('A', None, 'not heard'),
            ('A', self.leader(at=t - 6), 'not heard from in 6 s'),
            ('A', self.leader(zone=''), "zone isn't known"),
            ('', self.leader(), "this wizard's zone"),
            ('C', self.leader(), 'same zone'),
            ('A', self.leader(loading='1'), 'loading'),
            ('A', self.leader(zage=None), 'older version'),
            ('A', self.leader(zage=1000), 'only just got'),
            ('A', self.leader(doors=[{'zone': 'A', 'to': 'B', 'walked': True}]), 'walked through'),
            # (walked not known - an older leader's helper: a door to try, as ever)
            ('A', self.leader(doors=[{'zone': 'A', 'to': 'B', 'walked': None}]), 'walked through'),
        ]
        for me_zone, L, why in cases:
            with self.subTest(why=why):
                port, said = P.port_advice(me_zone, L, t)
                self.assertEqual(port, '0')
                self.assertIn(why, said)

    def test_zone_age_counts_since_heard(self):
        # (2.5 s in its zone as sent, heard 1 s ago: 3.5 s - old enough)
        L = self.leader(zage=2500, at=self.clock.t - 1.0)
        self.assertEqual(P.port_advice('A', L, self.clock.t)[0], '1')


class Lines(PartyCase):
    def leader_row(self, follower):
        rows = [ln for ln in follower.lines() if ln.startswith('leader|')]
        self.assertEqual(len(rows), 1)
        self.assertEqual(len(rows[0].split('|')), 37)              # 38-39 left for the battle planner's hit round
        return ahk_fields(rows[0])

    def test_chain_door_out_of_own_zone(self):
        # (A -> B -> C walked: a follower in A gets the door A -> B, not the last one - it had none before)
        L, F = self.make('leader'), self.make('follower')
        self.walk(L, 'A', 0, 0, 500, 0)
        self.at(L, 'B', 0, 0)
        self.walk(L, 'B', 0, 0, 0, 500)
        self.at(L, 'C', 0, 0)
        self.stand(L, 'C', 0, 0, secs=4.0)
        self.at(F, 'A', 300, 0)
        self.follow(L, F)
        f = self.leader_row(F)
        self.assertEqual((f[3], f[14], f[20], f[33], f[36]), ('C', 'A', 'B', '1', '0'))
        self.assertAlmostEqual(float(f[18]), 1.0)
        self.assertIn('walked through', f[37])
        # (through it, in B: the door B -> C)
        self.at(F, 'B', 0, 0)
        f = self.leader_row(F)
        self.assertEqual((f[14], f[20], f[33]), ('B', 'C', '1'))

    def test_teleport_away(self):
        L, F = self.make('leader'), self.make('follower')
        self.stand(L, 'A', 50, 50)
        self.at(L, 'Home', 0, 0)
        self.stand(L, 'Home', 0, 0, secs=1.2)
        self.at(F, 'A', 300, 0)
        self.follow(L, F)
        f = self.leader_row(F)
        self.assertEqual((f[14], f[20], f[33]), ('A', 'Home', '0'))
        self.assertEqual(f[36], '0')                               # under PORT_ZONE_AGE s there: not yet
        self.assertIn('only just got', f[37])
        self.stand(L, 'Home', 0, 0, secs=3.2)
        self.at(F, 'A', 300, 0)
        self.follow(L, F)
        f = self.leader_row(F)
        self.assertEqual(f[36], '1')
        self.assertGreaterEqual(int(f[34]), 3000)                  # its zone's age
        self.assertGreaterEqual(int(f[35]), int(f[34]))            # the door's: older

    def test_long_in_its_zone(self):
        # (17 minutes in Home, its door 20 minutes old - past 1e6 ms: they read as no age, "an older version", and the
        # teleport advice never came)
        L, F = self.make('leader'), self.make('follower')
        self.stand(L, 'A', 50, 50)
        self.at(L, 'Home', 0, 0)
        L.zone_at = self.clock.t - 17 * 60
        L.doors[-1]['at'] = L.door['at'] = self.clock.t - 20 * 60
        self.stand(L, 'Home', 0, 0, secs=0.4)
        self.at(F, 'A', 300, 0)
        self.follow(L, F)
        self.assertGreater(F.leader['zage'], 1000000)
        f = self.leader_row(F)
        self.assertGreaterEqual(int(f[34]), 17 * 60 * 1000)
        self.assertGreaterEqual(int(f[35]), 20 * 60 * 1000)
        self.assertEqual(f[36], '1')
        self.assertIn('teleported', f[37])

    def test_fields_known_before_stay(self):
        L, F = self.make('leader'), self.make('follower')
        L.ahk = P.clean_state({'battle': '1', 'hp': '77', 'ready': '1', 'walk': '1', 'hold': 'Bob is loading',
                               'brole': 'hitter', 'wiz': 'Ned Stormblade', 'school': 'storm', 'hits': '4', 'hitr': '9',
                               'plan': 'storm,fire', 'lasthit': 'storm', 'loading': '1'})
        L.cfg['name'] = 'Ned'
        self.walk(L, 'A', 0, 0, 500, 0)
        L.battle_spot = (11.0, 22.0, 33.0)
        self.at(L, 'B', 10, 20, 30)
        self.at(F, 'A', 0, 0)
        self.follow(L, F)
        f = self.leader_row(F)
        self.assertEqual(len(f) - 1, 37)
        # (Party.ahk PartyTick's leader fields 2-31, as ever)
        want = {2: 'Ned', 3: 'B', 4: '10', 5: '20', 6: '30', 8: '1', 9: '77', 10: '1', 11: '1', 14: 'A', 15: '1000',
                16: '0', 17: '0', 18: '1.000', 19: '0.000', 20: 'B', 21: '11', 22: '22', 23: '33', 24: 'Bob is loading',
                25: 'hitter', 26: 'Ned Stormblade', 27: 'storm', 28: '4', 29: '9', 30: 'storm,fire', 31: 'storm'}
        for k, v in want.items():
            with self.subTest(field=k):
                self.assertEqual(f[k], v)
        self.assertEqual(f[7], '0.0000')                            # its yaw
        self.assertTrue(f[12].isdigit())                            # the answer's age (ms)
        self.assertEqual(f[13], '')                                 # another zone: no distance
        # (the new ones: 32 loading, 33 dwalk, 36 port - it's loading: not now)
        self.assertEqual((f[32], f[33], f[36]), ('1', '1', '0'))
        self.assertIn('loading', f[37])

    def test_older_leader(self):
        # (a leader running the helper before this: one door, no walked, no ages, no zone age - fields 14-20 as before)
        F = self.make('follower')
        self.at(F, 'A', 0, 0)
        old = {'name': 'Ned', 'zone': 'B', 'x': 1, 'y': 2, 'z': 3, 'loading': '0',
               'door': {'zone': 'A', 'x': 10, 'y': 20, 'z': 0, 'dx': 0.6, 'dy': 0.8, 'to': 'B', 'at': 12345.0},
               'bspot': None}
        F.leader = dict(P.clean_peer(old), at=self.clock.t, others=[])
        self.assertEqual(len(F.leader['doors']), 1)
        self.assertIsNone(F.leader['doors'][0]['walked'])
        f = self.leader_row(F)
        self.assertEqual((f[14], f[15], f[16], f[18], f[19], f[20]), ('A', '10', '20', '0.600', '0.800', 'B'))
        self.assertEqual((f[33], f[34], f[35], f[36]), ('', '', '', '0'))
        self.assertIn('older version', f[37])

    def test_older_follower_reads_new_leader(self):
        # (a follower running the helper before this reads the new answer's door as ever: the doors list and the zone's
        # age aren't text or numbers it takes)
        L = self.make('leader')
        self.walk(L, 'A', 0, 0, 500, 0)
        self.at(L, 'B', 0, 0)
        d = json.loads(json.dumps(L.beat_in({'id': 'ab'}, '10.0.0.2')))
        old_view = {k: str(v) for k, v in d['leader'].items() if isinstance(v, (str, int, float))}
        self.assertNotIn('doors', old_view)
        self.assertEqual(d['leader']['door']['zone'], 'A')
        self.assertEqual(P.clean_state(old_view)['zone'], 'B')

    def test_me_line_not_stale(self):
        F = self.make('follower')
        self.at(F, 'A', 5, 6)
        self.assertEqual(ahk_fields(F.lines()[1])[2], 'A')
        self.clock.t += P.FRESH + 1                                 # a loading screen: nothing read since
        f = ahk_fields(F.lines()[1])
        self.assertEqual((f[1], f[2], f[3]), ('me', '', ''))


class TeleportState(PartyCase):
    def test_tp_cleaned(self):
        s = P.clean_state({'tp': 'wait', 'tpwhy': 'no door the leader walked through leads to WizardCity/WC_Commons'})
        self.assertEqual(s['tp'], 'wait')
        self.assertTrue(s['tpwhy'].startswith('no door'))
        self.assertEqual(P.clean_state({'tp': 'buy crowns', 'tpwhy': 'x'})['tp'], '')
        self.assertEqual(P.clean_state({'tp': 'wait', 'tpwhy': 'a|b'})['tpwhy'], '')
        self.assertEqual(P.clean_state({'tpwhy': 'nothing to say it for'})['tpwhy'], '')   # no tp, no why
        self.assertEqual(P.clean_state({})['tp'], '')

    def test_member_rows_carry_tp(self):
        L, F, G = self.make('leader'), self.make('follower'), self.make('follower')
        self.at(L, 'A', 0, 0)
        self.at(F, 'B', 0, 0)
        F.ahk = P.clean_state({'name': 'Bob', 'tp': 'wait', 'tpwhy': 'the leader teleported from here to Home'})
        F.cfg['name'] = 'Bob'
        self.follow(L, F)
        rows = [ahk_fields(ln) for ln in L.lines() if ln.startswith('member|')]
        self.assertEqual(len(rows), 1)
        f = rows[0]
        self.assertEqual(len(f) - 1, 37)                            # padded as Party.ahk pads
        self.assertEqual(len(L.lines()[-1].split('|')), 23)         # 24-25 left for the battle planner
        why = 'the leader teleported from here to Home'
        self.assertEqual((f[2], f[3], f[13], f[22], f[23]), ('Bob', 'B', '0', 'wait', why))
        # (another follower sees Bob's the same way - the leader passes it on)
        self.at(G, 'A', 0, 0)
        d = self.follow(L, G)
        others = []
        for o in d['others']:
            c = P.clean_state({k: str(v) for k, v in o.items() if isinstance(v, (str, int, float))})
            c['age'] = int(o['age'])
            others.append(c)
        G.leader['others'] = others
        rows = [ahk_fields(ln) for ln in G.lines() if ln.startswith('member|')]
        self.assertEqual((rows[0][2], rows[0][22], rows[0][23]), ('Bob', 'wait', why))

    def test_beat_query(self):
        F = self.make('follower')
        F.cfg['name'] = 'Bob'
        F.ahk = P.clean_state({'name': 'Bob', 'tp': 'stuck', 'tpwhy': 'stuck on the way to the leader', 'hold': ''})
        self.walk(F, 'A', 0, 0, 500, 0)
        self.at(F, 'B', 0, 0)
        q = F._beat_query()
        for k in ('door', 'doors', 'bspot', 'zage'):
            self.assertNotIn(k, q)
        self.assertEqual((q['tp'], q['id']), ('stuck', F.id))
        # (an everyday long one - a 40-character zone, a 70-character why and hold, every school: all of it sent)
        F.ahk = P.clean_state({'name': 'Bob', 'wiz': 'Bob Stormblade', 'tp': 'wait', 'tpwhy': 'x' * 70,
                               'hold': 'Ned is in another zone (stuck on its way)', 'plan': ','.join(P.SCHOOLS)})
        self.at(F, 'WizardCity/WC_Streets/Interiors/WC_Ravenwood', 1234.5, -5678.5, 90.25)
        q = F._beat_query()
        self.assertEqual((q['tpwhy'], q['hold']), ('x' * 70, 'Ned is in another zone (stuck on its way)'))
        # (the longest the checks let by - each field of the characters the URL makes 3 of: a 120-character zone of
        # backslashes, 24-character names and an 80-character hold and why of apostrophes, every school: ~1300, over the
        # server's 1024 - its why and hold left out till it fits, the rest kept)
        F.ahk = P.clean_state({'name': "'" * 24, 'wiz': "'" * 24, 'tp': 'wait', 'tpwhy': "'" * 80,
                               'hold': "'" * 80, 'plan': ','.join(P.SCHOOLS), 'lasthit': ','.join(P.SCHOOLS),
                               'hits': '999999', 'hitr': '999999', 'hp': '100', 'brole': 'healer', 'school': 'balance'})
        F.cfg['name'] = "'" * 24
        self.at(F, '\\' * 120, -99999.5, -99999.5, -99999.5)
        self.assertEqual(len(F._me()['zone']), 120)
        full = dict(F._me(), id=F.id)
        full = {k: ('' if v is None else v) for k, v in full.items() if k not in ('door', 'doors', 'bspot', 'zage')}
        self.assertGreater(len('/party/beat?' + urllib.parse.urlencode(full)), P.MAX_PATH)
        path = '/party/beat?' + urllib.parse.urlencode(F._beat_query())
        self.assertLessEqual(len(path), P.MAX_PATH)
        got = P.clean_state({k: v[0] for k, v in urllib.parse.parse_qs(path.split('?', 1)[1]).items()})
        self.assertEqual((got['tp'], got['zone'], got['name'], got['wiz']), ('wait', '\\' * 120, "'" * 24, "'" * 24))
        self.assertEqual((got['tpwhy'], got['hold']), ('', ''))


class Clean(unittest.TestCase):
    def test_doors_cleaned(self):
        s = P.clean_peer({'zone': 'B', 'doors': [{'zone': 'A\n', 'to': 'B'}, 'junk', None,
                                                 {'zone': 'C', 'to': 'D', 'x': 'nan', 'walked': 'yes', 'age': -5},
                                                 {'zone': 'D', 'to': 'E', 'x': 1, 'walked': 0, 'age': 250.7}]})
        self.assertEqual([d['zone'] for d in s['doors']], ['C', 'D'])   # the last three sent, the junk left out
        self.assertEqual((s['doors'][0]['x'], s['doors'][0]['walked'], s['doors'][0]['age']), (None, None, None))
        self.assertEqual((s['doors'][1]['walked'], s['doors'][1]['age']), (False, 250))
        s = P.clean_peer({'doors': [{'zone': 'A\n', 'to': 'B|C'}]})
        self.assertEqual((s['doors'][0]['zone'], s['doors'][0]['to']), ('', ''))   # nothing that breaks a line
        self.assertEqual(P.clean_peer({'doors': 'A'})['doors'], [])
        self.assertEqual(P.clean_peer({})['doors'], [])
        self.assertIsNone(P.clean_peer({'zage': 'soon'})['zage'])
        self.assertEqual(P.clean_peer({'zage': 4000})['zage'], 4000)
        self.assertEqual(P.clean_peer('not a dict')['doors'], [])

    def test_ages_past_16_minutes(self):
        # (ms ages aren't places: 1e6 - _f's cap - is 16.7 minutes; up to ~11 days taken)
        self.assertEqual((P._ms(999999), P._ms(1000000), P._ms('1200000'), P._ms(1026000.7)),
                         (999999, 1000000, 1200000, 1026000))
        for junk in (1e9, -1, 'nan', 'inf', None, '', 'soon', True, [5]):
            with self.subTest(age=junk):
                self.assertIsNone(P._ms(junk))
        s = P.clean_peer({'zage': 1026000, 'doors': [{'zone': 'A', 'to': 'Home', 'walked': 0, 'age': 1200000}]})
        self.assertEqual((s['zage'], s['doors'][0]['age']), (1026000, 1200000))


if __name__ == '__main__':
    unittest.main()
