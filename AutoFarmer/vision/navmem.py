"""navmem - READ-ONLY reader of the wizard's position and the quest goal in a running Wizard101 client
(WizardGraphicalClient.exe), for the vision helper's /nav and /navmap.

    nm = NavMem(log=print)
    r, why = nm.read(path=True)     # r: a dict (see NavMem.read), or None and why it can't be read

    mobs, why = nm.mobs()           # the zone's mobs: [{name, pos (x, y, z), yaw, gid, template}], or None and why

    hand, why = nm.cards()          # the cards in the wizard's hand in a battle and its pips (handmem.py), or None and why

    goal, why = nm.goal()           # the quest's active goal: its line as the game shows it under the arrow, its kind,
                                    # count and the mob / item / NPC it names (questmem.py), or None and why

    python navmem.py [-n 5] [-i 1] [--path] [--mobs] [--goal]   readings from the command line (and how long each took)

SAFETY. The game is opened with PROCESS_VM_READ | PROCESS_QUERY_INFORMATION (falling back to
PROCESS_VM_READ | PROCESS_QUERY_LIMITED_INFORMATION) and nothing else. The only process APIs used are
CreateToolhelp32Snapshot / Process32*W (finding the pid), OpenProcess, ReadProcessMemory, VirtualQueryEx and
QueryWorkingSetEx (which of its memory is in use and in RAM - for the mobs; only that is read, nothing is paged
in), EnumProcessModulesEx, GetModuleBaseNameW,
QueryFullProcessImageNameW and GetExitCodeProcess. Nothing is
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
           The camera's object is checked to be a ClientObject by its type name (...ClientObject): a destroyed one's
           reads as PropertyClass (its destructor leaves the base class's vtable) and isn't followed - logged out or
           disconnected, the old world stays in memory a while.
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
           mobs:    every ClientObject of the zone holds the zone's ClientZone (GameClient +0x21368) at +0x130:
             the game's heap (its committed private read-write memory) is looked through for that pointer by a
             background thread - all of it (the pages in RAM) every OBJ_SETTLE_EVERY s for OBJ_SETTLE s in a new zone (its
             mobs come after the loading screen) and while none is found, then every OBJ_FULL s, in between only
             where objects were found, every OBJ_QUICK s (it stops when nobody has asked for OBJ_IDLE s - a long
             battle - keeping what it found: each is checked again at every read, and it carries on from there).
             ClientObject +0 vtable (a live one's type name ends ClientObject: a destroyed one's is its base class's,
             PropertyClass), +0x48 global id, +0x58 template, +0xA8 x, y, z (its own copy - the body's,
             as the wizard's, when it has one); template +0x60 its name, +0xA8 its display name's key, +0x1C8 its
             school. A mob: a display name in one of the game's *Mobs name tables (Root.wad Locale/en-US/
             WizardMobs.lang, Mobs.lang) that has a name - wisps and the like have none - and a school (a teleporter
             can borrow a mob's name). An object is re-checked at each read
             - the same vtable (a destroyed one's is changed by its destructor), global id and zone - before its
             position is used.
           goal:    the goal line (txtGoalName under the QuestHelperHud, its ids at +0x2D8 / +0x2E0) and the quest
             manager's quest data (WizQuestData -> WizGoalData -> its madlibs) - questmem.py, its offsets found by name
             in the game's reflection registration (handmem.py's way), read under this lock, the names looked up outside
             it; its reader made once per game in a thread like the hand's
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


class MEMORY_BASIC_INFORMATION(C.Structure):
    _fields_ = [("BaseAddress", C.c_void_p), ("AllocationBase", C.c_void_p), ("AllocationProtect", W.DWORD),
                ("PartitionId", W.WORD), ("RegionSize", C.c_size_t), ("State", W.DWORD), ("Protect", W.DWORD),
                ("Type", W.DWORD)]


k32.VirtualQueryEx.argtypes = [W.HANDLE, C.c_void_p, C.POINTER(MEMORY_BASIC_INFORMATION), C.c_size_t]
k32.VirtualQueryEx.restype = C.c_size_t
psapi.QueryWorkingSetEx.argtypes = [W.HANDLE, C.c_void_p, W.DWORD]
psapi.QueryWorkingSetEx.restype = W.BOOL
MEM_COMMIT, MEM_PRIVATE, PAGE_READWRITE = 0x1000, 0x20000, 0x04
PAGE = 0x1000


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

    def regions(self):
        """[(base, size)] of the game's committed private read-write memory - where its heap objects are"""
        out, addr, m = [], 0x10000, MEMORY_BASIC_INFORMATION()
        while addr < 0x7FFFFFFF0000:
            if not k32.VirtualQueryEx(self.h, C.c_void_p(addr), C.byref(m), C.sizeof(m)):
                if not out and addr == 0x10000:
                    raise ReadError("VirtualQueryEx failed (%d) - the game was opened without "
                                    "PROCESS_QUERY_INFORMATION" % C.get_last_error())
                break
            base, size = m.BaseAddress or 0, m.RegionSize
            if size <= 0:
                break
            if m.State == MEM_COMMIT and m.Type == MEM_PRIVATE and m.Protect == PAGE_READWRITE:
                out.append((base, size))
            addr = base + size
        return out

    def resident(self, base, size):
        """[(base, size)] runs of the pages of [base, base + size) that are in the game's working set (in RAM) -
        reading only those pages nothing in; the whole range if that can't be asked"""
        import numpy as np
        n = size // PAGE
        if n <= 0:
            return []
        runs = []
        for b0 in range(0, n, 0x10000):
            k = min(0x10000, n - b0)
            info = np.zeros(2 * k, dtype=np.uint64)
            info[0::2] = base + (b0 + np.arange(k, dtype=np.uint64)) * PAGE
            if not psapi.QueryWorkingSetEx(self.h, info.ctypes.data, info.nbytes):
                return [(base, size)]
            valid = (info[1::2] & 1).astype(bool)
            edges = np.flatnonzero(np.diff(np.concatenate(([False], valid, [False])).astype(np.int8)))
            for s, e in zip(edges[0::2], edges[1::2]):
                runs.append((base + (b0 + int(s)) * PAGE, int(e - s) * PAGE))
        return runs

    def read_pieces(self, base, size, piece=0x10000):
        """[(address, bytes)] of [base, base + size) read in pieces, the unreadable ones left out"""
        out = []
        for off in range(0, size, piece):
            raw = self.try_read(base + off, min(piece, size - off))
            if raw is not None:
                out.append((base + off, raw))
        return out

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
        name = self.cache.get(vt, self)               # (one look: the objects thread may clear the cache meanwhile)
        if name is not self:
            return name
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
        "body_parent": 0x48, "co_orientation_after_location": 0xC,
        "co_gid": 0x48, "co_template": 0x58, "co_zone": 0x130, "tpl_name": 0x60, "tpl_display": 0xA8,
        "tpl_school": 0x1C8}
