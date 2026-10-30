"""test_statemem.py - a zone object's state (vision\\statemem.py: its ObjectStateBehavior found among its behaviours by
vtable or type name, its owner checked, its state's text read; the state property picked by name; every failure soft) on
made-up memory, and navmem putting each door's state on blockers() (its reader stood in for) - no game, no Windows (the
real navmem with its DLLs stood in for, as test_navroute.py does):  python -m unittest test_statemem   (from
AutoFarmer\\vision)"""
import io
import os
import struct
import sys
import time
import types
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import statemem as S  # noqa: E402

PROPS = {"CoreObject": {"m_inactiveBehaviors": 0xE0, "m_globalID.m_full": 0x48},
         "ObjectStateBehavior": {"m_stateSetName": 0x60, "m_currentState": 0x80, "m_flags": 0xA0}}
VT_STATE, VT_NPC = 0x7FF600AB0000, 0x7FF600CC0000


class Mem:
    """made-up memory: regions of bytes - try_read / try_string as navmem's Proc (None when it can't be read)"""

    def __init__(self):
        self.regions = {}
        self.next = 0x10000000

    def alloc(self, n):
        a = self.next
        self.next += (n + 0xFFF) & ~0xFFF
        self.regions[a] = bytearray(n)
        return a

    def _at(self, a, n):
        for base, buf in self.regions.items():
            if base <= a and a + n <= base + len(buf):
                return buf, a - base
        return None, 0

    def write(self, a, data):
        buf, o = self._at(a, len(data))
        assert buf is not None, hex(a)
        buf[o:o + len(data)] = data

    def try_read(self, a, n):
        buf, o = self._at(a, n)
        return bytes(buf[o:o + n]) if buf is not None else None

    def try_string(self, a, stable=False):
        raw = self.try_read(a, 0x20)
        if raw is None:
            return None
        size, cap = struct.unpack_from("<QQ", raw, 0x10)
        if size > 0x1000 or cap < size or cap > 0x100000:
            return None
        data = raw[:size] if cap < 16 else (self.try_read(struct.unpack_from("<Q", raw)[0], size) if size else b"")
        if data is None:
            return None
        s = data.decode("latin-1")
        return s if all(32 <= ord(ch) < 127 for ch in s) else None

    def put_string(self, a, s):
        b = s.encode("latin-1")
        if len(b) < 16:
            self.write(a, b.ljust(16, b"\0") + struct.pack("<QQ", len(b), 15))
        else:
            h = self.alloc(len(b) + 1)
            self.write(h, b)
            self.write(a, struct.pack("<QQQQ", h, 0, len(b), len(b)))


class World:
    """a made-up game: a door object whose behaviour vector holds an NPC-like behaviour and an ObjectStateBehavior"""

    def __init__(self, state="Closed", owner=True, with_state=True):
        self.p = Mem()
        self.types = {}
        self.tn = types.SimpleNamespace(of=lambda obj: self.types.get(obj))
        self.m = types.SimpleNamespace(build="TEST-1")
        p = self.p
        self.obj = p.alloc(0x200)
        self.npc = p.alloc(0x100)
        p.write(self.npc, struct.pack("<Q", VT_NPC))
        self.beh = p.alloc(0x100)
        p.write(self.beh, struct.pack("<Q", VT_STATE))
        p.write(self.beh + S.KNOWN["beh_owner"], struct.pack("<Q", self.obj if owner else self.npc))
        p.put_string(self.beh + 0x60, "GateStates")
        p.put_string(self.beh + 0x80, state)
        p.write(self.beh + 0xA0, struct.pack("<QQQQ", 0xFFFFFFFFFFFFFFFF, 0, 0x5000, 0x10))     # (not a text)
        elems = [self.npc] + ([self.beh] if with_state else [])
        arr = p.alloc(16 * len(elems))
        p.write(arr, b"".join(struct.pack("<QQ", e, 0) for e in elems))
        p.write(self.obj + 0xE0, struct.pack("<QQ", arr, arr + 16 * len(elems)))

    def reader(self, props=None, vts=None, **kw):
        return S.StateMem(self, props=PROPS if props is None else props,
                          vts={"ObjectStateBehavior": {VT_STATE}} if vts is None else vts, **kw)


