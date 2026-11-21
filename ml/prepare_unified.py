"""Build data/unified/{train,val,test_<domain>}/<label>/*.jpg for the unified
crop + disease + pest model. Every source gets a seeded, stratified split;
test images are never used for training or model selection.
Domains: plantvillage (lab), plantdoc (field), agml (mixed field/lab, Indian
subcontinent crops), ip102 (insects, official split)."""
import json, os, random, sys
from collections import defaultdict
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
from unified_sources import HF, IP102
from plantdoc_map import PD2PV

PV, PD, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
CAP_TRAIN, CAP_PEST, CAP_TEST_PEST = 500, 250, 60
rng = random.Random(0)
stats = defaultdict(lambda: defaultdict(int))

def save(img, split, label, key):
    d = os.path.join(OUT, split, label); os.makedirs(d, exist_ok=True)
    im = img.convert("RGB"); im.thumbnail((320, 320))
    im.save(os.path.join(d, f"{key}.jpg"), quality=90); stats[split][label] += 1

def split3(items, val=0.15, test=0.15):
    by = defaultdict(list)
    for it in items: by[it[1]].append(it)
    tr, va, te = [], [], []
    for lab, xs in by.items():
        rng.shuffle(xs); n = len(xs); nt, nv = max(1, int(n * test)), max(1, int(n * val))
        te += xs[:nt]; va += xs[nt:nt + nv]; tr += xs[nt + nv:]
    return tr, va, te

# 1. PlantVillage (lab)
items = [(os.path.join(PV, c, f), c) for c in sorted(os.listdir(PV)) for f in sorted(os.listdir(os.path.join(PV, c)))]
tr, va, te = split3(items, 0.05, 0.10)
cnt = defaultdict(int)
for i, (p, l) in enumerate(tr):
    if cnt[l] < CAP_TRAIN: cnt[l] += 1; save(Image.open(p), "train", l, f"pv{i}")
for i, (p, l) in enumerate(va[:]): save(Image.open(p), "val", l, f"pv{i}") if stats["val"][l] < 40 else None
for i, (p, l) in enumerate(te):
    if stats["test_plantvillage"][l] < 100: save(Image.open(p), "test_plantvillage", l, f"pv{i}")

# 2. PlantDoc (field): train split -> train (x2) / val ; official test -> test_plantdoc
for split_dir, out in (("train", "train"), ("test", "test_plantdoc")):
    for d, lab in PD2PV.items():
        dd = os.path.join(PD, split_dir, d)
        if not os.path.isdir(dd): continue
        fs = sorted(os.listdir(dd)); rng.shuffle(fs)
        for i, f in enumerate(fs):
            try: im = Image.open(os.path.join(dd, f))
            except Exception: continue
            if out == "train" and i < 0.15 * len(fs): save(im, "val", lab, f"pd{i}")
            elif out == "train":
                save(im, "train", lab, f"pd{i}a"); save(im, "train", lab, f"pd{i}b")  # oversample field images
            else: save(im, out, lab, f"pd{i}")

# 3. Hugging Face AgML sources (Indian-subcontinent crops)
from datasets import load_dataset
for repo, mp in HF.items():
    ds = load_dataset(repo, split="train")
    names = ds.features["label"].names
    items = [(i, mp.get(names[l])) for i, l in enumerate(ds["label"]) if mp.get(names[l])]
    tr, va, te = split3(items)
    cnt = defaultdict(int)
    for split, its in (("train", tr), ("val", va), ("test_agml", te)):
        for i, lab in its:
            if split == "train":
                if cnt[lab] >= CAP_TRAIN: continue
                cnt[lab] += 1
            save(ds[i]["image"], split, lab, f"{repo.split('/')[1][:12]}{i}")
    print(repo, len(items), flush=True)

# 4. IP102 pests (official splits)
names = [l.strip() for l in open(os.path.join(os.path.dirname(__file__), "ip102_classes.txt")) if l.strip()]
lab = lambda k: "Pest___" + names[k].replace(" ", "_").replace("/", "-")
for split, out, cap in (("train", "train", CAP_PEST), ("validation", "val", 40), ("test", "test_ip102", CAP_TEST_PEST)):
    ds = load_dataset(IP102, split=split)
    labels = ds["label"]
    if max(labels) == len(names): labels = [l - 1 for l in labels]   # 1-based ids
    idx = list(range(len(ds))); rng.shuffle(idx); cnt = defaultdict(int)
    for i in idx:
        k = labels[i]
        if cnt[k] >= cap: continue
        cnt[k] += 1; save(ds[i]["image"], out, lab(k), f"ip{i}")
    print("ip102", split, sum(cnt.values()), flush=True)

json.dump({s: dict(v) for s, v in stats.items()}, open(os.path.join(OUT, "stats.json"), "w"), indent=1)
print({s: (len(v), sum(v.values())) for s, v in stats.items()})
