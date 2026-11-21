"""Evaluate FP32 and INT8 TFLite models on the PlantVillage test split (lab)
and the PlantDoc test set (field). Writes ml/out/metrics.json."""
import json, os, sys, time
import numpy as np, tensorflow as tf
from PIL import Image
from sklearn.metrics import accuracy_score, precision_recall_fscore_support
sys.path.insert(0, os.path.dirname(__file__)); from plantdoc_map import PD2PV

OUT = sys.argv[1] if len(sys.argv) > 1 else "ml/out"
PD_TEST = sys.argv[2] if len(sys.argv) > 2 else "/home/user/data/pd/test"
labels = [l.strip() for l in open(f"{OUT}/labels.txt") if l.strip()]
pv = [(p, labels.index(p.split("/")[-2])) for p in json.load(open(f"{OUT}/split.json"))["test"]]
pd = []
for d, lab in PD2PV.items():
    dd = os.path.join(PD_TEST, d)
    if os.path.isdir(dd):
        pd += [(os.path.join(dd, f), labels.index(lab)) for f in sorted(os.listdir(dd))]

def load(p):
    im = Image.open(p).convert("RGB")
    w, h = im.size; s = min(w, h)   # centre square crop, same as the app
    im = im.crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s)).resize((224, 224), Image.BILINEAR)
    return np.asarray(im)

def run(model, items):
    it = tf.lite.Interpreter(model_path=model, num_threads=4); it.allocate_tensors()
    i, o = it.get_input_details()[0], it.get_output_details()[0]
    preds, ts = [], []
    for p, _ in items:
        x = load(p)[None].astype(i["dtype"])
        t = time.perf_counter(); it.set_tensor(i["index"], x); it.invoke(); ts.append(time.perf_counter() - t)
        preds.append(int(np.argmax(it.get_tensor(o["index"])[0])))
    y = [l for _, l in items]
    pr, rc, f1, _ = precision_recall_fscore_support(y, preds, average="macro", zero_division=0)
    present = sorted(set(y))
    prp, rcp, f1p, _ = precision_recall_fscore_support(y, preds, labels=present, average="macro", zero_division=0)
    per = precision_recall_fscore_support(y, preds, labels=present, zero_division=0)
    # Crop-level accuracy: right crop even if wrong disease
    crop_acc = np.mean([labels[a].split("___")[0] == labels[b].split("___")[0] for a, b in zip(y, preds)])
    return dict(n=len(items), accuracy=accuracy_score(y, preds), macro_precision=prp, macro_recall=rcp,
                macro_f1=f1p, crop_accuracy=float(crop_acc), x86_ms_median=1000 * float(np.median(ts)),
                per_class={labels[c]: dict(p=round(float(per[0][k]), 3), r=round(float(per[1][k]), 3), n=int(per[3][k]))
                           for k, c in enumerate(present)})

res = {}
MODELS = os.environ.get("MODELS", "classifier_fp32.tflite,classifier_int8.tflite").split(",")
for m in MODELS:
    path = f"{OUT}/{m}"
    res[m] = dict(size_mb=os.path.getsize(path) / 1e6, plantvillage_test=run(path, pv), plantdoc_test=run(path, pd))
    print(m, {k: (v if not isinstance(v, dict) else {kk: vv for kk, vv in v.items() if kk != "per_class"}) for k, v in res[m].items()})
json.dump(res, open(f"{OUT}/metrics_" + "_".join(x.split(".")[0].split("_")[-1] for x in MODELS) + ".json", "w"), indent=1)
