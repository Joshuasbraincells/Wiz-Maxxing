"""test_navroute.py - the route planner's mob checks on a flat stand-in zone (no game, no zone files):
python -m unittest vision\\test_navroute.py  (from AutoFarmer\\vision: python -m unittest test_navroute)

Today's ways pinned first (rings, sight cones, the waits, getting out, a new field when mobs move), then mobs walking
(MobMotion, the sweep, the predicted replans and waits), a line of mobs as one wall, other players' battles, and the
vision helper's lines for them (/mobs, /caught, /nav's route line, /duels, the map)"""
import math
import os
import sys
import tempfile
import time
import unittest

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import navroute as R  # noqa: E402


class FlatGeo:
    """a stand-in ZoneGeo: floor everywhere at height 0, no water, solid only inside the rectangles walls
    [(x1, y1, x2, y2)]; no nav graph"""

    def __init__(self, walls=(), zone='Test/Flat'):
        self.zone, self.why, self.walls = zone, '', list(walls)

    def grids(self, x0, y0, nx, ny, ref):
        X = x0 + (np.arange(nx) + 0.5) * R.CELL
        Y = y0 + (np.arange(ny) + 0.5) * R.CELL
        solid = np.zeros((ny, nx), dtype=bool)
        for x1, y1, x2, y2 in self.walls:
            solid |= (X[None, :] >= x1) & (X[None, :] <= x2) & (Y[:, None] >= y1) & (Y[:, None] <= y2)
        return np.ones((ny, nx), dtype=int), np.zeros((ny, nx)), solid

    def navgraph(self):
        return None

    def is_jump(self, a, b):
        return R.is_jump(a, b)


def field(mobs=(), pos=(0.0, 0.0, 0.0), carrot=(0.0, 2000.0), mob_near=300.0, cone=(0.0, 0.0), geo=None, **kw):
    return R.Field(geo or FlatGeo(), pos, carrot, (carrot[0], carrot[1], 0.0), 0.0, carrot_z=0.0, mobs=mobs,
                   mob_near=mob_near, cone=cone, **kw)


def route_pts(f, pos):
    cells, _ = f.walk(pos)
    return [(pos[0], pos[1])] + [f.world(*c) for c in cells[1:]]


def crossing(pts, y):
    """the x where the route crosses height y (the first time)"""
    for a, b in zip(pts, pts[1:]):
        if (a[1] - y) * (b[1] - y) <= 0 and a[1] != b[1]:
            return a[0] + (b[0] - a[0]) * (y - a[1]) / (b[1] - a[1])
    return None


def mob(x, y, yaw=None, gid=1, name='Crab', vel=None, moving=None, **kw):
    m = {'pos': (float(x), float(y), 0.0), 'yaw': yaw, 'gid': gid, 'name': name}
    if vel is not None:
        m['vel'], m['moving'] = vel, True if moving is None else moving
    m.update(kw)
    return m


def planner(geo=None):
    logs = []
    p = R.Planner(log=logs.append)
    geo = geo or FlatGeo()
    p.zones[geo.zone] = geo
    return p, logs, geo


def settle(p, r, n=60, **kw):
    """route() asked again until the background field is made for it and no new one is wanted"""
    out = None
    for _ in range(n):
        out = p.route(r, **kw)
        t0 = time.time()
        while (p.busy or p.want is not None) and time.time() - t0 < 10:
            time.sleep(0.005)
        if out.get('aim') is not None and p.want is None and not p.busy:
            again = p.route(r, **kw)
            if p.want is None and not p.busy:
                return again
    return out


def reading(pos=(0.0, 0.0, 0.0), goal=(0.0, 2000.0, 0.0), zone='Test/Flat', yaw=math.pi):
    return {'pos': pos, 'goal': goal, 'zone': zone, 'path': [], 'yaw': yaw, 'target': goal}


