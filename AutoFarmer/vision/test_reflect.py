"""test_reflect.py - the reflected-class dumper's checks (reflect.py): its pure parts on made-up bytes, then report() and
the command line on a made-up game image - x64 code with a GetType and a property registration the way the game's are,
read by the real handmem.Image and questmem.class_props (navmem stood in for: its ctypes.WinDLL can't load here):
    python -m unittest test_reflect   (from AutoFarmer\\vision)"""
import io
import os
import struct
import sys
import tempfile
import types
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reflect as R  # noqa: E402   (its pure parts need no navmem)


def _stub_navmem():
    """a stand-in navmem module (what bagmem / handmem / questmem use of it at import and in the parts tested) - the
    real one when it's already imported (Windows)"""
    m = sys.modules.get("navmem")
    if m is None:
        m = sys.modules["navmem"] = types.ModuleType("navmem")
    need = {"ptr_ok": lambda v: 0x10000 <= v < 0x7FFFFFFF0000, "ReadError": type("ReadError", (Exception,), {}),
            "DATA": {"window_name": 0x50}, "KNOWN": {}, "SIGS": {}, "NavMem": None, "find_pids": lambda *a: [],
            "foreground_pid": lambda: 0}
    for k, v in need.items():
        if not hasattr(m, k):
            setattr(m, k, v)
    return m


# ============================================================================ a made-up game image
BASE = 0x140000000
SECS = {".text": (0x1000, 0x4000, 0x60000020), ".rdata": (0x10000, 0x2000, 0x40000040),
        ".data": (0x20000, 0x1000, 0xC0000040)}
T0, R0, D0 = (BASE + SECS[n][0] for n in (".text", ".rdata", ".data"))
ADDER = {"int": 0x3000, "u32": 0x3100, "string": 0x3200}       # AddProperty<T> functions (where in .text)


