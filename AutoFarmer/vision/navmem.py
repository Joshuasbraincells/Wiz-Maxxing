"""navmem - READ-ONLY reader of the wizard's position and the quest goal in a running Wizard101 client
(WizardGraphicalClient.exe), for the vision helper's /nav and /navmap.

    nm = NavMem(log=print)
    r, why = nm.read(path=True)     # r: a dict (see NavMem.read), or None and why it can't be read

    python navmem.py [-n 5] [-i 1] [--path]     readings from the command line (and how long each took)

SAFETY. The game is opened with PROCESS_VM_READ | PROCESS_QUERY_INFORMATION (falling back to
PROCESS_VM_READ | PROCESS_QUERY_LIMITED_INFORMATION) and nothing else. The only process APIs used are
CreateToolhelp32Snapshot / Process32*W (finding the pid), OpenProcess, ReadProcessMemory,
EnumProcessModulesEx, GetModuleBaseNameW, QueryFullProcessImageNameW and GetExitCodeProcess. Nothing is
ever written, allocated, injected, hooked, suspended or debugged; no window is touched and no input is
sent. Signatures are looked for in a copy of the game's code read with ReadProcessMemory.

FAILS SOFT. Nothing here raises into the caller: every read gives (None, why) when it can't be done, and a
value that can't be read for sure is None (never a guess). Values the game's threads write are read twice
and kept only when two reads in a row agree.

WHAT IS READ (offsets of the client of 2026-10-13; when the helper attaches to a game, each is found again
by a signature in its code, or checked by a type name / window name it carries):

  player:  [exe + rva] GameClient*                          sig ZONE (also gives the zone offsets),
                                                             else sig GAMECLIENT
             +0x21368  ClientZone* -> +0x58 std::string     the zone, e.g. WizardCity/WC_Ravenwood
             +0x222C8  ElasticCamController*                checked by its type name, else found by it
               +0x108  the ClientObject the camera follows  = the wizard (type name ...ClientObject)
                 +0x1B8 AnimationBehavior* -> +0x70 ActorBody*   sig GETLOCATION
                   ActorBody +0x48 parent ClientObject (must be the wizard), +0x58 x, y, z (floats),
                   +0x64 pitch, +0x68 roll, +0x6C yaw (radians)
                 ClientObject +0xA8 x, y, z, +0xB4 pitch, roll, yaw: its own copy, used while it has
                   no body (zoning)
           Z is up; yaw is measured from -Y: forward = (-sin yaw, -cos yaw).

  quest:   [exe + rva] WizardGUIManager*                    sig GUIMGR_HUD (candidates, voted), each
             +0x2D0  HUDWindow*                             checked by its window name "windowHUD"
               +0x6A8  QuestHelperHud*                      sig HUD_QHH, window name "QuestHelperHud"
                 +0x300 arrow target x, y, z (the node the on-screen arrow points at)  \
                 +0x334 arrow distance (along the path), +0x338 hops                    / sig HUD_FIELDS
                 +0x2C8 QuestHelperThread*                  sig QHH_THREAD, thread name "QuestHelper"
                   +0xC68 enabled (byte)                    sig ENABLED
                   +0xC88 quest id, +0xC90 goal id (GIDs)   sigs ACTIVE_QUEST, ACTIVE_GOAL
                   +0xCC0 std::string the thread's zone     sig ZONEINFO
                   +0xCFC goal x, y, z                      sig GOAL
                   +0xD08 hops (int): 0 = the goal is in this zone; N = N zone changes away, and
                          +0xCFC is the teleporter to take in this zone        sig HOPS
                   +0xD10 Path*: +0 std::list head, +8 count; list node +0x10 NavNode*,
                          NavNode +0x30 x, y, z (a zone.nav node)              sig PATH
           The quest thread (it updates every 100 ms) keeps its own zone name: after a zone change its goal
           belongs to the old zone until it catches up, so goal, target, distance and path count only while
           the thread's zone is the game's zone (and target / distance only while the arrow's hops are the
           thread's). The HUD and the thread are rebuilt on a character switch, so the chain is walked
           again on every read.
"""
import ctypes as C
import ctypes.wintypes as W
import math
import re
import struct
import threading
import time
from collections import Counter

EXE = "WizardGraphicalClient.exe"

# ============================================================================ read-only process access
PROCESS_VM_READ = 0x0010
PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
STILL_ACTIVE = 259
TH32CS_SNAPPROCESS = 0x2
LIST_MODULES_ALL = 0x3

k32 = C.WinDLL("kernel32", use_last_error=True)
psapi = C.WinDLL("psapi", use_last_error=True)
u32 = C.WinDLL("user32", use_last_error=True)


class PROCESSENTRY32W(C.Structure):
    _fields_ = [("dwSize", W.DWORD), ("cntUsage", W.DWORD), ("th32ProcessID", W.DWORD),
                ("th32DefaultHeapID", C.c_size_t), ("th32ModuleID", W.DWORD),
                ("cntThreads", W.DWORD), ("th32ParentProcessID", W.DWORD),
                ("pcPriClassBase", C.c_long), ("dwFlags", W.DWORD), ("szExeFile", W.WCHAR * 260)]