class Baseline(unittest.TestCase):
    """today's behaviour, pinned before mobs walking and walls changed anything"""

    def test_ring_cost(self):
        f = field([(0.0, 1000.0, 0.0, None, True)], mob_near=300.0)
        j, i = f.cell((0.0, 1000.0))
        self.assertAlmostEqual(f.cost[j, i], 1.0 + R.MOB_COST)
        j, i = f.cell((0.0, 1400.0))                         # (between mob_near and MOB_SOFT: dearer, less)
        self.assertTrue(1.0 < f.cost[j, i] < 1.0 + R.MOB_SOFT_COST + 1e-9)
        j, i = f.cell((0.0, 1700.0))
        self.assertAlmostEqual(f.cost[j, i], 1.0)
        self.assertTrue(f.mob_mask[f.cell((0.0, 1250.0))])
        self.assertFalse(f.mob_mask[f.cell((0.0, 1400.0))])

    def test_cone_by_yaw(self):
        # yaw 0 faces -Y: a semi-circle 300 long that way, its body 120 all round
        f = field([(0.0, 1000.0, 0.0, 0.0, True)], mob_near=120.0, cone=(180.0, 300.0))
        self.assertTrue(f.mob_mask[f.cell((0.0, 760.0))])
        self.assertFalse(f.mob_mask[f.cell((0.0, 1240.0))])
        self.assertTrue(f.mob_mask[f.cell((0.0, 1100.0))])

    def test_unknown_facing_whole_circle(self):
        f = field([(0.0, 1000.0, 0.0, None, True)], mob_near=120.0, cone=(180.0, 300.0))
        self.assertTrue(f.mob_mask[f.cell((0.0, 760.0))])
        self.assertTrue(f.mob_mask[f.cell((0.0, 1240.0))])

    def test_route_round_one_mob(self):
        f = field([(0.0, 1000.0, 0.0, None, True)], mob_near=300.0)
        pts = route_pts(f, (0.0, 0.0))
        self.assertGreater(min(math.hypot(p[0], p[1] - 1000.0) for p in pts), 300.0)

    def test_mob_on_way_ring_and_cone(self):
        pts = [(0.0, y) for y in range(0, 1001, 20)]
        m = mob(0.0, 600.0)
        self.assertEqual(R.Planner._mob_on_way(pts, [m], 300.0, 0.0)['block'], 'ring')
        # (a cone facing the route from the side - the ring nowhere near it)
        m2 = mob(500.0, 600.0, yaw=math.pi / 2)              # forward (-1, 0): towards the route
        self.assertEqual(R.Planner._mob_on_way(pts, [m2], 120.0, 0.0, (60.0, 600.0))['block'], 'cone')
        # (one behind the wizard doesn't count)
        self.assertIsNone(R.Planner._mob_on_way(pts, [mob(0.0, -400.0)], 300.0, 0.0))

    def test_escape_out_of_a_ring(self):
        f = field([(0.0, 1000.0, 0.0, None, True)], pos=(0.0, 850.0, 0.0), carrot=(0.0, 2000.0))
        pts = route_pts(f, (0.0, 850.0))
        esc = R.Planner()._escape(f, (0.0, 850.0, 0.0), pts, [mob(0.0, 1000.0)], 300.0, (0.0, 0.0))
        self.assertIn(esc[0], ('route', 'spot'))
        if esc[0] == 'spot':
            self.assertGreater(math.hypot(esc[2][0], esc[2][1] - 1000.0), 300.0)

    def test_mobs_moved(self):
        f = field([(0.0, 1000.0, 0.0, 0.5, True)], mob_near=120.0, cone=(180.0, 300.0))
        P = R.Planner
        self.assertFalse(P._mobs_moved(f, [(0.0, 1000.0, 0.0, 0.5, True)]))
        self.assertFalse(P._mobs_moved(f, [(30.0, 1000.0, 0.0, 0.5, True)]))
        self.assertTrue(P._mobs_moved(f, [(100.0, 1000.0, 0.0, 0.5, True)]))
        self.assertTrue(P._mobs_moved(f, [(0.0, 1000.0, 0.0, 1.0, True)]))           # (turned 0.5 rad)
        self.assertTrue(P._mobs_moved(f, []))                                         # (gone)
        self.assertTrue(P._mobs_moved(f, [(0.0, 1000.0, 0.0, 0.5, False)]))          # (its sight given up)

    def test_still_mobs_as_before(self):
        # a mob given with no velocity, a 'moving' False one and the old 5-long tuple: the same field to the last bit
        old = field([(300.0, 1000.0, 0.0, 0.3, True)], mob_near=120.0, cone=(180.0, 300.0))
        new = field([(300.0, 1000.0, 0.0, 0.3, True, None, 5, True)], mob_near=120.0, cone=(180.0, 300.0))
        self.assertTrue(np.array_equal(old.cost, new.cost))
        self.assertTrue(np.array_equal(old.D, new.D))
        p1, _, _ = planner()
        p2, _, _ = planner()
        a = settle(p1, reading(), wait=False, mobs=[mob(300.0, 1000.0, yaw=0.3)], mob_near=120.0, cone=(180.0, 300.0))
        b = settle(p2, reading(), wait=False, mobs=[mob(300.0, 1000.0, yaw=0.3, vel=(200.0, 0.0), moving=False)],
                   mob_near=120.0, cone=(180.0, 300.0))
        self.assertEqual(a['route'], b['route'])

    def test_planner_route_and_mob_wait(self):
        # a corridor 400 wide with a mob standing in it: no way round - the wait, then given up after MOB_GIVEUP
        geo = FlatGeo([(-3000.0, -1000.0, -200.0, 3000.0), (200.0, -1000.0, 3000.0, 3000.0)])
        p, logs, _ = planner(geo)
        r = reading()
        mobs = [mob(0.0, 700.0, gid=9, name='Guard')]
        out = settle(p, r, wait=True, mobs=mobs, cone=(0.0, 0.0))
        self.assertIn('mob', out)
        self.assertEqual(out['mob_name'], 'Guard')
        p.mwait['waited'] = R.MOB_GIVEUP + 1
        out = p.route(r, wait=True, mobs=mobs, cone=(0.0, 0.0))
        self.assertNotIn('mob', out)
        self.assertEqual(p.mob_ignored[9][1], 'ring')
        self.assertTrue(any('walking on past it' in s for s in logs))


class Motion(unittest.TestCase):
    """MobMotion: which way and how fast each mob walks"""

    @staticmethod
    def feed(mm, track, gid=1, me=None):
        for k, (t, x, y) in enumerate(track):
            mm.update(t, [{'gid': gid, 'pos': (x, y, 0.0), 'yaw': R.heading_yaw((1.0, 0.0))}],
                      me[k] if me is not None else None)

    def test_straight_walk(self):
        mm = R.MobMotion()
        self.feed(mm, [(k * 0.15, 100.0 * k * 0.15, 50.0) for k in range(14)])
        i = mm.info(1)
        self.assertTrue(i['moving'])
        self.assertAlmostEqual(i['vel'][0], 100.0, delta=1.0)
        self.assertAlmostEqual(i['vel'][1], 0.0, delta=1.0)
        self.assertAlmostEqual(i['agree'], 1.0, places=2)        # (it faces the way it walks)
        x, y = mm.predict(1, 1.0)
        self.assertAlmostEqual(x, 100.0 * 13 * 0.15 + 100.0, delta=2.0)
        self.assertGreater(i['walk_s'], 1.0)

    def test_too_few_readings(self):
        mm = R.MobMotion()
        self.feed(mm, [(0.0, 0.0, 0.0), (0.15, 15.0, 0.0)])
        self.assertIsNone(mm.info(1)['vel'])
        self.assertIsNone(mm.info(1)['moving'])
        self.assertEqual(mm.info(99), {})

    def test_stop(self):
        mm = R.MobMotion()
        walk = [(k * 0.15, 100.0 * k * 0.15, 0.0) for k in range(8)]
        stand = [(walk[-1][0] + k * 0.15, walk[-1][1], 0.0) for k in range(1, 6)]
        self.feed(mm, walk)
        self.assertTrue(mm.info(1)['moving'])
        self.feed(mm, stand)
        i = mm.info(1)
        self.assertFalse(i['moving'])                             # (stopped at once: still for MOVE_STILL_S)
        self.assertTrue(i['legs'] and i['legs'][-1][0])           # (the walk that ended kept)

    def test_turn(self):
        mm = R.MobMotion()
        a = [(k * 0.15, 100.0 * k * 0.15, 0.0) for k in range(11)]
        t0, x0 = a[-1][0], a[-1][1]
        b = [(t0 + k * 0.15, x0, 100.0 * k * 0.15) for k in range(1, 9)]
        self.feed(mm, a + b)
        v = mm.info(1)['vel']
        self.assertGreater(v[1], 80.0)
        self.assertLess(abs(v[0]), 20.0)

    def test_jitter_is_standing(self):
        mm = R.MobMotion()
        rng = np.random.default_rng(1)
        self.feed(mm, [(k * 0.15, float(rng.uniform(-5, 5)), float(rng.uniform(-5, 5))) for k in range(14)])
        self.assertFalse(mm.info(1)['moving'])

    def test_teleport_and_gap(self):
        mm = R.MobMotion()
        self.feed(mm, [(k * 0.15, 100.0 * k * 0.15, 0.0) for k in range(8)])
        self.feed(mm, [(1.2, 3000.0, 0.0)])                      # (2700 in 0.15 s: a jump)
        i = mm.info(1)
        self.assertEqual(i['jumps'], 1)
        self.assertIsNone(i['vel'])
        self.feed(mm, [(1.35, 3015.0, 0.0), (1.5, 3030.0, 0.0), (1.65, 3045.0, 0.0), (1.8, 3060.0, 0.0)])
        self.assertAlmostEqual(mm.info(1)['vel'][0], 100.0, delta=2.0)
        self.feed(mm, [(5.0, 3060.0, 0.0)])                      # (a gap: starts again, not a jump)
        self.assertEqual(mm.info(1)['jumps'], 1)
        self.assertIsNone(mm.info(1)['vel'])
        mm.update(5.0 + R.MOTION_FORGET + 1, [], None)           # (not read for long: forgotten)
        self.assertEqual(mm.info(1), {})

    def test_my_speed(self):
        mm = R.MobMotion()
        self.assertIsNone(mm.my_speed())
        for k in range(12):
            mm.update(k * 0.2, [], (1000.0 * k * 0.2 if k != 6 else 1000.0 * 1.0, 0.0, 0.0))
        self.assertAlmostEqual(mm.my_speed(), 1000.0, delta=60.0)

    def test_fit_velocity(self):
        self.assertIsNone(R.fit_velocity([(0.0, 0.0, 0.0), (0.1, 1.0, 0.0), (0.2, 2.0, 0.0)]))   # (over too short)
        v = R.fit_velocity([(0.0, 0.0, 0.0), (0.3, 30.0, -15.0), (0.6, 60.0, -30.0)])
        self.assertAlmostEqual(v[0], 100.0)
        self.assertAlmostEqual(v[1], -50.0)


