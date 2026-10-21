"""Vision helper for AutoFarmer: finds cards in the hand and school badges on name plates.

AutoFarmer (AutoHotkey) starts this with pythonw and asks it over HTTP on 127.0.0.1. Instead of
ImageSearch's "found or not at this tolerance", every picture is matched at every position with a
distance (the RMS colour difference over the picture's solid pixels, see-through magenta left out), so
the best match wins and a threshold tells a real match from a near miss.

Pictures come from the same picture sets as AutoFarmer's (the main set at UI scale 1 and the ui<scale>
folders; see PicScale.ahk): each is resized from the cut set nearest above the UI size in use (a solid
<name>.raw.png next to a cut picture gives the colours to resize; the cut picture's magenta gives what to
leave out).

Requests (all GET, answers are plain text lines, "ERR <why>" on a problem):
  /ping                                   -> "OK <version>"
  /cards?x1=&y1=&x2=&y2=&scale=&pics=balance/hit1,resources/sharpen,... -> one line per card found: "dir/name|x|y|dist" (x, y = the
                                             picture's top left on screen, like ImageSearch's), best first
  /badge?x1=&y1=&x2=&y2=&scale=&schools=  -> one line per school whose badge is there: "school|x|y|dist",
                                             best first ("unclear": two schools too close at the best spot)
  /hand?x1=&y1=&x2=&y2=&scale=&pics=&learned=<id>:<set folder>:<slot>,...&here=<set folder for this size>
                                          -> one line per card in hand, left to right: "card|left|top|w|h|
                                             known picture|its dist|grey|type|type dist|pips|pips score|same|liked"
                                             (known "" = none of pics; grey 1 = greyed out, can't be cast now;
                                             type = cardicons\<type>.png that matches, "" none; pips "" unread;
                                             same = the number of an unknown card further left that
                                             it is a copy of, 0 none; liked 1 = a slot's learned picture
                                             was just written - made see-through where this copy
                                             differs, or cut at this UI size into here=<set folder> -
                                             so the plain search finds it if it looks again)
                                             &thumbs=<folder> also saves each card as it looks:
                                             <folder>\hand1.png, hand2.png... left to right (for the dashboard)
  /cut?left=&top=&scale=&out=<path>       -> saves the card at left, top: <out>.png (its picture, cut like
                                             hit1.png etc.) and .raw.png, .card.png (the whole card), .icon.png
                                             (its type icon), .pips.png (its pip cost)
  /usable?rel=balance\hit2.png            -> "1" if a cut picture big enough to use is there for it, else "0"
  /forget                                 -> reads the picture folders again (after pictures were added)
  /globes?left=&bottom=&scale=            -> "health|<n>" and "mana|<n>" off the globes at the game's bottom
                                             left (n "" if it can't be read for sure)
  /nav[?path=1][&route=1]                 -> where the wizard and its quest goal are, read from the game's memory
                                             (read-only, see vision\navmem.py), one line each:
                                               ok|1
                                               zone|<zone path, e.g. WizardCity/WC_Ravenwood>
                                               pos|x|y|z|yaw        (z up; yaw radians, forward = (-sin yaw, -cos yaw))
                                               target|x|y|z         (the node the on-screen arrow points at)
                                               goal|x|y|z|hops      (hops 0: the goal is in this zone; N: N zone changes
                                                                     away, and x|y|z is the teleporter to take here)
                                               dist|d               (the arrow's distance, along the path)
                                               quest|enabled|questid|goalid
                                               path|x,y,z;x,y,z;... (only with path=1: the game's own path over the
                                                                     zone's nav graph, from the wizard to the goal)
                                               route|x|y|left       (only with route=1: where to steer - a point ahead on
                                                                     the route planned round the walls over the zone's
                                                                     map, vision\navroute.py - and how far is left to
                                                                     walk; route|||  with routewhy|<why> when there's
                                                                     none yet: the walker steers at the target then)
                                                    |jump|jx|jy     (5-7: right at a teleport on the game's path: the
                                                                     seconds waited there, where it is)
                                                    |mob|mx|my|name (8-11: a mob on the way the route can't go round: the
                                                                     seconds waited for it to move off, where, its name)
                                             &avoid=1[&mobr=300][&shape=2][&cone=60][&goal=<the quest's goal line>] (with
                                             route=1): the route kept out of what each of the zone's mobs (navmem,
                                             read-only) sees, mobr far: shape 1 a circle all round, 2 a semi-circle in
                                             front, 3 a cone cone degrees wide in front (no shape: mobr all round and a
                                             cone= / sight= cone) - not those named in the goal line, nor (a fight
                                             goal) one by the goal
  /navto?x=&y=&z=[&avoid=1&mobr=300]      -> where the wizard is and the route to a spot of the bot's own (the potion
                                             seller): ok|1, zone|, pos|, route|x|y|left (all mobs kept away from with
                                             avoid=1)
  /snap?x1=&y1=&x2=&y2=&out=<...\Wiz-Maxxing logs\<PC>\snap_<when>.jpg>[&keep=15] -> the screen rectangle (the
                                             game: the bot checks it's on top) saved as a JPEG (half size when wider
                                             than 1600) - the log's OneDrive copy; that folder's oldest snap_*.jpg
                                             beyond keep removed: "ok|<file>" or "ERR <why>" (nowhere else: 400)
  /caught                                 -> the mob that started a battle (asked at its first round), off the mobs
                                             read lately (while walking with mob avoidance on): the one nearest the
                                             wizard, looked back to where it set off towards him (noticed him):
                                             caught|name|how far he was then|degrees off its facing then|came (1: it
                                             came for him, 0: he walked into it)|seconds before; or "none (<why>)"
  /mobs[?goal=<the quest's goal line>]    -> the zone's mobs (the game's memory, read-only), nearest first:
                                             mob|name|x|y|z|distance|quest (1: the quest's)|degrees from where it
                                             faces to the wizard (0: straight ahead of it), or "none (<why>)"
                                             A field that can't be read for sure is left empty (target|||): goal, target,
                                             dist and path while the quest helper is still on the last zone, target and
                                             dist while the arrow is behind the goal's hops. One line "ERR <why>" when the
                                             game can't be read: not running, being attached to (its code is looked through
                                             once per game process, under a second), or a signature isn't in this build
  /navmap?w=&h=&out=<png path in the AutoFarmer folder>[&span=6000]
                                          -> "ok|<out>": a w x h top-down picture of the zone round the wizard, span game
                                             units across its shorter side (+X right, +Y up): the walkable floor, obstacles
                                             and the faint nav graph (the zone's .wad, decoded once per zone - see
                                             vision\navgeo.py - and drawn in tiles that are kept), then, drawn each time,
                                             the game's path, the route planned round the walls (green, with the point
                                             it steers at), the wizard as an arrow showing its facing, the arrow's target
                                             (a ring) and the goal (a diamond; a door with the number of zone changes when
                                             it's in another zone; on the edge, pointing, when off the picture), the mobs
                                             (red dots, faint rings while the walker keeps away from them; the quest's
                                             amber; the nearest named). No zone
                                             file: the overlay on a blank background. "ERR <why>" as /nav, or when the
                                             wizard's position can't be read
  /quit                                   -> stops
Add &file=<path> to /cards, /badge, /hand or /cut to look at a saved screenshot instead of the screen (for
tests; the rectangle is then in that picture's pixels).

Only numpy and Pillow (katsuba is used for a zone .wad only if installed and the built-in reader can't read
it). Stops by itself when the AutoFarmer process (--parent <pid>) is gone.
"""
import argparse
import collections, ctypes, glob, json, math, os, re, struct, sys, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

import numpy as np
from PIL import Image

VERSION = '1'
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # the AutoFarmer folder
PORT = 47128
# A card counts as there when its RMS distance is under this (calibrated on saved rounds at UI 0.87-1.5:
# the right card 0-6.3, the closest wrong one 9 - Epic's thin strip; see vision\calibrate.py)
CARD_DIST = 8.0
# A badge: the best school's distance under BADGE_DIST and BADGE_GAP better than the next (badges share
# their gold ring, so a resized badge is never close to exact; calibrated: the right badge 0-46 at UI
# 0.87-1.5, the next school 57+)
BADGE_DIST = 50.0
BADGE_GAP = 12.0
LOG = os.path.join(ROOT, 'vision', 'vision.log')


def log(msg):
    try:
        if os.path.exists(LOG) and os.path.getsize(LOG) > 512 * 1024:
            os.replace(LOG, LOG + '.old')
        with open(LOG, 'a', encoding='utf-8') as f:
            f.write(time.strftime('%H:%M:%S ') + msg + '\n')
    except OSError:
        pass


# ---------------------------------------------------------------- pictures

def picture_sets():
    """[(dir, scale)]: the main set (UI scale 1) and every hand-cut ui<scale> folder"""
    sets = [(ROOT, 1.0)]
    for d in glob.glob(os.path.join(ROOT, 'ui*')):
        m = re.fullmatch(r'ui(\d+(?:\.\d+)?)', os.path.basename(d))
        if m and os.path.isdir(d) and 0.5 <= float(m.group(1)) <= 3:
            sets.append((d, float(m.group(1))))
    return sets


def load_rgb_mask(path):
    a = np.asarray(Image.open(path).convert('RGB')).astype(np.float32)
    mask = ~((a[..., 0] == 255) & (a[..., 1] == 0) & (a[..., 2] == 255))
    return a, mask


class Library:
    """The pictures, resized to a UI scale on first use (cached)"""

    def __init__(self):
        self.sets = picture_sets()
        self.cache = {}
        self.lock = threading.Lock()

    def names_in(self, sub):
        """picture names (without .png) in a folder of any set"""
        names = set()
        for d, sc in self.sets:
            for p in glob.glob(os.path.join(d, sub, '*.png')):
                n = os.path.basename(p)[:-4]
                if not n.endswith('.raw'):
                    names.add(n)
        return sorted(names)

    def masters(self, rel, scale):
        """cut copies of rel, best first: the smallest set at or above scale (shrinking keeps detail),
        then bigger ones, then smaller ones, biggest first"""
        have = [(d, sc) for d, sc in self.sets if os.path.exists(os.path.join(d, rel))]
        up = sorted([x for x in have if x[1] >= scale * 0.97], key=lambda x: x[1])
        down = sorted([x for x in have if x[1] < scale * 0.97], key=lambda x: -x[1])
        return up + down

    def usable(self, rel):
        """whether rel has a cut copy big enough to use (the 8x8 placeholders of 2018 aren't). The folders
        are looked at again: a picture set made since (a card learned at a new UI size) counts"""
        for d, sc in picture_sets():
            p = os.path.join(d, rel)
            if os.path.exists(p):
                with Image.open(p) as im:
                    if im.width >= 12 and im.height >= 12:
                        return True
        return False

    def get(self, rel, scale):
        """(colours HxWx3, mask HxW bool) of picture rel at UI scale, or None if it can't be had"""
        key = (rel, round(scale, 3))
        with self.lock:
            if key in self.cache:
                return self.cache[key]
        made = None
        for d, sc in self.masters(rel, scale):
            made = self.make(os.path.join(d, rel), sc, scale)
            if made is not None:
                break
        with self.lock:
            self.cache[key] = made
        return made

    @staticmethod
    def make(path, from_scale, scale):
        tpl, mask = load_rgb_mask(path)
        h, w = mask.shape
        ratio = scale / from_scale
        # a tiny patch (the 8x8 placeholders cut at UI 1 in 2018) matches almost anything: never used
        if w < 12 or h < 12:
            return None
        if abs(ratio - 1) < 0.01:
            return (tpl, mask) if mask.sum() >= 12 else None
        raw = path[:-4] + '.raw.png'
        colours = np.asarray(Image.open(raw).convert('RGB')).astype(np.float32) if os.path.exists(raw) else tpl
        if colours.shape[:2] != mask.shape:
            colours = tpl
        tw, th = max(4, round(w * ratio)), max(4, round(h * ratio))
        m = mask.astype(np.float32)
        # colours: area average of the solid pixels only; mask: pixels that were (nearly) all solid
        num = np.stack([np.asarray(Image.fromarray(colours[..., c] * m).resize((tw, th), Image.BOX)) for c in range(3)], -1)
        den = np.asarray(Image.fromarray(m).resize((tw, th), Image.BOX))
        out = num / np.maximum(den, 1e-6)[..., None]
        keep = den >= 0.75
        # (the picture's own edge pixels mix with whatever is round it on screen)
        keep[0, :] = keep[-1, :] = False
        keep[:, 0] = keep[:, -1] = False
        if keep.sum() < 12:
            return None
        return out.astype(np.float32), keep


# ---------------------------------------------------------------- matching

