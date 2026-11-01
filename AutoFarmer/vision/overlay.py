"""overlay.py - the overlay over the game's pictures, drawn by the vision helper (vision.py /ovmap and POST /ovlog)
for AutoFarmer\\Overlay.ahk: the zone map round the wizard and the newest log lines, which Overlay.ahk shows over
borderless Wizard101 as click-through layered windows (UpdateLayeredWindow) kept out of every screen capture
(SetWindowDisplayAffinity WDA_EXCLUDEFROMCAPTURE) - the bot's own screen reading never sees them. Nothing here
calls Windows or reads the game, and this never imports vision (vision.py hands it the map's picture).

Where each part goes (layout): the game's client size (gw x gh, physical pixels) and the overlay's settings -
mapat / logat (1 Off, 2 top left, 3 top right, 4 bottom left, 5 bottom right), msize (the map's side, % of the
client's shorter side), lines, lw (the log's width, % of gw), text (its text size %), back (the dark box %),
mdx / mdy / ldx / ldy (pixel nudges) and span (the map's game units across) - LIMITS.

The frame file (.wzov), all little-endian: a 32-byte header, struct '<4sIIIIIii' - b'WZOV', version 1, w, h,
stride (always w * 4), seq (the request's, echoed), x, y (the part's top left, relative to the game's client
origin) - then h rows, top-down, of w pixels B, G, R, A premultiplied (c' = (c * a + 127) // 255, so B, G, R <= A):
32 + w * h * 4 bytes, 1 <= w, h <= 4000. Written whole to <out>.tmp, then put in place (write_frame); a picture
the same as the last one written there isn't written again ("same").

The log's body (POST /ovlog, text/plain us-ascii): one line per log line, oldest first -
RRGGBB<TAB><the line escaped as BattleRec.ahk BrecEsc escapes it><LF>, RRGGBB the line's dashboard colour
(Dashboard.ahk DashLogColors / DashLogKind) and the line "HH:mm:ss msg" cut to 300 characters before escaping. A
line without a colour is drawn light grey.
"""
import collections
import hashlib
import os
import re
import struct
import threading
import time

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFont

FRAME_MAGIC = b'WZOV'
FRAME_VERSION = 1
FRAME_HEAD = struct.Struct('<4sIIIIIii')   # 32 bytes
LIMITS = {'mapat': (1, 5, 2), 'msize': (15, 60, 28), 'logat': (1, 5, 2), 'lines': (3, 30, 10), 'lw': (20, 90, 38),
          'text': (60, 200, 100), 'back': (0, 90, 35), 'mdx': (-4000, 4000, 0), 'mdy': (-4000, 4000, 0),
          'ldx': (-4000, 4000, 0), 'ldy': (-4000, 4000, 0), 'span': (500, 100000, 4000)}   # (lo, hi, default)
SETTINGS = {'overlaymapat': 'mapat', 'overlaymapsize': 'msize', 'overlaylogat': 'logat', 'overlaylines': 'lines',
            'overlaylogwidth': 'lw', 'overlaytext': 'text', 'overlayback': 'back'}   # PlayerStats key -> query key
BG = (17, 19, 23)
LOG_DEFAULT_RGB = (218, 218, 218)
LOG_DIM_RGB = (154, 160, 166)
LOG_LINES_KEPT = 60
STRIPS_KEPT = 240
LOG_FADE = 0.6
BOX_MAX = 4000
LOG_FONTS = ('consolab.ttf', 'consola.ttf', 'lucon.ttf', 'cour.ttf')
OV_LOCK = threading.RLock()     # guards FONTS, STRIPS, MASKS
FRAME_LOCK = threading.Lock()   # guards FRAME_LAST and the file writes
FONTS = {}
STRIPS = collections.OrderedDict()
MASKS = collections.OrderedDict()
FRAME_LAST = {}


# ---------------------------------------------------------------- the request and the layout

def layout_args(q):
    """the layout's settings from the query q ({key: str}): each LIMITS key a whole number, clamped to its range -
    missing or unreadable ('x', 'nan', 'inf'): its default"""
    out = {}
    for k, (lo, hi, d) in LIMITS.items():
        try:
            v = int(float(q.get(k, d)))
        except (TypeError, ValueError, OverflowError):
            v = d
        out[k] = min(hi, max(lo, v))
    return out


