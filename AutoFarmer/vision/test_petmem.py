"""test_petmem.py - the pets reader (vision\\petmem.py: every pet worn and in the backpack, its level and its level's power
cards, the values not confirmed yet read only once pinned - by name -, every failure soft; pet_lines), deckmem's pet
cards through petmem's shared walk (a pet that can't be read loses only its own cards, not the gear's), navmem's pets()
plumbing and the vision helper's /pets on a local server - on made-up memory: no game, no Windows (the real navmem with
its DLLs stood in for, as test_navroute.py does; sys.modules put back as it was):
python -m unittest test_petmem   (from AutoFarmer\\vision)"""
import io
import os
import struct
import sys
import tempfile
import threading
import types
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import petmem as M  # noqa: E402

# offsets as they were in build 6A9721E9-370E000 (any will do - the reader takes them from props)
PROPS = {"CoreObject": {"m_inactiveBehaviors": 0xE0, "m_globalID.m_full": 0x48, "m_templateID.m_full": 0x60},
         "InventoryBehaviorBase": {"m_itemList": 0x70}, "ClientEquipmentBehavior": {"m_itemList": 0x78},
         "BasePetItemBehavior": {"m_level": 0x70, "m_XP": 0x74, "m_talentList": 0x80, "m_derbyList": 0x98},
         "ClientPetItemBehavior": {"m_clientOnly": 0xB0},
         "PetItemBehaviorTemplate": {"m_Levels": 0x130, "m_maxStats": 0x150},
         "PetLevelInfo": {"m_level": 0x48, "m_requiredXP": 0x4C, "m_powerCardCount": 0x54, "m_powerCardName": 0x58,
                          "m_powerCardName2": 0x78, "m_powerCardName3": 0x98},
         "GameObjectTemplate": {"m_objectName": 0x60, "m_displayName": 0xA8},
         "WizClientObject": {"m_gameStats": 0x230}, "WizGameStats": {"m_petEnergy": 0x90, "m_petEnergyMax": 0x94},
         "PetTalentTemplate": {"m_talentName": 0x60},
         "SpellData": {"m_templateID": 0x48, "m_quantity": 0x50}, "DeckBehavior": {"m_spellList": 0x78},
         "ItemTemplate": {"m_equipEffects": 0x128}, "ProvideSpellEffectInfo": {"m_spellName": 0x68, "m_numSpells": 0x88}}
CAM, ATT = 0x88, 0x40          # (navmem's gc_elastic_cam / cam_attached_object - made up)


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

    def q(self, a, v):
        self.write(a, struct.pack("<Q", v))