k32.CreateToolhelp32Snapshot.restype = W.HANDLE
k32.CreateToolhelp32Snapshot.argtypes = [W.DWORD, W.DWORD]
k32.Process32FirstW.argtypes = [W.HANDLE, C.POINTER(PROCESSENTRY32W)]
k32.Process32NextW.argtypes = [W.HANDLE, C.POINTER(PROCESSENTRY32W)]
k32.OpenProcess.restype = W.HANDLE
k32.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]
k32.CloseHandle.argtypes = [W.HANDLE]
k32.ReadProcessMemory.argtypes = [W.HANDLE, C.c_void_p, C.c_void_p, C.c_size_t, C.POINTER(C.c_size_t)]
k32.ReadProcessMemory.restype = W.BOOL
k32.GetExitCodeProcess.argtypes = [W.HANDLE, C.POINTER(W.DWORD)]
k32.GetExitCodeProcess.restype = W.BOOL
k32.QueryFullProcessImageNameW.argtypes = [W.HANDLE, W.DWORD, W.LPWSTR, C.POINTER(W.DWORD)]
k32.QueryFullProcessImageNameW.restype = W.BOOL
psapi.EnumProcessModulesEx.argtypes = [W.HANDLE, C.POINTER(W.HMODULE), W.DWORD, C.POINTER(W.DWORD), W.DWORD]
psapi.GetModuleBaseNameW.argtypes = [W.HANDLE, W.HMODULE, W.LPWSTR, W.DWORD]
u32.GetForegroundWindow.restype = W.HWND
u32.GetWindowThreadProcessId.argtypes = [W.HWND, C.POINTER(W.DWORD)]


def find_pids(exe=EXE):
    """the pids of the running game clients (a process snapshot: no process is opened)"""
    snap = k32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if not snap or snap == W.HANDLE(-1).value:
        return []
    pe = PROCESSENTRY32W()
    pe.dwSize = C.sizeof(pe)
    out = []
    try:
        ok = k32.Process32FirstW(snap, C.byref(pe))
        while ok:
            if pe.szExeFile.lower() == exe.lower():
                out.append(pe.th32ProcessID)
            ok = k32.Process32NextW(snap, C.byref(pe))
    finally:
        k32.CloseHandle(snap)
    return out


def foreground_pid():
    """the pid owning the foreground window (only asked, nothing is done to the window)"""
    try:
        pid = W.DWORD()
        hwnd = u32.GetForegroundWindow()
        if hwnd:
            u32.GetWindowThreadProcessId(hwnd, C.byref(pid))
        return pid.value
    except Exception:  # noqa: BLE001
        return 0


class ReadError(Exception):
    pass


def ptr_ok(v):
    """a user-mode address (heap objects, and the exe's own sections at 0x7FF6...)"""
    return 0x10000 <= v < 0x7FFFFFFF0000


class Proc:
    """a read-only handle on one game process"""

    def __init__(self, pid):
        self.pid = pid
        self.access = PROCESS_VM_READ | PROCESS_QUERY_INFORMATION
        h = k32.OpenProcess(self.access, False, pid)
        if not h:
            self.access = PROCESS_VM_READ | PROCESS_QUERY_LIMITED_INFORMATION
            h = k32.OpenProcess(self.access, False, pid)
        if not h:
            raise OSError(C.get_last_error(), "OpenProcess failed")
        self.h = h

    def close(self):
        if self.h:
            k32.CloseHandle(self.h)
            self.h = None

    def alive(self):
        code = W.DWORD()
        return bool(self.h) and bool(k32.GetExitCodeProcess(self.h, C.byref(code))) and code.value == STILL_ACTIVE

    def image_path(self):
        buf, n = C.create_unicode_buffer(1024), W.DWORD(1024)
        return buf.value if k32.QueryFullProcessImageNameW(self.h, 0, buf, C.byref(n)) else ""

    def exe_base(self):
        mods, need = (W.HMODULE * 1)(), W.DWORD()
        if not psapi.EnumProcessModulesEx(self.h, mods, C.sizeof(mods), C.byref(need), LIST_MODULES_ALL) or not mods[0]:
            raise OSError(C.get_last_error(), "EnumProcessModulesEx failed")
        name = C.create_unicode_buffer(260)
        psapi.GetModuleBaseNameW(self.h, mods[0], name, 260)
        if name.value.lower() != EXE.lower():
            raise OSError(0, "first module is %r, not %s" % (name.value, EXE))
        return mods[0]

    def read(self, addr, n):
        buf, got = C.create_string_buffer(n), C.c_size_t()
        if not ptr_ok(addr) or not k32.ReadProcessMemory(self.h, C.c_void_p(addr), buf, n, C.byref(got)) or got.value != n:
            raise ReadError("read %d @ %#x failed" % (n, addr))
        return buf.raw[:n]

    def try_read(self, addr, n):
        try:
            return self.read(addr, n)
        except ReadError:
            return None

    def u64(self, a):
        return struct.unpack("<Q", self.read(a, 8))[0]

    def stable(self, addr, n, tries=6):
        """n bytes at addr, read until two reads in a row agree (a game thread may be writing them)"""
        prev = self.read(addr, n)
        for _ in range(tries):
            cur = self.read(addr, n)
            if cur == prev:
                return cur
            prev = cur
        raise ReadError("%d bytes @ %#x keep changing" % (n, addr))

    def string(self, a, stable=False):
        """an MSVC x64 std::string (16-byte inline buffer or a pointer, size @+0x10, capacity @+0x18) of
        printable ASCII, or None"""
        raw = self.stable(a, 0x20) if stable else self.read(a, 0x20)
        size, cap = struct.unpack_from("<QQ", raw, 0x10)
        if size > 0x1000 or cap < size or cap > 0x100000:
            return None
        if cap < 16:
            data = raw[:size]
        else:
            p = struct.unpack_from("<Q", raw)[0]
            data = (self.stable(p, size) if stable else self.read(p, size)) if size else b""
        s = data.decode("latin-1")
        return s if all(32 <= ord(ch) < 127 for ch in s) else None

    def try_string(self, a, stable=False):
        try:
            return self.string(a, stable)
        except ReadError:
            return None


