"""test_gearmem.py - the gear reader (vision\\gearmem.py: the worn items and the backpack's, each template's equip effects
and requirements read by their reflected names and guessed types, the Equipment Sets, the level; every failure soft) on a
made-up wizard in made-up memory, and navmem's gear() with its reader stood in (the real navmem with its DLLs stood in for,
as test_navroute.py does) - no game, no Windows:  python3 -m unittest test_gearmem   (from AutoFarmer\\vision)"""
import io
import os
import struct
import sys
import types
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import gearmem as M  # noqa: E402
import gearrank as G  # noqa: E402

# made-up offsets (any will do - the reader takes them from props)
PROPS = {"CoreObject": {"m_globalID.m_full": 0x48, "m_templateID.m_full": 0x60, "m_inactiveBehaviors": 0xE0},
         "WizClientObject": {"m_gameStats": 0x230}, "WizGameStats": {"m_referenceLevel": 0x80},
         "ClientEquipmentBehavior": {"m_itemList": 0x78}, "InventoryBehaviorBase": {"m_itemList": 0x70},
         "ClientWizEquipmentBehavior": {"m_equipmentSets": 0xE8},
         "EquipmentSet": {"m_serializedItems": 0x60, "m_isEquipped": 0x80},
         "GameObjectTemplate": {"m_objectName": 0x60, "m_displayName": 0xA8, "m_adjectiveList": 0xF8},
         "ItemTemplate": {"m_equipEffects": 0x128, "m_equipRequirements": 0x140},
         "GameEffectInfo": {"m_effectName": 0x48},
         "StatisticEffectInfo": {"m_lookupIndex": 0x68},
         "StartingPipEffectInfo": {"m_pipsGiven": 0x68, "m_powerPipsGiven": 0x6C},
         "RequirementList": {"m_applyNOT": 0x48, "m_operator": 0x4C, "m_requirements": 0x50},
         "Requirement": {"m_applyNOT": 0x48, "m_operator": 0x4C},
         "ReqNumeric": {"m_numericValue": 0x58, "m_operatorType": 0x5C},
         "ReqMagicLevel": {"m_magicSchool": 0x60},
         "ReqSchoolOfFocus": {"m_magicSchool": 0x58}}
TYPES = {"GameEffectInfo": {"m_effectName": "std::string"}, "StatisticEffectInfo": {"m_lookupIndex": "int"},
         "StartingPipEffectInfo": {"m_pipsGiven": "int", "m_powerPipsGiven": "int"},
         "RequirementList": {"m_applyNOT": "bool", "m_operator": "?", "m_requirements": "?"},
         "Requirement": {"m_applyNOT": "bool", "m_operator": "?"},
         "ReqNumeric": {"m_numericValue": "float", "m_operatorType": "?"},
         "ReqMagicLevel": {"m_magicSchool": "std::string"}, "ReqSchoolOfFocus": {"m_magicSchool": "std::string"}}


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

    def put_list(self, a, values, strings=False, size=None):
        """an MSVC std::list at a: {head, size}, its nodes next, prev, the value at +0x10 (a 16-byte SharedPointer, or
        a std::string with strings)"""
        head = self.alloc(0x40)
        nodes = [self.alloc(0x40) for _ in values]
        chain = [head] + nodes
        for i, n in enumerate(chain):
            self.write(n, struct.pack("<QQ", chain[(i + 1) % len(chain)], chain[i - 1]))
        for n, v in zip(nodes, values):
            if strings:
                self.put_string(n + 0x10, v)
            else:
                self.write(n + 0x10, struct.pack("<QQ", v, 0))
        self.write(a, struct.pack("<QQ", head, len(values) if size is None else size))