class Reader(unittest.TestCase):
    """StateMem on made-up memory"""

    def test_state(self):
        w = World()
        sm = w.reader()
        self.assertEqual(sm.prop, ("ObjectStateBehavior", "m_currentState", 0x80))
        self.assertEqual(sm.behavior(w.obj), (w.beh, ""))
        self.assertEqual(sm.state(w.obj), ("Closed", ""))
        w.p.put_string(w.beh + 0x80, "Open")                                    # (the gate opens: read again)
        self.assertEqual(sm.state(w.obj), ("Open", ""))
        w.p.put_string(w.beh + 0x80, "A state name longer than 16")            # (on the heap)
        self.assertEqual(sm.state(w.obj)[0], "A state name longer than 16")
        self.assertEqual(sm.strings(w.beh), [("m_stateSetName", 0x60, "GateStates"),
                                             ("m_currentState", 0x80, "A state name longer than 16")])

    def test_type_name(self):
        w = World()
        w.types[w.beh] = "ClientObjectStateBehavior"                            # (no vtables: the TypeNamer's name)
        sm = w.reader(vts={})
        self.assertEqual(sm.state(w.obj), ("Closed", ""))
        w.types[w.beh] = "ObjectStateBehaviorTemplate"
        self.assertEqual(sm.state(w.obj), (None, "no ObjectStateBehavior"))

    def test_soft(self):
        w = World(owner=False)
        sm = w.reader()
        self.assertEqual(sm.state(w.obj), (None, "its ObjectStateBehavior isn't the object's"))
        self.assertEqual(World(with_state=False).reader().state(World(with_state=False).obj)[0], None)
        w2 = World(with_state=False)
        self.assertEqual(w2.reader().behavior(w2.obj), (0, "no ObjectStateBehavior"))
        w3 = World(state="   ")
        self.assertEqual(w3.reader().state(w3.obj), (None, "its m_currentState is empty"))
        w4 = World()
        props = {"CoreObject": PROPS["CoreObject"], "ObjectStateBehavior": {"m_currentState": 0xA0}}
        self.assertEqual(w4.reader(props=props).state(w4.obj), (None, "its m_currentState isn't a text"))
        self.assertEqual(sm.state(0), (None, "not an object"))
        self.assertEqual(sm.state(0x7FFFFFFF0000 - 8)[0], None)                # (unreadable memory)
        # (a vector that isn't one: no behaviours)
        w5 = World()
        w5.p.write(w5.obj + 0xE0, struct.pack("<QQ", 0x10000000, 0x0F000000))
        self.assertEqual(w5.reader().behavior(w5.obj), (0, "no ObjectStateBehavior"))

        class Boom:
            def try_read(self, a, n):
                raise RuntimeError("boom")
        w6 = World()
        sm6 = w6.reader()
        sm6.p = Boom()
        self.assertEqual(sm6.state(w6.obj)[0], None)                            # (never raises)
        self.assertEqual(sm6.strings(w6.beh), [])

    def test_lookup(self):
        w = World()
        with self.assertRaises(LookupError):
            w.reader(props={"ObjectStateBehavior": PROPS["ObjectStateBehavior"]})          # (no behaviour vector)
        with self.assertRaises(LookupError):
            w.reader(props={"CoreObject": PROPS["CoreObject"]}, vts={})                     # (no state class)
        noprop = {"CoreObject": PROPS["CoreObject"], "ObjectStateBehavior": {"m_stateSetName": 0x60}}
        with self.assertRaises(LookupError):
            w.reader(props=noprop)                                                          # (no state property)
        sm = w.reader(props=noprop, need_state=False)                                       # (--watch: made all the same)
        self.assertIsNone(sm.prop)
        self.assertEqual(sm.state(w.obj), (None, "no state property in this build"))
        self.assertEqual(sm.behavior(w.obj), (w.beh, ""))

    def test_pick(self):
        self.assertEqual(S.pick_state_prop({"ObjectStateBehavior": {"m_state": 8, "m_currentState": 16}}),
                         ("ObjectStateBehavior", "m_currentState", 16))
        self.assertEqual(S.pick_state_prop({"ClientObjectStateBehavior": {"m_state": 24},
                                            "ObjectStateBehavior": {"m_state": 8}}),
                         ("ClientObjectStateBehavior", "m_state", 24))
        self.assertEqual(S.pick_state_prop({"ObjectStateBehavior": {"m_curStateName": 40, "m_stateSet": 8}}),
                         ("ObjectStateBehavior", "m_curStateName", 40))
        self.assertIsNone(S.pick_state_prop({"ObjectStateBehavior": {"m_stateSet": 8, "m_states": 16}}))
        self.assertIsNone(S.pick_state_prop({}))
        old = S.STATE_PROP
        try:
            S.STATE_PROP = "m_stateSet"                                         # (pinned: that one only)
            self.assertEqual(S.pick_state_prop({"ObjectStateBehavior": {"m_stateSet": 8, "m_currentState": 16}}),
                             ("ObjectStateBehavior", "m_stateSet", 8))
            self.assertIsNone(S.pick_state_prop({"ObjectStateBehavior": {"m_currentState": 16}}))
        finally:
            S.STATE_PROP = old

    def test_watch_lines(self):
        w = World()
        sm = w.reader()
        rows = S.watch_rows(sm, [(w.obj, 0x55, "CL-Gate"), (w.npc, 0x66, "CL-Other")],
                            lambda b: "ObjectStateBehavior" if b == w.beh else None)
        self.assertEqual((rows[0]["state"], rows[0]["class"]), ("Closed", "ObjectStateBehavior"))
        line = S.watch_line(rows[0], (1.0, 2.0, 3.0))
        self.assertIn("state 'Closed'", line)
        self.assertIn("m_currentState+0x80='Closed'", line)
        self.assertEqual(rows[1]["behaviour"], 0)
        self.assertIn("CL-Other", S.watch_line(rows[1]))
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(S._main([]), 2)                                     # (no --watch: the help)
        self.assertIn("--watch", out.getvalue())


