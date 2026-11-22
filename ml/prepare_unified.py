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
CAP_TRAIN = int(os.environ.get("CAP_TRAIN", 500)); CAP_PEST = int(os.environ.get("CAP_PEST", 250)); CAP_TEST_PEST = 60
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
import gc, shutil
HF_KW = {"Project-AgML/VegNet_cauliflower_disease_classification": {"data_dir": "raw"}}
for repo, mp in HF.items():
    ds = load_dataset(repo, split="train", **HF_KW.get(repo, {}))
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
    print(repo, len(items), shutil.disk_usage("/").free // 2**30, "GB free", flush=True)
    del ds; gc.collect()
    # The runner has ~14 GB of disk: drop each source's download once its
    # thumbnails are written (a full cache of all sources crashed the runner).
    shutil.rmtree(os.path.expanduser("~/.cache/huggingface"), ignore_errors=True)

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

# 4b. DigiGreen: ~1,000 real Indian farmer photos (crop + diagnosis). Mapped to
# our classes where the diagnosis matches; 15% test_field, 15% val, train x3.
import csv
from huggingface_hub import snapshot_download
DG_CROP = {"Chilli": "Chilli", "Chili": "Chilli", "Potato": "Potato", "Brinjal": "Brinjal", "Maize": "Corn_(maize)", "Mango": "Mango",
           "Tomato": "Tomato", "Papaya": "Papaya", "Groundnut": "Groundnut", "Cauliflower": "Cauliflower", "Banana": "Banana",
           "Rice": "Rice", "Paddy": "Rice", "Pumpkin": "Gourd", "Bottle gourd": "Gourd", "Ridge gourd": "Gourd", "Sponge gourd": "Gourd",
           "Bitter gourd": "Gourd", "Citrus": "Orange", "Lemon": "Orange", "Cabbage": "Cabbage", "Bhindi": "Okra", "Okra": "Okra",
           "Cotton": "Cotton", "Cucumber": "Cucumber", "Watermelon": "Watermelon", "Soybean": "Soybean", "Turmeric": "Turmeric",
           "Strawberry": "Strawberry", "Spinach": "Spinach", "Rose": "Other", "Moringa": "Other", "Curry leaf": "Other", "Medicinal plants": "Other"}
DG_SYN = {"nitrogen deficiency": "nutrient", "potassium deficiency": "nutrient", "phosphorus deficiency": "nutrient", "thrips": "mites and thrips",
          "mites": "mite", "mealybugs": "mealybug", "sigatoka leaf spot": "sigatoka", "papaya ring spot virus": "ring spot", "leaf curl virus": "leaf curl",
          "tobacco mosaic virus": "mosaic", "mosaic virus": "mosaic", "fall armyworm": None}
known = sorted({os.path.basename(d) for d in os.listdir(os.path.join(OUT, "train"))})
def dg_label(crop, diag):
    c = DG_CROP.get(crop.strip())
    if not c: return None
    if c == "Other": return "Other___healthy"
    d = diag.split(";")[0].strip().lower()
    if d == "healthy": return f"{c}___healthy" if f"{c}___healthy" in known else None
    key = DG_SYN.get(d, d)
    if not key: return None
    for lab in known:
        if lab.startswith(c + "___") and key in lab.split("___")[1].lower().replace("_", " "): return lab
    return None
try:
    root = snapshot_download("DigiGreen/Crop_Disease_Images", repo_type="dataset")
    by = defaultdict(list)
    for r in csv.DictReader(open(os.path.join(root, "annotations.csv"))):
        lab = dg_label(r["crop"], r["diagnosis"])
        if lab: by[lab].append(os.path.join(root, r["image_file"] if "/" in r["image_file"] else os.path.join("images", r["image_file"])))
    for lab, files in sorted(by.items()):
        files.sort(); rng.shuffle(files); n = len(files)
        nt = int(n * 0.15) if n >= 4 else 0; nv = int(n * 0.15) if n >= 4 else 0
        for j, f in enumerate(files):
            try: im = Image.open(f).convert("RGB")
            except Exception: continue
            key = f"dg{abs(hash(f)) % 10**10}"
            if j < nt: save(im, "test_field", lab, key)
            elif j < nt + nv: save(im, "val", lab, key)
            else:
                for r_ in "abc": save(im, "train", lab, key + r_)
    print("digigreen", sum(map(len, by.values())), {k: len(v) for k, v in by.items()}, flush=True)
    shutil.rmtree(os.path.expanduser("~/.cache/huggingface"), ignore_errors=True)
except Exception as e:
    print("digigreen skipped:", e, flush=True)

# 5. Field photos from the Krishi Data collector app (zips in COLLECTED_DIR,
# folders <Crop>___<Condition>/*.jpg). Split 70/15/15 per class; training
# copies are repeated 3x because these are the closest to real farmer photos.
import glob, zipfile, io
cdir = os.environ.get("COLLECTED_DIR", "")
for zp in sorted(glob.glob(os.path.join(cdir, "*.zip"))) if cdir else []:
    with zipfile.ZipFile(zp) as z:
        by = defaultdict(list)
        for n in z.namelist():
            parts = n.split("/")
            if len(parts) >= 2 and "___" in parts[-2] and n.lower().endswith((".jpg", ".jpeg", ".png")):
                by[parts[-2]].append(n)
        for labc, files in by.items():
            files.sort(); rng.shuffle(files)
            nt, nv = int(len(files) * 0.15), int(len(files) * 0.15)
            for j, n in enumerate(files):
                im = Image.open(io.BytesIO(z.read(n))).convert("RGB")
                key = f"fd{abs(hash((zp, n))) % 10**10}"
                if j < nt: save(im, "test_field", labc, key)
                elif j < nt + nv: save(im, "val", labc, key)
                else:
                    for r in "abc": save(im, "train", labc, key + r)
        print("collected", zp, {k: len(v) for k, v in by.items()}, flush=True)

json.dump({s: dict(v) for s, v in stats.items()}, open(os.path.join(OUT, "stats.json"), "w"), indent=1)
print({s: (len(v), sum(v.values())) for s, v in stats.items()})