class World:
    """a made-up game: the wizard (the camera's object), its equipment and backpack behaviours and their item lists,
    items with a pet behaviour or none, the pets' template and its levels, item templates (handmem's map), a name table"""

    def __init__(self):
        self.p = Mem()
        self.types = {}
        self.tn = types.SimpleNamespace(of=lambda obj: self.types.get(obj))
        self.m = types.SimpleNamespace(build="TEST-1")
        self.o = {"gc_elastic_cam": CAM, "cam_attached_object": ATT}
        self.templates = {}
        self.names = {"Pets_SwordShield": "Sword and Shield", "Talents_SpellProof": "Spell-Proof"}
        p = self.p
        self.gc, cam, self.co = p.alloc(0x100), p.alloc(0x100), p.alloc(0x400)
        p.q(self.gc + CAM, cam)
        p.q(cam + ATT, self.co)
        self.types[self.co] = "WizClientObject"
        self.eq, self.inv = self.obj("ClientWizEquipmentBehavior", 0x200), self.obj("ClientWizInventoryBehavior", 0x200)
        self.behaviours(self.co, [self.eq, self.inv])
        self.worn, self.bag = [], []
        self.lists = {}
        self.gs = self.obj("WizGameStats", 0x200)
        p.q(self.co + PROPS["WizClientObject"]["m_gameStats"], self.gs)
        p.write(self.gs + 0x90, struct.pack("<ii", 37, 140))
        self.pet_tpl = self.levels([(1, 0, "Pet - Sharpened Blade", 1), (6, 100, "Pet - Spritely", 1),
                                    (7, 300, "Pet - Sharpened Blade", 2)])
        self.item_tpl(9001, "PET_SwordShield_01", "Pets_SwordShield")
        self.item_tpl(9002, "Hat-Plain-01", None)

    # (helpers)
    def obj(self, tname, n=0x100):
        a = self.p.alloc(n)
        self.types[a] = tname
        return a

    def behaviours(self, obj, behs):
        vec = self.p.alloc(16 * max(1, len(behs)))
        for i, b in enumerate(behs):
            self.p.q(vec + 16 * i, b)
        self.p.write(obj + PROPS["CoreObject"]["m_inactiveBehaviors"], struct.pack("<QQ", vec, vec + 16 * len(behs)))

    def slist(self, at, values, value_bytes=None):
        """an MSVC std::list {head, size} at at: nodes next, prev, then the value at +0x10 (a pointer, or bytes)"""
        p = self.p
        head = p.alloc(0x40)
        nodes = []
        for v in values:
            n = p.alloc(0x100)
            if value_bytes is None:
                p.q(n + 0x10, v)
            else:
                value_bytes(n + 0x10, v)
            nodes.append(n)
        ring = [head] + nodes + [head]
        for i in range(1, len(ring) - 1):
            p.write(ring[i], struct.pack("<QQ", ring[i + 1], ring[i - 1]))
        p.write(head, struct.pack("<QQ", ring[1], ring[-2]))
        p.write(at, struct.pack("<QQ", head, len(values)))
        return head, nodes

    def levels(self, rows):
        """a PetItemBehaviorTemplate whose m_Levels holds a PetLevelInfo (by value) a row: (level, xp, card, count)"""
        tpl = self.obj("PetItemBehaviorTemplate", 0x200)
        PL = PROPS["PetLevelInfo"]

        def put(a, row):
            lv, xp, card, cnt = row
            self.types[a] = "PetLevelInfo"
            self.p.write(a + PL["m_level"], bytes([lv]))
            self.p.write(a + PL["m_requiredXP"], struct.pack("<I", xp))
            self.p.write(a + PL["m_powerCardCount"], struct.pack("<i", cnt))
            self.p.put_string(a + PL["m_powerCardName"], card)
            for k in ("m_powerCardName2", "m_powerCardName3"):
                self.p.put_string(a + PL[k], "")
        self.slist(tpl + PROPS["PetItemBehaviorTemplate"]["m_Levels"], rows, put)
        return tpl

    def item_tpl(self, tid, name, key):
        t = self.obj("WizItemTemplate", 0x200)
        self.p.put_string(t + 0x60, name)
        self.p.put_string(t + 0xA8, key or "")
        self.templates[tid] = t
        return t

    def item(self, gid, tid, where, pet_level=None, tpl=None, beh_class="ClientPetItemBehavior"):
        it = self.obj("WizClientObjectItem", 0x200)
        self.p.q(it + 0x48, gid)
        self.p.write(it + 0x60, struct.pack("<I", tid))
        behs = [self.obj("ClientWizItemBehavior", 0x100)]
        beh = 0
        if pet_level is not None:
            beh = self.obj(beh_class, 0x200)
            self.p.write(beh + 0x70, bytes([pet_level]))
            self.p.q(beh + 0x58, tpl if tpl is not None else self.pet_tpl)
            behs.append(beh)
        self.behaviours(it, behs)
        (self.worn if where == "equipped" else self.bag).append(it)
        return it, beh

    def done(self):
        self.slist(self.eq + 0x78, self.worn)
        self.slist(self.inv + 0x70, self.bag)
        return self

    # (navmem's _Attached)
    def gameclient(self):
        return self.gc

    def player(self, gc):
        return self.co, ""


class Hand:
    """handmem.HandMem's template map and name tables, made up"""

    def __init__(self, w):
        self.w = w
        self.st = w

    def template(self, tid):
        return self.w.templates.get(tid, 0)

    def lang_text(self, key):
        return self.w.names.get(key)


def world_two_pets():
    w = World()
    w.item(0x11, 9002, "equipped")                                      # a hat: no pet
    _it, beh = w.item(0x22, 9001, "equipped", pet_level=6)              # the worn pet: Mega
    w.item(0x33, 9001, "backpack", pet_level=1)                         # a baby
    w.item(0x44, 9002, "backpack")
    return w.done(), beh