# The zone's objects (the mobs): the heap read in pieces this big; quick looks (where objects were found) every
# OBJ_QUICK s, all of it every OBJ_FULL s and on a new zone; the thread stops when nobody's asked for OBJ_IDLE s
SCAN_CHUNK = 0x400000
OBJ_QUICK, OBJ_FULL, OBJ_IDLE, OBJ_SETTLE, OBJ_SETTLE_EVERY = 3.0, 15.0, 120.0, 20.0, 5.0
OBJ_SPAN = 0x138                     # an object read from +0 to past its zone pointer (+0x130)
MOB_KEY = re.compile(r"^(\w*Mobs)_(\d+)$")
MOB_TABLES = ("WizardMobs", "Mobs")
# a thing lying about the zone that a quest has you collect (Piece Of Coral: CL-Coral-Object, WizItems_00001638) -
# its template's display key is in the items name table
ITEM_KEY = re.compile(r"^(WizItems)_(\d+)$")
ITEM_TABLES = ("WizItems",)


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

    def is_client_object(self, v):
        """v is a live ClientObject: its type name (from its vtable) ends ClientObject - a destroyed one's vtable is
        its base class's (it reads PropertyClass), its memory otherwise much as it was"""
        if not ptr_ok(v):
            return False
        n = self.tn.of(v)
        return bool(n) and n.endswith("ClientObject")

    def _object_at(self, obj, off):
        """the pointer at obj+off if it's a ClientObject, else 0"""
        b = self.p.try_read(obj + off, 8)
        v = struct.unpack("<Q", b)[0] if b else 0
        return v if self.is_client_object(v) else 0

    def _scan_objects(self, obj, size):
        """the first offset in obj (size bytes) holding a ClientObject"""
        raw = self.p.try_read(obj, size)
        if raw is None:
            return None
        for i in range(0, size - 7, 8):
            if self.is_client_object(struct.unpack_from("<Q", raw, i)[0]):
                return i
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
        co = self._member("cam_attached_object", cam, self._scan_objects, 0x400, self._object_at)
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

    def zone_ptr(self, gc):
        """the ClientZone the game is in (every object of the zone holds it at +0x130), or 0"""
        if self.o.get("gc_zone") is None:
            return 0
        cz = self.p.u64(gc + self.o["gc_zone"])
        return cz if ptr_ok(cz) and self.tn.of(cz) == "ClientZone" else 0

    def scan_objects(self, cz, regions=None):
        """([addresses of the objects holding cz at +0x130], [(base, size) of the regions they were in]) - in
        regions, or all of the game's heap (only its pages in RAM)"""
        import numpy as np                          # (only here: the rest of navmem doesn't need it)
        needle = np.uint64(cz)
        found, where = [], []
        for base, size in (regions if regions is not None else self.p.regions()):
            hit = False
            for rb, rs in self.p.resident(base, size):
                for off in range(0, rs, SCAN_CHUNK):
                    n = min(SCAN_CHUNK, rs - off)
                    raw = self.p.try_read(rb + off, n)
                    parts = [(rb + off, raw)] if raw is not None else self.p.read_pieces(rb + off, n)
                    for at, data in parts:
                        idx = np.flatnonzero(np.frombuffer(data, dtype=np.uint64, count=len(data) // 8) == needle)
                        if len(idx):
                            hit = True
                            found.extend(at + int(i) * 8 - DATA["co_zone"] for i in idx)
            if hit:
                where.append((base, size))
        return found, where

    def template_kind(self, tpl, names, cache):
        """(mob name or "", template name, item name or "") of a template - a mob's display name is in one of the
        *Mobs name tables (names: {key: English name}) and has a name, and it has a school (Fire, Storm...: one that
        fights - a teleporter can borrow a mob's name, Wormguts Tower); an item's (a thing a quest has you collect) is
        in the items table; None if tpl isn't a template (cached per template)"""
        if tpl in cache:
            return cache[tpl]
        k = None
        tname = self.tn.of(tpl) if ptr_ok(tpl) else None
        if tname and tname.endswith("Template"):
            key = self.p.try_string(tpl + DATA["tpl_display"]) or ""
            m = MOB_KEY.match(key)
            fights = bool(m) and bool((self.p.try_string(tpl + DATA["tpl_school"]) or "").strip())
            item = (names.get(key) or "") if ITEM_KEY.match(key) else ""
            k = ((names.get(key) or "") if fights else "", self.p.try_string(tpl + DATA["tpl_name"]) or "", item)
        if len(cache) > 20000:
            cache.clear()
        cache[tpl] = k
        return k

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
            # (a goal the game shows no way to - collect things lying about the zone, 2026-10-23 Piece Of Coral: no arrow,
            # the goal at exactly 0, 0, 0 - is no place: not read as one, else the walker stands "at" it)
            if finite(*g["goal"]) and 0 <= g["hops"] < 1000 and any(abs(v) > 1e-3 for v in g["goal"]):
                r["goal"], r["hops"] = g["goal"], g["hops"]
        if o["hud_arrow"] is not None:
            h = self._group(qhh, {"target": (o["hud_arrow"], "3f"), "dist": (o["hud_dist"], "f"),
                                  "hops": (o["hud_hops"], "i")})
            # (the arrow is the thread's message as of its last update: only while it has the same hops)
            if (r["hops"] is not None and h["hops"] == r["hops"] and finite(*h["target"]) and finite(h["dist"])
                    and h["dist"] >= 0 and any(abs(v) > 1e-3 for v in h["target"])):
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
        # the zone's mobs (the objects thread): {object address: (gid, name, template name)}, the zone they're
        # of, why there are none, when last asked for, the English names of the *Mobs tables (and the items table);
        # the things lying about it a quest has you collect: the same, {object address: (gid, item name, template)}
        self._objs, self._obj_cz, self._obj_why, self._obj_asked = {}, 0, "not looked yet", 0.0
        self._items = {}
        self._obj_thread, self._mob_names, self._names_retry, self.obj_stats = None, None, 0.0, {}
        self._obj_state = (None, 0.0, None, 0.0, {})   # the objects thread's: regions, last full scan, zone, since, cache
        # the hand (handmem.py): its reader of the attached game, the thread making it (its classes looked up once, about
        # half a second), why it couldn't be made (the game it was for, when to try again); the game opened for the
        # cards alone when one of the walker's signatures isn't in this build (handmem.LightAttach)
        self._hand, self._hand_thread, self._hand_fail, self._light = None, None, (None, 0.0, ""), None
        self._failed_sig = False
        # the quest's goal (questmem.py): its reader of the attached game, the thread making it (about a second), why it
        # couldn't be made (the game it was for, when to try again)
        self._quest, self._quest_thread, self._quest_fail = None, None, (None, 0.0, "")

    def close(self):
        with self.lock:
            if self.st:
                self.st.close()
                self.st = None
            if self._light:
                self._light.close()
                self._light = None
            self._hand = None
            self._quest = None

    def _attach(self, pid):
        try:
            st = _Attached(pid, self.log)
        except Exception as e:  # noqa: BLE001
            sig = isinstance(e, LookupError)
            why = str(e) if sig else "can't read the game (%s)" % (e,)
            with self.lock:
                self._failed = (pid, time.monotonic() + (self.RETRY_SIG if sig else self.RETRY_READ), why)
                self._failed_sig = sig
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

    # ------------------------------------------------------------ the hand (handmem.py)
    def cards(self, want_effects=True, wait=0.5):
        """(r, why): r = the cards in the wizard's hand and its pips, read now (handmem.HandMem.read: in_battle,
        planning, settled, state, why, ms, me, cards) - through the same read-only handle on the game as everything
        here, under the same lock; its reader made again when the game is (a restart). When one of the walker's
        signatures isn't in this build the game is opened for the cards alone (handmem.LightAttach, read-only the
        same way). None and why when the game can't be read (not running, being attached to, the reader being made).
        Never raises"""
        try:
            st, why = self._ensure(wait)
            if st is None:
                st, why = self._cards_light(why)
                if st is None:
                    return None, why
            with self.lock:
                if st is self.st and self._light is not None:      # (attached in full again: the extra handle closed)
                    self._light.close()
                    self._light = None
                hm = self._hand
                if hm is not None and hm.st is st:
                    return hm.read(want_effects), ""
                fst, again, fwhy = self._hand_fail
                if fst is st and time.monotonic() < again:
                    return None, fwhy
                th = self._hand_thread
                if th is None or not th.is_alive():
                    self._hand = None
                    th = self._hand_thread = threading.Thread(target=self._hand_make, args=(st,), name="hand", daemon=True)
                    th.start()
            th.join(wait)
            with self.lock:
                hm = self._hand
                if hm is not None and hm.st is st:
                    return hm.read(want_effects), ""
                fst, again, fwhy = self._hand_fail
                if fst is st:
                    return None, fwhy
            return None, "reading the game's card classes (once, about a second)"
        except Exception as e:  # noqa: BLE001 - never into the server
            return None, "reading the hand failed (%r)" % (e,)

    def _hand_make(self, st):
        """the hand's reader for game st (its code looked through once - outside the lock, then kept under it)"""
        try:
            import handmem
            hm = handmem.HandMem(st, log=self.log)
        except Exception as e:  # noqa: BLE001
            sig = isinstance(e, LookupError)
            why = ("the cards can't be read in this build: %s" % e) if sig else "the card classes couldn't be read (%r)" % (e,)
            self.log("handmem: " + why)
            with self.lock:
                self._hand_fail = (st, time.monotonic() + (self.RETRY_SIG if sig else 30.0), why)
            return
        with self.lock:
            self._hand = hm

    def _cards_light(self, why):
        """(the game opened for the cards alone, "") when navmem couldn't attach for a signature the walker needs (that
        won't change while it runs), else (None, why)"""
        with self.lock:
            lt = self._light
            if lt is not None and not lt.alive():
                lt.close()
                lt = self._light = None
                self._hand = None
            if lt is not None:
                return lt, ""
            sig, fpid = self._failed_sig, self._failed[0]
        if not sig:
            return None, why
        pids = find_pids()
        if fpid not in pids:
            return None, why
        try:
            import handmem
            lt = handmem.LightAttach(fpid, self.log)
        except Exception as e:  # noqa: BLE001
            return None, "%s; the game couldn't be opened for the cards (%r)" % (why, e)
        with self.lock:
            if self._light is None:
                self._light = lt
                self.log("navmem: the game opened for the cards alone (%s)" % why)
            else:
                lt.close()
            return self._light, ""

    # ------------------------------------------------------------ the quest's goal (questmem.py)
    def goal(self, r=None, wait=0.5):
        """(g, why): the quest's active goal, read now (questmem.QuestMem.resolve: text - the goal line as the game shows
        it under the arrow -, from, exact, shown, visible, distance, type, status, count, total, name, mob, item, npc,
        place, quest, quest_id, goal_id, ids_from, why, ms) - through the same read-only handle on the game as everything
        here, its memory read under the same lock (the names looked up in Root.wad outside it); its reader made in a
        thread once per game (its classes looked up, about a second - waited for up to wait s). wait 0: nothing waited
        for (the walker's /nav) - the reader made and a name table not read yet read in a thread meanwhile (the line is
        the HUD's own till then). r: a reading of read() whose quest helper ids stand in for the HUD's own (None: read
        now). None and why when there's no goal line to give (the game not running, being attached to, the reader being
        made, no quest...). Never raises"""
        try:
            st, why = self._ensure(wait)
            if st is None:
                return None, why
            qm, why = self._quest_reader(st, wait)
            if qm is None:
                return None, why
            with self.lock:
                if self.st is not st:
                    return None, "the game changed"
                if r is None:
                    r = self._read(st, False)
                snap = qm.snapshot((r.get("quest"), r.get("goalid")))
            g = qm.resolve(snap, block=wait > 0)
            if not g.get("text"):
                return None, g.get("why") or "no goal line"
            return g, ""
        except Exception as e:  # noqa: BLE001 - never into the server
            return None, "reading the quest's goal failed (%r)" % (e,)

    def _quest_reader(self, st, wait):
        """(the quest goal's reader for game st, "") - made in a thread the first time; (None, why) meanwhile, or when it
        can't be made (tried again later)"""
        with self.lock:
            qm = self._quest
            if qm is not None and qm.st is st:
                return qm, ""
            fst, again, fwhy = self._quest_fail
            if fst is st and time.monotonic() < again:
                return None, fwhy
            th = self._quest_thread
            if th is None or not th.is_alive():
                self._quest = None
                th = self._quest_thread = threading.Thread(target=self._quest_make, args=(st,), name="quest", daemon=True)
                th.start()
        if wait > 0:
            th.join(wait)
        with self.lock:
            qm = self._quest
            if qm is not None and qm.st is st:
                return qm, ""
            fst, again, fwhy = self._quest_fail
            if fst is st:
                return None, fwhy
        return None, "reading the game's quest classes (once, about a second)"

    def _quest_make(self, st):
        """the quest goal's reader for game st (its code looked through once - outside the lock, then kept under it)"""
        try:
            import questmem
            qm = questmem.QuestMem(st, log=self.log)
        except Exception as e:  # noqa: BLE001
            sig = isinstance(e, LookupError)
            why = ("the quest's goal can't be read in this build: %s" % e) if sig else \
                "the quest classes couldn't be read (%r)" % (e,)
            self.log("questmem: " + why)
            with self.lock:
                self._quest_fail = (st, time.monotonic() + (self.RETRY_SIG if sig else 30.0), why)
            return
        with self.lock:
            self._quest = qm

    # ------------------------------------------------------------ the zone's mobs
    def mobs(self):
        """(mobs, why): mobs = [{name, pos (x, y, z), yaw, gid, template}] - the mobs in the game's zone, their
        positions and facing (yaw, radians, forward = (-sin yaw, -cos yaw); None if unread) read now - or None and why
        (not attached, not looked yet, the names unreadable...). Never raises."""
        return self._live("mobs")

    def items(self):
        """(items, why): items = [{name, pos (x, y, z), yaw, gid, template}] - the things lying about the game's zone
        that a quest has you collect (their template's display name is in the items table: Piece Of Coral), read now -
        one picked up is gone from it; None and why as mobs(). Never raises."""
        return self._live("items")

    def _live(self, which):
        """mobs() / items(): the objects thread's of that kind still the same live objects, their places read now"""
        try:
            with self.lock:
                self._obj_asked = time.monotonic()
                if self._obj_thread is None or not self._obj_thread.is_alive():
                    self._obj_thread = threading.Thread(target=self._objects_run, name="objects", daemon=True)
                    self._obj_thread.start()
                st, cz, why = self.st, self._obj_cz, self._obj_why
                objs = list((self._objs if which == "mobs" else self._items).items())
            if st is None or not cz or why:
                return None, why or "not attached"
            out, gids = [], set()
            for obj, (gid, name, tname, vt) in objs:
                if gid in gids:
                    continue
                raw = st.p.try_read(obj, OBJ_SPAN)
                if raw is None:
                    continue
                # (still the same live object of this zone: a destroyed one's vtable is changed by its destructor,
                # freed and reused memory holds something else)
                if (struct.unpack_from("<Q", raw, 0)[0] != vt or struct.unpack_from("<Q", raw, DATA["co_gid"])[0] != gid
                        or struct.unpack_from("<Q", raw, DATA["co_zone"])[0] != cz):
                    continue
                pos = self._mob_pos(st, obj, raw)
                if pos is not None:
                    gids.add(gid)
                    out.append({"name": name, "pos": pos[:3], "yaw": pos[3], "gid": gid, "template": tname})
            return out, ""
        except Exception as e:  # noqa: BLE001 - never into the server
            return None, "reading the %s failed (%r)" % (which, e)

    @staticmethod
    def _mob_pos(st, obj, raw):
        """a mob's x, y, z, yaw: its body's (where it's drawn, moving, facing) when it has one - as the wizard's -
        else the object's own copy (pitch, roll, yaw follow x, y, z in both); yaw None if it isn't a number; None if
        the position isn't"""
        o, p = st.o, st.p

        def pose(raw24):
            x, y, z, _pitch, _roll, yaw = struct.unpack("<6f", raw24)
            if not finite(x, y, z):
                return None
            return (x, y, z, (yaw + math.pi) % (2 * math.pi) - math.pi if finite(yaw) else None)
        try:
            anim = p.u64(obj + o["co_anim"]) if o.get("co_anim") else 0
            body = p.u64(anim + o["anim_body"]) if ptr_ok(anim) and o.get("anim_body") else 0
            if ptr_ok(body) and p.try_read(body + DATA["body_parent"], 8) == struct.pack("<Q", obj):
                b = p.try_read(body + o["body_pos"], 24)
                got = pose(b) if b else None
                if got is not None:
                    return got
        except ReadError:
            pass
        at = o.get("co_location") or 0xA8
        return pose(raw[at:at + 24]) if len(raw) >= at + 24 else None

    def _names(self):
        """{display key: English name} of the game's *Mobs name tables (Root.wad); None while they can't be read
        (tried again after a minute)"""
        if self._mob_names is None and time.monotonic() >= self._names_retry:
            names = {}
            try:
                import os
                import navgeo
                root = os.path.join(self.game_dir or navgeo.GAME_DIR, "Data", "GameData", "Root.wad")
                files = navgeo.read_wad_files(root, ["Locale/en-US/%s.lang" % t for t in MOB_TABLES + ITEM_TABLES])
                for tbl in MOB_TABLES + ITEM_TABLES:
                    data = files.get("Locale/en-US/%s.lang" % tbl)
                    if not data:
                        continue
                    lines = data.decode("utf-16").split("\r\n")
                    # (a heading line, then key, comment, text - a text's own line breaks written as \n)
                    for i in range(1, len(lines) - 2, 3):
                        if lines[i].isdigit():
                            text = re.sub(r"\s+", " ", lines[i + 2].replace("\\r", " ").replace("\\n", " ")).strip()
                            names["%s_%s" % (tbl, lines[i])] = text
            except Exception as e:  # noqa: BLE001
                self.log("navmem: the mob names couldn't be read (%r)" % (e,))
            if names:
                self._mob_names = names
                self.log("navmem: %d mob names read" % len(names))
            else:
                self._names_retry = time.monotonic() + 60.0
        return self._mob_names

    def _set_objs(self, cz, objs, why, items=None):
        with self.lock:
            self._obj_cz, self._objs, self._obj_why, self._items = cz, objs, why, items or {}

    def _objects_run(self):
        """the objects thread: the zone's mobs looked for every OBJ_QUICK s (see the top) while anyone asks"""
        # (carried on from where it stopped when nobody asked: what it found is checked again at every read)
        regions, last_full, zone_seen, zone_from, cache = self._obj_state
        while True:
            t0 = time.monotonic()
            with self.lock:
                if t0 - self._obj_asked > OBJ_IDLE:
                    self._obj_thread = None
                    self._obj_state = (regions, last_full, zone_seen, zone_from, cache)
                    return
                st = self.st
            try:
                names = self._names() if st is not None else None
                gc = st.gameclient() if st is not None else 0
                cz = st.zone_ptr(gc) if ptr_ok(gc) else 0
                if st is None:
                    self._set_objs(0, {}, "not attached")
                elif not cz:
                    self._set_objs(0, {}, "not in a zone")
                elif names is None:
                    self._set_objs(0, {}, "the mob names couldn't be read (Root.wad)")
                else:
                    # (a new zone: its ClientZone or its name changed - the old one's may be freed and its memory
                    # given to the new one)
                    zone = (cz, st.zone(gc))
                    if zone != zone_seen:
                        zone_seen, zone_from, regions, cache = zone, t0, None, {}
                        self._set_objs(0, {}, "looking at the new zone")
                    full = (regions is None or not regions or t0 - last_full >= OBJ_FULL
                            or (t0 - zone_from < OBJ_SETTLE and t0 - last_full >= OBJ_SETTLE_EVERY))
                    found, where = st.scan_objects(cz, None if full else regions)
                    if full:
                        regions, last_full = where, t0
                    objs, items = {}, {}
                    for obj in found:
                        raw = st.p.try_read(obj, OBJ_SPAN)
                        if raw is None:
                            continue
                        vt = struct.unpack_from("<Q", raw, 0)[0]
                        vname = st.tn.of_vtable(vt) if st.m.in_section(vt, ".rdata") else None
                        if not vname or not vname.endswith("ClientObject"):
                            continue                        # (not a live one: destroyed - its base class's vtable - or freed)
                        gid = struct.unpack_from("<Q", raw, DATA["co_gid"])[0]
                        tpl = struct.unpack_from("<Q", raw, DATA["co_template"])[0]
                        k = st.template_kind(tpl, names, cache)
                        if k and k[0]:
                            objs[obj] = (gid, k[0], k[1], vt)
                        elif k and k[2]:
                            items[obj] = (gid, k[2], k[1], vt)
                    self._set_objs(cz, objs, "", items)
                    self.obj_stats = {"objects": len(found), "mobs": len(objs), "items": len(items), "full": full,
                                      "ms": round((time.monotonic() - t0) * 1000), "regions": len(regions or ())}
            except Exception as e:  # noqa: BLE001 - tried again next time
                self._set_objs(0, {}, "the zone's objects couldn't be read (%r)" % (e,))
            time.sleep(max(0.5, OBJ_QUICK - (time.monotonic() - t0)))


# ============================================================================ command line
def _main():
    import argparse
    ap = argparse.ArgumentParser(description="read-only: the wizard's position and the quest goal")
    ap.add_argument("-n", type=int, default=3)
    ap.add_argument("-i", type=float, default=0.5)
    ap.add_argument("--path", action="store_true")
    ap.add_argument("--mobs", action="store_true", help="the zone's mobs too")
    ap.add_argument("--goal", action="store_true", help="the quest's goal line too (questmem.py)")
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
            if a.mobs:
                mobs, why = nm.mobs()
                print("           mobs: %s %s" % (why or "%d" % len(mobs), nm.obj_stats))
                for mb in sorted(mobs or [], key=lambda q: math.hypot(q["pos"][0] - r["pos"][0], q["pos"][1] - r["pos"][1]) if r["pos"] else 0)[:15]:
                    off = ""
                    if mb.get("yaw") is not None and r["pos"]:
                        dx, dy = r["pos"][0] - mb["pos"][0], r["pos"][1] - mb["pos"][1]
                        c = (dx * -math.sin(mb["yaw"]) + dy * -math.cos(mb["yaw"])) / (math.hypot(dx, dy) or 1.0)
                        off = "  yaw %.2f, you %.0f deg off its facing" % (mb["yaw"], math.degrees(math.acos(max(-1.0, min(1.0, c)))))
                    print("             %-24s %-30s (%.0f, %.0f, %.0f)%s" % ((mb["name"], mb["template"]) + tuple(mb["pos"]) + (off,)))
            if a.goal:
                g, why = nm.goal(r, wait=30)
                print("           goal: " + ("%r (from %s) %s %s %s/%s mob %r item %r npc %r - %.2f ms" % (
                    g["text"], g["from"], g["type"], g["status"], g["count"], g["total"], g["mob"], g["item"], g["npc"],
                    g["ms"]) if g else "none (%s)" % why))
        if k + 1 < a.n:
            time.sleep(a.i)
    print(nm.describe())


if __name__ == "__main__":
    _main()