class Sweep(unittest.TestCase):
    """a walking mob's ring and sight swept along its way"""

    def test_route_behind_a_walker(self):
        # a mob crossing the way from the left, facing the way it walks; a semi-circle in front, its body 120 round
        face = R.heading_yaw((1.0, 0.0))
        still = field([(-200.0, 1000.0, 0.0, face, True)], mob_near=120.0, cone=(180.0, 300.0))
        walks = field([(-200.0, 1000.0, 0.0, face, True, (150.0, 0.0))], mob_near=120.0, cone=(180.0, 300.0))
        x_still = crossing(route_pts(still, (0.0, 0.0)), 1000.0)
        x_walks = crossing(route_pts(walks, (0.0, 0.0)), 1000.0)
        self.assertGreater(x_still, -200.0)                     # (standing: round the front - the shorter way)
        self.assertLess(x_walks, -320.0)                        # (walking: behind it, its trailing side)
        # (the swept squares are kept out of the aim's line too)
        self.assertTrue(walks.mob_mask[walks.cell((150.0, 1000.0))])
        self.assertFalse(still.mob_mask[still.cell((150.0, 1000.0))])

    def test_sweep_limits(self):
        self.assertEqual(R.sweep_of(None), (0.0, 0.0))
        h, l = R.sweep_of((100.0, 0.0))
        self.assertAlmostEqual(h, R.MOTION_AHEAD_S)
        self.assertAlmostEqual(l, 100.0 * R.MOTION_AHEAD_S)
        h, l = R.sweep_of((1000.0, 0.0))
        self.assertAlmostEqual(l, R.MOTION_AHEAD_U)

    def test_unknown_facing_uses_heading(self):
        f = field([(0.0, 1000.0, 0.0, None, True, (0.0, -200.0))], mob_near=120.0, cone=(60.0, 300.0))
        # (where it will be - 500 on towards -Y - and its cone that way; nothing swept behind it)
        self.assertTrue(f.mob_mask[f.cell((0.0, 1000.0 - 500.0 - 200.0))])
        self.assertFalse(f.mob_mask[f.cell((0.0, 1000.0 + 400.0))])


class Prediction(unittest.TestCase):
    """a new field for a walking mob only when it leaves the field's prediction"""

    def setUp(self):
        self.t0 = 1000.0
        self.f = field([(0.0, 1000.0, 0.0, None, True, (150.0, 0.0), 7, True)], at=self.t0)

    def test_steady_walker_keeps_its_field(self):
        P = R.Planner
        for dt in (0.3, 0.6, 1.0):
            self.assertFalse(P._mobs_moved(self.f, [(150.0 * dt, 1000.0, 0.0, None, True, (150.0, 0.0), 7, True)], self.t0 + dt))
        # (the old way: 60 units moved was a new field)
        old = field([(0.0, 1000.0, 0.0, None, True)])
        self.assertTrue(P._mobs_moved(old, [(90.0, 1000.0, 0.0, None, True)]))

    def test_changes_ask_for_a_new_field(self):
        P, t = R.Planner, self.t0 + 0.6
        here = 150.0 * 0.6
        self.assertTrue(P._mobs_moved(self.f, [(here, 1000.0, 0.0, None, True, (0.0, 150.0), 7, True)], t))     # turned
        self.assertTrue(P._mobs_moved(self.f, [(here, 1000.0, 0.0, None, True, None, 7, True)], t))             # stopped
        self.assertTrue(P._mobs_moved(self.f, [(here, 1000.0, 0.0, None, True, (300.0, 0.0), 7, True)], t))     # faster
        self.assertTrue(P._mobs_moved(self.f, [(here + 100, 1000.0, 0.0, None, True, (150.0, 0.0), 7, True)], t))  # off its line
        self.assertTrue(P._mobs_moved(self.f, [(here, 1000.0, 0.0, None, True, (150.0, 0.0), 8, True)], t))     # another mob
        h = R.sweep_of((150.0, 0.0))[0]
        late = self.t0 + h / 2 + 0.01
        self.assertTrue(P._mobs_moved(self.f, [(150.0 * (late - self.t0), 1000.0, 0.0, None, True, (150.0, 0.0), 7, True)], late))

    def test_pose_known(self):
        f = field([(0.0, 1000.0, 0.0, None, True, (150.0, 0.0), 7, True)], at=time.time() - 0.5)
        self.assertTrue(R.Planner._pose_known(f, mob(75.0, 1000.0, gid=7, vel=(150.0, 0.0)), (0.0, 0.0)))
        self.assertFalse(R.Planner._pose_known(f, mob(0.0, 1000.0, gid=7, vel=(150.0, 0.0)), (0.0, 0.0)))
        self.assertFalse(R.Planner._pose_known(f, mob(75.0, 1000.0, gid=7), (0.0, 0.0)))