class Reader(unittest.TestCase):
    """PetMem.read on made-up memory"""

    def test_every_pet_its_level_and_cards(self):
        w, _beh = world_two_pets()
        said = []
        pm = M.PetMem(w, Hand(w), log=said.append, props=PROPS, pins={})
        r = pm.read()
        self.assertEqual(r["why"], "")
        self.assertTrue(r["whole"])
        self.assertEqual([(p["gid"], p["where"], p["level"], p["level_name"]) for p in r["pets"]],
                         [(0x22, "equipped", 6, "Mega"), (0x33, "backpack", 1, "Baby")])
        mega = r["pets"][0]
        self.assertEqual((mega["object_name"], mega["display"], mega["template_id"]),
                         ("PET_SwordShield_01", "Sword and Shield", 9001))
        self.assertEqual(mega["cards"], [("Pet - Spritely", 1, "pet level 6")])
        self.assertEqual(mega["behavior_class"], "ClientPetItemBehavior")
        # (not pinned: every value not confirmed is None - nothing guessed)
        for k in ("xp", "xp_next", "talents", "talent_ids", "derby", "stats", "max_stats"):
            self.assertIsNone(mega[k], k)
        self.assertEqual((r["energy"], r["energy_max"]), (None, None))
        self.assertTrue(said and "petmem: ready" in said[0])

    def test_lines(self):
        w, _beh = world_two_pets()
        r = M.PetMem(w, Hand(w), props=PROPS, pins={}).read()
        ln = M.pet_lines(r)
        self.assertEqual(ln[0].split("|"), ["pet", "22", "equipped", "6", "Mega", "9001", "PET_SwordShield_01",
                                            "Sword and Shield", "Pet - Spritely*1", "", "", "", "", "", "",
                                            "ClientPetItemBehavior"])
        self.assertEqual(ln[1].split("|")[:5], ["pet", "33", "backpack", "1", "Baby"])
        self.assertEqual(ln[2], "energy||")
        f = ln[3].split("|")
        self.assertEqual(f[:3], ["pets", "2", "1"])
        self.assertEqual(M.pet_lines(None, "no GameClient yet"), ["none|no GameClient yet"])
        self.assertEqual(M._list([]), "-")
        self.assertEqual(M._list(None), "")
        self.assertEqual(M._list(["Pain-Giver", "a,b|c"]), "Pain-Giver,a b/c")

    def test_pins_read_by_name(self):
        w, beh = world_two_pets()
        p = w.p
        p.write(beh + 0x74, struct.pack("<I", 4321))
        # (talents: a std::vector<u32> of talent template ids, named through the talent_name pin; derby: std::list of
        # std::string - one a name-table key)
        t1 = w.obj("PetTalentTemplate", 0x100)
        t2 = w.obj("PetTalentTemplate", 0x100)
        p.put_string(t1 + 0x60, "Talents_SpellProof")
        p.put_string(t2 + 0x60, "Mighty")
        w.templates.update({501: t1, 502: t2})
        arr = p.alloc(8)
        p.write(arr, struct.pack("<II", 501, 502))
        p.write(beh + 0x80, struct.pack("<QQQ", arr, arr + 8, arr + 8))
        w.slist(beh + 0x98, ["Sprint", "Hop"], lambda a, s: p.put_string(a, s))
        tpl_stats = p.alloc(20)
        p.write(tpl_stats, struct.pack("<5I", 255, 250, 260, 250, 250))
        p.write(w.pet_tpl + 0x150, struct.pack("<QQQ", tpl_stats, tpl_stats + 20, tpl_stats + 20))
        pins = {"xp": ("BasePetItemBehavior", "m_XP", "u32"), "level_xp": ("PetLevelInfo", "m_requiredXP", "u32"),
                "talents": ("BasePetItemBehavior", "m_talentList", "vec_u32"),
                "talent_name": ("PetTalentTemplate", "m_talentName", "str"),
                "derby": ("BasePetItemBehavior", "m_derbyList", "list_str"),
                "max_stats": ("PetItemBehaviorTemplate", "m_maxStats", "vec_u32"),
                "energy": ("WizGameStats", "m_petEnergy", "i32"), "energy_max": ("WizGameStats", "m_petEnergyMax", "i32")}
        r = M.PetMem(w, Hand(w), props=PROPS, pins=pins).read()
        mega, baby = r["pets"]
        self.assertEqual(mega["xp"], 4321)
        self.assertEqual(mega["xp_next"], 300)                          # (the next level's entry: Ultra's)
        self.assertEqual(mega["talent_ids"], [501, 502])
        self.assertEqual(mega["talents"], ["Spell-Proof", "Mighty"])    # (the key given its words)
        self.assertEqual((mega["derby"], mega["derby_ids"]), (["Sprint", "Hop"], ["Sprint", "Hop"]))
        self.assertEqual(mega["max_stats"], [255, 250, 260, 250, 250])
        self.assertEqual((r["energy"], r["energy_max"]), (37, 140))
        self.assertIsNone(baby["xp_next"])                              # (no level 2 entry made up)
        self.assertEqual(baby["talents"], [])                           # (its vector all zero: an empty one - none shown)
        ln = M.pet_lines(r)
        self.assertEqual(ln[0].split("|")[9:15], ["4321", "300", "Spell-Proof,Mighty", "Sprint,Hop", "",
                                                  "255,250,260,250,250"])
        self.assertEqual(ln[2], "energy|37|140")

    def test_a_talent_not_named_makes_the_list_unread(self):
        w, beh = world_two_pets()
        arr = w.p.alloc(8)
        w.p.write(arr, struct.pack("<II", 501, 777))                    # (777: no template)
        w.p.write(beh + 0x80, struct.pack("<QQQ", arr, arr + 8, arr + 8))
        t1 = w.obj("PetTalentTemplate", 0x100)
        w.p.put_string(t1 + 0x60, "Mighty")
        w.templates[501] = t1
        pins = {"talents": ("BasePetItemBehavior", "m_talentList", "vec_u32"),
                "talent_name": ("PetTalentTemplate", "m_talentName", "str")}
        mega = M.PetMem(w, Hand(w), props=PROPS, pins=pins).read()["pets"][0]
        self.assertEqual(mega["talent_ids"], [501, 777])
        self.assertIsNone(mega["talents"])
        # (ids without the talent_name pin: not named either)
        pins.pop("talent_name")
        self.assertIsNone(M.PetMem(w, Hand(w), props=PROPS, pins=pins).read()["pets"][0]["talents"])

    def test_pin_not_in_this_build_or_bad(self):
        w, _beh = world_two_pets()
        said = []
        props = {k: dict(v) for k, v in PROPS.items()}
        del props["BasePetItemBehavior"]["m_XP"]
        pins = {"xp": ("BasePetItemBehavior", "m_XP", "u32"), "bogus": ("BasePetItemBehavior", "m_level", "u8"),
                "energy": ("BasePetItemBehavior", "m_level", "u8"), "stats": ("BasePetItemBehavior", "m_level", "u64")}
        pm = M.PetMem(w, Hand(w), log=said.append, props=props, pins=pins)
        self.assertEqual(sorted(pm.pins), ["xp"])
        self.assertIn("BasePetItemBehavior.m_XP (pin xp)", pm.lack)
        self.assertEqual(sum("a pin dropped" in s for s in said), 3)
        r = pm.read()
        self.assertIsNone(r["pets"][0]["xp"])
        self.assertIn("BasePetItemBehavior.m_XP (pin xp)", r["lack"])
        # (a ClientPetItemBehavior pin on a pet whose behaviour is only the base class: not read)
        w2 = World()
        _it, beh2 = w2.item(0x55, 9001, "backpack", pet_level=3, beh_class="BasePetItemBehavior")
        w2.p.write(beh2 + 0xB0, struct.pack("<I", 9))
        w2.done()
        r2 = M.PetMem(w2, Hand(w2), props=PROPS, pins={"xp": ("ClientPetItemBehavior", "m_clientOnly", "u32")}).read()
        self.assertEqual(r2["pets"][0]["level_name"], "Adult")
        self.assertIsNone(r2["pets"][0]["xp"])

    def test_need_missing_raises(self):
        w, _beh = world_two_pets()
        props = {k: dict(v) for k, v in PROPS.items()}
        del props["BasePetItemBehavior"]["m_level"]
        with self.assertRaises(LookupError):
            M.PetMem(w, Hand(w), props=props, pins={})

    def test_fails_soft(self):
        # (no camera: why; the backpack list cut short: whole False; a level out of range: None, said)
        w, _beh = world_two_pets()
        w.o = {}
        r = M.PetMem(w, Hand(w), props=PROPS, pins={}).read()
        self.assertEqual((r["pets"], r["whole"]), ([], False))
        self.assertIn("camera", r["why"])
        w, _beh = world_two_pets()
        head = struct.unpack("<Q", w.p.try_read(w.inv + 0x70, 8))[0]
        w.p.write(w.inv + 0x78, struct.pack("<Q", 5))                   # (the size says 5 - two are there)
        r = M.PetMem(w, Hand(w), props=PROPS, pins={}).read()
        self.assertFalse(r["whole"])
        self.assertIn("backpack read in part", r["why"])
        self.assertTrue(head)
        w = World()
        w.item(0x66, 9001, "backpack", pet_level=9)
        w.done()
        r = M.PetMem(w, Hand(w), props=PROPS, pins={}).read()
        self.assertEqual((r["pets"][0]["level"], r["pets"][0]["level_name"], r["pets"][0]["cards"]), (None, None, None))
        self.assertIn("level can't be read", r["why"])
        # (a reader that raises inside: why, never out)
        w, _beh = world_two_pets()
        pm = M.PetMem(w, Hand(w), props=PROPS, pins={})

        def boom():
            raise RuntimeError("the game changed")
        r = pm.read(pace=boom)
        self.assertIn("the game changed", r["why"])
        self.assertFalse(r["whole"])

    def test_an_item_not_read_is_never_whole(self):
        # (the review's finding: an item skipped without a word left whole True - QuickSell.ahk's guard then sold the
        # Pet group with a pet pets.txt keeps in it. Each way an item can't be read: whole False, said, the rest read)
        import petplan

        def world(gid=0x33):
            w = World()
            w.item(0x22, 9001, "equipped", pet_level=6)                 # the worn pet
            it, beh = w.item(gid, 9001, "backpack", pet_level=6)        # the backpack's
            w.item(0x44, 9002, "backpack")                              # a hat
            return w.done(), it, beh

        def read(w):
            return M.PetMem(w, Hand(w), props=PROPS, pins={}).read()
        IB = PROPS["CoreObject"]["m_inactiveBehaviors"]
        # its behaviours vector unreadable (freed or moved as it's read): not taken for an item with none
        w, it, _beh = world()
        w.p.write(it + IB, struct.pack("<QQ", 0x7DEAD0000, 0x7DEAD0020))
        r = read(w)
        self.assertEqual([p["gid"] for p in r["pets"]], [0x22])
        self.assertFalse(r["whole"])
        self.assertIn("1 backpack item(s) whose id or behaviours couldn't be read", r["why"])
        ln = petplan.pets_answer(r, "", "Spell-Proof, Mighty")
        self.assertEqual(next(x for x in ln if x.startswith("pets|")).split("|")[:3], ["pets", "1", "0"])
        # (a vector that isn't one - end before begin, or not a whole number of elements: the same)
        for bad in ((0x10000000, 0x0FFFFFF0), (0x10000000, 0x10000008)):
            w, it, _beh = world()
            w.p.write(it + IB, struct.pack("<QQ", *bad))
            self.assertFalse(read(w)["whole"], bad)
        # its global id reads 0
        w, _it, _beh = world(gid=0)
        r = read(w)
        self.assertEqual(([p["gid"] for p in r["pets"]], r["whole"]), ([0x22], False))
        self.assertIn("1 backpack item(s)", r["why"])
        # a list entry that isn't an item (its type unreadable)
        w, it, _beh = world()
        w.types[it] = None
        r = read(w)
        self.assertEqual(([p["gid"] for p in r["pets"]], r["whole"]), ([0x22], False))
        self.assertIn("1 not an item", r["why"])
        # a behaviour whose type can't be read on an item with no pet behaviour seen: it could be the pet's
        w, it, beh = world()
        w.types[beh] = None
        r = read(w)
        self.assertEqual(([p["gid"] for p in r["pets"]], r["whole"]), ([0x22], False))
        # (the same on the worn list: said as worn)
        w = World()
        _it_w, beh_w = w.item(0x22, 9001, "equipped", pet_level=6)
        w.done()
        w.types[beh_w] = None
        r = read(w)
        self.assertFalse(r["whole"])
        self.assertIn("1 worn item(s)", r["why"])
        # ... but a pet behaviour read beside one whose type can't be: the pet is there - nothing missed
        w = World()
        it2, _beh2 = w.item(0x33, 9001, "backpack", pet_level=6)
        w.done()
        vec = struct.unpack("<Q", w.p.try_read(it2 + IB, 8))[0]
        w.types[struct.unpack("<Q", w.p.try_read(vec, 8))[0]] = None   # (the item's other behaviour)
        r = read(w)
        self.assertEqual(([p["gid"] for p in r["pets"]], r["whole"], r["why"]), ([0x33], True, ""))

    def test_an_item_with_no_behaviours_is_read(self):
        # (an empty vector - begin = end, or both 0: read, and not a pet - whole stays True)
        for empty in ("same", "zero"):
            w = World()
            w.item(0x22, 9001, "equipped", pet_level=6)
            it, _ = w.item(0x44, 9002, "backpack")
            w.done()
            a = PROPS["CoreObject"]["m_inactiveBehaviors"]
            v = 0 if empty == "zero" else 0x10000000
            w.p.write(it + a, struct.pack("<QQ", v, v))
            r = M.PetMem(w, Hand(w), props=PROPS, pins={}).read()
            self.assertEqual(([p["gid"] for p in r["pets"]], r["whole"], r["why"]), ([0x22], True, ""), empty)
        # vec16 itself: [] read and empty, None not read
        w = World()
        pm = M.PetMem(w, Hand(w), props=PROPS, pins={})
        a = w.p.alloc(16)
        for begin_end, want in (((0, 0), []), ((0x10000000, 0x10000000), []), ((0x7DEAD0000, 0x7DEAD0010), None),
                                ((0x10000010, 0x10000000), None), ((0, 0x10), None), ((0x10000000, 0x10000004), None)):
            w.p.write(a, struct.pack("<QQ", *begin_end))
            self.assertEqual(pm.vec16(a), want, begin_end)
        self.assertIsNone(pm.vec16(0x7DEAD0000))                        # (the vector itself unreadable)

    def test_level_walk_and_cards(self):
        w = World()
        rd = M.PetMem(w, Hand(w), props=PROPS, pins={})
        PL = PROPS["PetLevelInfo"]
        ents = M.level_entries(rd, w.pet_tpl, PROPS["PetItemBehaviorTemplate"]["m_Levels"], PL["m_level"])
        self.assertEqual([lv for lv, _ in ents], [1, 6, 7])
        self.assertEqual(M.level_cards(rd, ents, 7, PL), [("Pet - Sharpened Blade", 2, "pet level 7")])
        self.assertEqual(M.level_cards(rd, ents, 3, PL), [])
        # (an entry not a PetLevelInfo: None)
        w.types[ents[1][1]] = "Something"
        self.assertIsNone(M.level_entries(rd, w.pet_tpl, PROPS["PetItemBehaviorTemplate"]["m_Levels"], PL["m_level"]))
        self.assertIsNone(M.level_entries(rd, 0, 0x130, 0x48))

    def test_pure_helpers(self):
        self.assertEqual([M.level_name(i) for i in (0, 1, 6, 7, 8, None)], [None, "Baby", "Mega", "Ultra", None, None])
        self.assertEqual(M.parse_pin("xp=BasePetItemBehavior.m_XP:u32"), ("xp", ("BasePetItemBehavior", "m_XP", "u32")))
        self.assertIsNone(M.parse_pin("xp=BasePetItemBehavior:u32"))
        self.assertIsNone(M.parse_pin("nonsense"))
        good, bad = M.check_pins({"xp": ("PetLevelInfo", "m_x", "u32"), "level_xp": ("PetLevelInfo", "m_x", "u32"),
                                  "talents": ("A", "m_t", "vec_u32"), "talent_name": ("PetTalentTemplate", "m_n", "str"),
                                  "derby": "junk", "stats": ("BasePetItemBehavior", "x", "u32")})
        self.assertEqual(sorted(good), ["level_xp", "talent_name"])
        self.assertEqual(len(bad), 4)
        self.assertEqual(M.PINS, {})                                    # (nothing pinned before the game's seen)

    def test_command_line_bad_pin(self):
        err = io.StringIO()
        with redirect_stdout(io.StringIO()), self.assertRaises(SystemExit):
            from contextlib import redirect_stderr
            with redirect_stderr(err):
                M._main(["--pin", "xp=PetLevelInfo.m_x:u32"])
        self.assertIn("--pin", err.getvalue())