class World:
    """a made-up wizard: its object, behaviours, worn items and backpack, the templates (hm.template), the type names"""

    def __init__(self):
        self.p = Mem()
        self.types = {}
        self.tpls = {}
        self.names = {"Key_Hat": "Fire Hat of Testing"}
        self.tn = types.SimpleNamespace(of=lambda obj: self.types.get(obj))
        self.m = types.SimpleNamespace(build="TEST-1")
        self.o = {"gc_elastic_cam": 0x100, "cam_attached_object": 0x108}
        self.gc = self.obj("GameClient", 0x200)
        cam = self.obj("ElasticCamController", 0x200)
        self.co = self.obj("WizClientObject", 0x300)
        self.p.write(self.gc + 0x100, struct.pack("<Q", cam))
        self.p.write(cam + 0x108, struct.pack("<Q", self.co))
        self.p.write(self.co + 0x48, struct.pack("<Q", 0xC0FFEE))
        gs = self.obj("WizGameStats", 0x100)
        self.p.write(self.co + 0x230, struct.pack("<Q", gs))
        self.p.write(gs + 0x80, struct.pack("<i", 72))
        self.eq = self.obj("ClientWizEquipmentBehavior", 0x100)
        self.inv = self.obj("ClientWizInventoryBehavior", 0x100)
        vec = self.p.alloc(0x40)
        self.p.write(vec, struct.pack("<QQQQ", self.eq, 0, self.inv, 0))
        self.p.write(self.co + 0xE0, struct.pack("<QQ", vec, vec + 32))
        self.hm = types.SimpleNamespace(template=lambda tid: self.tpls.get(tid, 0),
                                        lang_text=lambda k: self.names.get(k))

    def obj(self, tname, n=0x200):
        a = self.p.alloc(n)
        self.types[a] = tname
        return a

    def gameclient(self):
        return self.gc

    def player(self, gc):
        return self.co, ""

    def template(self, tid, name, adjs, effects=(), reqs=None, key=None):
        """an item template: its name, adjectives, display key, equip effects (objects) and requirement list (an object,
        0 none)"""
        t = self.obj("WizItemTemplate", 0x200)
        self.p.put_string(t + 0x60, name)
        self.p.put_list(t + 0xF8, list(adjs), strings=True)
        if key:
            self.p.put_string(t + 0xA8, key)
        self.p.put_list(t + 0x128, list(effects))
        self.p.write(t + 0x140, struct.pack("<QQ", reqs or 0, 0))
        self.tpls[tid] = t
        return t

    def stat(self, name, index):
        e = self.obj("StatisticEffectInfo", 0x100)
        self.p.put_string(e + 0x48, name)
        self.p.write(e + 0x68, struct.pack("<i", index))
        return e

    def pips(self, n, power):
        e = self.obj("StartingPipEffectInfo", 0x100)
        self.p.put_string(e + 0x48, "Pips")
        self.p.write(e + 0x68, struct.pack("<ii", n, power))
        return e

    def reqs(self, level=None, school=None, op=0, neg=False):
        rl = self.obj("RequirementList", 0x100)
        self.p.write(rl + 0x48, struct.pack("<?3xi", neg, op))
        lst = []
        if level is not None:
            q = self.obj("ReqMagicLevel", 0x100)
            self.p.write(q + 0x48, struct.pack("<?3xi", False, 0))
            self.p.write(q + 0x58, struct.pack("<fi", float(level), 3))
            self.p.put_string(q + 0x60, "")
            lst.append(q)
        if school is not None:
            q = self.obj("ReqSchoolOfFocus", 0x100)
            self.p.write(q + 0x48, struct.pack("<?3xi", False, 0))
            self.p.put_string(q + 0x58, school)
            lst.append(q)
        self.p.put_list(rl + 0x50, lst)
        return rl

    def item(self, gid, tid):
        it = self.obj("WizClientObjectItem", 0x100)
        self.p.write(it + 0x48, struct.pack("<Q", gid))
        self.p.write(it + 0x60, struct.pack("<I", tid))
        return it

    def sets(self, *sets):
        objs = []
        for ids, on in sets:
            es = self.obj("EquipmentSet", 0x100)
            data = struct.pack("<H", len(ids)) + b"".join(struct.pack("<Q", g) for g in ids)
            h = self.p.alloc(len(data) + 1)
            self.p.write(h, data)
            self.p.write(es + 0x60, struct.pack("<QQQQ", h, 0, len(data), max(len(data), 16)))
            self.p.write(es + 0x80, bytes([1 if on else 0]))
            objs.append(es)
        self.p.put_list(self.eq + 0xE8, objs)