class TimedWaits(unittest.TestCase):
    """the wait checks look at where a walking mob will be when the wizard gets there"""
    pts = [(0.0, float(y)) for y in range(0, 1001, 20)]

    def test_walking_off_the_route(self):
        m = mob(0.0, 600.0, vel=(300.0, 0.0))
        self.assertEqual(R.Planner._mob_on_way(self.pts, [mob(0.0, 600.0)], 300.0, 0.0)['block'], 'ring')
        self.assertIsNone(R.Planner._mob_on_way(self.pts, [m], 300.0, 0.0, speed=300.0))

    def test_walking_onto_the_route(self):
        m = mob(-600.0, 600.0, vel=(300.0, 0.0))
        self.assertIsNone(R.Planner._mob_on_way(self.pts, [mob(-600.0, 600.0)], 300.0, 0.0))
        self.assertEqual(R.Planner._mob_on_way(self.pts, [m], 300.0, 0.0, speed=300.0)['block'], 'ring')

    def test_walking_up_behind(self):
        # (standing still wouldn't keep it off: no wait - walking on is better)
        m = mob(0.0, -600.0, vel=(0.0, 300.0))
        self.assertIsNone(R.Planner._mob_on_way(self.pts, [m], 300.0, 0.0, speed=300.0))

    def test_blind_ahead_line(self):
        p, _, _ = planner()
        r = reading(goal=(0.0, 1000.0, 0.0), yaw=math.pi)
        r['target'] = (0.0, 1000.0, 0.0)
        onto = [mob(-450.0, 300.0, vel=(300.0, 0.0), name='Walker')]
        self.assertEqual(p.blind(r, [mob(-450.0, 300.0, name='Walker')], 300.0, (0.0, 0.0))[0], '')
        self.assertEqual(p.blind(r, onto, 300.0, (0.0, 0.0), speed=300.0)[0], 'Walker')
        off = [mob(0.0, 400.0, vel=(400.0, 0.0), name='Leaver')]
        self.assertEqual(p.blind(r, [mob(0.0, 400.0, name='Leaver')], 300.0, (0.0, 0.0))[0], 'Leaver')
        self.assertEqual(p.blind(r, off, 300.0, (0.0, 0.0), speed=300.0)[0], '')


class Walls(unittest.TestCase):
    """a line of mobs as one wall, routed all the way round"""
    line = [(x, 1000.0, 0.0, None, True) for x in (-1400.0, -700.0, 0.0, 700.0, 1400.0)]

    def tearDown(self):
        R.PASS_GAP = 250.0

    def test_line_routed_round_its_end(self):
        R.PASS_GAP = 0.0
        f0 = field(self.line)
        pts0 = route_pts(f0, (0.0, 0.0))
        self.assertLess(abs(crossing(pts0, 1000.0)), 700.0)         # (as before: through a gap)
        R.PASS_GAP = 250.0
        f = field(self.line)
        self.assertIsNotNone(f.fill)
        self.assertGreater(f.nx, f0.nx)                              # (the window took the line in)
        pts = route_pts(f, (0.0, 0.0))
        self.assertGreater(abs(crossing(pts, 1000.0)), 1700.0)
        self.assertGreater(min(min(math.hypot(p[0] - m[0], p[1] - m[1]) for m in self.line) for p in pts), 400.0)

    def test_wide_gap_still_used(self):
        mobs = [m for m in self.line if m[0] != 0.0]
        f = field(mobs)
        self.assertLess(abs(crossing(route_pts(f, (0.0, 0.0)), 1000.0)), 300.0)

    def test_long_line_as_before(self):
        long_line = [(float(x), 1000.0, 0.0, None, True) for x in range(-4200, 4201, 700)]
        f = field(long_line)
        self.assertIn('too long', f.note)
        self.assertIsNone(f.fill)
        R.PASS_GAP = 0.0
        f0 = field(long_line)
        self.assertTrue(np.array_equal(f.cost, f0.cost))

    def test_hollow_of_one_mob_not_filled(self):
        # (one mob's own shape - a narrow cone and its body - is never closed: only gaps between two)
        f = field([(0.0, 1000.0, 0.0, 0.0, True)], mob_near=120.0, cone=(60.0, 600.0))
        self.assertIsNone(f.fill)

    def test_wall_wait_and_gap_given_up(self):
        f = field(self.line, pos=(0.0, 300.0, 0.0),
                  geo=FlatGeo([(-4000.0, -1000.0, -1500.0, 3000.0), (1500.0, -1000.0, 4000.0, 3000.0)]))
        self.assertIsNotNone(f.fill)
        pts = route_pts(f, (0.0, 300.0))
        mobs = [mob(m[0], m[1], gid=k) for k, m in enumerate(self.line)]
        # (the wall's wait only when asked for - the mobwall setting; else through the gap as before)
        self.assertIsNone(R.Planner._mob_on_way(pts, mobs, 300.0, 0.0, None, f))
        blk = R.Planner._mob_on_way(pts, mobs, 300.0, 0.0, None, f, wall_wait=True)
        self.assertEqual(blk['block'], 'wall')
        # (given up: only the gaps by those mobs let go of - walls False - their rings kept)
        p, _, _ = planner()
        p.mob_ignored = {k: (time.time(), 'gap') for k in range(5)}
        kept = p._given_up(mobs)
        self.assertEqual(len(kept), 5)
        self.assertTrue(all(m['walls'] is False and m.get('sees', True) for m in kept))
        f2 = field([m[:5] + (None, k, False) for k, m in enumerate(self.line)])
        self.assertIsNone(f2.fill)
        blk2 = R.Planner._mob_on_way(route_pts(f2, (0.0, 0.0)), kept, 300.0, 0.0, None, f2, wall_wait=True)
        self.assertTrue(blk2 is None or blk2['block'] != 'wall')

    def test_wall_wait_given_up_through_route(self):
        # (the line across a street, sight a semi-circle in front: the wall's wait asked for - route() itself to
        # MOB_GIVEUP - is a 'gap' wait: only the gaps by the nearest mob let go of, its ring and sight kept)
        geo = FlatGeo([(-4000.0, -1000.0, -1500.0, 3000.0), (1500.0, -1000.0, 4000.0, 3000.0)])
        p, logs, _ = planner(geo)
        r = reading(pos=(0.0, 300.0, 0.0), goal=(0.0, 2500.0, 0.0))
        mobs = [mob(m[0], m[1], yaw=0.0, gid=k, name='Crab%d' % k) for k, m in enumerate(self.line)]
        cone = (180.0, 300.0)
        out = settle(p, r, wait=True, mobs=mobs, cone=cone, wall_wait=True)
        self.assertIn('mob', out)
        self.assertEqual(out['mob_name'], 'Crab2')
        self.assertEqual(p.mwait['gids'], {2: 'gap'})
        p.mwait['waited'] = R.MOB_GIVEUP + 1
        out = p.route(r, wait=True, mobs=mobs, cone=cone, wall_wait=True)
        self.assertNotIn('mob', out)
        self.assertEqual(p.mob_ignored[2][1], 'gap')
        self.assertTrue(any('walking on through the gap' in s for s in logs))
        kept = {m['gid']: m for m in p._given_up(mobs)}
        self.assertEqual(len(kept), 5)
        self.assertIs(kept[2]['walls'], False)
        self.assertTrue(kept[2].get('sees', True))                  # (its sight kept)
        # (the field still with its gaps closed - till the next one's made - no new wait on its neighbour; then through
        # the gap by it, out of every ring)
        out = p.route(r, wait=True, mobs=mobs, cone=cone, wall_wait=True)
        self.assertNotIn('mob', out)
        time.sleep(R.MOB_REPLAN + 0.05)
        out = settle(p, r, wait=True, mobs=mobs, cone=cone, wall_wait=True)
        self.assertNotIn('mob', out)
        self.assertIs([m for m in p.field.mobs if m[6] == 2][0][7], False)
        self.assertLess(abs(crossing(out['route'], 1000.0)), 700.0)
        self.assertGreater(min(min(math.hypot(q[0] - m[0], q[1] - m[1]) for m in self.line) for q in out['route']),
                           R.MOB_NEAR * 0.85)

    def test_two_mobs_across_a_street_as_before(self):
        # (two mobs either side of a street, their rings' gap closed: walked through it at once, as before - the wall's
        # wait only with wall_wait, the mobwall setting)
        geo = FlatGeo([(-3000.0, -1000.0, -700.0, 3000.0), (700.0, -1000.0, 3000.0, 3000.0)])
        mobs = [mob(-400.0, 1000.0, gid=1, name='A'), mob(400.0, 1000.0, gid=2, name='B')]
        r = reading(pos=(0.0, 300.0, 0.0))
        p, _, _ = planner(geo)
        out = settle(p, r, wait=True, mobs=mobs, cone=(0.0, 0.0))
        self.assertIsNotNone(p.field.fill)
        self.assertNotIn('mob', out)
        R.PASS_GAP = 0.0
        p0, _, _ = planner(geo)
        out0 = settle(p0, r, wait=True, mobs=mobs, cone=(0.0, 0.0))
        self.assertNotIn('mob', out0)
        self.assertAlmostEqual(crossing(out['route'], 1000.0), crossing(out0['route'], 1000.0), delta=2 * R.CELL)
        R.PASS_GAP = 250.0
        p2, _, _ = planner(geo)
        out2 = settle(p2, r, wait=True, mobs=mobs, cone=(0.0, 0.0), wall_wait=True)
        self.assertIn('mob', out2)

    def test_groups(self):
        ts = [R._mob_tuple(m) for m in self.line]
        self.assertEqual(len(R.mob_groups(ts, 300.0, 0.0)), 1)
        apart = [R._mob_tuple((x, 0.0, 0.0)) for x in (0.0, 5000.0)]
        self.assertEqual(len(R.mob_groups(apart, 300.0, 0.0)), 2)