# ============================================================================ deckmem, navmem, /pets
def import_navmem():
    """the real navmem, its Windows DLLs stood in for (test_navroute.py's way - another test file's stand-in put back)"""
    from test_navroute import import_navmem as imp
    return imp()


def import_deckmem():
    """deckmem imported against the real navmem (its DLLs stood in for); sys.modules' navmem and deckmem put back as they
    were"""
    nav = import_navmem()
    saved = {k: sys.modules.get(k) for k in ("navmem", "deckmem")}
    try:
        sys.modules["navmem"] = nav
        sys.modules.pop("deckmem", None)
        import deckmem
        return deckmem
    finally:
        for k, v in saved.items():
            if v is None:
                sys.modules.pop(k, None)
            else:
                sys.modules[k] = v


class DeckPets(unittest.TestCase):
    """deckmem: a pet's cards through petmem's walk; a pet that can't be read loses only its own cards"""

    @classmethod
    def setUpClass(cls):
        cls.D = import_deckmem()

    def deckmem(self, w, props):
        return self.D.DeckMem(w, Hand(w), props=props)

    def gear(self, w, tid, spell, n):
        """an item template (ItemTemplate.m_equipEffects: one ProvideSpellEffectInfo) - gear giving spell n times"""
        t = w.item_tpl(tid, "Wand-%d" % tid, None)
        e = w.obj("ProvideSpellEffectInfo", 0x100)
        w.p.put_string(e + 0x68, spell)
        w.p.write(e + 0x88, struct.pack("<i", n))
        w.slist(t + 0x128, [e])
        return t

    def test_pet_cards_and_item_cards(self):
        w = World()
        wand = self.gear(w, 9100, "Wand-Balance-T4-001", 2)
        it_pet, _beh = w.item(0x22, 9001, "equipped", pet_level=7)
        it_wand, _ = w.item(0x23, 9100, "equipped")
        w.done()
        dm = self.deckmem(w, PROPS)
        self.assertEqual(dm.pet_cards(it_pet), [("Pet - Sharpened Blade", 2, "pet level 7")])
        self.assertEqual(dm.pet_cards(it_wand), [])
        pet_tpl = w.item_tpl(9003, "PET_X", None)
        w.slist(pet_tpl + 0x128, [])
        self.assertEqual(dm.item_cards_of(it_pet, pet_tpl), [("Pet - Sharpened Blade", 2, "pet level 7")])
        self.assertEqual(dm.item_cards_of(it_wand, wand), [("Wand-Balance-T4-001", 2, "equip effect")])

    def test_unreadable_pet_keeps_the_gear(self):
        w = World()
        self.gear(w, 9100, "Wand-Balance-T4-001", 2)
        pet_tpl = w.item_tpl(9003, "PET_X", None)
        w.slist(pet_tpl + 0x128, [])
        w.item(0x22, 9003, "equipped", pet_level=7)
        w.item(0x23, 9100, "equipped")
        w.done()
        props = {k: dict(v) for k, v in PROPS.items()}
        del props["PetLevelInfo"]                                       # (the pet's classes not in this build)
        dm = self.deckmem(w, props)
        dm.tid_by_name = lambda name: {"Wand-Balance-T4-001": 7001}.get(name)
        dm.brief = lambda tid: {"display": "Minor Crusade"}
        objs = {0x22: (w.worn[0], "equipped", 9003), 0x23: (w.worn[1], "equipped", 9100)}
        cards, n = dm._item_cards([0x22, 0x23], objs, [])
        self.assertEqual(n, 2)                                          # (before v0.9.0: None, None)
        self.assertEqual([(c["name"], c["count"]) for c in cards], [("Wand-Balance-T4-001", 2)])
        self.assertEqual(dm.pet_unread, [w.worn[0]])
        # (readable: the pet's too, and pet_unread empty again)
        dm2 = self.deckmem(w, PROPS)
        dm2.tid_by_name = lambda name: {"Wand-Balance-T4-001": 7001, "Pet - Sharpened Blade": 7002}.get(name)
        dm2.brief = lambda tid: {"display": None}
        cards, n = dm2._item_cards([0x22, 0x23], objs, [])
        self.assertEqual(n, 4)
        self.assertEqual(dm2.pet_unread, [])