def parse_request(q, path_ok):
    """/ovmap's and /ovlog's query: ({'gw', 'gh', 'out', 'seq', 'force', 'args'}, '') - or (None, 'ERR <why>') for a
    bad request; path_ok(out): whether the frame file may be written there"""
    try:
        gw, gh = int(q['gw']), int(q['gh'])
    except (KeyError, TypeError, ValueError):
        return None, "ERR gw and gh (the game's size) are needed"
    if not (200 <= gw <= 10000 and 150 <= gh <= 10000):
        return None, 'ERR gw must be 200-10000 and gh 150-10000'
    out = q.get('out', '')
    if not (out.lower().endswith('.wzov') and path_ok(out)):
        return None, 'ERR out must be a .wzov file in the AutoFarmer folder or the temp folder'
    try:
        seq = int(q.get('seq', 0)) & 0xFFFFFFFF
    except (TypeError, ValueError):
        seq = 0
    return {'gw': gw, 'gh': gh, 'out': out, 'seq': seq, 'force': q.get('force') == '1', 'args': layout_args(q)}, ''


def font_px(gh, text):
    """the log's text height in pixels: 15 on a 1080-high game at 100 %, 9-48"""
    return int(min(48, max(9, round(gh / 72 * text / 100))))


def back_alpha(pct):
    """the dark box's alpha (0-255) for its %"""
    return int(round(2.55 * pct))