def fast_len(n):
    """the smallest size >= n made of 2s, 3s and 5s (an FFT of such a size is quick; a big prime factor,
    e.g. 916 = 4 x 229, makes it slow)"""
    m = n
    while True:
        k = m
        for f in (2, 3, 5):
            while k % f == 0:
                k //= f
        if k == 1:
            return m
        m += 1


class Region:
    """A piece of screen, ready to have pictures matched against it (its FFTs, at a quick size, kept).
    The pictures' FFTs at that size are kept too (TPL_FFT), so after the first look a picture costs one
    multiply and one inverse FFT"""

    def __init__(self, img):
        self.img = img
        self.H, self.W = img.shape[:2]
        self.s = (fast_len(self.H), fast_len(self.W))
        self.fi = [np.fft.rfft2(img[..., c], s=self.s) for c in range(3)]
        self.fi2 = np.fft.rfft2((img ** 2).sum(axis=2), s=self.s)

    def distance_map(self, tpl, mask, key=None):
        """RMS colour distance over the mask at every position where the picture fits (top left). key: a
        name for the picture's FFTs to be kept under (None: not kept)"""
        th, tw = mask.shape
        if th > self.H or tw > self.W:
            return None
        ck = (key, self.s) if key is not None else None
        parts = tpl_cached(ck) if ck else None
        if parts is None:
            m = mask.astype(np.float32)
            tp = tpl.astype(np.float32)
            fm = np.conj(np.fft.rfft2(m, s=self.s)).astype(np.complex64)
            fmt = [np.conj(np.fft.rfft2(m * tp[..., c], s=self.s)).astype(np.complex64) for c in range(3)]
            const = float(sum((m.astype(np.float64) * tp[..., c].astype(np.float64) ** 2).sum() for c in range(3)))
            parts = (fm, fmt, const, float(m.sum()))
            if ck:
                tpl_keep(ck, parts)
        fm, fmt, const, count = parts
        acc = self.fi2 * fm - 2 * (self.fi[0] * fmt[0] + self.fi[1] * fmt[1] + self.fi[2] * fmt[2])
        d = np.fft.irfft2(acc, s=self.s)[:self.H - th + 1, :self.W - tw + 1] + const
        return np.sqrt(np.maximum(d, 0) / (3 * count))


# The pictures' FFTs, by (picture, UI scale, FFT size), least recently used first. Each is the size of
# the screen rectangle it was made for (a badge on the hitter strip: ~15 MB), so past TPL_BUDGET bytes
# the oldest go - a new window size or UI scale would otherwise add a full set every time
TPL_FFT = collections.OrderedDict()
TPL_BYTES = 0
TPL_BUDGET = 200 * 2 ** 20
TPL_LOCK = threading.Lock()


def tpl_cached(ck):
    with TPL_LOCK:
        parts = TPL_FFT.get(ck)
        if parts is not None:
            TPL_FFT.move_to_end(ck)
        return parts


def tpl_keep(ck, parts):
    global TPL_BYTES
    size = parts[0].nbytes + sum(a.nbytes for a in parts[1])
    with TPL_LOCK:
        if ck in TPL_FFT:
            return
        TPL_FFT[ck] = parts
        TPL_BYTES += size
        while TPL_BYTES > TPL_BUDGET and len(TPL_FFT) > 1:
            _, old = TPL_FFT.popitem(last=False)
            TPL_BYTES -= old[0].nbytes + sum(a.nbytes for a in old[1])


def local_minima(dmap, limit, size):
    """(x, y, dist) of every position under limit that is the best within size (w, h) round it"""
    ys, xs = np.nonzero(dmap < limit)
    if not len(ys):
        return []
    order = np.argsort(dmap[ys, xs])
    taken, out = [], []
    w, h = size
    for i in order:
        x, y = int(xs[i]), int(ys[i])
        if any(abs(x - tx) < w and abs(y - ty) < h for tx, ty in taken):
            continue
        taken.append((x, y))
        out.append((x, y, float(dmap[y, x])))
    return out


def grab_screen(x1, y1, x2, y2):
    """the screen rectangle as HxWx3 RGB floats, copied with GDI (only that rectangle)"""
    w, h = x2 - x1, y2 - y1
    u32, g32 = ctypes.windll.user32, ctypes.windll.gdi32
    vp = ctypes.c_void_p
    u32.GetDC.restype = vp; u32.GetDC.argtypes = [vp]
    u32.ReleaseDC.argtypes = [vp, vp]
    g32.CreateCompatibleDC.restype = vp; g32.CreateCompatibleDC.argtypes = [vp]
    g32.CreateDIBSection.restype = vp
    g32.CreateDIBSection.argtypes = [vp, vp, ctypes.c_uint, ctypes.POINTER(vp), vp, ctypes.c_uint]
    g32.SelectObject.restype = vp; g32.SelectObject.argtypes = [vp, vp]
    g32.BitBlt.argtypes = [vp, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, vp, ctypes.c_int, ctypes.c_int, ctypes.c_uint]
    g32.DeleteObject.argtypes = [vp]; g32.DeleteDC.argtypes = [vp]
    bmi = (ctypes.c_uint32 * 10)()
    bmi[0] = 40
    bmi[1] = ctypes.c_uint32(w).value
    bmi[2] = ctypes.c_uint32(-h & 0xFFFFFFFF).value    # top-down rows
    bmi[3] = 1 | (32 << 16)                            # 1 plane, 32 bits
    sdc = u32.GetDC(None)
    mdc = g32.CreateCompatibleDC(sdc)
    bits = vp()
    hbm = g32.CreateDIBSection(mdc, ctypes.addressof(bmi), 0, ctypes.byref(bits), None, 0)
    try:
        if not hbm or not bits.value:
            raise OSError('CreateDIBSection failed')
        old = g32.SelectObject(mdc, hbm)
        g32.BitBlt(mdc, 0, 0, w, h, sdc, x1, y1, 0x00CC0020)
        buf = ctypes.string_at(bits.value, w * h * 4)
        g32.SelectObject(mdc, old)
    finally:
        if hbm:
            g32.DeleteObject(hbm)
        g32.DeleteDC(mdc)
        u32.ReleaseDC(None, sdc)
    return np.frombuffer(buf, np.uint8).reshape(h, w, 4)[..., 2::-1].astype(np.float32)


def snap_out_ok(out):
    """/snap writes only snap_<...>.jpg into a "Wiz-Maxxing logs\\<PC>" folder"""
    out = os.path.normpath(out)
    d = os.path.dirname(out)
    return (bool(re.match(r'^snap_[\w.-]+\.jpg$', os.path.basename(out), re.I))
            and os.path.basename(os.path.dirname(d)).lower() == 'wiz-maxxing logs' and os.path.isabs(out))