class NavmemPets(unittest.TestCase):
    """navmem: the pets reader made once per game in a thread, read under the lock, paced; never raises"""

    @classmethod
    def setUpClass(cls):
        cls.N = import_navmem()

    def test_reader_made_once_and_failure_kept(self):
        N = self.N
        nm = N.NavMem(log=lambda m: None)
        st = types.SimpleNamespace()
        made = []

        def make(s):
            made.append(s)
            with nm.lock:
                nm._petm = types.SimpleNamespace(st=s)
        nm._pet_make = make
        pm, why = nm._pet_reader(st, wait=1.0)
        self.assertIs(pm.st, st)
        self.assertIs(nm._pet_reader(st)[0], pm)
        self.assertEqual(len(made), 1)
        # (a build it can't read: kept, said why, not made again till RETRY_SIG)
        nm2 = N.NavMem(log=lambda m: None)
        nm2._hand_reader = lambda s, wait: (None, "no hand")
        nm2._pet_make(st)
        pm2, why2 = nm2._pet_reader(st)
        self.assertIsNone(pm2)
        self.assertIn("no hand", why2)

    def test_pets_read_paced_under_the_lock(self):
        N = self.N
        nm = N.NavMem(log=lambda m: None)
        st, hm = types.SimpleNamespace(alive=lambda: True), object()
        nm.st, nm._hand = st, hm
        nm.PET_HOLD = 0.0                                               # (let go at every pace)
        seen = []

        class PM:
            def __init__(self):
                self.st, self.hm = st, hm

            def read(self, pace=None):
                seen.append(nm.lock.locked())
                pace()
                seen.append(nm.lock.locked())
                return {"pets": [{"gid": 1}], "whole": True}
        nm._ensure = lambda wait: (st, "")
        nm._pet_reader = lambda s, wait=0.0: (PM(), "")
        r, why = nm.pets()
        self.assertEqual((r["pets"], why), ([{"gid": 1}], ""))
        self.assertEqual(seen, [True, True])
        self.assertFalse(nm.lock.locked())
        # (the hand's reader remade since: not read)
        nm._hand = object()
        self.assertEqual(nm.pets(), (None, "the game changed"))
        # (no game; a reader that raises: why, never out)
        nm._ensure = lambda wait: (None, "the game is not running")
        self.assertEqual(nm.pets(), (None, "the game is not running"))
        nm._ensure = lambda wait: (st, "")
        nm._pet_reader = lambda s, wait=0.0: (_ for _ in ()).throw(ValueError("x"))
        r, why = nm.pets()
        self.assertIsNone(r)
        self.assertIn("reading the pets failed", why)
        self.assertFalse(nm.lock.locked())