def layout(gw, gh, a):
    """where the parts go in a gw x gh game client for the settings a (layout_args): {'map': (x, y, w, h) or None,
    'log': (x, y, w, h) or None, 'px', 'line_h', 'pad', 'margin', 'why'} - each box inside the client and at most
    BOX_MAX a side, the map square, the two never overlapping (before the nudges) and the log at least 2 lines high;
    a log that can't go anywhere is None with why saying so. The log in the map's corner goes under it (at the top)
    or above it (at the bottom), else beside it; in another corner it loses lines till it's clear of the map"""
    m = max(6, round(min(gw, gh) * 0.012))
    px = font_px(gh, a['text'])
    line_h = round(px * 1.3)
    pad = max(4, px // 3)

    def corner(pos, w, h):
        return (m if pos in (2, 4) else gw - m - w, m if pos in (2, 3) else gh - m - h)

    def hgt(n):
        return n * line_h + 2 * pad

    def overlap(b, c):
        return b[0] < c[0] + c[2] and c[0] < b[0] + b[2] and b[1] < c[1] + c[3] and c[1] < b[1] + b[3]

    res = {'map': None, 'log': None, 'px': px, 'line_h': line_h, 'pad': pad, 'margin': m, 'why': ''}
    mapat, logat = a['mapat'], a['logat']
    if mapat != 1:
        side = int(min(max(64, round(min(gw, gh) * a['msize'] / 100)), min(gw, gh) - 2 * m, BOX_MAX))
        res['map'] = (*corner(mapat, side, side), side, side)
    if logat != 1:
        lw = int(min(max(160, round(gw * a['lw'] / 100)), gw - 2 * m, BOX_MAX))
        rows = int(min(a['lines'], max(2, (gh - 2 * m - 2 * pad) // line_h)))
        x, y = corner(logat, lw, hgt(rows))
        box = (x, y, lw, hgt(rows))
        if res['map'] is not None:
            mx, my, side, _ = res['map']
            top = logat in (2, 3)
            left = logat in (2, 4)
            if logat == mapat:
                fit = (gh - 3 * m - side - 2 * pad) // line_h
                if fit >= 2:
                    rows = min(rows, fit)
                    box = (x, my + side + m if top else my - m - hgt(rows), lw, hgt(rows))
                else:
                    lw = min(lw, gw - 3 * m - side)
                    if lw < 160:
                        box = None
                        res['why'] = "there's no room for the log next to the map (a smaller map or another corner)"
                    else:
                        box = (mx + side + m if left else mx - m - lw, corner(logat, lw, hgt(rows))[1], lw, hgt(rows))
            else:
                while overlap(box, res['map']) and rows > 2:
                    rows -= 1
                    box = (x, corner(logat, lw, hgt(rows))[1], lw, hgt(rows))
                if overlap(box, res['map']):
                    box = None
                    res['why'] = 'the log would cover the map (a smaller map, fewer lines or another corner)'
        res['log'] = box
    # (the nudges last, each part kept inside the client)
    for part, dx, dy in (('map', 'mdx', 'mdy'), ('log', 'ldx', 'ldy')):
        b = res[part]
        if b is not None:
            x, y, w, h = b
            res[part] = (int(min(max(0, x + a[dx]), gw - w)), int(min(max(0, y + a[dy]), gh - h)), w, h)
    return res


# ---------------------------------------------------------------- the box, the map's finish

def corner_r(w, h):
    """the boxes' corner radius"""
    return max(4, min(w, h) // 14)


def rounded_mask(w, h, r):
    """a w x h 'L' picture: 255, its four corners rounded off (radius r, smooth) - kept (MASKS, the last 8); never
    changed by its users"""
    r = max(1, min(r, w // 2, h // 2))
    key = (w, h, r)
    with OV_LOCK:
        img = MASKS.get(key)
        if img is not None:
            MASKS.move_to_end(key)
            return img
        m = np.full((h, w), 255, np.uint8)
        yy, xx = np.mgrid[0:r, 0:r].astype(np.float32) + 0.5
        d = np.hypot(xx - r, yy - r)
        p = (np.clip(r - d + 0.5, 0, 1) * 255 + 0.5).astype(np.uint8)
        m[:r, :r] = p
        m[:r, w - r:] = p[:, ::-1]
        m[h - r:, :r] = p[::-1, :]
        m[h - r:, w - r:] = p[::-1, ::-1]
        img = MASKS[key] = Image.fromarray(m)
        while len(MASKS) > 8:
            MASKS.popitem(last=False)
        return img


def backing(w, h, alpha):
    """the dark rounded box, w x h RGBA: BG at alpha (0-255) - 0: all clear"""
    img = Image.new('RGBA', (w, h), BG + (0,))
    img.putalpha(rounded_mask(w, h, corner_r(w, h)).point(lambda v: v * alpha // 255))
    return img


def finish_map(img, back_a):
    """the overlay's map (render_navmap clear=True, RGBA) on its dark box (alpha back_a), its corners rounded off"""
    w, h = img.size
    base = backing(w, h, back_a).copy()
    base.alpha_composite(img)
    base.putalpha(ImageChops.multiply(base.getchannel('A'), rounded_mask(w, h, corner_r(w, h))))
    return base


# ---------------------------------------------------------------- the log's picture

def log_font(px):
    """the log's font at px (Consolas bold, Consolas, Lucida Console, Courier New - else Pillow's own), kept"""
    with OV_LOCK:
        f = FONTS.get(px)
        if f is not None:
            return f
        for name in LOG_FONTS:
            try:
                f = ImageFont.truetype(name, px)
                break
            except OSError:
                pass
        else:
            try:
                f = ImageFont.load_default(px)
            except (TypeError, AttributeError):
                f = ImageFont.load_default()
        FONTS[px] = f
        return f


def fit_text(font, text, maxw):
    """text as it fits in maxw pixels: whole, or cut short with '...'"""
    if font.getlength(text) <= maxw:
        return text
    lo, hi = 0, len(text)            # (the largest k whose text[:k] + '...' fits)
    while lo < hi:
        k = (lo + hi + 1) // 2
        if font.getlength(text[:k].rstrip() + '...') <= maxw:
            lo = k
        else:
            hi = k - 1
    return text[:lo].rstrip() + '...' if lo else '...'


def line_strip(text, rgb, px, maxw, line_h):
    """one log line drawn in its colour with a black outline, maxw x line_h RGBA - kept (STRIPS, the last
    STRIPS_KEPT): the same line is drawn once while it's shown; never changed by its users"""
    key = (text, rgb, px, maxw, line_h)
    with OV_LOCK:
        s = STRIPS.get(key)
        if s is not None:
            STRIPS.move_to_end(key)
            return s
        f = log_font(px)
        sw = max(1, round(px / 12))
        t = fit_text(f, text, maxw - 2 * sw)
        s = Image.new('RGBA', (maxw, line_h), (0, 0, 0, 0))
        d = ImageDraw.Draw(s)
        if isinstance(f, ImageFont.FreeTypeFont):
            d.text((sw, line_h // 2), t, fill=rgb + (255,), font=f, anchor='lm', stroke_width=sw, stroke_fill=(0, 0, 0, 255))
        else:
            d.text((sw, 0), t, fill=rgb + (255,), font=f)          # (a bitmap font: no outline, no anchor)
        STRIPS[key] = s
        while len(STRIPS) > STRIPS_KEPT:
            STRIPS.popitem(last=False)
        return s


def parse_log_body(body):
    """POST /ovlog's body (bytes or str): [((r, g, b), text)], the last LOG_LINES_KEPT - each line's colour (light
    grey when it has none) and its text unescaped (battlerec.unesc - BrecEsc's), tabs and line breaks made spaces"""
    from battlerec import unesc
    if isinstance(body, (bytes, bytearray)):
        body = bytes(body).decode('ascii', 'replace')
    out = []
    for ln in (body or '').split('\n'):
        ln = ln.strip('\r')
        if not ln:
            continue
        col, tab, text = ln.partition('\t')
        if tab and re.fullmatch(r'[0-9A-Fa-f]{6}', col):
            rgb = (int(col[0:2], 16), int(col[2:4], 16), int(col[4:6], 16))
        else:
            rgb = LOG_DEFAULT_RGB
            text = text if tab else ln
        text = unesc(text).replace('\t', ' ').replace('\n', ' ').replace('\r', '')
        out.append((rgb, text))
    return out[-LOG_LINES_KEPT:]


def render_log(lines, w, h, px, line_h, pad, back_a):
    """the overlay's log, w x h RGBA: as many of the newest lines ([(rgb, text)], oldest first) as fit, the newest at
    the bottom at full strength and older ones fainter (to LOG_FADE), on the dark box (alpha back_a)"""
    with OV_LOCK:
        img = backing(w, h, back_a).copy()
        rows = max(1, (h - 2 * pad) // line_h)
        shown = list(lines[-rows:])
        if not shown:
            shown = [(LOG_DIM_RGB, '(nothing logged yet)')]
        n = len(shown)
        maxw = w - 2 * pad
        y = h - pad - n * line_h
        for k, (rgb, text) in enumerate(shown):
            s = line_strip(text, tuple(rgb), px, maxw, line_h)
            f = LOG_FADE + (1 - LOG_FADE) * (k + 1) / n
            if f < 0.999:
                s = s.copy()
                s.putalpha(s.getchannel('A').point(lambda v, f=f: int(v * f + 0.5)))
            img.alpha_composite(s, (pad, y))
            y += line_h
        return img


# ---------------------------------------------------------------- the frame file

def _premul_numpy(img):
    """img's pixels as premultiplied B, G, R, A bytes (numpy - premul_bgra's fallback)"""
    a = np.asarray(img.convert('RGBA'))
    al = a[..., 3:4].astype(np.uint16)
    pm = ((a[..., :3].astype(np.uint16) * al + 127) // 255).astype(np.uint8)
    return np.ascontiguousarray(np.concatenate([pm[..., ::-1], a[..., 3:4]], -1)).tobytes()


def premul_bgra(img):
    """img's pixels as premultiplied B, G, R, A bytes, rows top-down (UpdateLayeredWindow's)"""
    try:
        return img.convert('RGBA').tobytes('raw', 'BGRa')
    except (ValueError, KeyError, OSError):
        return _premul_numpy(img)


def frame_bytes(img, x, y, seq):
    """the whole .wzov frame of img at (x, y) in the client, with seq"""
    w, h = img.size
    return FRAME_HEAD.pack(FRAME_MAGIC, FRAME_VERSION, w, h, w * 4, seq & 0xFFFFFFFF, int(x), int(y)) + premul_bgra(img)


def write_frame(out, img, x, y, seq, force=False):
    """img written as the .wzov frame out (whole to out.tmp, then put in place - never written over directly):
    'ok' - or 'same', nothing written, when it's the picture and place last written there (seq left out) and the
    file is still there, unless force"""
    w, h = img.size
    x, y = int(x), int(y)
    data = premul_bgra(img)
    dig = hashlib.blake2b(data + struct.pack('<IIii', w, h, x, y), digest_size=16).digest()
    key = os.path.normcase(os.path.abspath(out))
    with FRAME_LOCK:
        if not force and FRAME_LAST.get(key) == dig and os.path.exists(out):
            return 'same'
        os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
        tmp = out + '.tmp'
        # (O_SHORT_LIVED: FILE_ATTRIBUTE_TEMPORARY on Windows - kept in memory if it can be)
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, 'O_BINARY', 0) | getattr(os, 'O_SHORT_LIVED', 0),
                     0o666)
        with os.fdopen(fd, 'wb') as f:
            f.write(FRAME_HEAD.pack(FRAME_MAGIC, FRAME_VERSION, w, h, w * 4, seq & 0xFFFFFFFF, x, y))
            f.write(data)
        for _ in range(10):
            try:
                os.replace(tmp, out)
                break
            except PermissionError:
                time.sleep(0.02)
        else:
            try:
                os.remove(tmp)
            except OSError:
                pass
            raise OSError('the frame file is in use: ' + out)
        FRAME_LAST[key] = dig
        return 'ok'
