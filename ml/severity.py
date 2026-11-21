"""Lesion-area-ratio severity estimator (reference implementation).

Kept deliberately simple and dependency-light so the Dart port in
app/lib/vision/severity.dart is a line-by-line equivalent:
  1. resize to 256x256, convert to HSV (H in degrees 0-360, S,V in 0-1)
  2. leaf candidates: plant-coloured pixels (green/yellow/brown hue, S>0.15, V>0.12)
  3. keep the largest 4-connected component, fill its holes -> leaf mask
     (holes are usually dark/white lesions, so filling matters)
  4. healthy tissue: hue 65-175 deg (green), S>0.10, V>0.10 (grid-searched)
  5. ratio = |leaf & ~healthy| / |leaf|
  6. ratio < 0.10 mild, < 0.25 moderate, else urgent; high-risk diseases
     (late blight, viruses, citrus greening) are bumped one level.
"""
from collections import deque
import numpy as np
from PIL import Image

N = 256
MILD, MODERATE = 0.10, 0.25

def hsv(rgb):
    r, g, b = [rgb[..., i].astype(np.float32) / 255 for i in range(3)]
    mx, mn = np.maximum(np.maximum(r, g), b), np.minimum(np.minimum(r, g), b)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rr = m & (mx == r); gg = m & (mx == g) & ~rr; bb = m & ~rr & ~gg
    h[rr] = (60 * ((g - b)[rr] / d[rr])) % 360
    h[gg] = 60 * ((b - r)[gg] / d[gg]) + 120
    h[bb] = 60 * ((r - g)[bb] / d[bb]) + 240
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0)
    return h, s, mx

def largest_cc(mask):
    lab = np.zeros(mask.shape, np.int32); best, best_n, cur = 0, 0, 0
    for y, x in zip(*np.nonzero(mask)):
        if lab[y, x]: continue
        cur += 1; q = deque([(y, x)]); lab[y, x] = cur; n = 0
        while q:
            cy, cx = q.popleft(); n += 1
            for ny, nx in ((cy+1, cx), (cy-1, cx), (cy, cx+1), (cy, cx-1)):
                if 0 <= ny < N and 0 <= nx < N and mask[ny, nx] and not lab[ny, nx]:
                    lab[ny, nx] = cur; q.append((ny, nx))
        if n > best_n: best, best_n = cur, n
    return lab == best if best else mask

def fill_holes(mask):
    outside = np.zeros_like(mask); q = deque()
    for i in range(N):
        for y, x in ((0, i), (N-1, i), (i, 0), (i, N-1)):
            if not mask[y, x] and not outside[y, x]:
                outside[y, x] = True; q.append((y, x))
    while q:
        cy, cx = q.popleft()
        for ny, nx in ((cy+1, cx), (cy-1, cx), (cy, cx+1), (cy, cx-1)):
            if 0 <= ny < N and 0 <= nx < N and not mask[ny, nx] and not outside[ny, nx]:
                outside[ny, nx] = True; q.append((ny, nx))
    return ~outside

def lesion_ratio(img: Image.Image):
    rgb = np.asarray(img.convert("RGB").resize((N, N), Image.BILINEAR))
    h, s, v = hsv(rgb)
    plant = (s > 0.15) & (v > 0.12) & (h >= 15) & (h <= 170)
    leaf = fill_holes(largest_cc(plant))
    healthy = (h >= 65) & (h <= 175) & (s > 0.10) & (v > 0.10)
    n_leaf = leaf.sum()
    if n_leaf < 0.05 * N * N:
        return 0.0, leaf, leaf
    lesion = leaf & ~healthy
    return float(lesion.sum() / n_leaf), leaf, lesion

def level(ratio, healthy_class=False, high_risk=False):
    if healthy_class: return "none"
    lv = 0 if ratio < MILD else 1 if ratio < MODERATE else 2
    if high_risk: lv = min(2, lv + 1)
    return ["mild", "moderate", "urgent"][lv]

if __name__ == "__main__":
    import sys
    r, *_ = lesion_ratio(Image.open(sys.argv[1]))
    print(f"lesion ratio {r:.3f}")