class Image:
    """the bytes of a made-up exe: .text all int3 but for the functions put in, .rdata the strings and vtables"""

    def __init__(self):
        self.text = bytearray(b"\xCC" * SECS[".text"][1])
        self.rdata = bytearray(SECS[".rdata"][1])
        self.data = bytearray(SECS[".data"][1])
        self.rpos, self.strs, self.vt = 0x10, {}, 0x1800

    def string(self, s):
        """s in .rdata (a NUL before it): its address"""
        if s not in self.strs:
            self.rpos += 1
            b = s.encode() + b"\0"
            self.rdata[self.rpos:self.rpos + len(b)] = b
            self.strs[s] = R0 + self.rpos
            self.rpos += len(b)
        return self.strs[s]

    def put(self, at, code):
        assert b"\xCC\xCC" not in code, code.hex()           # (no padding look-alike inside a function)
        self.text[at:at + len(code)] = code

    @staticmethod
    def rip(at, op, target, n=7):
        """an instruction at .text+at whose last 4 bytes are a RIP-relative displacement to target"""
        return op + struct.pack("<i", target - (T0 + at + n))

    def klass(self, name, gt_at, reg_at, props):
        """class name: its GetType at .text+gt_at (lea rcx, "name"; mov [rip+static], rax; ret), a vtable whose slot 0 is
        it, and its registration at .text+reg_at - for each (property, offset, adder): lea r8, [rcx+offset]; lea rdx,
        "property"; call adder - then ret"""
        code = self.rip(gt_at, b"\x48\x8D\x0D", self.string(name))
        code += self.rip(gt_at + 7, b"\x48\x89\x05", D0 + 0x100 + gt_at // 8)
        self.put(gt_at, code + b"\xC3")
        struct.pack_into("<Q", self.rdata, self.vt, T0 + gt_at)
        self.vt += 0x20
        pos, code = reg_at, b""
        for prop, off, adder in props:
            c = bytes([0x4C, 0x8D, 0x41, off]) if off < 0x80 else b"\x4C\x8D\x81" + struct.pack("<i", off)
            c += self.rip(pos + len(c), b"\x48\x8D\x15", self.string(prop))
            c += self.rip(pos + len(c), b"\xE8", T0 + ADDER[adder], 5)
            code += c
            pos += len(c)
        self.put(reg_at, code + b"\xC3")

    def st(self):
        """the game as handmem.Image reads it: st.p.try_read, st.m (base, sections, in_section, build)"""
        bufs = {".text": self.text, ".rdata": self.rdata, ".data": self.data}

        def try_read(a, n):
            for nm, (va, vs, _c) in SECS.items():
                if BASE + va <= a and a + n <= BASE + va + vs:
                    return bytes(bufs[nm][a - BASE - va:a - BASE - va + n])
            return None

        def in_section(a, nm):
            s = SECS.get(nm)
            return bool(s) and BASE + s[0] <= a < BASE + s[0] + s[1]
        return types.SimpleNamespace(p=types.SimpleNamespace(try_read=try_read, pid=4242, close=lambda: None),
                                     m=types.SimpleNamespace(base=BASE, sections=SECS, in_section=in_section,
                                                             build="TEST-1"),
                                     close=lambda: None)


def game():
    """WizThing (m_alpha int +0x58, m_trainingPoints u32 +0x100), OtherThing (m_beta string +0x10, m_trainingPoints u32
    +0x60), SpellEffect (m_numRounds int +0x48 - an anchor: int) and a name that isn't a class (TrainingTemplate)"""
    im = Image()
    im.klass("WizThing", 0x100, 0x180, [("m_alpha", 0x58, "int"), ("m_trainingPoints", 0x100, "u32")])
    im.klass("OtherThing", 0x400, 0x480, [("m_beta", 0x10, "string"), ("m_trainingPoints", 0x60, "u32")])
    im.klass("SpellEffect", 0x700, 0x780, [("m_numRounds", 0x48, "int")])
    im.string("TrainingTemplate")
    return im


# ============================================================================ the pure parts
class Pure(unittest.TestCase):
    BUF = (b"junk\0m_trainingPoints\0WizGameStats\0m_trainingPoints\0hello world!\0Training Points\0kTrainer\0"
           b"GoalTemplate::GOAL_TYPE_TRAIN\0\x01\x02train\0")

    def test_grep_names(self):
        got = R.grep_names(self.BUF, "train", base=0x1000)
        self.assertEqual([(n, c) for _a, n, c in got], [("m_trainingPoints", 2), ("Training Points", 1),
                                                         ("kTrainer", 1), ("GoalTemplate::GOAL_TYPE_TRAIN", 1)])
        self.assertEqual(got[0][0], 0x1000 + self.BUF.index(b"m_training"))          # (its first copy)
        self.assertEqual([n for _a, n, _c in R.grep_names(self.BUF, "train", case=True)], ["m_trainingPoints"])
        self.assertEqual([n for _a, n, _c in R.grep_names(self.BUF, "^junk$")], ["junk"])  # (at the very start)
        self.assertEqual(R.grep_names(self.BUF, "hello"), [])                        # ("!": not a name)
        self.assertEqual(R.grep_names(b"", "x"), [])

    def test_name_kind(self):
        self.assertEqual([R.name_kind(s) for s in ("m_level", "kDamage", "GoalTemplate::GOAL_TYPE_X", "WizGameStats",
                                                   "Training Points", "SharedPointer<Window>")],
                         ["prop", "enum", "enum", "name", "other", "other"])

    def test_name_at(self):
        buf = b"\0WizThing\0m_alpha\0bad!name\0"
        self.assertEqual(R.name_at(buf, 0x500, 0x501), "WizThing")
        self.assertIsNone(R.name_at(buf, 0x500, 0x503))         # (inside a string: not its start)
        self.assertIsNone(R.name_at(buf, 0x500, 0x500 + buf.index(b"m_alpha")))       # (a property's name)
        self.assertIsNone(R.name_at(buf, 0x500, 0x500 + buf.index(b"bad!")))
        self.assertIsNone(R.name_at(buf, 0x500, 0x400))         # (outside it)

    def test_owner_candidates(self):
        t0 = 0x1000
        text = bytearray(b"\xCC" * 0x400)
        # functions at 0x10 (loads 100 at +0, 300 at +0x220 - past lim), 0x300 (loads 200 at +4), then la's at 0x380
        text[0x10:0x18] = b"\x90" * 8
        text[0x2F0:0x2F2] = b"\xC3\xCC"                         # (a ret and one int3: a function boundary too)
        text[0x2F2:0x300] = b"\x90" * 14
        text[0x300:0x310] = b"\x90" * 16
        text[0x380:0x390] = b"\x90" * 16
        lea_at = [t0 + 0x10, t0 + 0x10 + 0x220, t0 + 0x304, t0 + 0x384]
        lea_tgt = [100, 300, 200, 400]
        names = {100: "WizThing", 200: "Other", 300: "Far", 400: "Mine"}
        got = R.owner_candidates(text, t0, t0 + 0x388, lea_at, lea_tgt, names.get)
        self.assertEqual(got, ["Other", "WizThing"])           # (nearest first; 300 too far in; 400 la's own function)
        self.assertEqual(R.owner_candidates(text, t0, t0 + 0x388, lea_at, lea_tgt, names.get, back=1), ["Other"])
        self.assertEqual(R.owner_candidates(text, t0, t0 + 0x388, lea_at, lea_tgt, names.get, span=0xA0), ["Other"])
        # (a function starting before span isn't looked at)
        self.assertEqual(R.owner_candidates(text, t0, t0 + 0x388, lea_at, lea_tgt, names.get, span=0x90), [])
        self.assertEqual(R.owner_candidates(b"\x90" * 64, t0, t0 + 0x20, lea_at, lea_tgt, names.get), [])

    def test_guess_types(self):
        props = {"A": {"m_x": (0x10, 0x500), "m_s": (0x18, 0x600)}, "B": {"m_y": (0x8, 0x500)}, "C": {}}
        anchors = (("A", "m_x", "int"), ("B", "m_y", "int"), ("A", "m_s", "std::string"), ("C", "m_z", "float"),
                   ("B", "m_y", "unsigned int"))
        self.assertEqual(R.guess_types(props, anchors), {0x500: "int / unsigned int", 0x600: "std::string"})
        self.assertEqual(R.guess_types({}, anchors), {})

    def test_class_lines(self):
        props = {"m_b": (0x60, 0x3100), "m_a": (0x58, 0x3000), "m_c": (0x60, None)}
        ln = R.class_lines("WizThing", props, BASE + 0x1100, [BASE + 0x11800], BASE, {0x3000: "int"})
        self.assertEqual(ln, ["class|WizThing|3|0x1100|1|0x11800",
                              "prop|WizThing|0x58|m_a|int|0x8|0x3000",
                              "prop|WizThing|0x60|m_b|?||0x3100",
                              "prop|WizThing|0x60|m_c|?||"])
        ln = R.class_lines("Nope", {}, None)
        self.assertEqual(ln[0], "class|Nope|0|||")
        self.assertTrue(ln[1].startswith("none|Nope: not a reflected class"))
        self.assertTrue(R.class_lines("Empty", {}, BASE + 0x10, [], BASE)[1].startswith("none|Empty: a class, but"))

    def test_name_lines(self):
        self.assertEqual(R.name_lines([(BASE + 0x10010, "m_x|y", 2, "prop", "A+0x10 B+0x8")], 5, BASE),
                         ["grep|5|1", "name|m_x y|prop|0x10010|2|A+0x10 B+0x8"])


# ============================================================================ on the made-up game
class OnImage(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        _stub_navmem()
        import handmem as H
        cls.H = H
        cls.im = game()
        cls.img = H.Image(cls.im.st())

    def test_class_props_reads_it(self):
        # (the fixture is what the game's code looks like to class_props - else the rest proves nothing)
        import questmem as Q
        p, gt, vts = Q.class_props(self.img, "WizThing")
        self.assertEqual({k: v[0] for k, v in p.items()}, {"m_alpha": 0x58, "m_trainingPoints": 0x100})
        self.assertEqual(p["m_alpha"][1], 0x1000 + ADDER["int"])
        self.assertEqual(gt, T0 + 0x100)
        self.assertEqual(len(vts), 1)

    def test_report_classes(self):
        ln = R.report(self.img, BASE, ["WizThing", "Missing", "OtherThing"])
        self.assertEqual(ln[:3], ["class|WizThing|2|0x1100|1|0x11800",
                                  "prop|WizThing|0x58|m_alpha|int|0xa8|0x4000",       # (SpellEffect.m_numRounds' adder)
                                  "prop|WizThing|0x100|m_trainingPoints|?||0x4100"])
        self.assertEqual(ln[3], "class|Missing|0|||")
        self.assertTrue(ln[4].startswith("none|Missing:"))
        self.assertEqual(ln[5:8], ["class|OtherThing|2|0x1400|1|0x11820",
                                   "prop|OtherThing|0x10|m_beta|?|0x50|0x4200",
                                   "prop|OtherThing|0x60|m_trainingPoints|?||0x4100"])

    def test_report_grep(self):
        ln = R.report(self.img, BASE, [], "train|thing")
        self.assertEqual(ln[0], "grep|4|4")
        rows = {x.split("|")[1]: x.split("|")[2:] for x in ln[1:]}
        self.assertEqual(rows["WizThing"][0::3], ["class", "2 properties"])
        self.assertEqual(rows["OtherThing"][0::3], ["class", "2 properties"])
        self.assertEqual(rows["m_trainingPoints"][0], "prop")
        self.assertEqual(rows["m_trainingPoints"][3], "WizThing+0x100 OtherThing+0x60")   # (both that register it)
        self.assertEqual(rows["TrainingTemplate"][0::3], ["name", ""])                      # (no GetType: not a class)
        self.assertEqual(int(rows["WizThing"][1], 16), self.im.strs["WizThing"] - BASE)
        # (--props: the classes found dumped after; --limit)
        ln = R.report(self.img, BASE, ["WizThing"], "thing", props=True)
        self.assertEqual([x for x in ln if x.startswith("class|")], ["class|WizThing|2|0x1100|1|0x11800",
                                                                      "class|OtherThing|2|0x1400|1|0x11820"])
        ln = R.report(self.img, BASE, [], "train|thing", limit=1)
        self.assertEqual(ln[0], "grep|4|1")

    def test_attach(self):
        N = sys.modules["navmem"]
        keep = {k: getattr(N, k, None) for k in ("find_pids", "foreground_pid", "_Attached")}
        keep_la = self.H.LightAttach
        try:
            N.find_pids = lambda *a: []
            self.assertEqual(R.attach(), (None, "the game is not running"))
            N.find_pids, N.foreground_pid = (lambda *a: [7, 9]), (lambda: 9)
            N._Attached = lambda pid, log: ("attached", pid)
            self.assertEqual(R.attach(), (("attached", 9), ""))
            self.assertEqual(R.attach(7), (("attached", 7), ""))
            self.assertIn("no game client with pid 5", R.attach(5)[1])

            def no_sig(pid, log):
                raise LookupError("the GameClient signature isn't in this game build")
            N._Attached = no_sig
            self.H.LightAttach = lambda pid, log=None: ("light", pid)
            said = []
            self.assertEqual(R.attach(log=said.append), (("light", 9), ""))
            self.assertIn("without the walker's signatures", said[0])
        finally:
            for k, v in keep.items():
                setattr(N, k, v)
            self.H.LightAttach = keep_la

    def test_command_line(self):
        keep_attach, keep_argv = R.attach, sys.argv
        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "reflect.txt")
            try:
                R.attach = lambda pid=None, log=None: (self.im.st(), "")
                sys.argv = ["reflect.py", "--class", "WizThing,OtherThing", "--grep", "training", "--out", out]
                buf = io.StringIO()
                with redirect_stdout(buf):
                    R._main()
            finally:
                R.attach, sys.argv = keep_attach, keep_argv
            with open(out, encoding="utf-8") as f:
                lines = f.read().splitlines()
        self.assertTrue(lines[0].startswith("# python reflect.py --class WizThing,OtherThing --grep training --out "))
        self.assertTrue(lines[0].endswith("- build TEST-1, pid 4242"))
        self.assertEqual(lines[1], "class|WizThing|2|0x1100|1|0x11800")
        self.assertIn("grep|2|2", lines)
        self.assertIn("written to", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
