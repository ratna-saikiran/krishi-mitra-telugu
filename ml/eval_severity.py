"""Sanity-check severity: lesion ratio should separate healthy from diseased
leaves (no pixel-level lesion ground truth exists in PlantVillage)."""
import json, sys, numpy as np, time
from PIL import Image
from sklearn.metrics import roc_auc_score
sys.path.insert(0, "ml"); from severity import lesion_ratio
OUT = sys.argv[1] if len(sys.argv) > 1 else "ml/out"
split = json.load(open(f"{OUT}/split.json"))["test"]
rng = np.random.default_rng(0); idx = rng.choice(len(split), 600, replace=False)
ys, rs, per = [], [], {}
t = time.time()
for i in idx:
    p = split[i]; cls = p.split("/")[-2]; r, *_ = lesion_ratio(Image.open(p))
    ys.append(0 if cls.endswith("healthy") else 1); rs.append(r); per.setdefault(cls, []).append(r)
dt = (time.time() - t) / len(idx) * 1000
res = {"n": len(idx), "auc_healthy_vs_diseased": roc_auc_score(ys, rs),
       "median_ratio_healthy": float(np.median([r for r, y in zip(rs, ys) if y == 0])),
       "median_ratio_diseased": float(np.median([r for r, y in zip(rs, ys) if y == 1])),
       "ms_per_image_python_x86": dt,
       "per_class_median": {k: round(float(np.median(v)), 3) for k, v in sorted(per.items())}}
json.dump(res, open(f"{OUT}/severity_eval.json", "w"), indent=1); print(json.dumps(res, indent=1))