def snap(x1, y1, x2, y2, out, keep=15):
    """/snap: the screen rectangle into out (JPEG, half size when wider than 1600); the newest keep snap_*.jpg kept
    (by their time on disk)"""
    if x2 <= x1 or y2 <= y1:
        raise ValueError('an empty rectangle')
    a = grab_screen(x1, y1, x2, y2)
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    if im.width > 1600:
        im = im.resize((im.width // 2, im.height // 2), Image.BILINEAR)
    d = os.path.dirname(out)
    os.makedirs(d, exist_ok=True)
    im.save(out + '.tmp', 'JPEG', quality=70)
    os.replace(out + '.tmp', out)
    if keep > 0:
        for f in sorted(glob.glob(os.path.join(d, 'snap_*.jpg')), key=os.path.getmtime)[:-keep]:
            try:
                os.remove(f)
            except OSError:
                pass
    return out


def grab(x1, y1, x2, y2, file=None):
    if file:
        return np.asarray(Image.open(file).convert('RGB').crop((x1, y1, x2, y2))).astype(np.float32)
    return grab_screen(x1, y1, x2, y2)


LIB = None


def find_cards(x1, y1, x2, y2, scale, pics, file=None, missing=None):
    """where the card pictures pics ("dir/name", e.g. "balance/hit1") are in the rectangle: [(pic, x, y,
    dist)], best first. Where two pictures claim the same card, the closer one keeps it. missing (a list):
    gets the pictures that have a real cut copy but couldn't be looked for (it couldn't be made at this
    size, or it's bigger than the rectangle) - a picture with none (an 8x8 placeholder) is just absent"""
    region = Region(grab(x1, y1, x2, y2, file))
    found = []
    for want in pics:
        if '/' not in want:
            continue
        sub, name = want.split('/', 1)
        pic = LIB.get(f'{sub}\\{name}.png', scale)
        if pic is None:
            if missing is not None and LIB.usable(f'{sub}\\{name}.png'):
                missing.append(want)
            continue
        tpl, mask = pic
        dmap = region.distance_map(tpl, mask, (want, round(scale, 3)))
        if dmap is None:
            if missing is not None:
                missing.append(want)
            continue
        for x, y, dist in local_minima(dmap, CARD_DIST, (tpl.shape[1], tpl.shape[0])):
            found.append((want, x + x1, y + y1, dist, tpl.shape[1], tpl.shape[0]))
    found.sort(key=lambda f: f[3])
    kept = []
    for f in found:
        # the same spot (a card is about 3 pictures wide) taken by a better match already? (a learned
        # picture - cut from the whole card picture, so often the closer - never hides a hand-cut one)
        if any(abs(f[1] - k[1]) < max(f[4], k[4]) * 0.8 and abs(f[2] - k[2]) < max(f[5], k[5]) and f[0] != k[0]
               and not (k[0].startswith('learned/') and not f[0].startswith('learned/')) for k in kept):
            continue
        kept.append(f)
    return [(f[0], f[1], f[2], f[3]) for f in kept]


def round_only(mask):
    """a badge is round: its square picture's corners show whatever is behind the name plate"""
    h, w = mask.shape
    yy, xx = np.mgrid[0:h, 0:w]
    r = min(h, w) / 2 - 1
    return mask & ((xx + 0.5 - w / 2) ** 2 + (yy + 0.5 - h / 2) ** 2 <= r * r)


def find_badges(x1, y1, x2, y2, scale, schools, file=None):
    """the badges in the rectangle that are clearly one school: each school's best spot, kept if it's
    under BADGE_DIST, BADGE_GAP better than every other school's best at the same spot (badges share
    their gold ring, so a resized one is never close to exact - the ranking is what tells them apart).
    A team battle shows several plates: real badges came to 0-49, a school's best on no badge 55+.
    [(school, x, y, dist)] best first; [] none; None: the best spot is unclear (two schools too close)"""
    region = Region(grab(x1, y1, x2, y2, file))
    out = []
    for sch in schools:
        pic = LIB.get(f'{sch}\\{sch}.png', scale)
        if pic is None:
            continue
        tpl, mask = pic
        dmap = region.distance_map(tpl, round_only(mask), ('badge ' + sch, round(scale, 3)))
        if dmap is None:
            continue
        y, x = np.unravel_index(np.argmin(dmap), dmap.shape)
        out.append((sch, int(x) + x1, int(y) + y1, float(dmap[y, x]), tpl.shape[1], tpl.shape[0]))
    out.sort(key=lambda f: f[3])
    log('  badges: ' + (', '.join(f'{o[0]} {o[3]:.1f} at {o[1]},{o[2]}' for o in out) or 'none to compare'))
    kept = []
    for s in out:
        if s[3] >= BADGE_DIST:
            break
        rivals = [r for r in out if r is not s and abs(r[1] - s[1]) < s[4] and abs(r[2] - s[2]) < s[5]]
        if any(r[3] - s[3] < BADGE_GAP for r in rivals):
            if not kept and not any(r[3] < s[3] for r in rivals):
                return None
            continue
        kept.append(s)
    return [k[:4] for k in kept]


# ---------------------------------------------------------------- the hand, card by card

# A card in hand, in UI-scale-1 pixels (measured at UI 1.144 / 1440p: 81 x 135 px, 93.84 px apart, top
# 64 px above the middle of the screen)
CARD_W, CARD_H, CARD_PITCH, CARD_TOP = 70.8, 118.0, 82.03, -55.94
# from the card's top left: the picture cut for it (as hit1.png etc. were cut), the type icon's box (the
# cardicons pictures are cut from 1 px inside it), the pip cost's digit (in here), the part that's grey
# when the card is greyed out
ART_BOX = (19.23, 25.35, 28.85, 21.85)
ICON_BOX = (54.2, 55.9, 14.9, 14.9)
DIGIT_BOX = (3.5, 15.7, 12.2, 14.0)
GREY_BOX = (8.0, 18.0, 52.0, 34.0)
# A type icon matches under ICON_DIST, ICON_GAP better than the next type (saved rounds at UI 0.87-1.5:
# the right icon 0-36, a wrong one 42+); a digit with at least
# DIGIT_IOU of its pixels in common with the cut one (and DIGIT_GAP more than the next; at UI 1.144 the
# right digit 0.62+, a wrong one 0.55 at most - at other sizes the 8 px digits often go unread)
ICON_DIST, ICON_GAP = 40.0, 8.0
DIGIT_IOU, DIGIT_GAP = 0.6, 0.1


def box(b, sc, left, top):
    """a card box (UI-1 pixels from the card's top left) as integer x1, y1, x2, y2 at scale sc"""
    x, y, w, h = b
    return (int(round(left + x * sc)), int(round(top + y * sc)), int(round(left + (x + w) * sc)), int(round(top + (y + h) * sc)))


def card_lefts(img, sc, expect_top):
    """the cards' left edges and top in img (the hand rectangle) from the cards' top edges: (top, [left])"""
    H, W = img.shape[:2]
    cw, pitch = CARD_W * sc, CARD_PITCH * sc
    g = np.abs(np.diff(img.sum(axis=2), axis=0)) > 90           # row r -> r + 1 changes sharply
    t0 = int(round(expect_top))
    top, best = t0, -1.0
    for r in range(max(1, t0 - 8), min(H - 1, t0 + 9)):
        v = g[r - 1].mean()
        if v > best:
            best, top = v, r
    on = g[max(0, top - 4):top + 2].any(axis=0)
    k = max(1, round(3 * sc))
    on = np.convolve(on.astype(float), np.ones(2 * k + 1), 'same') > 0
    starts, x = [], 0
    while x < W:
        if not on[x]:
            x += 1
            continue
        s = x
        while x < W and on[x]:
            x += 1
        s, e = s + k, x - k
        if e - s < cw * 0.8:
            continue
        # touching cards (no gap seen between them): split by the pitch
        for i in range(max(1, round((e - s + pitch - cw) / pitch))):
            starts.append(s + i * pitch)
    return top, starts


def grid(starts, pitch, anchors=()):
    """the lefts on one grid (cards are exactly pitch apart): its phase from anchors (lefts known exactly,
    from known pictures) if any, else from starts"""
    pts = list(anchors) or list(starts)
    if not pts:
        return []
    base = pts[0]
    phase = base + float(np.median([(p - base) - round((p - base) / pitch) * pitch for p in pts]))
    ks = sorted(set(round((p - phase) / pitch) for p in list(starts) + list(anchors)))
    return [phase + k * pitch for k in ks]


def fit_lefts(img, lefts, sc, top):
    """the lefts moved together (within 5 px) to where the cards' left edges change most sharply"""
    if not lefts:
        return lefts
    g = np.abs(np.diff(img.sum(axis=2), axis=1))
    ya, yb = int(top + 10 * sc), int(top + (CARD_H - 10) * sc)
    best = (-1.0, 0.0)
    for off in np.arange(-5, 5.01, 0.5):
        s = 0.0
        for left in lefts:
            x = int(round(left + off)) - 1
            if 0 <= x < g.shape[1]:
                s += float(g[ya:yb, x].mean())
        if s > best[0]:
            best = (s, float(off))
    return [left + best[1] for left in lefts]


def yellow(p):
    """the pip digit's pixels: bright yellow (the art's tan has G well under R)"""
    r, g, b = p[..., 0], p[..., 1], p[..., 2]
    return (r > 130) & (g > 0.9 * r) & (b < 0.45 * r)


def digit_masks(sc):
    """the cut pip digits at scale sc: {digit: bool mask cropped to the digit}"""
    out = {}
    for d, dsc in LIB.sets:
        for p in glob.glob(os.path.join(d, 'carddigits', '*.png')):
            n = os.path.basename(p)[:-4]
            if n.endswith('.raw') or n.startswith('unknown') or n in out:
                continue
            a, m = load_rgb_mask(p)
            if abs(sc / dsc - 1) >= 0.01:
                h, w = m.shape
                m = np.asarray(Image.fromarray(m.astype(np.uint8) * 255).resize((max(1, round(w * sc / dsc)), max(1, round(h * sc / dsc))), Image.BILINEAR)) > 127
            out[n] = m
    return out


def read_digit(patch, masks):
    """(digit, score) of the pip cost in patch: each cut digit slid over the patch's yellow pixels, scored
    by how many it shares with them over all of both (so a 1 inside a 4 scores low). ("", best score) if
    none matches clearly"""
    m = yellow(patch)
    total = int(m.sum())
    if total < 4:
        return '', 0.0
    H, W = m.shape
    scores = []
    for d, t in masks.items():
        th, tw = t.shape
        best = 0.0
        tn = int(t.sum())
        for y in range(0, max(1, H - th + 1)):
            for x in range(0, max(1, W - tw + 1)):
                win = m[y:y + th, x:x + tw]
                if win.shape != t.shape:
                    continue
                both = int((win & t).sum())
                best = max(best, both / (tn + total - both))
        scores.append((best, d))
    scores.sort(reverse=True)
    if not scores or scores[0][0] < DIGIT_IOU or (len(scores) > 1 and scores[0][0] - scores[1][0] < DIGIT_GAP):
        return '', scores[0][0] if scores else 0.0
    return scores[0][1], scores[0][0]


def read_icon(img, sc, left, top):
    """(type, dist) of the card's type icon: the best cardicons picture within 4 px of where it should be"""
    x1, y1, x2, y2 = box(ICON_BOX, sc, left, top)
    pad = max(3, round(4 * sc))
    H, W = img.shape[:2]
    x1, y1, x2, y2 = max(0, x1 - pad), max(0, y1 - pad), min(W, x2 + pad + 2), min(H, y2 + pad + 2)
    if x2 - x1 < 8 or y2 - y1 < 8:
        return '', 99.0
    region = Region(img[y1:y2, x1:x2])
    out = []
    for n in LIB.names_in('cardicons'):
        if n.startswith('unknown'):
            continue
        pic = LIB.get(f'cardicons\\{n}.png', scale_key(sc))
        if pic is None:
            continue
        tpl, mask = pic
        dmap = region.distance_map(tpl, mask)
        if dmap is None:
            continue
        out.append((float(dmap.min()), n))
    out.sort()
    if not out or out[0][0] >= ICON_DIST or (len(out) > 1 and out[1][0] - out[0][0] < ICON_GAP):
        return '', out[0][0] if out else 99.0
    return out[0][1], out[0][0]


def scale_key(sc):
    return round(sc, 3)


def is_grey(img, sc, left, top):
    """greyed out (can't be cast now): nearly all of the card's middle has no colour"""
    x1, y1, x2, y2 = box(GREY_BOX, sc, left, top)
    p = img[max(0, y1):y2, max(0, x1):x2]
    if p.size == 0:
        return False
    return float(((p.max(axis=2) - p.min(axis=2)) <= 6).mean()) > 0.85


def read_hand(x1, y1, x2, y2, scale, pics, file=None, learned=None, here='', thumbs=''):
    """the cards in hand, left to right (see /hand). learned: the learned cards ("<id>:<picture set
    folder>:<slot>"), each also recognised as a copy that differs a little. here: the picture set folder
    for this UI size (a card learned at another size is cut into it)"""
    img = grab(x1, y1, x2, y2, file)
    known = find_cards(x1, y1, x2, y2, scale, pics, file)
    pitch, cw, ch = CARD_PITCH * scale, CARD_W * scale, CARD_H * scale
    # the hand's height is fixed (y1 is ScreenY - 75 UI px, as AutoFarmer asks); the cards' lefts come
    # from their top edges, on one grid, then fitted to their left edges (the hand-cut pictures sit at
    # different places on their cards, so they can't place a card)
    top = int(round((75 + CARD_TOP) * scale))
    starts = card_lefts(img, scale, top)[1]
    lefts = fit_lefts(img, grid(starts, pitch), scale, top)
    masks = digit_masks(scale)
    cards = []
    for left in lefts:
        if left < -cw * 0.2 or left + cw > img.shape[1] + cw * 0.2:
            continue
        mine = [k for k in known if left - 0.15 * cw <= k[1] - x1 <= left + 0.85 * cw]
        # (a hand-cut or slot picture names the card before a learned one of the same card)
        mine = [k for k in mine if not k[0].startswith('learned/')] or mine
        best = min(mine, key=lambda k: k[3]) if mine else None
        kind, kd = read_icon(img, scale, left, top)
        dx1, dy1, dx2, dy2 = box(DIGIT_BOX, scale, left, top)
        pips, ps = read_digit(img[max(0, dy1):dy2, max(0, dx1):dx2], masks)
        cards.append(dict(left=int(round(left)) + x1, top=top + y1, w=int(round(cw)), h=int(round(ch)),
                          known=best[0] if best else '', kdist=best[3] if best else 0.0,
                          grey=is_grey(img, scale, left, top), kind=kind, kinddist=kd, pips=pips, pipscore=ps,
                          art=img[max(0, box(ART_BOX, scale, left, top)[1]):box(ART_BOX, scale, left, top)[3],
                                  max(0, box(ART_BOX, scale, left, top)[0]):box(ART_BOX, scale, left, top)[2]]))
    # Copies of a card differ a little (a shimmer: a few variants, 0-17 apart over the whole picture), so a
    # learned picture - cut solid from one copy - is compared leaving out the 20% of pixels that differ
    # most (LIKE_DIST); each time another copy is seen like that, the pixels that differ go see-through in
    # the learned picture (and its slot's copy), until it matches every copy as a hand-cut one does
    # A card learned at another UI size: its picture resized doesn't match closely enough, so this copy is
    # cut into the picture set for this size (here) - its learned picture and its slot's.
    # liked 1 = a slot's picture was just written (made see-through, or cut at this size): the battle's own
    # search finds the card if it looks again
    for i, c in enumerate(cards):
        c['same'], c['liked'] = 0, 0
        if c['known'] or c['grey'] or c['art'].size == 0:
            continue
        bx1, by1, bx2, by2 = box(ART_BOX, scale, c['left'] - x1, c['top'] - y1)
        around = img[max(0, by1 - LIKE_PAD):by2 + LIKE_PAD, max(0, bx1 - LIKE_PAD):bx2 + LIKE_PAD]
        for ent in learned or ():
            pic = learned_pic(ent, scale, here)
            if pic is None:
                continue
            d, (dy, dx), diff = like(around, pic['tpl'], pic['mask'])
            if d < LIKE_DIST:
                c['known'], c['kdist'] = pic['name'], d
                if pic['files']:
                    c['liked'] = int(refine(pic, diff) and pic['slot'] != '')
                elif here:
                    h, w = pic['mask'].shape
                    c['liked'] = int(cut_here(around[dy:dy + h, dx:dx + w], pic, here))
                break
        # (or a card the bot has a picture for that the plain match missed: never learned twice. A
        # hand-cut picture can be anywhere on its card: its best place by the plain match, then compared
        # there leaving out the pixels that differ most)
        if not c['known']:
            L, T = c['left'] - x1, c['top'] - y1
            whole = img[max(0, T):T + int(round(ch)), max(0, L):L + int(round(cw))]
            region = Region(whole)
            for want in pics:
                if '/' not in want or want.startswith('learned/'):
                    continue
                sub, name = want.split('/', 1)
                pic = LIB.get(f'{sub}{os.sep}{name}.png', scale)
                if pic is None:
                    continue
                dmap = region.distance_map(pic[0], pic[1])
                if dmap is None:
                    continue
                py, px = np.unravel_index(np.argmin(dmap), dmap.shape)
                h, w = pic[1].shape
                d = like(whole[max(0, py - 1):py + h + 1, max(0, px - 1):px + w + 1], pic[0], pic[1])[0]
                if d < LIKE_CUT:
                    c['known'], c['kdist'] = want, d
                    break
        if c['known']:
            continue
        # the same as a card further left nobody knows (two copies in hand): same = that one's number
        # (1 = the leftmost), so it isn't learned twice
        for j in range(i):
            o = cards[j]
            if o['known'] or o['grey'] or o['art'].size == 0:
                continue
            if like(around, o['art'], np.ones(o['art'].shape[:2], bool))[0] < LIKE_DIST:
                c['same'] = o['same'] or j + 1
                break
    # each card as it looks, for the dashboard (thumbs: a folder)
    if thumbs:
        os.makedirs(thumbs, exist_ok=True)
        cw_i, ch_i = int(round(cw)), int(round(ch))
        for i, c in enumerate(cards, 1):
            L, T = c['left'] - x1, c['top'] - y1
            whole = img[max(0, T):T + ch_i, max(0, L):L + cw_i]
            if whole.size:
                Image.fromarray(np.clip(whole, 0, 255).astype(np.uint8)).save(os.path.join(thumbs, f'hand{i}.png'))
    return cards


# Two copies of the same card: under LIKE_DIST with the 20% of pixels that differ most left out (saved
# rounds: the same card 0-19, another card 37+), looked for within LIKE_PAD px; a pixel that differs by
# more than LIKE_PIXEL goes see-through in the learned picture (so the plain match, under CARD_DIST over the
# pixels left, finds the next copy like this one)
LIKE_DIST, LIKE_PAD, LIKE_PIXEL = 27.0, 3, 10.0
# A hand-cut picture (its shimmering pixels already see-through): under LIKE_CUT that way (another card
# came to 26 against a thin, resized one)
LIKE_CUT = 15.0


def like(around, tpl, mask):
    """(distance leaving out the worst 20% of pixels, (dy, dx), each pixel's distance there) of picture tpl
    (solid where mask) at its best place in around"""
    H, W = around.shape[:2]
    h, w = tpl.shape[:2]
    best = (1e9, (0, 0), None)
    if mask.sum() < 12:
        return best
    for dy in range(H - h + 1):
        for dx in range(W - w + 1):
            per = np.sqrt(((around[dy:dy + h, dx:dx + w] - tpl) ** 2).mean(axis=2))
            d = np.sort(per[mask])
            v = float(np.sqrt((d[:max(1, int(len(d) * 0.8))] ** 2).mean()))
            if v < best[0]:
                best = (v, (dy, dx), per)
    return best


def set_scale(setdir):
    """a picture set folder's UI scale (ui1.144 -> 1.144; the main set 1)"""
    m = re.fullmatch(r'ui(\d+(?:\.\d+)?)', os.path.basename(setdir))
    return float(m.group(1)) if m else 1.0


def same_picture(a, b):
    """two picture files with the same pixels"""
    try:
        return np.array_equal(np.asarray(Image.open(a).convert('RGB')), np.asarray(Image.open(b).convert('RGB')))
    except OSError:
        return False


def learned_pic(ent, scale, here=''):
    """a learned card from /hand's learned= list ("<id>:<picture set folder>:<slot>", slot e.g.
    balance\\hit1 or blank) at UI scale: {tpl, mask, name it's known by, files (written when it's made
    see-through: [] when the picture is from another size, resized), cid, slot, setdir}. A copy cut at this
    size into here (the picture set for it) comes first. The slot counts only while its picture is still
    this card's (else the card is known by its own name, learned/<id>, and the slot is left alone)"""
    try:
        cid, setdir, slot = ent.split(':', 2)
    except ValueError:
        return None
    # (still its slot's card where it was learned?)
    if slot and not same_picture(os.path.join(ROOT, setdir, slot + '.png'), os.path.join(ROOT, setdir, 'learned', cid + '.png')):
        slot = ''
    if here and abs(scale / set_scale(here) - 1) < 0.01 and os.path.exists(os.path.join(ROOT, here, 'learned', cid + '.png')):
        setdir = here
    base = os.path.join(ROOT, setdir, 'learned', cid)
    if not os.path.exists(base + '.png'):
        return None
    slotfile = os.path.join(ROOT, setdir, slot + '.png') if slot else ''
    if slotfile and not same_picture(slotfile, base + '.png'):
        slotfile = ''
    name = slot.replace('\\', '/') if slot else 'learned/' + cid
    if abs(scale / set_scale(setdir) - 1) >= 0.01:
        pic = LIB.get(os.path.join('learned', cid + '.png'), scale)
        if pic is None:
            return None
        return dict(tpl=pic[0], mask=pic[1], name=name, files=[], cid=cid, slot=slot, setdir=setdir)
    tpl, mask = load_rgb_mask(base + '.png')
    return dict(tpl=tpl, mask=mask, name=name, files=[base + '.png'] + ([slotfile] if slotfile else []), cid=cid, slot=slot, setdir=setdir)


def pictures_changed():
    """picture files were written: the folders and every resized picture are looked at again"""
    with LIB.lock:
        LIB.sets = picture_sets()
        LIB.cache.clear()
    with TPL_LOCK:
        TPL_FFT.clear()
        globals()['TPL_BYTES'] = 0


def refine(pic, diff):
    """the pixels that differ in this copy go see-through in the learned picture (and its slot's copy) -
    unless too little would be left to tell the card apart. True if it wrote them"""
    if not pic['files'] or diff is None:
        return False
    tpl, mask = pic['tpl'], pic['mask']
    keep = mask & (diff <= LIKE_PIXEL)
    if keep.sum() == mask.sum() or keep.sum() < max(12, 0.1 * keep.size):
        return False
    out = tpl.astype(np.uint8).copy()
    out[~keep] = (255, 0, 255)
    for f in pic['files']:
        if os.path.exists(f):
            Image.fromarray(out).save(f)
    pictures_changed()
    log(f"  {pic['name']}: {int(mask.sum() - keep.sum())} pixels that differ between copies made see-through ({int(keep.sum())} of {keep.size} left)")
    return True


def cut_here(art, pic, here):
    """a learned card seen at a UI size it wasn't learned at: this copy (art, as big as its resized
    picture) saved into the picture set for this size, here - as its learned picture, and as its slot's if
    that set has none. True if the slot's picture was written"""
    dest = os.path.join(ROOT, here)
    os.makedirs(os.path.join(dest, 'learned'), exist_ok=True)
    a = Image.fromarray(np.clip(art, 0, 255).astype(np.uint8))
    for ext in ('.png', '.raw.png'):
        a.save(os.path.join(dest, 'learned', pic['cid'] + ext))
    slot_done = False
    if pic['slot'] and not os.path.exists(os.path.join(dest, pic['slot'] + '.png')):
        os.makedirs(os.path.dirname(os.path.join(dest, pic['slot'] + '.png')), exist_ok=True)
        for ext in ('.png', '.raw.png'):
            a.save(os.path.join(dest, pic['slot'] + ext))
        slot_done = True
    pictures_changed()
    log(f"  {pic['name']}: learned at another UI size - this copy cut into {here}" + (f" (and as {pic['slot']})" if slot_done else ''))
    return slot_done


def cut_card(left, top, scale, out, file=None):
    """saves the card whose top left is at left, top (screen): see /cut"""
    cw, ch = CARD_W * scale, CARD_H * scale
    pad = round(2 * scale)
    gx1, gy1 = int(left) - pad, int(top) - pad
    img = grab(gx1, gy1, int(round(left + cw)) + pad, int(round(top + ch)) + pad, file)
    lx, ly = left - gx1, top - gy1
    os.makedirs(os.path.dirname(out), exist_ok=True)
    save = lambda a, p: Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(p)
    ax1, ay1, ax2, ay2 = box(ART_BOX, scale, lx, ly)
    save(img[ay1:ay2, ax1:ax2], out + '.png')
    save(img[ay1:ay2, ax1:ax2], out + '.raw.png')
    save(img[pad:pad + int(round(ch)), pad:pad + int(round(cw))], out + '.card.png')
    ix1, iy1, ix2, iy2 = box(ICON_BOX, scale, lx, ly)
    save(img[iy1 - 1:iy2 + 2, ix1 - 1:ix2 + 2], out + '.icon.png')
    dx1, dy1, dx2, dy2 = box(DIGIT_BOX, scale, lx, ly)
    save(img[dy1:dy2, dx1:dx2], out + '.pips.png')
    return out


# ---------------------------------------------------------------- the health and mana globes

# Where the numbers on the globes are, in UI-scale-1 pixels from the game's bottom left: (x, how far up
# their top is, w, h) - measured at UI 1.144 / 1440p
GLOBE_HEALTH = (24.0, 131.0, 100.0, 34.0)
GLOBE_MANA = (118.0, 92.0, 46.0, 30.0)
# a digit is the cut one it's closest to, if under this (mean pixel difference at 10 x 14, plus half the
# width/height ratio's difference); saved shots: right 0-0.2, wrong 0.3+
GLOBE_DIGIT = 0.3
GLOBE_NORM = (10, 14)


def globe_digits():
    """the cut globe digits: [(digit, normalised picture, width/height)]"""
    out = []
    for d, sc in LIB.sets:
        for p in sorted(glob.glob(os.path.join(d, 'globedigits', '*.png'))):
            m = np.asarray(Image.open(p).convert('L')) > 127
            if m.any():
                out.append((os.path.basename(p)[0], np.asarray(Image.fromarray(m.astype(np.uint8) * 255).resize(GLOBE_NORM, Image.BILINEAR)) / 255.0, m.shape[1] / m.shape[0]))
    return out


def read_number(a, cut):
    """the yellow number in picture a ("" if a digit isn't clear): digits split by empty columns"""
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    m = (r > 190) & (g > 0.82 * r) & (b < 0.55 * r)
    cols = m.any(axis=0)
    text, x = '', 0
    while x < m.shape[1]:
        if not cols[x]:
            x += 1
            continue
        s = x
        while x < m.shape[1] and cols[x]:
            x += 1
        blob = m[:, s:x]
        ys = np.nonzero(blob.any(axis=1))[0]
        blob = blob[ys.min():ys.max() + 1]
        # (specks of the background, and anything as tall as the whole box isn't a digit)
        if blob.shape[0] < 0.3 * m.shape[0] or blob.sum() < 8 or blob.shape[0] >= m.shape[0] - 1:
            continue
        n = np.asarray(Image.fromarray(blob.astype(np.uint8) * 255).resize(GLOBE_NORM, Image.BILINEAR)) / 255.0
        ar = blob.shape[1] / blob.shape[0]
        best = min(((np.abs(n - t).mean() + abs(ar - tar) * 0.5, d) for d, t, tar in cut), default=(9, ''))
        if best[0] >= GLOBE_DIGIT:
            return ''
        text += best[1]
    return text if 0 < len(text) <= 5 else ''


def read_globes(left, bottom, scale, file=None):
    """(health, mana) off the globes ("" for one that can't be read)"""
    cut = globe_digits()
    out = []
    for gx, gtop, gw, gh in (GLOBE_HEALTH, GLOBE_MANA):
        x1, y1 = int(round(left + gx * scale)), int(round(bottom - gtop * scale))
        x2, y2 = int(round(left + (gx + gw) * scale)), int(round(bottom - (gtop - gh) * scale))
        out.append(read_number(grab(x1, y1, x2, y2, file).astype(int), cut))
    return out


# ---------------------------------------------------------------- walking: the game's memory and the zone map

# Where the wizard and the quest goal are comes from the game's memory, read-only (vision\navmem.py: it opens
# the game with PROCESS_VM_READ | PROCESS_QUERY_INFORMATION and only ever calls ReadProcessMemory on it); the
# zone's floor, obstacles and nav graph from its .wad (vision\navgeo.py). Both are imported on the first
# /nav or /navmap, so nothing else here depends on them
NAV = None
NAV_LOCK = threading.Lock()
NAV_SPAN = 6000.0           # /navmap: game units across the picture's shorter side
NAV_TILE = 256              # the static layers are drawn in tiles this many pixels square, kept per zone and scale
NAV_SS = 2                  # drawn this many times bigger, then shrunk (smooth edges)
NAV_TILES_KEPT = 64         # tiles kept, all zones (64 x 192 KB)
NAV_ZONES_KEPT = 3
# colours, to sit on the dashboard (1B1D22 / 111317, accent 8AB4F8)
MAP_BG = (17, 19, 23)
MAP_FLOOR = (44, 48, 56)
MAP_FLOOR_LOW = (34, 38, 46)        # the floor shaded by height: the zone's lowest...
MAP_FLOOR_HIGH = (104, 112, 130)    # ...and highest (a dais, a ramp, a balcony stand out)
MAP_RIM = (72, 78, 90)
MAP_WATER = (28, 52, 74)
MAP_OBST = (204, 112, 74)
MAP_NAV = (138, 180, 248)
MAP_PATH = (138, 180, 248)
MAP_TARGET = (242, 193, 78)
MAP_GOAL = (123, 216, 143)
MAP_ROUTE = (110, 231, 183)
MAP_DOOR = (197, 138, 249)
MAP_ME = (242, 242, 242)
MAP_TEXT = (154, 160, 166)
MAP_MOB = (240, 82, 82)             # a mob kept away from
MAP_MOB_QUEST = (245, 166, 35)      # ...one the quest is about (walked to)
QUEST_NEAR = 400.0                  # a mob this near the quest's goal (in this zone) is what the goal is
MOBS_SHOWN = {}                     # the last /nav's split, for the map: {'quest': {gids}, 'near': mob radius, 'at': time}


def nav_reader():
    global NAV
    with NAV_LOCK:
        if NAV is None:
            import navmem
            NAV = navmem.NavMem(log=log)
        return NAV


def word_forms(w):
    """a word and its plurals: Soul / Souls, Fairy / Fairies, Wolf / Wolves, Axeman / Axemen"""
    out = {w, w + 's', w + 'es'}
    if w.endswith('y'):
        out.add(w[:-1] + 'ies')
    if w.endswith('f'):
        out.add(w[:-1] + 'ves')
    if w.endswith('man'):
        out.add(w[:-3] + 'men')
    return out


def mob_name_re(name):
    """a regex for a mob's name as a goal line writes it - any of its words plural (Lost Souls, Keepers of the Fang)"""
    words = re.sub(r'[^a-z0-9 ]', ' ', name.lower()).split()
    if not words:
        return None
    return re.compile(r'\b' + r'\s+'.join('(?:' + '|'.join(sorted(map(re.escape, word_forms(w)), key=len, reverse=True)) + ')'
                                           for w in words) + r'\b')


def mob_plural(name):
    """(kept for the tests) the whole name and its plurals"""
    return word_forms(name.lower())


FIGHT_GOAL = re.compile(r'\b(defeat|destroy|kill|hunt|vanquish|beat|fight|battle|slay|collect|gather|obtain|retrieve|recover)\b'
                        r'|\(\s*\d+\s*(of|/)\s*\d+\s*\)', re.I)


def quest_mob(m, r, goal_line):
    """the quest is about this mob: its name is in the goal line ("Defeat 3 Lost Souls ..."), or - the goal a fight
    (or no goal line read) - it stands by the quest's goal in this zone (a boss the arrow leads to). Not a mob
    wandering by a "Talk to ..." goal"""
    line = re.sub(r'\s+', ' ', re.sub(r'[^a-z0-9 ]', ' ', (goal_line or '').lower()))
    rx = mob_name_re(m['name'])
    if rx is not None and line.strip() and rx.search(line):
        return True
    g = r.get('goal') if r else None
    if goal_line and not FIGHT_GOAL.search(goal_line):
        return False
    return (g is not None and r.get('hops') == 0
            and math.hypot(m['pos'][0] - g[0], m['pos'][1] - g[1]) <= QUEST_NEAR and abs(m['pos'][2] - g[2]) <= 260)


def mobs_now(r, goal_line='', trail=False):
    """(the zone's mobs [{name, pos, yaw, gid, template, quest}], why) - none ([], why) when they can't be read.
    trail: the reading goes on MOB_TRAIL too (the walker's route asks)"""
    mobs, why = nav_reader().mobs()
    if mobs is None:
        return [], why
    for m in mobs:
        m['quest'] = quest_mob(m, r, goal_line)
    if trail and r is not None and r.get('pos') is not None:
        MOB_TRAIL.append((time.time(), tuple(r['pos']), {m['gid']: (m['name'], m['pos'][0], m['pos'][1], m['pos'][2], m.get('yaw'))
                                                       for m in mobs}))
    return mobs, ''


# The mobs read lately: (time, the wizard's x, y, z, {gid: (name, x, y, z, yaw)}) - /caught looks back along it
MOB_TRAIL = collections.deque(maxlen=400)
CAUGHT_FRESH = 20.0     # the last reading at most this old (s) when a battle's first round is up
CAUGHT_NEAR = 450.0     # the mob that started it: the nearest, at most this far from the wizard in the last reading
CAUGHT_GAP = 2.0        # readings further apart than this (s) aren't followed back across


def caught_line(now=None):
    """/caught (see the top): which mob started the battle, and how far and how far off its facing the wizard was
    when it set off towards him - its steps followed back while each went his way"""
    trail = list(MOB_TRAIL)
    now = time.time() if now is None else now
    if not trail or now - trail[-1][0] > CAUGHT_FRESH:
        return 'none (no mobs read lately - they are read while walking with mob avoidance on)'
    _, me, mobs = trail[-1]
    near = sorted((math.hypot(v[1] - me[0], v[2] - me[1]), g) for g, v in mobs.items() if abs(v[3] - me[2]) <= 200)
    if not near:
        return 'none (no mob near)'
    d, gid = near[0]
    if d > CAUGHT_NEAR:
        return f'none (the nearest mob was {d:.0f} away)'
    k, came = len(trail) - 1, False
    # (standing in the battle already - neither moving: back to where they last moved)
    while (k > 0 and gid in trail[k - 1][2] and trail[k][0] - trail[k - 1][0] <= CAUGHT_GAP
           and math.dist(trail[k][1][:2], trail[k - 1][1][:2]) < 4
           and math.dist(trail[k][2][gid][1:3], trail[k - 1][2][gid][1:3]) < 4):
        k -= 1
    while k > 0:
        prev, cur = trail[k - 1], trail[k]
        if gid not in prev[2] or cur[0] - prev[0] > CAUGHT_GAP:
            break
        a, b = prev[2][gid], cur[2][gid]
        sx, sy = b[1] - a[1], b[2] - a[2]
        step = math.hypot(sx, sy)
        tx, ty = prev[1][0] - a[1], prev[1][1] - a[2]
        if step < 4 or (sx * tx + sy * ty) / (step * (math.hypot(tx, ty) or 1.0)) < 0.7:
            break
        came, k = True, k - 1
    # (where it stood when it noticed him: the reading before its first step his way - it turns to him first)
    if came and k > 0 and gid in trail[k - 1][2] and trail[k][0] - trail[k - 1][0] <= CAUGHT_GAP:
        k -= 1
    t0, me0, mobs0 = trail[k]
    name, x, y, _, yaw = mobs0[gid]
    dist = math.hypot(me0[0] - x, me0[1] - y)
    off = ''
    if yaw is not None and dist > 1:
        c = ((me0[0] - x) * -math.sin(yaw) + (me0[1] - y) * -math.cos(yaw)) / dist
        off = f'{math.degrees(math.acos(max(-1.0, min(1.0, c)))):.0f}'
    return f"caught|{name.replace('|', ' ')}|{dist:.0f}|{off}|{1 if came else 0}|{now - t0:.1f}"


ROUTER = None


def router(game_dir=''):
    """the route planner (vision\navroute.py: the zone's map from its .wad, read-only), made on first use"""
    global ROUTER
    with NAV_LOCK:
        if ROUTER is None:
            import navroute
            ROUTER = navroute.Planner(log=log, game_dir=game_dir)
        return ROUTER


ROUTER_TO = None


def router_to(game_dir=''):
    """a second route planner, for /navto (a walk to a spot of the bot's own: the potion seller) - the walker's
    (router) keeps its field, its carrot and its teleport waits"""
    global ROUTER_TO
    with NAV_LOCK:
        if ROUTER_TO is None:
            import navroute
            ROUTER_TO = navroute.Planner(log=log, game_dir=game_dir)
        return ROUTER_TO


# The potion sellers: the NPC templates with a PotionShopBehavior (the potion shop's window) - found by looking
# through every ObjectData template in Root.wad: Hilda Brewer in Wizard City's Commons and one in the Arcanum.
# Where each stands is read from the zone's own gamedata.bin (its placements: "<template> instance", the location
# property - hash 1b dc 7e 85, then x, y, z - just before the name), so a seller the game moves is still found
POTION_SELLERS = ('WC_PotionShopkeeper', 'AR-ARC-NPC13')
SELLER_LOC = b'\x1b\xdc\x7e\x85'
SELLERS_SEEN = {}


def potion_sellers(zone, game_dir=''):
    """[(name, (x, y, z)), ...] - the potion sellers placed in zone (from its gamedata.bin; read-only), kept; None
    when the zone's file can't be read"""
    if zone in SELLERS_SEEN:
        return SELLERS_SEEN[zone]
    import navgeo
    out = []
    try:
        b = navgeo.read_wad_files(navgeo.wad_path(zone, game_dir or navgeo.GAME_DIR), ['gamedata.bin']).get('gamedata.bin')
    except (OSError, ValueError) as e:
        log(f'/seller {zone}: {e!r}')
        return None                                    # (not kept: asked again next time)
    for name in POTION_SELLERS if b else ():
        for m in re.finditer(re.escape(name.encode()) + rb' instance( \(\d+\))?', b):
            k = b.rfind(SELLER_LOC, max(0, m.start() - 160), m.start())
            if k >= 0:
                x, y, z = struct.unpack_from('<3f', b, k + 4)
                if all(math.isfinite(v) and abs(v) < 1e6 for v in (x, y, z)):
                    out.append((name, (x, y, z)))
    SELLERS_SEEN[zone] = out
    return out


# A zone's volumes - the spheres that do something when walked into (a door's teleport, a quest's goal): from its
# volumes.xml (read-only), each a name (hash 8b 04 e6 c6, then its length x2 in a byte - or x2+1 in a u32 - and the
# letters) and after it the centre (hashes 28/29/2a f8 b3 7d, each then a float) and the radius (df 33 f9 3a). The
# Dorm's way out is "Teleport_Out"; Ravenwood's door to the Commons "TeleportVol_Teleport location (to Commons)"
VOL_NAME, VOL_X, VOL_Y, VOL_Z, VOL_R = (struct.pack('<I', h) for h in (0xc6e6048b, 0x7db3f828, 0x7db3f829, 0x7db3f82a, 0x3af933df))
VOLUMES_SEEN = {}


def zone_volumes(zone, game_dir=''):
    """[(name, (x, y, z), radius), ...] - zone's volumes with a centre, kept; None when the zone's file can't be read"""
    if zone in VOLUMES_SEEN:
        return VOLUMES_SEEN[zone]
    import navgeo
    try:
        b = navgeo.read_wad_files(navgeo.wad_path(zone, game_dir or navgeo.GAME_DIR), ['volumes.xml']).get('volumes.xml')
    except (OSError, ValueError) as e:
        log(f'/volumes {zone}: {e!r}')
        return None                                    # (not kept: asked again next time)
    b = b or b''
    out = []
    starts = [m.start() for m in re.finditer(re.escape(VOL_NAME), b)]
    for i, k in enumerate(starts):
        p = k + 4
        if p + 4 > len(b):
            continue
        n, p = (b[p] >> 1, p + 1) if not b[p] & 1 else (struct.unpack_from('<I', b, p)[0] >> 1, p + 4)
        name = b[p:p + n].decode('latin-1', 'replace').replace('|', '/').strip()
        seg = b[p + n:starts[i + 1] if i + 1 < len(starts) else len(b)]

        def num(h):
            j = seg.find(h)
            return struct.unpack_from('<f', seg, j + 4)[0] if 0 <= j and j + 8 <= len(seg) else None
        x, y, z, r = num(VOL_X), num(VOL_Y), num(VOL_Z), num(VOL_R)
        if name and None not in (x, y, z) and all(math.isfinite(v) and abs(v) < 1e6 for v in (x, y, z)):
            out.append((name, (x, y, z), r if r is not None and math.isfinite(r) else 0.0))
    VOLUMES_SEEN[zone] = out
    return out


def navto_lines(target, game_dir, avoid=False, mob_near=None, cone=None):
    """/navto's answer: where the wizard is (the game's memory, read-only) and the route to target - a spot of the
    bot's own - planned by router_to along the zone's nav graph; avoid: kept mob_near away from every mob"""
    nm = nav_reader()
    r, why = nm.read(path=False, wait=3.0)
    if r is None:
        return ['ERR ' + why]
    if r['pos'] is None or r['yaw'] is None or not r['zone']:
        return ['ERR the game\'s memory can\'t say where the wizard is']
    lines = ['ok|1', 'zone|' + r['zone'], 'pos|' + '|'.join(f'{c:.2f}' for c in r['pos']) + f"|{r['yaw']:.4f}"]
    try:
        p = router_to(nm.game_dir or game_dir)
        geo = p._geo(r['zone'])
        # (walked links only - no teleports on the way to a spot of the bot's own: nothing there to wait at one)
        if geo.why or geo.navgraph() is None:
            path = None
        else:
            P, adj = geo.navgraph()
            jumps = {(a, b) for a in range(len(P)) for b, _, j in adj[a] if j}
            path = geo.nav_path(r['pos'], target, jumps)
        # (all the mobs kept away from - avoid: mobavoid - on the way to the potion seller none is the quest's)
        import navroute
        mobs = mobs_now(None)[0] if avoid else None
        res = p.route(dict(r, goal=tuple(target), hops=0, path=path or []), wait=False, mobs=mobs or None,
                      mob_near=mob_near or navroute.MOB_NEAR, cone=cone or navroute.MOB_CONE)
    except Exception as e:  # noqa: BLE001 - no route: the bot steers straight at the spot
        log(f'/navto: {e!r}')
        res = {'why': f'the planner failed ({e!r})'}
    if res.get('aim') is None:
        return lines + ['route|||', 'routewhy|' + (res.get('why') or '?')]
    return lines + [f"route|{res['aim'][0]:.1f}|{res['aim'][1]:.1f}|{res['left']:.0f}"]


def mob_cone(q):
    """the mobs' sight cone asked for: (degrees wide, long) from cone= / sight= (0 wide: none), else the planner's"""
    import navroute
    try:
        wide = float(q['cone']) if q.get('cone', '') != '' else navroute.MOB_CONE[0]
        far = float(q['sight']) if q.get('sight', '') != '' else navroute.MOB_CONE[1]
    except ValueError:
        return navroute.MOB_CONE
    return (min(180.0, max(0.0, wide)), min(3000.0, max(0.0, far)))


def mob_avoid(q):
    """(how far all round, (degrees wide, long) in front) to keep from the mobs, as asked: mobr= how far they notice
    you; shape= 1 a circle all round, 2 a semi-circle in front, 3 a cone in front cone= degrees wide (a semi-circle or
    cone: navroute.MOB_BODY all round as well). No shape=: mobr all round and the cone= / sight= cone (mob_cone)"""
    import navroute

    def num(k, default, lo, hi):
        try:
            v = float(q.get(k) or 0) or default
        except ValueError:
            v = default
        return min(hi, max(lo, v))
    rng = num('mobr', 300.0, 100.0, 3000.0)
    shape = q.get('shape', '')
    if shape == '1':
        return rng, (0.0, 0.0)
    if shape == '2':
        return navroute.MOB_BODY, (180.0, rng)
    if shape == '3':
        return navroute.MOB_BODY, (num('cone', 60.0, 5.0, 180.0), rng)
    return min(1500.0, rng), mob_cone(q)


def route_lines(r, game_dir, avoid=None, mob_near=None, cone=None):
    """/nav's route lines for a reading r (made with path=True); avoid: the mobs to keep away from - mob_near round
    them, out of their sight cone (degrees wide, long) in front"""
    try:
        import navroute
        res = router(game_dir).route(r, mobs=avoid or None, mob_near=mob_near or navroute.MOB_NEAR, cone=cone or navroute.MOB_CONE)
    except Exception as e:  # noqa: BLE001 - no route: the walker steers at the target
        log(f'route: {e!r}')
        res = {'why': f'the planner failed ({e!r})'}
    if res.get('aim') is None:
        return ['route|||', 'routewhy|' + (res.get('why') or '?')]
    # (fields 5-7: right at a teleport on the game's path - the seconds waited there, and where it is; 8-11: a mob
    # on the way the route can't go round - the seconds waited for it to move off, where it is, its name)
    jump = res.get('jump')
    tail = '||' if jump is None else f"{jump:.0f}|{res['jump_at'][0]:.0f}|{res['jump_at'][1]:.0f}"
    mob = res.get('mob')
    tail += '||||' if mob is None else f"|{mob:.0f}|{res['mob_at'][0]:.0f}|{res['mob_at'][1]:.0f}|{res['mob_name'].replace('|', ' ')}"
    return [f"route|{res['aim'][0]:.1f}|{res['aim'][1]:.1f}|{res['left']:.0f}|" + tail]


def nav_lines(r, with_path):
    """/nav's answer from a navmem reading (fields that can't be read for sure left empty)"""
    def xyz(v):
        return '|'.join(f'{c:.2f}' for c in v) if v is not None else '||'
    have_pos = r['pos'] is not None and r['yaw'] is not None
    have_goal = r['goal'] is not None and r['hops'] is not None
    lines = ['ok|1',
             'zone|' + (r['zone'] or ''),
             'pos|' + (xyz(r['pos']) + f"|{r['yaw']:.4f}" if have_pos else '|||'),
             'target|' + xyz(r['target']),
             'goal|' + (xyz(r['goal']) + f"|{r['hops']}" if have_goal else '|||'),
             'dist|' + ('' if r['dist'] is None else f"{r['dist']:.1f}"),
             'quest|' + '|'.join('' if r[k] is None else str(r[k]) for k in ('enabled', 'quest', 'goalid'))]
    if with_path:
        lines.append('path|' + ';'.join(f'{x:.1f},{y:.1f},{z:.1f}' for x, y, z in (r['path'] or ())))
    return lines


NAV_RETRY = 30


class ZoneLayers:
    """One zone's static map layers - walkable floor, water, obstacles, the nav graph - decoded once, drawn
    in NAV_TILE tiles on first use at a scale (upp: game units per pixel). Pixel (px, py) of the zone's
    picture at a scale is world (px * upp, -py * upp): +X to the right, +Y up. No zone file: no layers
    (why says why), the map is the overlay on a blank background"""

    def __init__(self, zone, game_dir=''):
        self.zone, self.why = zone, ''
        self.tris = {}          # 'floor' / 'water': (F, 3, 2) world XY triangles, with (F, 4) bounds
        self.polys = {}         # 'floor' / 'obst': [(k, 2) polygon], with (n, 4) bounds
        self.tz = {}            # 'floor': (F,) each floor triangle's height; 'floorpoly': each walkable box's top
        self.zlo = self.zhi = 0.0  # the floor's height range (for its shading)
        self.segs = np.zeros((0, 2, 2))
        self.nodes = np.zeros((0, 2))
        self.bounds = None      # x1, y1, x2, y2 of everything
        try:
            import navgeo
            d = navgeo.load_zone(zone, game_dir or navgeo.GAME_DIR)
        except Exception as e:  # noqa: BLE001 - no map, just the overlay
            self.why = str(e) if isinstance(e, FileNotFoundError) else f"the zone file can't be read ({e!r})"
            return
        nav, bcd = d['nav'], d['bcd'] or []
        P = nav['positions'].astype(np.float64) if nav is not None and len(nav['positions']) else np.zeros((0, 3))
        if nav is not None and len(nav['edges']):
            self.segs = P[nav['edges']][:, :, :2]
        self.nodes = P[:, :2]
        tris = {'floor': [], 'water': []}
        polys = {'floor': [], 'obst': []}
        tz = {'floor': [], 'floorpoly': []}
        for s in bcd:
            cat = s['category_flags']
            if s['type'] == 'mesh':
                kind = 'floor' if cat & 0x2 else 'water' if cat & 0x40 else None
                if kind and len(s['mesh']['faces']):
                    v, f = navgeo.mesh_world(s)
                    tris[kind].append(v[f][:, :, :2])
                    if kind == 'floor':
                        tz['floor'].append(v[f][:, :, 2].mean(1))
            elif cat & 0x2:                                          # a walkable box (a platform)
                ps = [p for p in navgeo.footprint(s, 24) if len(p) >= 3]
                ab = navgeo.aabb(s)
                polys['floor'] += ps
                tz['floorpoly'] += [ab[1][2] if ab is not None else 0.0] * len(ps)
            elif cat & 0x81 and s['type'] in ('box', 'cylinder', 'sphere', 'tube'):
                # an obstacle - unless it hangs over the floor (an arch's top, a roof): its bottom higher
                # than a wizard over every nav node round it
                ab = navgeo.aabb(s)
                if ab is not None and len(P):
                    lo, hi = ab
                    near = (P[:, 0] > lo[0] - 300) & (P[:, 0] < hi[0] + 300) & (P[:, 1] > lo[1] - 300) & (P[:, 1] < hi[1] + 300)
                    if near.any() and lo[2] > P[near, 2].max() + 180:
                        continue
                polys['obst'] += [p for p in navgeo.footprint(s, 28) if len(p) >= 3]
        self.tz = {'floor': np.concatenate(tz['floor']) if tz['floor'] else np.zeros(0), 'floorpoly': np.array(tz['floorpoly'])}
        allz = np.concatenate([self.tz['floor'], self.tz['floorpoly']])
        if len(allz):
            self.zlo, self.zhi = float(np.percentile(allz, 2)), float(np.percentile(allz, 98))
        allb = []
        for k, t in tris.items():
            t = np.concatenate(t) if t else np.zeros((0, 3, 2))
            b = np.concatenate([t.min(1), t.max(1)], 1) if len(t) else np.zeros((0, 4))
            self.tris[k] = (t, b)
            allb.append(b)
        for k, ps in polys.items():
            b = np.array([[*p.min(0), *p.max(0)] for p in ps]) if ps else np.zeros((0, 4))
            self.polys[k] = (ps, b)
            allb.append(b)
        if len(self.nodes):
            allb.append(np.concatenate([self.nodes, self.nodes], 1))
        allb = np.concatenate(allb) if allb else np.zeros((0, 4))
        if len(allb):
            self.bounds = (allb[:, 0].min(), allb[:, 1].min(), allb[:, 2].max(), allb[:, 3].max())
        else:
            self.why = 'the zone file has no floor or nav graph'

    def tile(self, upp, i, j):
        """tile (i, j) at upp as an RGB picture, or None if nothing is in it"""
        T, S = NAV_TILE, NAV_SS
        pad = 3                                                  # (for the floor's rim, then cut off)
        wx1, wx2 = (i * T - pad) * upp, ((i + 1) * T + pad) * upp
        wy1, wy2 = -((j + 1) * T + pad) * upp, -(j * T - pad) * upp
        if self.bounds is None or wx2 < self.bounds[0] or wx1 > self.bounds[2] or wy2 < self.bounds[1] or wy1 > self.bounds[3]:
            return None
        size = (T + 2 * pad) * S

        def px(a):
            """world XY (..., 2) -> this tile's big pixels, as a flat list for ImageDraw"""
            a = np.asarray(a, dtype=np.float64)
            return np.stack([(a[..., 0] / upp - i * T + pad) * S, (-a[..., 1] / upp - j * T + pad) * S], -1)

        def inside(b):
            return (b[:, 2] >= wx1) & (b[:, 0] <= wx2) & (b[:, 3] >= wy1) & (b[:, 1] <= wy2)

        from PIL import ImageDraw, ImageFilter
        ground = Image.new('L', (size, size), 0)                  # 0 nothing, 1 floor, 2 water
        dg = ImageDraw.Draw(ground)
        shade = Image.new('L', (size, size), 0)                   # the floor's height, 0-255 over the zone's range
        dsh = ImageDraw.Draw(shade)
        span = max(1.0, self.zhi - self.zlo)

        def level(z):
            return int(round(255 * min(1.0, max(0.0, (z - self.zlo) / span))))
        for kind, val in (('floor', 1), ('water', 2)):
            t, b = self.tris[kind]
            sel = np.nonzero(inside(b))[0]
            if kind == 'floor' and len(sel):
                sel = sel[np.argsort(self.tz['floor'][sel], kind='stable')]          # higher floors over lower
            for k, tri in zip(sel.tolist(), px(t[sel]).tolist()):
                dg.polygon([tuple(q) for q in tri], fill=val, outline=val)
                if kind == 'floor':
                    dsh.polygon([tuple(q) for q in tri], fill=level(self.tz['floor'][k]), outline=level(self.tz['floor'][k]))
            if kind == 'floor':
                ps, b = self.polys['floor']
                for k in np.nonzero(inside(b))[0] if len(b) else ():
                    dg.polygon([tuple(q) for q in px(ps[k]).tolist()], fill=val, outline=val)
                    lv = level(self.tz['floorpoly'][k]) if k < len(self.tz['floorpoly']) else 0
                    dsh.polygon([tuple(q) for q in px(ps[k]).tolist()], fill=lv, outline=lv)
        g = np.asarray(ground)
        sh = np.asarray(shade).astype(np.float32)[..., None] / 255.0
        solid = Image.fromarray(((g > 0) * 255).astype(np.uint8))
        rim = (np.asarray(solid.filter(ImageFilter.MaxFilter(2 * S + 1))) > 0) & (g == 0)
        rgb = np.empty((size, size, 3), np.uint8)
        rgb[:] = MAP_BG
        lo, hi = np.array(MAP_FLOOR_LOW, np.float32), np.array(MAP_FLOOR_HIGH, np.float32)
        floor_rgb = (lo + (hi - lo) * sh).astype(np.uint8)
        rgb[g == 1] = floor_rgb[g == 1]
        rgb[g == 2] = MAP_WATER
        rgb[rim] = MAP_RIM
        img = Image.fromarray(rgb).convert('RGBA')
        layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        dl = ImageDraw.Draw(layer)
        segs = self.segs
        if len(segs):
            b = np.concatenate([segs.min(1), segs.max(1)], 1)
            for (x1, y1), (x2, y2) in px(segs[inside(b)]).tolist():
                dl.line([(x1, y1), (x2, y2)], fill=MAP_NAV + (46,), width=S)
        nb = np.concatenate([self.nodes, self.nodes], 1) if len(self.nodes) else np.zeros((0, 4))
        r = 1.2 * S
        for x, y in px(self.nodes[inside(nb)]).tolist() if len(nb) else ():
            dl.ellipse([x - r, y - r, x + r, y + r], fill=MAP_NAV + (70,))
        img.alpha_composite(layer)
        layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        dl = ImageDraw.Draw(layer)
        ps, b = self.polys['obst']
        for k in np.nonzero(inside(b))[0] if len(b) else ():
            dl.polygon([tuple(q) for q in px(ps[k]).tolist()], fill=MAP_OBST + (105,), outline=MAP_OBST + (215,), width=S)
        img.alpha_composite(layer)
        img = img.convert('RGB').resize((T + 2 * pad, T + 2 * pad), Image.BOX)
        return img.crop((pad, pad, pad + T, pad + T))


NAV_ZONES = collections.OrderedDict()       # zone -> ZoneLayers
NAV_TILES = collections.OrderedDict()       # (zone, upp, i, j) -> picture or None
MAP_LOCK = threading.Lock()
MAP_FONTS = {}


def zone_layers(zone, game_dir):
    z = NAV_ZONES.get(zone)
    # (a zone whose file couldn't be read - still downloading or being written while it loads - is tried
    # again after NAV_RETRY seconds rather than kept as 'no map' for the whole visit)
    if z is not None and z.why and time.time() - getattr(z, 'made', 0) > NAV_RETRY:
        NAV_ZONES.pop(zone, None)
        for k in [k for k in NAV_TILES if k[0] == zone]:
            del NAV_TILES[k]
        z = None
    if z is None:
        t0 = time.perf_counter()
        z = NAV_ZONES[zone] = ZoneLayers(zone, game_dir)
        z.made = time.time()
        log(f'/navmap: zone {zone} read in {(time.perf_counter() - t0) * 1000:.0f} ms' + (f' - {z.why}' if z.why else ''))
        while len(NAV_ZONES) > NAV_ZONES_KEPT:
            old, _ = NAV_ZONES.popitem(last=False)
            for k in [k for k in NAV_TILES if k[0] == old]:
                del NAV_TILES[k]
    NAV_ZONES.move_to_end(zone)
    return z


def map_font(size):
    from PIL import ImageFont
    if size not in MAP_FONTS:
        for name in ('segoeuib.ttf', 'segoeui.ttf', 'arialbd.ttf', 'arial.ttf'):
            try:
                MAP_FONTS[size] = ImageFont.truetype(name, size)
                break
            except OSError:
                pass
        else:
            MAP_FONTS[size] = ImageFont.load_default()
    return MAP_FONTS[size]


def render_navmap(r, w, h, game_dir='', span=NAV_SPAN, route=None, mobs=None, rings_on=False):
    """the /navmap picture (RGB, w x h) round the wizard for a navmem reading r (r['pos'] known); route: the
    planned route's answer (navroute) to draw, if any; mobs: the zone's mobs (mobs_now) - red dots, the quest's
    amber, and (rings_on: the walker keeps away from them) a faint ring round the others, mob_near across"""
    from PIL import ImageDraw
    upp = span / min(w, h)
    ukey = round(upp, 4)
    x0, y0 = r['pos'][0], r['pos'][1]
    ox, oy = int(math.floor(x0 / upp - w / 2)), int(math.floor(-y0 / upp - h / 2))
    img = Image.new('RGB', (w, h), MAP_BG)
    zone = r['zone'] or ''
    layers = zone_layers(zone, game_dir) if zone else None
    T = NAV_TILE
    if layers is not None and not layers.why:
        for j in range(oy // T, (oy + h - 1) // T + 1):
            for i in range(ox // T, (ox + w - 1) // T + 1):
                key = (zone, ukey, i, j)
                if key in NAV_TILES:
                    NAV_TILES.move_to_end(key)
                else:
                    NAV_TILES[key] = layers.tile(upp, i, j)
                    while len(NAV_TILES) > NAV_TILES_KEPT:
                        NAV_TILES.popitem(last=False)
                if NAV_TILES[key] is not None:
                    img.paste(NAV_TILES[key], (i * T - ox, j * T - oy))
    # the overlay, drawn big and shrunk
    S = NAV_SS
    ov = Image.new('RGBA', (w * S, h * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    unit = max(1.0, min(w, h) / 240) * S                     # line width / marker size unit (big pixels)

    def at(p):
        return ((p[0] / upp - ox) * S, (-p[1] / upp - oy) * S)

    def on_pic(q, m=0):
        return m <= q[0] <= w * S - m and m <= q[1] <= h * S - m

    def edge_pointer(q, col):
        """a point off the picture: a small triangle on its edge pointing at it"""
        cx, cy = w * S / 2, h * S / 2
        dx, dy = q[0] - cx, q[1] - cy
        n = math.hypot(dx, dy) or 1.0
        dx, dy = dx / n, dy / n
        m = 7 * unit
        k = min((cx - m) / abs(dx) if dx else 1e9, (cy - m) / abs(dy) if dy else 1e9)
        tx, ty = cx + dx * k, cy + dy * k
        L = 6 * unit
        d.polygon([(tx + dx * L, ty + dy * L), (tx - dy * L * 0.7, ty + dx * L * 0.7), (tx + dy * L * 0.7, ty - dx * L * 0.7)],
                  fill=col + (235,), outline=MAP_BG + (255,))

    me = at(r['pos'])
    path = r.get('path') or []
    if path:
        pts = [me] + [at(p) for p in path]
        if r['goal'] is not None and r['hops'] == 0:
            d.line([pts[-1], at(r['goal'])], fill=MAP_PATH + (120,), width=int(unit))
        d.line(pts, fill=MAP_PATH + (230,), width=int(2 * unit), joint='curve')
        for q in pts[1:]:
            d.ellipse([q[0] - 1.6 * unit, q[1] - 1.6 * unit, q[0] + 1.6 * unit, q[1] + 1.6 * unit], fill=MAP_PATH + (255,))
    if route and route.get('route'):
        pts = [me] + [at(p) for p in route['route'][1:]]
        if len(pts) >= 2:
            d.line(pts, fill=MAP_ROUTE + (235,), width=int(2 * unit), joint='curve')
        q = at(route['aim'])
        d.ellipse([q[0] - 2.2 * unit, q[1] - 2.2 * unit, q[0] + 2.2 * unit, q[1] + 2.2 * unit], fill=MAP_ROUTE + (255,), outline=MAP_BG + (255,))
    if r['goal'] is not None:
        q = at(r['goal'])
        door = (r['hops'] or 0) > 0
        col = MAP_DOOR if door else MAP_GOAL
        if on_pic(q, 4 * unit):
            s = 5 * unit
            if door:
                d.rectangle([q[0] - s, q[1] - s * 1.2, q[0] + s, q[1] + s * 1.2], fill=col + (255,), outline=MAP_BG + (255,), width=int(unit))
                f = map_font(int(7 * unit))
                d.text((q[0] + s * 1.5, q[1]), str(r['hops']), fill=col + (255,), font=f, anchor='lm', stroke_width=int(unit), stroke_fill=MAP_BG + (255,))
            else:
                d.polygon([(q[0], q[1] - s * 1.3), (q[0] + s * 1.3, q[1]), (q[0], q[1] + s * 1.3), (q[0] - s * 1.3, q[1])],
                          fill=col + (255,), outline=MAP_BG + (255,))
        else:
            edge_pointer(q, col)
    # the mobs: a red dot each (the quest's amber), faintly the shape they're kept out of - a circle all round, or a
    # semi-circle / cone in front with their body's small circle (its facing unknown: the whole circle) - on a layer
    # under everything else drawn (a see-through fill would wipe out what's under it here); names by the nearest few
    near_r = (MOBS_SHOWN.get('near') or 300.0) / upp * S
    cone = MOBS_SHOWN.get('cone')
    sector = bool(cone and cone[0] > 0 and cone[1] > 0)
    sight_r = cone[1] / upp * S if sector else 0.0
    by_dist = sorted(mobs or [], key=lambda m: math.hypot(m['pos'][0] - r['pos'][0], m['pos'][1] - r['pos'][1]))
    fm = map_font(int(5.5 * unit))
    rings = None
    for k, m in enumerate(by_dist):
        q = at(m['pos'])
        if not on_pic(q, -max(near_r, sight_r)):
            continue
        col = MAP_MOB_QUEST if m.get('quest') else MAP_MOB
        if not m.get('quest') and rings_on:
            if rings is None:
                rings = Image.new('RGBA', (w * S, h * S), (0, 0, 0, 0))
                dr = ImageDraw.Draw(rings)
            ring_r = sight_r if sector and m.get('yaw') is None else near_r
            dr.ellipse([q[0] - ring_r, q[1] - ring_r, q[0] + ring_r, q[1] + ring_r], fill=col + (34,), outline=col + (120,), width=max(1, int(unit * 0.7)))
            # (its sight in front of it: forward = (-sin yaw, -cos yaw); the picture's y is -Y)
            if sector and m.get('yaw') is not None:
                face = math.degrees(math.atan2(math.cos(m['yaw']), -math.sin(m['yaw'])))
                dr.pieslice([q[0] - sight_r, q[1] - sight_r, q[0] + sight_r, q[1] + sight_r], face - cone[0] / 2, face + cone[0] / 2,
                            fill=col + (34,), outline=col + (120,), width=max(1, int(unit * 0.7)))
        s = 2.8 * unit
        d.ellipse([q[0] - s, q[1] - s, q[0] + s, q[1] + s], fill=col + (255,), outline=MAP_BG + (255,), width=max(1, int(unit * 0.7)))
        if k < 6 and on_pic(q, 4 * unit):
            d.text((q[0] + s * 1.6, q[1]), m['name'], fill=col + (235,), font=fm, anchor='lm', stroke_width=max(1, int(unit * 0.8)), stroke_fill=MAP_BG + (255,))
    if r['target'] is not None:
        q = at(r['target'])
        if on_pic(q, 4 * unit):
            s = 4.5 * unit
            d.ellipse([q[0] - s, q[1] - s, q[0] + s, q[1] + s], outline=MAP_TARGET + (255,), width=int(1.6 * unit))
            d.ellipse([q[0] - unit, q[1] - unit, q[0] + unit, q[1] + unit], fill=MAP_TARGET + (255,))
        else:
            edge_pointer(q, MAP_TARGET)
    # the wizard: an arrow pointing where it faces (forward = (-sin yaw, -cos yaw); picture y is -Y)
    fx, fy = -math.sin(r['yaw']), math.cos(r['yaw'])
    nx, ny = -fy, fx
    L = 8 * unit
    d.polygon([(me[0] + fx * L, me[1] + fy * L),
               (me[0] - fx * L * 0.7 + nx * L * 0.62, me[1] - fy * L * 0.7 + ny * L * 0.62),
               (me[0] - fx * L * 0.3, me[1] - fy * L * 0.3),
               (me[0] - fx * L * 0.7 - nx * L * 0.62, me[1] - fy * L * 0.7 - ny * L * 0.62)],
              fill=MAP_ME + (255,), outline=MAP_BG + (255,), width=max(1, int(unit * 0.8)))
    # a scale bar, bottom left
    bar = 1000 if 1000 / upp <= w * 0.4 else 500
    bx, by, bl = 6 * unit, h * S - 6 * unit, bar / upp * S
    d.line([(bx, by), (bx + bl, by)], fill=MAP_TEXT + (200,), width=int(unit))
    d.line([(bx, by - 2.5 * unit), (bx, by)], fill=MAP_TEXT + (200,), width=int(unit))
    d.line([(bx + bl, by - 2.5 * unit), (bx + bl, by)], fill=MAP_TEXT + (200,), width=int(unit))
    f = map_font(int(6 * unit))
    d.text((bx + bl + 2.5 * unit, by), str(bar), fill=MAP_TEXT + (220,), font=f, anchor='lm')
    if layers is None or layers.why:
        d.text((w * S - 4 * unit, h * S - 4 * unit), 'no map for this zone', fill=MAP_TEXT + (200,), font=f, anchor='rs')
    out = img.convert('RGBA')
    if rings is not None:
        out.alpha_composite(rings.resize((w, h), Image.BOX))
    out.alpha_composite(ov.resize((w, h), Image.BOX))
    return out.convert('RGB')


def save_png(img, out):
    """written whole, then put in place (the dashboard may be reading the last one)"""
    os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
    tmp = out + '.tmp'
    img.save(tmp, 'PNG', compress_level=1)
    for _ in range(10):
        try:
            os.replace(tmp, out)
            return
        except PermissionError:
            time.sleep(0.02)
    img.save(out, 'PNG', compress_level=1)
    try:
        os.remove(tmp)
    except OSError:
        pass


def inside_temp(path):
    """whether path is inside the temp folder"""
    tmp = os.path.normcase(os.path.abspath(tempfile.gettempdir()))
    p = os.path.normcase(os.path.abspath(path))
    return p.startswith(tmp + os.sep)


def inside_root(path):
    p = os.path.normcase(os.path.abspath(path))
    return p.startswith(os.path.normcase(ROOT) + os.sep)


# ---------------------------------------------------------------- the server

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def reply(self, text, code=200):
        body = text.encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        try:
            if u.path == '/ping':
                return self.reply('OK ' + VERSION)
            if u.path == '/forget':
                global LIB
                LIB = Library()
                with TPL_LOCK:
                    TPL_FFT.clear()
                    globals()['TPL_BYTES'] = 0
                log('pictures read again: ' + ', '.join(f'{os.path.basename(d) or "main"}={sc}' for d, sc in LIB.sets))
                return self.reply('OK')
            if u.path == '/globes':
                hp, mp = read_globes(float(q['left']), float(q['bottom']), float(q['scale']), q.get('file'))
                return self.reply(f'health|{hp}\nmana|{mp}')
            if u.path == '/usable':
                return self.reply('1' if LIB.usable(q['rel'].replace('/', os.sep)) else '0')
            if u.path == '/hand':
                x1, y1, x2, y2 = (int(round(float(q[k]))) for k in ('x1', 'y1', 'x2', 'y2'))
                scale = float(q['scale'])
                t0 = time.perf_counter()
                thumbs = q.get('thumbs', '')
                if thumbs and not os.path.abspath(thumbs).lower().startswith(ROOT.lower()):
                    return self.reply('ERR thumbs must be in ' + ROOT, 400)
                cards = read_hand(x1, y1, x2, y2, scale, [p for p in q.get('pics', '').split(',') if p], q.get('file'),
                                  [e for e in q.get('learned', '').split(',') if e], q.get('here', ''), thumbs)
                lines = ['card|{left}|{top}|{w}|{h}|{known}|{kdist:.1f}|{g}|{kind}|{kinddist:.1f}|{pips}|{pipscore:.2f}|{same}|{liked}'.format(g=int(c['grey']), **c) for c in cards]
                log(f'/hand scale {scale} {(time.perf_counter() - t0) * 1000:.0f} ms: ' + ', '.join(
                    (c['known'].split('/')[-1] or f"?{c['kind'] or 'type?'}") + ('(grey)' if c['grey'] else '') for c in cards))
                # (how many: an empty hand - the deck used up - answers hand|0, not nothing)
                lines.append(f'hand|{len(cards)}')
                return self.reply('\n'.join(lines))
            if u.path == '/cut':
                out = q['out']
                if not os.path.abspath(out).lower().startswith(ROOT.lower()):
                    return self.reply('ERR out must be in ' + ROOT, 400)
                cut_card(float(q['left']), float(q['top']), float(q['scale']), out, q.get('file'))
                log(f'/cut {out}')
                return self.reply('OK')
            if u.path == '/seller':
                zone = q.get('zone', '')
                # (the game's folder comes from its running .exe: attached first, so another install is found)
                nm = nav_reader()
                nm.read(path=False, wait=3.0)
                found = potion_sellers(zone, nm.game_dir) if zone else []
                if found is None:
                    return self.reply("ERR the zone's file can't be read")
                return self.reply('\n'.join(f'seller|{n}|{x:.1f}|{y:.1f}|{z:.1f}' for n, (x, y, z) in found) or 'none')
            if u.path == '/volumes':
                zone = q.get('zone', '')
                nm = nav_reader()
                nm.read(path=False, wait=3.0)
                found = zone_volumes(zone, nm.game_dir) if zone else []
                if found is None:
                    return self.reply("ERR the zone's file can't be read")
                return self.reply('\n'.join(f'vol|{n}|{x:.1f}|{y:.1f}|{z:.1f}|{r:.0f}' for n, (x, y, z), r in found) or 'none')
            if u.path == '/navto':
                try:
                    target = (float(q['x']), float(q['y']), float(q['z']))
                except (KeyError, ValueError):
                    return self.reply('ERR x, y, z wanted', 400)
                avoid = q.get('avoid', '0') not in ('', '0')
                near, cone = mob_avoid(q)
                return self.reply('\n'.join(navto_lines(target, nav_reader().game_dir, avoid, near, cone)))
            if u.path == '/snap':
                if not snap_out_ok(q.get('out', '')):
                    return self.reply('ERR out must be a snap_*.jpg in a Wiz-Maxxing logs\\<PC> folder', 400)
                try:
                    return self.reply('ok|' + snap(int(q['x1']), int(q['y1']), int(q['x2']), int(q['y2']), q['out'],
                                                   max(1, int(q.get('keep') or 15))))
                except Exception as e:
                    return self.reply('ERR ' + repr(e))
            if u.path == '/caught':
                return self.reply(caught_line())
            if u.path == '/mobs':
                nm = nav_reader()
                r, why = nm.read(path=False)
                if r is None:
                    return self.reply('ERR ' + why)
                mobs, why = mobs_now(r, q.get('goal', ''))
                if not mobs:
                    return self.reply('none' + (' (' + why + ')' if why else ''))
                me = r['pos'] or (0.0, 0.0, 0.0)
                def off_facing(m):
                    """how far round from where m faces the wizard is (degrees; 0 straight ahead of it)"""
                    if m.get('yaw') is None:
                        return ''
                    dx, dy = me[0] - m['pos'][0], me[1] - m['pos'][1]
                    d = math.hypot(dx, dy) or 1.0
                    c = (dx * -math.sin(m['yaw']) + dy * -math.cos(m['yaw'])) / d
                    return f"{math.degrees(math.acos(max(-1.0, min(1.0, c)))):.0f}"
                return self.reply('\n'.join(
                    f"mob|{m['name'].replace('|', ' ')}|{m['pos'][0]:.1f}|{m['pos'][1]:.1f}|{m['pos'][2]:.1f}|"
                    f"{math.hypot(m['pos'][0] - me[0], m['pos'][1] - me[1]):.0f}|{1 if m['quest'] else 0}|{off_facing(m)}"
                    for m in sorted(mobs, key=lambda m: math.hypot(m['pos'][0] - me[0], m['pos'][1] - me[1]))))
            if u.path == '/nav':
                with_path = q.get('path', '0') not in ('', '0')
                with_route = q.get('route', '0') not in ('', '0')
                # (the walker walked on with F8: teleports given up get another go - something may have opened one)
                if q.get('unblock', '0') not in ('', '0') and ROUTER is not None:
                    ROUTER.blocked.clear()
                    ROUTER.jwait, ROUTER._round = None, None
                    log('route: teleports given up forgotten (walking on with F8)')
                nm = nav_reader()
                r, why = nm.read(path=with_path or with_route)
                if r is None:
                    return self.reply('ERR ' + why)
                lines = nav_lines(r, with_path)
                if with_route:
                    # (the mobs kept away from: all but the quest's - asked for with avoid=1)
                    avoid, near = None, None
                    if q.get('avoid', '0') not in ('', '0'):
                        near, cone = mob_avoid(q)
                        mobs, _ = mobs_now(r, q.get('goal', ''), trail=True)
                        avoid = [m for m in mobs if not m['quest']]
                        MOBS_SHOWN.update(quest={m['gid'] for m in mobs if m['quest']}, near=near, avoid=True, at=time.time(),
                                          cone=cone)
                    else:
                        MOBS_SHOWN.update(quest=set(), avoid=False, at=time.time())
                    lines += route_lines(r, nm.game_dir, avoid, near, MOBS_SHOWN.get('cone'))
                return self.reply('\n'.join(lines))
            if u.path == '/navmap':
                w, h = int(q['w']), int(q['h'])
                out = q['out']
                if not (16 <= w <= 4000 and 16 <= h <= 4000):
                    return self.reply('ERR w and h must be 16-4000', 400)
                # (the temp folder too: the dashboard's map is rewritten every second, which OneDrive would
                # keep uploading if it were in the bot's folder)
                if not out.lower().endswith('.png') or not (inside_root(out) or inside_temp(out)):
                    return self.reply('ERR out must be a .png in ' + ROOT + ' or the temp folder', 400)
                span = min(100000.0, max(500.0, float(q.get('span', NAV_SPAN))))
                nm = nav_reader()
                r, why = nm.read(path=True)
                if r is None:
                    return self.reply('ERR ' + why)
                if r['pos'] is None or r['yaw'] is None:
                    return self.reply("ERR the wizard's position can't be read (" + (r.get('why_player') or '?') + ')')
                # (the mobs as the walker's last ask split them - the quest's, the ones kept away from)
                mobs, _ = mobs_now(r)
                fresh = time.time() - (MOBS_SHOWN.get('at') or 0) < 10
                for m in mobs:
                    m['quest'] = m['gid'] in MOBS_SHOWN.get('quest', ()) if fresh else False
                try:
                    import navroute
                    avoid = [m for m in mobs if not m['quest']] if fresh and MOBS_SHOWN.get('avoid') else None
                    route = router(nm.game_dir).route(r, wait=False, mobs=avoid, mob_near=MOBS_SHOWN.get('near') or navroute.MOB_NEAR,
                                                      cone=MOBS_SHOWN.get('cone') or navroute.MOB_CONE)
                except Exception:  # noqa: BLE001 - the map without it
                    route = None
                with MAP_LOCK:
                    img = render_navmap(r, w, h, nm.game_dir, span, route, mobs, bool(fresh and MOBS_SHOWN.get('avoid')))
                save_png(img, os.path.abspath(out))
                return self.reply('ok|' + os.path.abspath(out))
            if u.path == '/quit':
                self.reply('OK bye')
                threading.Thread(target=self.server.shutdown, daemon=True).start()
                return
            if u.path in ('/cards', '/badge'):
                x1, y1, x2, y2 = (int(round(float(q[k]))) for k in ('x1', 'y1', 'x2', 'y2'))
                scale = float(q['scale'])
                file = q.get('file')
                t0 = time.perf_counter()
                extra = []
                if u.path == '/cards':
                    missing = []
                    res = find_cards(x1, y1, x2, y2, scale, [p for p in q.get('pics', '').split(',') if p], file, missing)
                    if missing:
                        extra.append('missing|' + ','.join(missing))
                else:
                    res = find_badges(x1, y1, x2, y2, scale, [s for s in q.get('schools', '').split(',') if s], file)
                    if res is None:
                        res, extra = [], ['unclear']
                ms = (time.perf_counter() - t0) * 1000
                lines = [f'{r[0]}|{r[1]}|{r[2]}|{r[3]:.1f}' for r in res] + extra
                log(f'{u.path} scale {scale} ({x2 - x1}x{y2 - y1}) {ms:.0f} ms: ' + (', '.join(f'{r[0]} {r[3]:.1f}' for r in res) or 'nothing') + (' | ' + ' '.join(extra) if extra else ''))
                return self.reply('\n'.join(lines))
            return self.reply('ERR unknown request ' + u.path, 404)
        except Exception as e:  # noqa: BLE001 - any problem goes back to AutoFarmer, which falls back
            log(f'ERR {self.path}: {e!r}')
            return self.reply('ERR ' + repr(e), 500)


def parent_alive(pid):
    PROCESS_QUERY_LIMITED_INFORMATION, STILL_ACTIVE = 0x1000, 259
    h = ctypes.windll.kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if not h:
        return False
    code = ctypes.c_ulong()
    ok = ctypes.windll.kernel32.GetExitCodeProcess(h, ctypes.byref(code))
    ctypes.windll.kernel32.CloseHandle(h)
    return bool(ok) and code.value == STILL_ACTIVE


def main():
    global LIB
    ap = argparse.ArgumentParser()
    ap.add_argument('--parent', type=int, default=0, help='stop when this process is gone')
    ap.add_argument('--port', type=int, default=PORT)
    args = ap.parse_args()
    try:
        ctypes.windll.user32.SetProcessDPIAware()   # screen pixels, like AutoHotkey's
    except Exception:  # noqa: BLE001
        pass
    LIB = Library()
    try:
        server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    except OSError as e:
        log(f'port {args.port} taken ({e}) - another copy is running')
        return
    log(f'started (version {VERSION}, port {args.port}, parent {args.parent}, sets: ' + ', '.join(f'{os.path.basename(d) or "main"}={sc}' for d, sc in LIB.sets) + ')')
    if args.parent:
        def watch():
            while parent_alive(args.parent):
                time.sleep(5)
            log('AutoFarmer is gone - stopping')
            server.shutdown()
        threading.Thread(target=watch, daemon=True).start()
    server.serve_forever()
    log('stopped')


if __name__ == '__main__':
    main()
