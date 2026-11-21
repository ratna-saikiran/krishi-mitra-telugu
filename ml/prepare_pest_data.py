"""Download the IP102-style insect pest dataset from Hugging Face and write it
as data/pests/{train,val,test}/<class>/*.jpg. Prints the README and class
list so the run log documents exactly what was used."""
import os, sys, io, random
from datasets import load_dataset
from huggingface_hub import hf_hub_download

REPO = sys.argv[1] if len(sys.argv) > 1 else "EnmmmmOvO/insect-pest-dataset"
OUT = sys.argv[2] if len(sys.argv) > 2 else "data/pests"
try:
    print(open(hf_hub_download(REPO, "README.md", repo_type="dataset")).read()[:3000])
except Exception as e:
    print("no README", e)
ds = load_dataset(REPO)
print(ds)
split0 = next(iter(ds.values()))
img_col = next(k for k, f in split0.features.items() if f.__class__.__name__ == "Image")
lab_col = next(k for k, f in split0.features.items() if f.__class__.__name__ == "ClassLabel")
names = split0.features[lab_col].names
print("classes", len(names), names)
splits = {"train": ds["train"]}
if "validation" in ds: splits["val"] = ds["validation"]
if "test" in ds: splits["test"] = ds["test"]
if "val" not in splits:  # carve a validation split from train (10%), test stays untouched
    sp = ds["train"].train_test_split(test_size=0.1, seed=0, stratify_by_column=lab_col)
    splits["train"], splits["val"] = sp["train"], sp["test"]
for name, d in splits.items():
    for i, ex in enumerate(d):
        c = f"{ex[lab_col]:03d}_" + names[ex[lab_col]].strip().replace("/", "-").replace(" ", "_")
        os.makedirs(f"{OUT}/{name}/{c}", exist_ok=True)
        ex[img_col].convert("RGB").save(f"{OUT}/{name}/{c}/{i}.jpg", quality=90)
    print(name, len(d))