class Module:
    """the game's exe image: its sections from the in-memory PE header"""

    def __init__(self, proc):
        self.p = proc
        self.base = proc.exe_base()
        hdr = proc.read(self.base, 0x1000)
        pe = struct.unpack_from("<I", hdr, 0x3C)[0]
        if hdr[:2] != b"MZ" or hdr[pe:pe + 4] != b"PE\0\0":
            raise OSError(0, "not a PE image")
        self.timestamp = struct.unpack_from("<I", hdr, pe + 8)[0]
        nsec = struct.unpack_from("<H", hdr, pe + 6)[0]
        optsz = struct.unpack_from("<H", hdr, pe + 20)[0]
        self.image_size = struct.unpack_from("<I", hdr, pe + 24 + 56)[0]
        self.sections = {}
        so = pe + 24 + optsz
        for _ in range(nsec):
            name = hdr[so:so + 8].rstrip(b"\0").decode("latin-1")
            vsize, va = struct.unpack_from("<II", hdr, so + 8)
            self.sections[name] = (va, vsize, struct.unpack_from("<I", hdr, so + 36)[0])
            so += 40

    @property
    def build(self):
        return "%08X-%X" % (self.timestamp, self.image_size)

    def in_section(self, addr, name):
        s = self.sections.get(name)
        return bool(s) and self.base + s[0] <= addr < self.base + s[0] + s[1]

    def code(self):
        """[(rva, bytes)] of the executable sections (unreadable pages as zeros)"""
        out = []
        for name, (va, vsize, chars) in self.sections.items():
            if chars & 0x20000000:
                parts = []
                for off in range(0, vsize, 0x100000):
                    n = min(0x100000, vsize - off)
                    parts.append(self.p.try_read(self.base + va + off, n) or b"\0" * n)
                out.append((va, b"".join(parts)))
        return out


LEA_RIP = re.compile(rb"[\x48\x4C]\x8D([\x05\x0D\x15\x1D\x25\x2D\x35\x3D])(....)", re.DOTALL)
TYPE_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_:<>, ]+")


class TypeNamer:
    """KingsIsle's reflected type names: vtable[0] of every PropertyClass is GetType(), whose body loads
    the class name with a RIP-relative LEA - the first one in its first 128 bytes that points at an
    identifier-like C string in .rdata (cached per vtable)"""

    def __init__(self, mod):
        self.m, self.p, self.cache = mod, mod.p, {}

    def of_vtable(self, vt):
        if vt in self.cache:
            return self.cache[vt]
        name = None
        if self.m.in_section(vt, ".rdata"):
            f = self.p.try_read(vt, 8)
            fn = struct.unpack("<Q", f)[0] if f else 0
            b = self.p.try_read(fn, 5) if ptr_ok(fn) else None
            if b and b[0] == 0xE9:                              # incremental-link thunk
                fn = fn + 5 + struct.unpack_from("<i", b, 1)[0]
            if fn and self.m.in_section(fn, ".text"):
                for mt in LEA_RIP.finditer(self.p.try_read(fn, 128) or b""):
                    tgt = fn + mt.start() + 7 + struct.unpack("<i", mt.group(2))[0]
                    if self.m.in_section(tgt, ".rdata"):
                        raw = self.p.try_read(tgt, 96) or b""
                        s = raw.split(b"\0", 1)[0].decode("latin-1")
                        if s and TYPE_NAME.fullmatch(s):
                            name = s
                            break
        if len(self.cache) > 50000:
            self.cache.clear()
        self.cache[vt] = name
        return name

    def of(self, obj):
        b = self.p.try_read(obj, 8) if ptr_ok(obj) else None
        return self.of_vtable(struct.unpack("<Q", b)[0]) if b else None