class Duels(unittest.TestCase):
    """other players' battles kept out of"""

    def test_circle_on_the_way_gone_round(self):
        d = [(0.0, 1000.0, 0.0, R.DUEL_R)]
        f = field(duels=d)
        pts = route_pts(f, (0.0, 0.0))
        self.assertGreater(min(math.hypot(p[0], p[1] - 1000.0) for p in pts), R.DUEL_R)
        self.assertTrue(f.duel_mask[f.cell((0.0, 1000.0))])
        f0 = field()
        self.assertIsNone(f0.duel_mask)

    def test_no_duels_as_before(self):
        p1, _, _ = planner()
        p2, _, _ = planner()
        a = settle(p1, reading(), wait=False, mobs=[mob(200.0, 1000.0)])
        b = settle(p2, reading(), wait=False, mobs=[mob(200.0, 1000.0)], duels=[])
        self.assertEqual(a['route'], b['route'])

    def test_wait_in_a_corridor_then_given_up(self):
        geo = FlatGeo([(-3000.0, -1000.0, -200.0, 3000.0), (200.0, -1000.0, 3000.0, 3000.0)])
        p, logs, _ = planner(geo)
        r = reading()
        duels = [{'pos': (0.0, 700.0, 0.0), 'gid': 77}]
        out = settle(p, r, wait=True, duels=duels)
        self.assertIn('duel', out)
        self.assertEqual(out['duel_at'], (0.0, 700.0))
        p.dwait['waited'] = R.DUEL_GIVEUP + 1
        out = p.route(r, wait=True, duels=duels)
        self.assertNotIn('duel', out)
        self.assertIn(77, p.duel_ignored)
        self.assertTrue(any("another player's battle" in s for s in logs))
        out = p.route(r, wait=True, duels=duels)
        self.assertNotIn('duel', out)

    def test_duel_moved_asks_for_a_new_field(self):
        f = field(duels=[(0.0, 1000.0, 0.0, R.DUEL_R)])
        self.assertFalse(R.Planner._duels_moved(f, [(0.0, 1000.0, 0.0, R.DUEL_R)]))
        self.assertTrue(R.Planner._duels_moved(f, []))
        self.assertTrue(R.Planner._duels_moved(f, [(200.0, 1000.0, 0.0, R.DUEL_R)]))


def import_bossmem():
    """bossmem with navmem, handmem and questmem stood in for (they open the game's process API at import - Windows only)"""
    import types
    saved = {k: sys.modules.get(k) for k in ('navmem', 'handmem', 'questmem', 'bossmem')}
    try:
        nav = types.ModuleType('navmem')
        nav.ptr_ok = lambda v: 0x10000 <= v < 0x7FFFFFFF0000
        nav.DATA = {"co_gid": 0x48, "co_template": 0x58}
        hand = types.ModuleType('handmem')
        hand.SCHOOL_IDS = {}
        sys.modules.update(navmem=nav, handmem=hand, questmem=types.ModuleType('questmem'))
        sys.modules.pop('bossmem', None)
        import bossmem
        return bossmem
    finally:
        for k, v in saved.items():
            if k == 'bossmem':
                continue
            if v is None:
                sys.modules.pop(k, None)
            else:
                sys.modules[k] = v