def import_navmem():
    """the real navmem, its Windows DLLs stood in for (test_navroute.py's way - another test file's stand-in put back)"""
    from test_navroute import import_navmem as imp
    return imp()


class NavmemState(unittest.TestCase):
    """navmem: each door blockers() lists gets its state (the reader stood in for); None while it isn't known"""

    @classmethod
    def setUpClass(cls):
        cls.N = import_navmem()

    def test_fill(self):
        nm = self.N.NavMem(log=lambda m: None)
        st = object()
        nm.st = st

        class SM:
            def state(self, obj):
                return ("Open", "") if obj == 0xD0 else (None, "no ObjectStateBehavior")
        sm = SM()
        sm.st = st
        nm._state_reader = lambda s, wait=0.0: (sm, "")
        live = [(0xD0, 5, {}), (0xE0, 6, {})]
        nm._state_fill(st, live)
        self.assertEqual([d["state"] for _o, _g, d in live], ["Open", None])
        nm._state_reader = lambda s, wait=0.0: (None, "being made")
        nm._state_fill(st, live)
        self.assertEqual([d["state"] for _o, _g, d in live], [None, None])
        sm.st = object()                                                        # (another game's reader: not used)
        nm._state_reader = lambda s, wait=0.0: (sm, "")
        nm._state_fill(st, live)
        self.assertEqual([d["state"] for _o, _g, d in live], [None, None])

    def test_reader_made_once(self):
        N = self.N
        nm = N.NavMem(log=lambda m: None)
        st = types.SimpleNamespace()
        made = []

        def make(s):
            made.append(s)
            with nm.lock:
                nm._state = types.SimpleNamespace(st=s)
        nm._state_make = make
        sm, why = nm._state_reader(st, wait=1.0)
        self.assertIs(sm.st, st)
        self.assertIs(nm._state_reader(st)[0], sm)
        self.assertEqual(len(made), 1)
        # (a build it can't read: kept, said why, not made again till RETRY_SIG)
        nm2 = N.NavMem(log=lambda m: None)
        nm2._state_failed(st, LookupError("no ObjectStateBehavior class"))
        sm2, why2 = nm2._state_reader(st)
        self.assertIsNone(sm2)
        self.assertIn("no ObjectStateBehavior class", why2)

    def test_live_blockers(self):
        N = self.N
        nm = N.NavMem(log=lambda m: None)
        CZ, VT, obj = 0x200000, 0x7FF600001000, 0x500000
        raw = bytearray(N.OBJ_SPAN)
        struct.pack_into("<Q", raw, 0, VT)
        struct.pack_into("<Q", raw, N.DATA["co_gid"], 77)
        struct.pack_into("<Q", raw, N.DATA["co_zone"], CZ)
        struct.pack_into("<6f", raw, 0xA8, 1.0, 2.0, 3.0, 0.0, 0.0, 0.0)
        st = types.SimpleNamespace(o={}, p=types.SimpleNamespace(try_read=lambda a, n: bytes(raw[:n]) if a == obj else None))
        nm.st, nm._obj_cz, nm._obj_why = st, CZ, ""
        nm._obj_thread = types.SimpleNamespace(is_alive=lambda: True)
        nm._blockers = {obj: (77, "CL-Gate", "CL-Gate", VT)}
        nm._state_fill = lambda s, live: [d.update(state="Shut") for _o, _g, d in live]
        doors, why = nm.blockers()
        self.assertEqual(why, "")
        self.assertEqual([(d["template"], d["state"], d["pos"]) for d in doors], [("CL-Gate", "Shut", (1.0, 2.0, 3.0))])

        def boom(s, live):
            raise RuntimeError("boom")
        said = []
        nm.log = said.append
        nm._state_fill = boom
        doors, why = nm.blockers()
        self.assertEqual((why, doors[0]["state"]), ("", None))                 # (the doors all the same, no state)
        self.assertTrue(said and "statemem" in said[0])
        # (items and mobs: no state looked at)
        nm._items = {obj: (77, "Thing", "CL-Gate", VT, "Key_1", "object")}
        items, _ = nm.items()
        self.assertNotIn("state", items[0])
        self.assertTrue(time.monotonic() > 0)


if __name__ == "__main__":
    unittest.main()