def wizard():
    """worn: a hat (two stats, level 50, fire only) and a deck; backpack: a better hat, a robe with pips (no requirement
    list), a reagent; Equipment Set 1 holds the worn hat"""
    w = World()
    w.template(1, "Hat-Fire-L50-001", ["Hat", "FLAG_NoTrade"], [w.stat("CanonicalFireDamage", 3),
                                                                w.stat("CanonicalMaxHealth", 2)],
               w.reqs(level=50, school="Fire"), key="Key_Hat")
    w.template(2, "Deck-Purchased-50", ["Deck"])
    w.template(3, "Hat-Fire-L60-002", ["Hat"], [w.stat("CanonicalFireDamage", 5)], w.reqs(level=60))
    w.template(4, "Robe-L10-003", ["Robe", "FLAG_NoSell"], [w.pips(1, 0)])
    w.template(5, "Reagent-Bones", ["Reagent"])
    worn = [w.item(0x111, 1), w.item(0x112, 2)]
    bag = [w.item(0x221, 3), w.item(0x222, 4), w.item(0x223, 5)]
    w.p.put_list(w.eq + 0x78, worn)
    w.p.put_list(w.inv + 0x70, bag)
    w.sets(([0x111, 0x112], True), ([0x999], False))
    return w


class Pure(unittest.TestCase):
    def test_either(self):
        self.assertEqual(M.either(struct.pack("<i", 100)), 100)
        self.assertEqual(M.either(struct.pack("<f", 100.0)), 100.0)
        self.assertEqual(M.either(struct.pack("<f", 0.25)), 0.25)
        self.assertEqual(M.either(struct.pack("<i", -7)), -7)
        self.assertIsNone(M.either(struct.pack("<f", float("nan"))))
        self.assertIsNone(M.either(b"\x01"))
        self.assertIsNone(M.either(None))

    def test_kind_of(self):
        self.assertEqual(M.kind_of("m_effectName", "std::string"), "str")
        self.assertEqual(M.kind_of("m_lookupIndex", "int"), "i32")
        self.assertEqual(M.kind_of("m_sThing", "?"), "str")
        self.assertEqual(M.kind_of("m_magicSchool", "?"), "str")
        self.assertEqual(M.kind_of("m_bThing", "?"), "flag")
        self.assertEqual(M.kind_of("m_applyNOT", "?"), "flag")
        self.assertEqual(M.kind_of("m_operator", "?"), "num")
        self.assertEqual(M.kind_of("m_requirements", "std::list<SharedPointer<Requirement>>"), "skip")
        self.assertEqual(M.parse_set_ids(struct.pack("<HQ", 1, 5)), [5])
        self.assertIsNone(M.parse_set_ids(struct.pack("<H", 3)))