class FakeMem:
    """a stand-in for navmem's Proc: try_read over a few blocks of bytes {address: bytearray}"""

    def __init__(self):
        self.blocks = {}

    def put(self, addr, data):
        self.blocks[addr] = bytearray(data)

    def try_read(self, a, n):
        for base, b in self.blocks.items():
            if base <= a and a + n <= base + len(b):
                return bytes(b[a - base:a - base + n])
        return None


class BossDuels(unittest.TestCase):
    """bossmem's duel circle reading on stand-in bytes (the reads themselves need the game)"""

    @classmethod
    def setUpClass(cls):
        cls.B = import_bossmem()

    def reader(self):
        import struct
        B = self.B
        bm = object.__new__(B.BossMem)
        bm.p = mem = FakeMem()
        bm.P = {"CoreObject": {"m_inactiveBehaviors": 0xE0}, "DuelBehavior": {"m_pDuel": 0x70},
                "Duel": {"m_flatParticipantList": 0x50, "m_roundNum": 0x60, "m_duelPhase": 0x64, "m_bPVP": 0x68},
                "CombatParticipant": {"m_ownerID.m_full": 0x10, "m_isPlayer": 0x20, "m_teamID": 0x24}}
        bm.vt = {"ClientCombatParticipant": {0xCC00}, "CombatParticipant": {0xCC10}, "ClientDuel": {0xD000}, "Duel": set()}
        bm.duel_vt = {0xDB00}
        bm.duel_phases = {0: "Planning", 1: "Execution", 2: "Victory"}
        obj, vec, beh0, beh, duel, parts = 0x100000, 0x200000, 0x300000, 0x310000, 0x400000, 0x500000
        mem.put(obj, bytes(0xE0) + struct.pack("<QQ", vec, vec + 32) + bytes(0x40))
        mem.put(vec, struct.pack("<QQQQ", beh0, 0, beh, 0))
        mem.put(beh0, struct.pack("<Q", 0xAAAA) + bytes(0x80))
        mem.put(beh, struct.pack("<Q", 0xDB00) + bytes(0x68) + struct.pack("<Q", duel) + bytes(0x10))
        mem.put(duel, struct.pack("<Q", 0xD000) + bytes(0x48) + struct.pack("<QQ", parts, parts + 48) + struct.pack("<iiB", 3, 1, 0)
                + bytes(0x20))
        ps = [(0x600000, 0xCC00, 0x11, 1, 0), (0x610000, 0xCC10, 0x22, 1, 0), (0x620000, 0xCC00, 0x33, 0, 1)]
        mem.put(parts, b"".join(struct.pack("<QQ", p[0], 0) for p in ps))
        for addr, vt, owner, player, team in ps:
            mem.put(addr, struct.pack("<Q", vt) + bytes(8) + struct.pack("<Q", owner) + bytes(8) + struct.pack("<Bxxxi", player, team)
                    + bytes(0x20))
        return bm, obj, beh, duel, mem

    def test_duel_of(self):
        bm, obj, beh, duel, mem = self.reader()
        self.assertEqual(bm.is_duel_object(obj), beh)
        info = bm.duel_of(obj, me=0x22)
        self.assertEqual(info['duel'], duel)
        self.assertEqual((info['round'], info['phase'], info['phase_name'], info['pvp']), (3, 1, 'Execution', False))
        self.assertEqual((info['parts'], info['players'], info['teams']), (3, 2, 2))
        self.assertTrue(info['mine'])
        self.assertTrue(info['active'])
        self.assertFalse(bm.duel_of(obj, me=0x99)['mine'])
        self.assertIsNone(bm.duel_of(obj)['mine'])
        self.assertIsNone(bm.duel_of(0x200000))                    # (no duel behaviour: not a duel circle)

    def test_idle_sigil(self):
        import struct
        bm, obj, beh, duel, mem = self.reader()
        mem.put(beh, struct.pack("<Q", 0xDB00) + bytes(0x68) + struct.pack("<Q", 0) + bytes(0x10))   # (m_pDuel empty)
        info = bm.duel_of(obj)
        self.assertIsNone(info['duel'])
        self.assertIsNone(info['active'])

    def test_active_and_parse(self):
        B = self.B
        self.assertIsNone(B.duel_active(None))
        self.assertFalse(B.duel_active({'parts': 0}))
        self.assertTrue(B.duel_active({'parts': 2, 'phase_name': None}))
        self.assertFalse(B.duel_active({'parts': 2, 'phase_name': 'Victory'}))
        self.assertFalse(B.duel_active({'parts': 2, 'phase_name': 'kDuelPhase_Ended'}))
        import struct
        raw = struct.pack("<iiB", 5000, 99, 7)
        got = B.parse_duel(raw, 0x60, {"m_roundNum": 0x60, "m_duelPhase": 0x64, "m_bPVP": 0x68}, {})
        self.assertEqual(got, {'round': None, 'phase': None, 'phase_name': None, 'pvp': None})


def import_navmem():
    """navmem with its Windows DLLs stood in for where there are none (nothing is ever called on them here)"""
    import ctypes
    had = hasattr(ctypes, 'WinDLL')

    class Dll:
        def __init__(self, *a, **kw):
            pass

        def __getattr__(self, name):
            def fn(*a):
                raise OSError('no Windows here')
            setattr(self, name, fn)
            return fn
    if not had:
        ctypes.WinDLL = Dll
    stand_in = sys.modules.get('navmem')                 # (another test file's stand-in: put back afterwards)
    if stand_in is not None and getattr(stand_in, '__file__', None):
        stand_in = None
    try:
        if stand_in is not None:
            del sys.modules['navmem']
        import navmem
        return navmem
    finally:
        if stand_in is not None:
            sys.modules['navmem'] = stand_in
        if not had:
            del ctypes.WinDLL