# ============================================================================ signatures
# Each regex is matched in the game's code; captured int32s are RIP-relative displacements ("rip": resolved
# to an RVA; the displacement is the last 4 bytes of its instruction) or struct offsets ("off"; "u8" a
# one-byte offset). The hits' results are voted, then checked (see _Attached.resolve).
D = rb"(....)"
SIGS = {
    # mov rax,[rip+GameClient]; mov rax,[rax+ClientZone]; test rax,rax; je ..; lea rcx,[rax+name]
    "ZONE": (rb"\x48\x8B\x05" + D + rb"\x48\x8B\x80" + D + rb"\x48\x85\xC0(?:\x74.|\x0F\x84....)\x48\x8D\x48(.)",
             ("rip", "off", "u8")),
    # mov rax,[rip+GameClient]; mov rbx,rcx; cmp byte [rax+0x2xxxx],imm8 (wizwalker's, offset wildcarded)
    "GAMECLIENT": (rb"\x48\x8B\x05" + D + rb"\x48\x8B\xD9\x80\xB8..\x02\x00", ("rip",)),
    # the ClientObject location getter (the one wizwalker's PlayerHook patched):
    # mov rbx,[rcx+anim]; test; je; mov rax,[rbx+body]; ...; movsd xmm0,[rax+pos]; ...; movss [rcx+loc+4/8/0]
    "GETLOCATION": (rb"\x48\x8B\x99" + D + rb"\x48\x85\xDB\x74.\x48\x8B\x43(.)\x48\x8B\x5B.\x48\x85\xDB\x74."
                    rb"\xF0\xFF\x43\x08\x48\x85\xC0\x74.\xF2\x0F\x10\x40(.)\xF2\x0F\x11\x02\x8B\x40.\xEB."
                    rb"\xF3\x0F\x10\x91" + D + rb"\xF3\x0F\x10\x81" + D + rb"\xF3\x0F\x11\x44\x24.\xF3\x0F\x10\x89" + D,
                    ("off", "u8", "u8", "off", "off", "off")),
    # mov rax,[rip+GUIManager]; mov rcx,[rax+HUD]; (mov [..],rcx)?; mov rbx,[rax+HUD+8]  (copying the
    # SharedPointer<HUDWindow>) - many hits; the candidates are checked by the HUD's window name
    "GUIMGR_HUD": (rb"\x48\x8B\x05" + D + rb"[\x48\x4C]\x8B[\x80\x88\x90\x98\xA8\xB0\xB8]" + D +
                   rb"(?:[\x48\x4C]\x89(?:[\x45\x4D\x55\x5D\x65\x6D\x75\x7D].|[\x44\x4C\x54\x5C\x64\x6C\x74\x7C]\x24.|"
                   rb"[\x85\x8D\x95\x9D\xA5\xAD\xB5\xBD]....)|[\x48\x4C]\x8B[\xC0-\xFF])?"
                   rb"[\x48\x4C]\x8B[\x80\x88\x90\x98\xA8\xB0\xB8]" + D, ("rip", "off", "off")),
    # lea rdi,[r14+slot]; cmp qword [rdi],0; jne ..; mov ecx,sizeof(QuestHelperHud); call new
    "HUD_QHH": (rb"\x49\x8D\xBE" + D + rb"\x48\x83\x3F\x00\x75.\xB9" + D + rb"\xE8", ("off", "off")),
    # call QuestHelperThread::ctor; jmp; mov rax,rdi; mov [rsi+slot],rax; xor r8d,r8d; mov dl,1
    "QHH_THREAD": (rb"\xE8....\xEB\x03\x48\x8B\xC7\x48\x89\x86" + D + rb"\x45\x33\xC0\xB2\x01\x48\x8B\xC8\xE8",
                   ("off",)),
    # movss xmm0,[r15+goal]; movss [rbp-..],xmm0; movss xmm1,[r15+goal+4]; ...; +8  (wizwalker's QuestHook spot)
    "GOAL": (rb"\xF3\x41\x0F\x10[\x80-\xBF]" + D + rb"\xF3\x0F\x11\x45.\xF3\x41\x0F\x10[\x80-\xBF]" + D +
             rb"\xF3\x0F\x11\x4D.\xF3\x41\x0F\x10[\x80-\xBF]" + D + rb"\xF3\x0F\x11\x45.\x48\x8B\x4D.\x48\x85\xC9\x74",
             ("off", "off", "off")),
    # mov ecx,[r15+hops]; mov [rax+18h],ecx; imul eax,[r15+hops],10000
    "HOPS": (rb"\x41\x8B[\x80-\xBF]" + D + rb"\x89\x48\x18\x41\x69[\x80-\xBF]" + D + rb"\x10\x27\x00\x00",
             ("off", "off")),
    # QuestHelperThread::OnUpdateZoneInfo: lea rcx,[rdi+nav]; ...; lea rcx,[rdi+zone]; ...;
    #   mov eax,[rbx+30h]; mov [rdi+..],eax; movsd xmm0,[rbx+34h]; movsd [rdi+player],xmm0
    "ZONEINFO": (rb"\x48\x8D\x8F" + D + rb"\x48\x8B\xD3\xE8....\x4C\x8D\x43\x10\x48\x8D\x8F" + D +
                 rb".{10,40}?\x8B\x43\x30\x89\x87....\xF2\x0F\x10\x43\x34\xF2\x0F\x11\x87" + D,
                 ("off", "off", "off")),
    # QuestHelperThread::FindPathToClosestGoal's start: cmp byte [rcx+enabled],r12b; je; mov rax,[rcx+nav];
    # test rax,rax; je  (nav must be ZONEINFO's)
    "ENABLED": (rb"[\x40-\x4F]\x38[\x80-\xBF]" + D + rb"\x0F\x84....[\x48\x49]\x8B[\x80-\xBF]" + D + rb"\x48\x85\xC0\x0F\x84",
                ("off", "off")),
    # lea rcx,[r15+path]; call SharedPointer copy; mov ecx,50h; call new (the HUD message)
    "PATH": (rb"\x49\x8D\x8F" + D + rb"\xE8....\xB9\x50\x00\x00\x00\xE8", ("off",)),
    # mov rax,[r15+quest]; mov rcx,[rbp-..]; test rcx,rcx; je +9; cmp rax,[rcx+..]
    "ACTIVE_QUEST": (rb"\x49\x8B\x87" + D + rb"\x48\x8B\x4D.\x48\x85\xC9\x74\x09\x48\x3B\x81", ("off",)),
    # mov rcx,[r15+goal]; cmp rbx,rcx; je ..; mov rax,[rbp-..]; mov [rax],rcx
    "ACTIVE_GOAL": (rb"\x49\x8B\x8F" + D + rb"\x48\x3B\xD9\x74.\x48\x8B\x45.\x48\x89\x08", ("off",)),
    # QuestHelperHud::ThreadUpdateCallback copying the thread's message (hops, cost, distance, target)
    "HUD_FIELDS": (rb"\x48\x8B\x07\x8B\x48\x18\x89\x8B" + D + rb"\x48\x8B\x07\x8B\x48\x1C\x89\x8B" + D +
                   rb"\x48\x8B\x07\x8B\x48\x20\x89\x8B" + D +
                   rb"\x48\x8B\x07\xF3\x0F\x10\x40\x30\xF3\x0F\x10\x48\x2C.{5}\xF3\x0F\x10\x50\x28\x0F\x14\xD1"
                   rb"\xF2\x0F\x11\x93" + D, ("off", "off", "off", "off")),
}

# Offsets of objects that are checked by a name before use (so these are tried, never trusted): the
# client of 2026-10-13, build KNOWN_BUILD (PE timestamp - image size). In that build a failed check means
# the object isn't there now (login screen, loading); in another one the object is also looked for by name
KNOWN_BUILD = "6A9721E9-370E000"
KNOWN = {"gameclient_rva": 0x3320FF0, "guimgr_rva": 0x3322460, "gm_hud": 0x2D0, "hud_qhh": 0x6A8,
         "qhh_thread": 0x2C8, "gc_elastic_cam": 0x222C8, "cam_attached_object": 0x108, "gc_zone": 0x21368}
