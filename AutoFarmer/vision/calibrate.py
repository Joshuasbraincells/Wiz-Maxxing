"""Checks vision.py's card matching on saved battle screenshots with known hands.

For every card slot: the distance of the right picture (should be small) and of the closest wrong one
(should be big), at the UI size the screenshot was taken and at other sizes (the screenshot resized - a
stand-in for the game drawn at that size). Run: python calibrate.py <labels.json> [scales...]
labels.json: {"<screenshot path>": {"scale": 1.144, "dirs": ["balance", "resources"],
              "hand": ["balance/hit1", "balance/wand", null, ...]}}   (null = a card with no picture)
"""
import json, os, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vision  # noqa: E402

vision.LIB = vision.Library()
labels = json.load(open(sys.argv[1]))
extra = [float(s) for s in sys.argv[2:]]
worst_true, best_false = [], []
for path, info in labels.items():
    base = info['scale']
    im0 = Image.open(path).convert('RGB')
    for sc in [base] + extra:
        r = sc / base
        im = im0 if r == 1 else im0.resize((round(im0.width * r), round(im0.height * r)), Image.LANCZOS)
        W, H = im.size
        cx, cy = W // 2, H // 2
        x1, y1, x2, y2 = cx - round(400 * sc), cy - round(75 * sc), cx + round(400 * sc), cy + round(150 * sc)
        img = np.asarray(im).astype(np.float32)[y1:y2, x1:x2]
        region = vision.Region(img)
        pitch = 82 * sc
        hand = info['hand']
        n = len(hand)
        # (measured at 1440p with 7 cards: card k's left = middle + (-240.4 + 82.03 k) x UI scale; the
        # deck pile on the left shifts the hand)
        pitch = 82.03 * sc
        lefts = [cx + (-240.4 + 82.03 * k) * sc - x1 for k in range(n)]
        per_slot = [{} for _ in range(n)]
        for sub in info['dirs']:
            for name in vision.LIB.names_in(sub):
                pic = vision.LIB.get(f'{sub}\\{name}.png', sc)
                if pic is None:
                    continue
                dmap = region.distance_map(*pic)
                if dmap is None:
                    continue
                for k in range(n):
                    a, b = int(max(0, lefts[k] - 4)), int(min(dmap.shape[1], lefts[k] + pitch + 4))
                    per_slot[k][f'{sub}/{name}'] = float(dmap[:, a:b].min())
        line = []
        for k, want in enumerate(hand):
            d = per_slot[k]
            wrong = min((v for kk, v in d.items() if kk != want), default=999)
            right = d.get(want, None) if want else None
            if right is not None:
                worst_true.append(right)
            best_false.append(wrong)
            line.append(f'{(want or "-").split("/")[-1]}={right if right is None else round(right, 1)}/{round(wrong, 1)}')
        print(f'{os.path.basename(path)} @ {sc}: ' + ' '.join(line))
print(f'\nright pictures: worst {max(worst_true):.1f}   wrong pictures: closest {min(best_false):.1f}   (threshold now {vision.CARD_DIST})')