class NavmemDuels(unittest.TestCase):
    """navmem's duel circles (the objects thread's look, duels()) and --mobs --motion, on stand-ins"""

    @classmethod
    def setUpClass(cls):
        import_bossmem()
        cls.N = import_navmem()

    def test_duel_look(self):
        N = self.N
        nm = N.NavMem(log=lambda m: None)
        st = object()
        asked = []

        class BM:
            def is_duel_object(self, obj):
                asked.append(obj)
                return 0x77 if obj == 0xD0 else 0
        bm = BM()
        bm.st = st
        nm.st = st
        nm._boss_reader = lambda s, wait=0.0: (bm, '')
        cands = [(0xD0, 5, 'Sigil', 0xAA), (0xE0, 6, 'Thing', 0xBB)]
        self.assertEqual(nm._duel_look(st, cands), {})               # (duels not asked for: none looked at)
        nm._duel_asked = time.monotonic()
        self.assertEqual(nm._duel_look(st, cands), {0xD0: (5, 'Sigil', 'Sigil', 0xAA)})
        self.assertEqual(nm._duel_look(st, cands), {0xD0: (5, 'Sigil', 'Sigil', 0xAA)})
        self.assertEqual(asked, [0xD0, 0xE0])                         # (each object looked at once)

    def test_duels(self):
        N = self.N
        nm = N.NavMem(log=lambda m: None)

        class St:
            def gameclient(self):
                return 0x100000

            def player_gid(self, gc):
                return 0x22
        st = St()

        class BM:
            def duel_of(self, obj, me):
                return {'duel': 0x400000, 'phase': 1, 'phase_name': 'Execution', 'round': 2, 'parts': 2, 'players': 1,
                        'teams': 2, 'mine': me == 0x33, 'pvp': False, 'active': True, 'behavior': 0x77}
        bm = BM()
        bm.st = st
        nm.st = st
        nm._boss_reader = lambda s, wait=0.0: (bm, '')
        nm._duels = {0xD0: (5, 'Sigil', 'Sigil', 0xAA)}
        nm._live = lambda which: ([{'name': 'Sigil', 'pos': (1.0, 2.0, 3.0), 'yaw': None, 'gid': 5, 'template': 'Sigil'}], '')
        got, why = nm.duels()
        self.assertEqual(why, '')
        self.assertEqual((got[0]['phase_name'], got[0]['players'], got[0]['mine'], got[0]['active']), ('Execution', 1, False, True))
        nm._live = lambda which: (None, 'not attached')
        self.assertEqual(nm.duels(), (None, 'not attached'))

    def test_motion_cli(self):
        import contextlib
        import io
        N = self.N
        t0 = time.time()

        class NM:
            def read(self, path=False, wait=0):
                return {'pos': (0.0, 0.0, 0.0)}, ''

            def mobs(self):
                t = time.time() - t0
                return [{'name': 'Walker', 'gid': 9, 'pos': (120.0 * t, 300.0, 0.0), 'yaw': R.heading_yaw((1.0, 0.0))},
                        {'name': 'Sitter', 'gid': 8, 'pos': (-300.0, 0.0, 0.0), 'yaw': 0.0}], ''
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            N._motion_cli(NM(), 1.2, every=0.05)
        text = out.getvalue()
        self.assertIn('Walker', text)
        self.assertIn('Sitter', text)
        self.assertIn('walking', text)
        self.assertIn('== ', text)