# Data offsets that every object of the kind carries (not tied to a signature; seen on every object)
DATA = {"window_name": 0x50, "thread_name": 0xB0, "navnode_pos": 0x30, "list_value": 0x10,
        "body_parent": 0x48, "co_orientation_after_location": 0xC}


def scan(code):
    """{signature: [result tuple, most voted first]}"""
    res = {}
    for name, (pat, kinds) in SIGS.items():
        rx = re.compile(pat, re.DOTALL)
        votes = Counter()
        for va, data in code:
            for m in rx.finditer(data):
                vals = []
                for g, k in enumerate(kinds, 1):
                    raw = m.group(g)
                    if k == "rip":
                        vals.append(va + m.start(g) + 4 + struct.unpack("<i", raw)[0])
                    elif k == "u8":
                        vals.append(raw[0])
                    else:
                        vals.append(struct.unpack("<i", raw)[0])
                votes[tuple(vals)] += 1
        res[name] = [k for k, _ in votes.most_common()]
    return res


def finite(*v):
    return all(isinstance(x, float) and math.isfinite(x) and abs(x) < 1e7 for x in v)


# ============================================================================ one attached game
class _Attached:
    """the game process with pid, its signatures resolved (once: they hold for the process's lifetime)"""

    RESCAN_EVERY = 10.0      # s between name scans for an object whose known place failed

    def __init__(self, pid, log):
        self.log = log
        self._next_scan = {}
        t0 = time.perf_counter()
        self.p = Proc(pid)
        try:
            self.m = Module(self.p)
            self.tn = TypeNamer(self.m)
            self.how = {}
            self.o = {}
            code = self.m.code()
            self.scan_s = time.perf_counter() - t0
            self.sig = scan(code)
            del code
            self.resolve()
        except Exception:
            self.p.close()
            raise
        self.attach_s = time.perf_counter() - t0

    def close(self):
        self.p.close()

    def alive(self):
        return self.p.alive()

    # ------------------------------------------------------------ resolving (once per process)
    def _first(self, name, check=None):
        for cand in self.sig.get(name, []):
            try:
                if check is None or check(cand):
                    return cand
            except (IndexError, TypeError, ReadError):
                pass
        return None

    def _gameclient_ok(self, rva):
        """a GameClient static: it points at an object readable 0x20000 in"""
        b = self.p.try_read(self.m.base + rva, 8)
        gc = struct.unpack("<Q", b)[0] if b else 0
        return ptr_ok(gc) and self.p.try_read(gc + 0x20000, 8) is not None

    def resolve(self):
        o, how = self.o, self.how
        # GameClient and the zone name
        z = self._first("ZONE", lambda c: self._gameclient_ok(c[0]))
        if z:
            o["gameclient_rva"], o["gc_zone"], o["zone_name"] = z
            how["gameclient"] = "sig ZONE"
        else:
            g = self._first("GAMECLIENT", lambda c: self._gameclient_ok(c[0]))
            if not g:
                raise LookupError("the GameClient signature isn't in this game build (%s)" % self.m.build)
            o["gameclient_rva"] = g[0]
            o["gc_zone"], o["zone_name"] = None, 0x58     # gc_zone found by its type name on first read
            how["gameclient"] = "sig GAMECLIENT"
        # the wizard's location
        loc = self._first("GETLOCATION", lambda c: c[3] == c[5] + 4 and c[4] == c[5] + 8)   # y, z, x
        if not loc:
            raise LookupError("the location signature isn't in this game build (%s)" % self.m.build)
        o["co_anim"], o["anim_body"], o["body_pos"], o["co_location"] = loc[0], loc[1], loc[2], loc[5]
        how["location"] = "sig GETLOCATION"
        o["gc_elastic_cam"] = o["cam_attached_object"] = None     # checked by type name on read
        # the quest helper (each one may be missing: those fields are then left empty)
        o["gm_candidates"] = [(c[0], c[1]) for c in self.sig.get("GUIMGR_HUD", []) if c[2] == c[1] + 8][:16]
        if (KNOWN["guimgr_rva"], KNOWN["gm_hud"]) not in o["gm_candidates"]:
            o["gm_candidates"].append((KNOWN["guimgr_rva"], KNOWN["gm_hud"]))
        o["gm"] = None                                              # (rva, hud offset) once a HUD is named
        c = self._first("HUD_QHH")
        o["hud_qhh"] = c[0] if c else None
        c = self._first("QHH_THREAD")
        o["qhh_thread"] = c[0] if c else None
        c = self._first("GOAL", lambda c: c[1] == c[0] + 4 and c[2] == c[0] + 8)
        o["th_goal"] = c[0] if c else None
        c = self._first("HOPS", lambda c: c[0] == c[1])
        o["th_hops"] = c[0] if c else None
        c = self._first("ZONEINFO")
        o["th_nav"], o["th_zone"] = (c[0], c[1]) if c else (None, None)
        c = self._first("ENABLED", lambda c: o["th_nav"] is not None and c[1] == o["th_nav"])
        o["th_enabled"] = c[0] if c else None
        c = self._first("PATH")
        o["th_path"] = c[0] if c else None
        c = self._first("ACTIVE_QUEST")
        o["th_quest"] = c[0] if c else None
        c = self._first("ACTIVE_GOAL")
        o["th_goalid"] = c[0] if c else None
        c = self._first("HUD_FIELDS", lambda c: len(set(c)) == 4)
        o["hud_hops"], o["hud_cost"], o["hud_dist"], o["hud_arrow"] = c if c else (None,) * 4
        missing = [k for k in ("hud_qhh", "qhh_thread", "th_goal", "th_hops", "th_zone", "th_enabled", "th_path",
                               "th_quest", "th_goalid", "hud_arrow") if o[k] is None]
        how["quest"] = "all signatures found" if not missing else "missing: " + ", ".join(missing)

    def describe(self):
        o = self.o
        hx = lambda v: "?" if v is None else ("%#x" % v if isinstance(v, int) else str(v))     # ? = checked on read
        keys = ("gameclient_rva", "gc_zone", "zone_name", "gc_elastic_cam", "cam_attached_object", "co_anim",
                "anim_body", "body_pos", "co_location", "gm", "hud_qhh", "qhh_thread", "th_enabled", "th_quest",
                "th_goalid", "th_zone", "th_goal", "th_hops", "th_path", "hud_arrow", "hud_dist", "hud_hops")
        gm = o.get("gm")
        parts = [k + "=" + (("%#x+%#x" % gm) if k == "gm" and gm else hx(o.get(k))) for k in keys]
        return ("pid %d build %s, %.2f s (code read %.2f s); %s; %s; %s" %
                (self.p.pid, self.m.build, self.attach_s, self.scan_s, self.how.get("gameclient"),
                 self.how.get("location"), self.how.get("quest")) + "\n  " + " ".join(parts))

    # ------------------------------------------------------------ helpers
    def _due(self, key):
        """True at most once per RESCAN_EVERY for key (a name scan that may be slow)"""
        now = time.monotonic()
        if now < self._next_scan.get(key, 0):
            return False
        self._next_scan[key] = now + self.RESCAN_EVERY
        return True

    def _typed(self, obj, off, accept):
        """the pointer at obj+off if its type name passes accept, else 0"""
        b = self.p.try_read(obj + off, 8)
        v = struct.unpack("<Q", b)[0] if b else 0
        if ptr_ok(v):
            n = self.tn.of(v)
            if n and accept(n):
                return v
        return 0

    def _scan_typed(self, obj, size, accept):
        """the first offset in obj (size bytes) holding a pointer whose type name passes accept"""
        for base in range(0, size, 0x1000):
            blob = self.p.try_read(obj + base, min(0x1000, size - base))
            if blob is None:
                break
            for i in range(0, len(blob) - 7, 8):
                v = struct.unpack_from("<Q", blob, i)[0]
                if ptr_ok(v):
                    n = self.tn.of(v)
                    if n and accept(n):
                        return base + i
        return None

    def _named(self, obj, off, name_off, name):
        """the pointer at obj+off if the object's name string (at name_off) is name, else 0"""
        b = self.p.try_read(obj + off, 8)
        v = struct.unpack("<Q", b)[0] if b else 0
        return v if ptr_ok(v) and self.p.try_string(v + name_off) == name else 0

    def _scan_named(self, obj, size, name_off, name):
        raw = self.p.try_read(obj, size)
        if raw is None:
            return None
        for i in range(0, size - 7, 8):
            v = struct.unpack_from("<Q", raw, i)[0]
            if ptr_ok(v) and self.p.try_string(v + name_off) == name:
                return i
        return None

    def _member(self, key, parent, find, size, check):
        """the object at parent + o[key]: the known offset first (KNOWN), else one found by a scan of
        parent (at most every RESCAN_EVERY s); a found offset is kept for the process's lifetime"""
        o = self.o
        if o.get(key) is not None:
            return check(parent, o[key])
        v = check(parent, KNOWN[key]) if key in KNOWN else 0
        if v:
            o[key] = KNOWN[key]
            self.how[key] = "known offset, checked"
            return v
        if self.m.build == KNOWN_BUILD or not self._due(key):
            return 0
        off = find(parent, size)
        if off is not None:
            v = check(parent, off)
            if v:
                o[key] = off
                self.how[key] = "found by name"
                self.log("navmem: %s found at +%#x" % (key, off))
                return v
        return 0

    # ------------------------------------------------------------ reading
    def gameclient(self):
        return self.p.u64(self.m.base + self.o["gameclient_rva"])

    def zone(self, gc):
        o = self.o
        if o["gc_zone"] is None:
            o["gc_zone"] = self._scan_typed(gc, 0x30000, lambda n: n == "ClientZone") if self._due("gc_zone") else None
            if o["gc_zone"] is None:
                return None
        cz = self.p.u64(gc + o["gc_zone"])
        return self.p.try_string(cz + o["zone_name"], stable=True) if ptr_ok(cz) else None

    def player(self, gc):
        """{pos (x, y, z), yaw, source} or None, why"""
        p, o = self.p, self.o
        is_cam = lambda n: n == "ElasticCamController"
        cam = self._member("gc_elastic_cam", gc,
                           lambda obj, size: self._scan_typed(obj, size, is_cam), 0x30000,
                           lambda obj, off: self._typed(obj, off, is_cam))
        if not cam:
            return None, "no camera controller (not in the game world)"
        is_obj = lambda n: n.endswith("ClientObject")
        co = self._member("cam_attached_object", cam,
                          lambda obj, size: self._scan_typed(obj, size, is_obj), 0x400,
                          lambda obj, off: self._typed(obj, off, is_obj))
        if not co:
            return None, "the camera follows no object"
        anim = p.u64(co + o["co_anim"])
        body = p.u64(anim + o["anim_body"]) if ptr_ok(anim) else 0
        if ptr_ok(body) and p.try_read(body + DATA["body_parent"], 8) == struct.pack("<Q", co):
            raw, src = p.stable(body + o["body_pos"], 24), "body"
        else:                                    # no body (zoning): the object's own copy
            raw, src = p.stable(co + o["co_location"], 24), "object"
        x, y, z, pitch, roll, yaw = struct.unpack("<6f", raw)
        if not finite(x, y, z, yaw):
            return None, "the position isn't a number"
        yaw = (yaw + math.pi) % (2 * math.pi) - math.pi
        return {"pos": (x, y, z), "yaw": yaw, "source": src}, ""

    def _group(self, base, fields):
        """{name: value} of fields {name: (offset, struct format)} at base, the whole span read until two
        reads agree (one span: they were written together)"""
        lo = min(off for off, f in fields.values())
        hi = max(off + struct.calcsize("<" + f) for off, f in fields.values())
        raw = self.p.stable(base + lo, hi - lo)
        out = {}
        for k, (off, f) in fields.items():
            v = struct.unpack_from("<" + f, raw, off - lo)
            out[k] = v[0] if len(v) == 1 else v
        return out

    def quest(self, gc_zone, want_path):
        """{enabled, quest, goalid, goal, hops, target, dist, path, thread_zone} (each None when it can't be
        read for sure) or None, why"""
        p, o = self.p, self.o
        wn, tn = DATA["window_name"], DATA["thread_name"]
        hud = 0
        if o["gm"] is not None:
            rva, off = o["gm"]
            gm = p.try_read(self.m.base + rva, 8)
            hud = self._named(struct.unpack("<Q", gm)[0], off, wn, "windowHUD") if gm else 0
        else:
            for rva, off in o["gm_candidates"]:
                gm = p.try_read(self.m.base + rva, 8)
                hud = self._named(struct.unpack("<Q", gm)[0], off, wn, "windowHUD") if gm else 0
                if hud:
                    o["gm"] = (rva, off)
                    self.how["gm"] = "sig GUIMGR_HUD, named windowHUD"
                    break
        if not hud:
            return None, "no HUD (not in the game world)"
        if o["hud_qhh"] is None or o["qhh_thread"] is None:
            return None, "the quest helper's signatures aren't in this build"
        qhh = self._named(hud, o["hud_qhh"], wn, "QuestHelperHud")
        if not qhh:
            # (the slot moved in a build where the signature still matched something else)
            if self.m.build != KNOWN_BUILD and self._due("hud_qhh"):
                off = self._scan_named(hud, 0xD00, wn, "QuestHelperHud")
                if off is not None:
                    o["hud_qhh"] = off
                    qhh = self._named(hud, off, wn, "QuestHelperHud")
            if not qhh:
                return None, "no quest helper on the HUD"
        th = self._named(qhh, o["qhh_thread"], tn, "QuestHelper")
        if not th:
            if self.m.build != KNOWN_BUILD and self._due("qhh_thread"):
                off = self._scan_named(qhh, 0x450, tn, "QuestHelper")
                if off is not None:
                    o["qhh_thread"] = off
                    th = self._named(qhh, off, tn, "QuestHelper")
            if not th:
                return None, "no quest helper thread"
        r = dict.fromkeys(("enabled", "quest", "goalid", "goal", "hops", "target", "dist", "path", "thread_zone"))
        ids = {k: v for k, v in (("enabled", (o["th_enabled"], "B")), ("quest", (o["th_quest"], "Q")),
                                 ("goalid", (o["th_goalid"], "Q"))) if v[0] is not None}
        if ids:
            r.update(self._group(th, ids))
        if o["th_zone"] is not None:
            r["thread_zone"] = p.try_string(th + o["th_zone"], stable=True)
        same_zone = r["thread_zone"] is not None and gc_zone is not None and r["thread_zone"] == gc_zone
        if not same_zone:
            return r, "the quest helper is still on zone %r" % r["thread_zone"]
        if o["th_goal"] is not None and o["th_hops"] is not None:
            g = self._group(th, {"goal": (o["th_goal"], "3f"), "hops": (o["th_hops"], "i")})
            if finite(*g["goal"]) and 0 <= g["hops"] < 1000:
                r["goal"], r["hops"] = g["goal"], g["hops"]
        if o["hud_arrow"] is not None:
            h = self._group(qhh, {"target": (o["hud_arrow"], "3f"), "dist": (o["hud_dist"], "f"),
                                  "hops": (o["hud_hops"], "i")})
            # (the arrow is the thread's message as of its last update: only while it has the same hops)
            if r["hops"] is not None and h["hops"] == r["hops"] and finite(*h["target"]) and finite(h["dist"]):
                r["target"], r["dist"] = h["target"], h["dist"]
        if want_path and o["th_path"] is not None:
            r["path"] = self.path(th)
        return r, ""

    def path(self, th, limit=2000):
        """the thread's path: [(x, y, z)] in the game's order, read until two reads agree, or None"""
        p = self.p
        prev = None
        for _ in range(4):
            try:
                cur = self._path_once(th, limit)
            except ReadError:
                cur = None
            if cur is not None and cur == prev:
                return cur
            prev = cur
        return None

    def _path_once(self, th, limit):
        p = self.p
        sp = p.u64(th + self.o["th_path"])
        if not ptr_ok(sp):
            return []
        head, cnt = struct.unpack("<QQ", p.read(sp, 16))
        if not ptr_ok(head) or cnt > limit:
            return None
        pts, n = [], p.u64(head)
        while n != head:
            if len(pts) >= cnt or not ptr_ok(n):
                return None
            nxt, _prev, node = struct.unpack("<QQQ", p.read(n, 24))
            if not ptr_ok(node):
                return None
            x, y, z = struct.unpack("<3f", p.read(node + DATA["navnode_pos"], 12))
            if not finite(x, y, z):
                return None
            pts.append((x, y, z))
            n = nxt
        return pts if len(pts) == cnt else None


