"""End-to-end check of vision.find_cards on labelled screenshots (see calibrate.py for labels.json), at the
size taken and resized to other UI sizes: every labelled card found in its slot, nothing else found.
Run: python check_cards.py labels.json [scales...]"""
import json, os, sys
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vision  # noqa: E402

vision.LIB = vision.Library()
vision.log = lambda m: None
labels = json.load(open(sys.argv[1]))
extra = [float(s) for s in sys.argv[2:]]
tmp = os.path.join(os.path.dirname(os.path.abspath(__file__)), '_check.png')
problems, checks = 0, 0


def pic_list(school):
    """the pictures AutoFarmer asks the helper for (Vision.ahk's VisionPicList), school = the hitter's"""
    return ([f'{school}/{n}' for n in ['hit1', 'hit2', 'hit3', 'hit4', 'blade', 'trap', 'aura', 'bubble', 'convert', 'wand', 'heal1', 'heal2']]
            + [f'resources/{n}' for n in ['sharpen', 'potent', 'blade3', 'blade4', 'trap3', 'trap4', 'tower', 'reshuffle', 'feint', 'epic', 'colossal', 'gargantuan', 'elementalblade', 'elementaltrap', 'spiritblade', 'spirittrap']]
            + ['life/enchant'])

for path, info in labels.items():
    base = info['scale']
    im0 = Image.open(path).convert('RGB')
    for sc in [base] + extra:
        r = sc / base
        im = im0 if r == 1 else im0.resize((round(im0.width * r), round(im0.height * r)), Image.LANCZOS)
        im.save(tmp)
        W, H = im.size
        cx, cy = W // 2, H // 2
        x1, y1, x2, y2 = cx - round(400 * sc), cy - round(75 * sc), cx + round(400 * sc), cy + round(150 * sc)
        found = vision.find_cards(x1, y1, x2, y2, sc, pic_list(info['dirs'][0]), tmp)
        hand = info['hand']
        lefts = [cx + (-240.4 + 82.03 * k) * sc for k in range(len(hand))]
        slot_of = lambda x: max(range(len(hand)), key=lambda k: -abs(x - (lefts[k] + 22 * sc)))
        got = {}
        for rel, x, y, d in found:
            got.setdefault(slot_of(x), []).append((rel, round(d, 1)))
        bad = []
        for k, want in enumerate(hand):
            names = [g[0] for g in got.get(k, [])]
            checks += 1
            if want and want not in names:
                bad.append(f'slot {k}: {want} missing (got {got.get(k)})')
            extra_here = [g for g in got.get(k, []) if g[0] != want]
            if extra_here:
                bad.append(f'slot {k} ({want}): also {extra_here}')
        problems += len(bad)
        print(f'{os.path.basename(path)} @ {sc}: ' + ('ok' if not bad else '; '.join(bad)))
os.remove(tmp)
print(f'\n{checks} slots checked, {problems} problems')