class Route(unittest.TestCase):
    """the vision helper's /pets on a local server: the pets' lines, then want| and keep|"""

    def test_pets_route(self):
        import urllib.request
        from http.server import ThreadingHTTPServer
        import vision as V
        r = {"pets": [{"gid": 0x22, "where": "equipped", "level": 6, "level_name": "Mega", "talents": None},
                      {"gid": 0x33, "where": "backpack", "level": 1, "level_name": "Baby", "talents": None}],
             "whole": True, "why": "", "ms": 1.0}
        nav = types.SimpleNamespace(pets=lambda wait=0.3: (r, ""))
        keep = (V.nav_reader, V.LOG)
        with tempfile.TemporaryDirectory() as d:
            V.nav_reader, V.LOG = (lambda: nav), os.path.join(d, "vision.log")
            srv = ThreadingHTTPServer(("127.0.0.1", 0), V.Handler)
            th = threading.Thread(target=srv.serve_forever, daemon=True)
            th.start()
            try:
                def get(path):
                    with urllib.request.urlopen("http://127.0.0.1:%d%s" % (srv.server_address[1], path), timeout=5) as rr:
                        return rr.status, rr.read().decode()
                code, text = get("/pets?want=Spell-Proof,Mighty")
                self.assertEqual(code, 200)
                lines = text.split("\n")
                self.assertEqual([ln.split("|")[0] for ln in lines], ["pet", "pet", "energy", "pets", "want", "keep", "keep"])
                self.assertEqual(lines[4], "want|2|Spell-Proof, Mighty|0")
                self.assertEqual(lines[6], "keep|33|backpack|talents not read - kept to be safe")
                code, text = get("/pets")
                self.assertEqual(text.split("\n")[-1], "want|0||0")     # (nothing wanted: no keep| line)
                nav.pets = lambda wait=0.3: (None, "the game is not running")
                self.assertEqual(get("/pets?want=Mighty"), (200, "none|the game is not running"))
            finally:
                srv.shutdown()
                srv.server_close()
                V.nav_reader, V.LOG = keep


if __name__ == "__main__":
    unittest.main()
