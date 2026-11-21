"""Lesion-area-ratio severity estimator (reference implementation, OpenCV).

The Android app runs the same steps in android/.../SeverityBridge.kt with
OpenCV for Android (Arm KleidiCV-accelerated builds):
  1. centre-square crop, resize to 256x256
  2. GrabCut initialised with the central rectangle (12% margin) -> foreground
     (farmers are told to centre one leaf; this ignores background, soil and
     neighbouring leaves, which a colour threshold alone could not)
  3. keep the foreground component closest to the centre (area >= 2%), fill holes
  4. healthy tissue: hue 65-175 deg, S > 0.10, V > 0.10 (grid-searched)
  5. ratio = |leaf & ~healthy| / |leaf|
  6. ratio < 0.10 mild, < 0.25 moderate, else urgent; high-risk diseases
     (late blight, viruses, citrus greening) are raised one level.
"""
import cv2
import numpy as np
from PIL import Image

N = 256
MARGIN = 0.12
MILD, MODERATE = 0.10, 0.25


def segment_leaf(rgb):
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    mask = np.zeros((N, N), np.uint8)
    m = int(N * MARGIN)
    bgd, fgd = np.zeros((1, 65), np.float64), np.zeros((1, 65), np.float64)
    cv2.grabCut(bgr, mask, (m, m, N - 2 * m, N - 2 * m), bgd, fgd, 4, cv2.GC_INIT_WITH_RECT)
    leaf = ((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD)).astype(np.uint8)
    n, lab, stats, cent = cv2.connectedComponentsWithStats(leaf, connectivity=4)
    cands = [(np.hypot(*(cent[i] - N / 2)) / np.sqrt(stats[i, cv2.CC_STAT_AREA]), i)
             for i in range(1, n) if stats[i, cv2.CC_STAT_AREA] >= 0.02 * N * N]
    if not cands:
        return np.zeros((N, N), bool)
    leaf = (lab == min(cands)[1]).astype(np.uint8)
    ff = leaf.copy()
    cv2.floodFill(ff, np.zeros((N + 2, N + 2), np.uint8), (0, 0), 1)
    return (leaf | (1 - ff)).astype(bool)


def lesion_ratio(img: Image.Image):
    im = img.convert("RGB"); w, h = im.size; s = min(w, h)
    im = im.crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s))
    rgb = cv2.resize(np.asarray(im), (N, N), interpolation=cv2.INTER_AREA)
    leaf = segment_leaf(rgb)
    hsv = cv2.cvtColor(rgb, cv2.COLOR_RGB2HSV_FULL).astype(np.float32)
    hdeg, s_, v_ = hsv[..., 0] * 360 / 256, hsv[..., 1] / 255, hsv[..., 2] / 255
    healthy = (hdeg >= 65) & (hdeg <= 175) & (s_ > 0.10) & (v_ > 0.10)
    lesion = leaf & ~healthy
    n_leaf = leaf.sum()
    return (float(lesion.sum() / n_leaf) if n_leaf else 0.0), leaf, lesion


def level(ratio, healthy_class=False, high_risk=False):
    if healthy_class:
        return "none"
    lv = 0 if ratio < MILD else 1 if ratio < MODERATE else 2
    if high_risk:
        lv = min(2, lv + 1)
    return ["mild", "moderate", "urgent"][lv]


if __name__ == "__main__":
    import sys
    r, leaf, _ = lesion_ratio(Image.open(sys.argv[1]))
    print(f"lesion ratio {r:.3f}, leaf covers {leaf.mean():.2f} of the image")