class Reader(unittest.TestCase):
    def make(self, w, props=PROPS, types_=TYPES):
        return M.GearMem(w, w.hm, props=props, types=types_)

    def test_read(self):
        w = wizard()
        gm = self.make(w)
        r, why = gm.read()
        self.assertEqual(why, "")
        self.assertEqual((r["level"], r["player_gid"], r["bag_size"]), (72, 0xC0FFEE, 3))
        self.assertEqual(r["bag_gids"], [0x221, 0x222, 0x223])
        self.assertEqual([d["slot"] for d in r["worn"]], ["hat", "deck"])
        self.assertEqual([d["slot"] for d in r["bag"]], ["hat", "robe"])           # (the reagent: its id only)
        hat = r["worn"][0]
        self.assertEqual((hat["gid"], hat["tid"], hat["name"], hat["sets"]), (0x111, 1, "Hat-Fire-L50-001", [1]))
        self.assertEqual([e["type"] for e in hat["effects"]], ["StatisticEffectInfo", "StatisticEffectInfo"])
        self.assertEqual(hat["effects"][0]["fields"], {"m_effectName": "CanonicalFireDamage", "m_lookupIndex": 3})
        self.assertTrue(hat["effects"][0]["own"])
        reqs = hat["reqs"]
        self.assertEqual((reqs["op"], reqs["not"]), (0, False))
        self.assertEqual([q["type"] for q in reqs["list"]], ["ReqMagicLevel", "ReqSchoolOfFocus"])
        self.assertEqual(reqs["list"][0]["fields"]["m_numericValue"], 50.0)        # (ReqNumeric's, its base)
        self.assertEqual(reqs["list"][0]["fields"]["m_operatorType"], 3)           # (an enum: "?" - read as a number)
        self.assertEqual(reqs["list"][1]["fields"]["m_magicSchool"], "Fire")
        self.assertIsNone(r["worn"][1]["effects"])                                  # (a deck: no effects read)
        robe = r["bag"][1]
        self.assertEqual(robe["reqs"], {"op": None, "not": None, "list": []})       # (no RequirementList)
        self.assertTrue(robe["nosell"])
        self.assertFalse(robe["crowns"])
        self.assertEqual(robe["effects"][0]["fields"]["m_pipsGiven"], 1)
        self.assertTrue(r["sets_ok"])
        self.assertEqual([s["ids"] for s in r["sets"]], [[0x111, 0x112], [0x999]])
        # (what gearrank makes of it: the stat sizes are indexes - not known -, the requirements are)
        self.assertEqual(G.meets_reqs(hat["reqs"], 72, "fire")[0], True)
        self.assertEqual(G.meets_reqs(hat["reqs"], 72, "ice")[0], False)
        st, unk, how = G.item_stats(hat["effects"])
        self.assertEqual(sorted(unk), ["damage.fire", "health"])
        self.assertEqual(how["damage.fire"], "index:3")
        # (the display names, outside the lock)
        M.finish(r, w.hm.lang_text)
        self.assertEqual((hat["display"], r["bag"][0]["display"]), ("Fire Hat of Testing", None))
        lines = M.item_lines(r, effects=True)
        self.assertTrue(lines[0].startswith("worn|hat|111|1|Hat-Fire-L50-001|Fire Hat of Testing|1|damage.fire=#3"))
        self.assertIn("  effect|StatisticEffectInfo|1|m_effectName=CanonicalFireDamage,m_lookupIndex=3", lines)
        self.assertEqual(lines[-1].split("|")[:6], ["read", "2", "2", "3", "72", "1"])

    def test_templates_kept(self):
        w = wizard()
        gm = self.make(w)
        gm.read()
        self.assertIn(1, gm.gear)
        self.assertIn(5, gm.tpl)
        # (a template read whole isn't read again: its effects list broken now - still the kept one)
        w.p.write(w.tpls[1] + 0x128, struct.pack("<QQ", 0, 0))
        r, _ = gm.read()
        self.assertEqual(len(r["worn"][0]["effects"]), 2)

    def test_soft(self):
        w = wizard()
        # (an effect list that says more than it holds: that item's effects None, the rest read)
        w.p.put_list(w.tpls[3] + 0x128, [w.stat("CanonicalFireDamage", 1)], size=5)
        r, why = self.make(w).read()
        self.assertEqual(why, "")
        self.assertIsNone(r["bag"][0]["effects"])
        j = G.swap_plan(r["worn"], r["bag"], {}, "fire", 72)["judged"][0]
        self.assertEqual((j["verdict"], j["why"]), ("unknown", "its equip effects couldn't be read"))
        # (a backpack list cut short: nothing - a drop could be missed)
        w2 = wizard()
        w2.p.put_list(w2.inv + 0x70, [w2.item(0x1, 3)], size=4)
        r2, why2 = self.make(w2).read()
        self.assertIsNone(r2)
        self.assertIn("broke off", why2)
        # (no camera object: why)
        w3 = wizard()
        w3.types[w3.co] = "PropertyClass"
        self.assertEqual(self.make(w3).read(), (None, "the camera follows no wizard (PropertyClass)"))
        # (a requirement list of another type: not read)
        w4 = wizard()
        rl = struct.unpack("<Q", w4.p.try_read(w4.tpls[1] + 0x140, 8))[0]
        w4.types[rl] = "Junk"
        r4, _ = self.make(w4).read()
        self.assertIsNone(r4["worn"][0]["reqs"])
        # (a raise inside: (None, why), never out)
        w5 = wizard()
        w5.player = lambda gc: (_ for _ in ()).throw(RuntimeError("x"))
        self.assertEqual(self.make(w5).read()[0], None)

    def test_missing_and_lacking(self):
        w = wizard()
        props = {k: dict(v) for k, v in PROPS.items()}
        del props["ItemTemplate"]["m_equipEffects"]
        with self.assertRaises(LookupError):
            self.make(w, props)
        props = {k: dict(v) for k, v in PROPS.items()}
        del props["ItemTemplate"]["m_equipRequirements"]
        del props["WizGameStats"]
        gm = self.make(w, props)
        self.assertIn("ItemTemplate.m_equipRequirements", gm.lack)
        self.assertIn("SpeedEffectInfo", gm.lack)
        r, _ = gm.read()
        self.assertIsNone(r["level"])
        self.assertIsNone(r["worn"][0]["reqs"])
        self.assertEqual(len(r["worn"][0]["effects"]), 2)          # (kept without requirements: this build has none)
        # (props with adders - the real lookup's shape - and a field with no type: by its name)
        props = {c: {k: (o, 0x1000) for k, o in v.items()} for c, v in PROPS.items()}
        gm = self.make(w, props, {})
        r, _ = gm.read()
        f = r["worn"][0]["effects"][0]["fields"]
        self.assertEqual(f, {"m_effectName": "CanonicalFireDamage", "m_lookupIndex": 3})
        self.assertEqual(r["worn"][0]["reqs"]["list"][0]["fields"]["m_numericValue"], 50.0)     # (either: a float)

    def test_unknown_effect_type(self):
        w = wizard()
        e = w.obj("BrandNewEffectInfo", 0x100)
        w.p.put_string(e + 0x48, "Mystery")
        w.p.put_list(w.tpls[3] + 0x128, [e])
        r, _ = self.make(w).read()
        eff = r["bag"][0]["effects"][0]
        self.assertEqual((eff["type"], eff["own"], eff["fields"]), ("BrandNewEffectInfo", False,
                                                                    {"m_effectName": "Mystery"}))