# ============================================================================ the reader
class NavMem:
    """Attaches to the game (the foreground client if there are several), re-attaching when it is
    restarted; read() never raises. Thread-safe."""

    # s before attaching to the same pid again after it failed: it couldn't be opened or read (the game
    # starting up, or run as administrator) / a signature isn't in its code (that won't change while it runs)
    RETRY_READ, RETRY_SIG = 5.0, 300.0

    def __init__(self, log=None):
        self.log = log or (lambda msg: None)
        self.lock = threading.Lock()
        self.st = None
        self.game_dir = ""
        self._thread = None
        self._failed = (0, 0.0, "")      # pid, when to try again, why
        self._last_why = None

    def close(self):
        with self.lock:
            if self.st:
                self.st.close()
                self.st = None

    def _attach(self, pid):
        try:
            st = _Attached(pid, self.log)
        except Exception as e:  # noqa: BLE001
            sig = isinstance(e, LookupError)
            why = str(e) if sig else "can't read the game (%s)" % (e,)
            with self.lock:
                self._failed = (pid, time.monotonic() + (self.RETRY_SIG if sig else self.RETRY_READ), why)
            self.log("navmem: attaching to pid %d failed: %s" % (pid, why))
            return
        game_dir = ""
        try:
            exe = st.p.image_path()
            if exe.lower().endswith("\\bin\\" + EXE.lower()):
                game_dir = exe[: -len("\\bin\\" + EXE)]
        except Exception:  # noqa: BLE001
            pass
        with self.lock:
            self.st, self.game_dir = st, game_dir
        self.log("navmem: attached - " + st.describe())

    def _ensure(self, wait):
        with self.lock:
            if self.st is not None and not self.st.alive():
                self.log("navmem: the game (pid %d) has closed" % self.st.p.pid)
                self.st.close()
                self.st = None
            if self.st is not None:
                return self.st, ""
            th = self._thread
            if th is None or not th.is_alive():
                pids = find_pids()
                if not pids:
                    return None, "the game is not running"
                fg = foreground_pid()
                pid = fg if fg in pids else pids[0]
                fpid, again, fwhy = self._failed
                if fpid == pid and time.monotonic() < again:
                    return None, fwhy
                th = self._thread = threading.Thread(target=self._attach, args=(pid,), daemon=True)
                th.start()
        th.join(wait)
        with self.lock:
            if self.st is not None:
                return self.st, ""
            if th.is_alive():
                return None, "attaching to the game (its code is looked through once)"
            return None, self._failed[2] or "can't attach to the game"

    def read(self, path=False, wait=1.0):
        """(r, why): r = {zone, pos (x, y, z), yaw, source, enabled, quest, goalid, goal (x, y, z), hops,
        target (x, y, z), dist, path [(x, y, z)], thread_zone, why_player, why_quest} - a value None when it
        can't be read for sure; r is None (and why says why) when the game can't be read at all"""
        try:
            st, why = self._ensure(wait)
            if st is None:
                return None, why
            with self.lock:
                r = self._read(st, path)
            note = (r.get("why_player") or "") + " / " + (r.get("why_quest") or "")
            if note != self._last_why:
                self._last_why = note
                if note != " / ":
                    self.log("navmem: " + note)
            return r, ""
        except Exception as e:  # noqa: BLE001 - never into the server
            return None, "reading the game failed (%r)" % (e,)

    @staticmethod
    def _read(st, path):
        r = dict.fromkeys(("zone", "pos", "yaw", "source", "enabled", "quest", "goalid", "goal", "hops",
                           "target", "dist", "path", "thread_zone", "why_player", "why_quest"))
        try:
            gc = st.gameclient()
        except ReadError as e:
            r["why_player"] = r["why_quest"] = "no GameClient (%s)" % e
            return r
        if not ptr_ok(gc):
            r["why_player"] = r["why_quest"] = "no GameClient yet"
            return r
        try:
            r["zone"] = st.zone(gc)
        except ReadError:
            pass
        try:
            pl, r["why_player"] = st.player(gc)
            if pl:
                r.update(pl)
        except ReadError as e:
            r["why_player"] = "player: %s" % e
        try:
            q, r["why_quest"] = st.quest(r["zone"], path)
            if q:
                r.update(q)
        except ReadError as e:
            r["why_quest"] = "quest: %s" % e
        return r

    def describe(self):
        with self.lock:
            return self.st.describe() if self.st else "not attached"


