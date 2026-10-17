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
  /cut?left=&top=&scale=&out=<path>       -> saves the card at left, top: <out>.png (its picture, cut like
                                             hit1.png etc.) and .raw.png, .card.png (the whole card), .icon.png
                                             (its type icon), .pips.png (its pip cost)
  /usable?rel=balance\hit2.png            -> "1" if a cut picture big enough to use is there for it, else "0"
  /forget                                 -> reads the picture folders again (after pictures were added)
  /globes?left=&bottom=&scale=            -> "health|<n>" and "mana|<n>" off the globes at the game's bottom
                                             left (n "" if it can't be read for sure)
  /quit                                   -> stops
Add &file=<path> to /cards, /badge, /hand or /cut to look at a saved screenshot instead of the screen (for
tests; the rectangle is then in that picture's pixels).

Only numpy and Pillow. Stops by itself when the AutoFarmer process (--parent <pid>) is gone.
"""
import argparse
import collections, ctypes, glob, json, os, re, sys, threading, time
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


def read_hand(x1, y1, x2, y2, scale, pics, file=None, learned=None, here=''):
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
                cards = read_hand(x1, y1, x2, y2, scale, [p for p in q.get('pics', '').split(',') if p], q.get('file'),
                                  [e for e in q.get('learned', '').split(',') if e], q.get('here', ''))
                lines = ['card|{left}|{top}|{w}|{h}|{known}|{kdist:.1f}|{g}|{kind}|{kinddist:.1f}|{pips}|{pipscore:.2f}|{same}|{liked}'.format(g=int(c['grey']), **c) for c in cards]
                log(f'/hand scale {scale} {(time.perf_counter() - t0) * 1000:.0f} ms: ' + ', '.join(
                    (c['known'].split('/')[-1] or f"?{c['kind'] or 'type?'}") + ('(grey)' if c['grey'] else '') for c in cards))
                return self.reply('\n'.join(lines))
            if u.path == '/cut':
                out = q['out']
                if not os.path.abspath(out).lower().startswith(ROOT.lower()):
                    return self.reply('ERR out must be in ' + ROOT, 400)
                cut_card(float(q['left']), float(q['top']), float(q['scale']), out, q.get('file'))
                log(f'/cut {out}')
                return self.reply('OK')
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