def import_navmem():
    """the real navmem, its Windows DLLs stood in for (test_navroute.py's way - another test file's stand-in put back)"""
    from test_navroute import import_navmem as imp
    return imp()


class NavmemGear(unittest.TestCase):
    """navmem.gear(): its reader stood in - read under the lock, the names finished, the game changing caught"""

    @classmethod
    def setUpClass(cls):
        cls.N = import_navmem()

    def test_gear(self):
        nm = self.N.NavMem(log=lambda m: None)
        w = wizard()
        w.alive = lambda: True
        st = w
        gm = M.GearMem(w, w.hm, props=PROPS, types=TYPES)
        nm.st = st
        nm._ensure = lambda wait: (st, "")
        nm._gear_reader = lambda s, wait=0.0: (gm, "")
        r, why = nm.gear()
        self.assertEqual(why, "")
        self.assertEqual(r["worn"][0]["display"], "Fire Hat of Testing")
        gm.st = object()
        self.assertEqual(nm.gear(), (None, "the game changed"))
        nm._gear_reader = lambda s, wait=0.0: (None, "reading the game's gear classes (once, about a second)")
        self.assertEqual(nm.gear()[1], "reading the game's gear classes (once, about a second)")
        nm._ensure = lambda wait: (_ for _ in ()).throw(RuntimeError("boom"))
        self.assertTrue(nm.gear()[1].startswith("reading the gear failed"))

    def test_reader_made_once_and_failure_kept(self):
        N = self.N
        nm = N.NavMem(log=lambda m: None)
        st = object()
        made = []

        def make(s):
            made.append(s)
            with nm.lock:
                nm._gearm_fail = (s, 1e18, "the gear can't be read in this build: X")
        nm._gear_make = make
        self.assertEqual(nm._gear_reader(st, wait=1.0), (None, "the gear can't be read in this build: X"))
        self.assertEqual(nm._gear_reader(st), (None, "the gear can't be read in this build: X"))
        self.assertEqual(len(made), 1)
        nm.close()
        self.assertIsNone(nm._gearm)


class CommandLine(unittest.TestCase):
    def test_help(self):
        out = io.StringIO()
        with redirect_stdout(out), self.assertRaises(SystemExit):
            M._main(["--help"])
        self.assertIn("--effects", out.getvalue())


if __name__ == "__main__":
    unittest.main()