# ============================================================================ command line
def _main():
    import argparse
    ap = argparse.ArgumentParser(description="read-only: the wizard's position and the quest goal")
    ap.add_argument("-n", type=int, default=3)
    ap.add_argument("-i", type=float, default=0.5)
    ap.add_argument("--path", action="store_true")
    a = ap.parse_args()
    nm = NavMem(log=print)
    for k in range(a.n):
        t0 = time.perf_counter()
        r, why = nm.read(path=a.path, wait=30)
        ms = (time.perf_counter() - t0) * 1000
        if r is None:
            print("%7.1f ms  ERR %s" % (ms, why))
        else:
            fmt = lambda v: "-" if v is None else "(%.1f, %.1f, %.1f)" % tuple(v)
            print("%7.1f ms  zone %s  pos %s yaw %s [%s]  goal %s hops %s  target %s dist %s  quest %s/%s/%s  path %s"
                  % (ms, r["zone"], fmt(r["pos"]), None if r["yaw"] is None else round(r["yaw"], 4), r["source"],
                     fmt(r["goal"]), r["hops"], fmt(r["target"]), None if r["dist"] is None else round(r["dist"], 1),
                     r["enabled"], r["quest"], r["goalid"], "-" if r["path"] is None else len(r["path"])))
            for k2 in ("why_player", "why_quest"):
                if r[k2]:
                    print("           " + k2 + ": " + r[k2])
        if k + 1 < a.n:
            time.sleep(a.i)
    print(nm.describe())


if __name__ == "__main__":
    _main()