class Helper(unittest.TestCase):
    """the vision helper's lines (vision.py imports on any system; the game's readers are stood in for)"""

    @classmethod
    def setUpClass(cls):
        import vision
        cls.V = vision
        cls.log = vision.log
        vision.log = lambda *a, **kw: None             # (nothing into vision\vision.log from the tests)

    @classmethod
    def tearDownClass(cls):
        cls.V.log = cls.log

    def test_mob_line_motion_fields(self):
        V = self.V
        m = {'name': 'Crab', 'pos': (10.0, 20.0, 0.0), 'yaw': 0.0, 'quest': False, 'gid': 5, 'named': False,
             'template': 'CL-Crab', 'title': 'Normal', 'rank': 3, 'health': 100, 'school': 'Ice', 'boss': False}
        f = V.mob_line(m, (0.0, 0.0, 0.0)).split('|')
        self.assertEqual(len(f), 16)                               # (no motion known: as before)
        m.update(fit=(120.0, -3.0), moving=True)
        f = V.mob_line(m, (0.0, 0.0, 0.0)).split('|')
        self.assertEqual(f[15], 'CL-Crab')
        self.assertEqual(f[16:], ['120.0', '-3.0', '1'])
        m.update(fit=None, moving=None)
        del m['template']
        f = V.mob_line(m, (0.0, 0.0, 0.0)).split('|')
        self.assertEqual(len(f), 15)

    def test_motion_fields_from_readings(self):
        V = self.V
        V.MOTION = R.MobMotion()
        for k in range(10):
            mobs = [{'gid': 1, 'name': 'Crab', 'pos': (150.0 * k * 0.15, 0.0, 0.0), 'yaw': R.heading_yaw((1.0, 0.0))}]
            V.motion_feed(k * 0.15, mobs, (0.0, -500.0, 0.0))
        self.assertTrue(mobs[0]['moving'])
        self.assertAlmostEqual(mobs[0]['vel'][0], 150.0, delta=3.0)
        self.assertEqual(mobs[0]['fit'], mobs[0]['vel'])

    def test_mobs_now_feeds_motion(self):
        V = self.V
        V.MOTION = R.MobMotion()
        V.MOB_TRAIL.clear()
        t0 = time.time()

        class FakeNav:
            def mobs(self):
                x = 200.0 * (time.time() - t0)
                return [{'name': 'Walker', 'gid': 41, 'pos': (x, 900.0, 0.0), 'yaw': R.heading_yaw((1.0, 0.0)),
                         'template': 'W', 'kind': None}], ''
        old = V.nav_reader
        V.nav_reader = lambda: FakeNav()
        try:
            r = {'pos': (0.0, 0.0, 0.0), 'zone': 'Test/Flat', 'goal': None, 'hops': None}
            for _ in range(6):
                mobs, _ = V.mobs_now(r, '', trail=True)
                time.sleep(0.12)
            self.assertEqual(len(V.MOB_TRAIL), 6)
            self.assertTrue(mobs[0]['moving'])
            self.assertAlmostEqual(mobs[0]['vel'][0], 200.0, delta=30.0)
            line = V.mob_line(mobs[0], (0.0, 0.0, 0.0)).split('|')
            self.assertEqual(line[18], '1')
        finally:
            V.nav_reader = old

    def test_caught_moving_field(self):
        V = self.V
        V.MOB_TRAIL.clear()
        t0 = time.time() - 3.0
        # (a crab walking along -X, away from the wizard at (400, 300), then turning to come for him)
        for k in range(8):
            V.MOB_TRAIL.append((t0 + k * 0.15, (400.0, 300.0, 0.0), {5: ('Crab', -100.0 * k * 0.15, 0.0, 0.0, None)}))
        x = -100.0 * 7 * 0.15
        for k in range(1, 6):
            p = (x + (400.0 - x) * k / 6, 300.0 * k / 6)
            V.MOB_TRAIL.append((t0 + 1.05 + k * 0.15, (400.0, 300.0, 0.0), {5: ('Crab', p[0], p[1], 0.0, None)}))
        f = V.caught_line(t0 + 2.0).split('|')
        self.assertEqual(f[0], 'caught')
        self.assertEqual(f[4], '1')                                # (it came for him)
        self.assertEqual(f[7], '1')                                # (walking when it noticed him)
        # (the wizard walking into a crab that stands still)
        V.MOB_TRAIL.clear()
        for k in range(10):
            me = (400.0 - 340.0 * min(k, 7) / 7, 0.0, 0.0)
            V.MOB_TRAIL.append((t0 + k * 0.15, me, {5: ('Crab', 0.0, 0.0, 0.0, None)}))
        f = V.caught_line(t0 + 2.0).split('|')
        self.assertEqual(f[4], '0')
        self.assertEqual(f[7], '0')

    def test_route_line_fields(self):
        V = self.V

        class FakeRouter:
            def route(self, r, **kw):
                self.kw = kw
                return {'aim': (1.0, 2.0), 'left': 300.0, 'route': [], 'why': '', 'duel': 12.4, 'duel_at': (50.0, 60.0)}

            def blind(self, *a, **kw):
                return '', '', ''

            def arc_clear(self, *a):
                return 1
        fake = FakeRouter()
        old = V.router
        V.router = lambda game_dir='': fake
        try:
            lines = V.route_lines({'pos': (0.0, 0.0, 0.0)}, '', [mob(0.0, 500.0)], 300.0, (0.0, 0.0), 400.0,
                                  duels=[{'pos': (50.0, 60.0, 0.0), 'gid': 3}])
            f = lines[0].split('|')
            self.assertEqual(f[0], 'route')
            self.assertEqual(f[13:16], ['12', '50', '60'])
            self.assertEqual(f[12], '1')
            self.assertEqual(fake.kw['duels'], [{'pos': (50.0, 60.0, 0.0), 'gid': 3}])
            self.assertIs(fake.kw['wall_wait'], False)
            V.route_lines({'pos': (0.0, 0.0, 0.0)}, '', [mob(0.0, 500.0)], 300.0, (0.0, 0.0), wall_wait=True)
            self.assertIs(fake.kw['wall_wait'], True)
            fake.route = lambda r, **kw: {'aim': (1.0, 2.0), 'left': 300.0, 'route': [], 'why': ''}
            f = V.route_lines({'pos': (0.0, 0.0, 0.0)}, '', None, 300.0, (0.0, 0.0))[0].split('|')
            self.assertEqual(len(f), 16)
            self.assertEqual(f[13:16], ['', '', ''])
        finally:
            V.router = old

    def test_map_route_keeps_the_walkers_field(self):
        # (the dashboard's map asks the walker's planner every second: with the battles the walker kept out of, its
        # field stays the walker's - before, a map ask with none replaced it with one walking at the battle)
        V = self.V
        p, _, _ = planner()
        r = reading()
        mobs = [mob(1500.0, 1000.0)]
        duels = [{'pos': (0.0, 1000.0, 0.0), 'gid': 77}]
        out = settle(p, r, wait=True, mobs=mobs, duels=duels)
        f1 = p.field
        self.assertTrue(f1.duels)
        V.MOBS_SHOWN.update(near=R.MOB_NEAR, cone=R.MOB_CONE, avoid=True, at=time.time(), quest=set())
        V.DUELS_SHOWN.update(list=duels, at=time.time())
        old = V.router
        V.router = lambda game_dir='': p
        try:
            time.sleep(R.MOB_REPLAN + 0.05)
            self.assertIsNotNone(V.map_route(r, '', mobs, V.DUELS_SHOWN['list']))
            t0 = time.time()
            while (p.busy or p.want is not None) and time.time() - t0 < 10:
                time.sleep(0.005)
            self.assertIs(p.field, f1)
            out = p.route(r, wait=True, mobs=mobs, duels=duels)
            self.assertNotIn('duel', out)
            self.assertGreater(min(math.hypot(q[0], q[1] - 1000.0) for q in out['route']), R.DUEL_R)
            # (the map's ask as it was - no battles: a field without the battle, the walker's next ask walking at it)
            time.sleep(R.MOB_REPLAN + 0.05)
            V.map_route(r, '', mobs, None)
            t0 = time.time()
            while (p.busy or p.want is not None) and time.time() - t0 < 10:
                time.sleep(0.005)
            self.assertEqual(p.field.duels, ())
        finally:
            V.router = old

    def test_duels_now_filter(self):
        V = self.V

        class FakeNav:
            def duels(self):
                return [{'pos': (0.0, 0.0, 0.0), 'gid': 1, 'active': True, 'mine': False, 'players': 2},
                        {'pos': (9.0, 0.0, 0.0), 'gid': 2, 'active': False, 'mine': False, 'players': 2},
                        {'pos': (9.0, 9.0, 0.0), 'gid': 3, 'active': True, 'mine': True, 'players': 1},
                        {'pos': (5.0, 9.0, 0.0), 'gid': 4, 'active': True, 'mine': False, 'players': 0},
                        {'pos': (7.0, 9.0, 0.0), 'gid': 5, 'active': True, 'mine': False, 'players': None}], ''
        old = V.nav_reader
        V.nav_reader = lambda: FakeNav()
        try:
            got, why = V.duels_now()
            self.assertEqual(sorted(d['gid'] for d in got), [1, 5])
            lines = V.duel_lines(FakeNav().duels()[0], {'pos': (3.0, 4.0, 0.0)})
            self.assertTrue(lines[0].startswith('duel|'))
        finally:
            V.nav_reader = old

    def test_map_draws_walkers_walls_and_duels(self):
        V = self.V
        r = {'pos': (0.0, 0.0, 0.0), 'yaw': 0.0, 'zone': 'Test/NoSuchZone', 'goal': None, 'hops': None, 'target': None,
             'path': []}
        V.MOBS_SHOWN.update(near=120.0, cone=(180.0, 300.0), avoid=True, at=time.time(), quest=set())
        mobs = [dict(mob(300.0, 200.0, yaw=0.0, vel=(150.0, 0.0)), quest=False), dict(mob(-300.0, 200.0), quest=False)]
        f = field([(x, 1000.0, 0.0, None, True) for x in (-700.0, 0.0, 700.0)])
        img = V.render_navmap(r, 200, 160, '/nonexistent', 3000.0, None, mobs, True, None,
                              duels=[{'pos': (0.0, -600.0, 0.0), 'gid': 1}], walls=f)
        self.assertEqual(img.size, (200, 160))
        out = os.path.join(tempfile.mkdtemp(), 'map.png')
        V.save_png(img, out)
        self.assertTrue(os.path.getsize(out) > 0)


if __name__ == '__main__':
    unittest.main()
