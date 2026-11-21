"""Rigorous metrics for a TFLite classifier on a held-out set."""
import json, os, time
import numpy as np
import tensorflow as tf
from PIL import Image
from sklearn.metrics import accuracy_score, confusion_matrix, precision_recall_fscore_support

def _load(p, img):
    im = Image.open(p).convert("RGB"); w, h = im.size; s = min(w, h)
    im = im.crop(((w - s) // 2, (h - s) // 2, (w - s) // 2 + s, (h - s) // 2 + s)).resize((img, img), Image.BILINEAR)
    return np.asarray(im, np.float32)[None]

def evaluate_tflite(model_path, items, names, out_prefix, img=224, group=None):
    """items: [(path, label_idx)], names: class names. group: optional fn label->group name
    (e.g. crop) for group-level accuracy. Writes <out_prefix>.json and _confusion.png."""
    it = tf.lite.Interpreter(model_path=model_path, num_threads=4); it.allocate_tensors()
    i, o = it.get_input_details()[0], it.get_output_details()[0]
    P, ts = [], []
    for pth, _ in items:
        x = _load(pth, img).astype(i["dtype"])
        t = time.perf_counter(); it.set_tensor(i["index"], x); it.invoke(); ts.append(time.perf_counter() - t)
        P.append(it.get_tensor(o["index"])[0])
    P = np.array(P); y = np.array([l for _, l in items]); pred = P.argmax(1); conf = P.max(1)
    present = sorted(set(y.tolist()))
    pr, rc, f1, sup = precision_recall_fscore_support(y, pred, labels=present, zero_division=0)
    top5 = float(np.mean([yy in np.argsort(-pp)[:5] for yy, pp in zip(y, P)]))
    rng = np.random.default_rng(0); boots = [accuracy_score(y[s], pred[s]) for s in (rng.integers(0, len(y), len(y)) for _ in range(1000))]
    bins = np.linspace(0, 1, 11); ece = 0.0
    for lo, hi in zip(bins[:-1], bins[1:]):
        m = (conf > lo) & (conf <= hi)
        if m.any(): ece += m.mean() * abs((pred[m] == y[m]).mean() - conf[m].mean())
    cov = {f"{t:.1f}": dict(coverage=float((conf >= t).mean()), accuracy=float((pred[conf >= t] == y[conf >= t]).mean()) if (conf >= t).any() else None)
           for t in (0.0, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9)}
    res = dict(model=os.path.basename(model_path), size_mb=os.path.getsize(model_path) / 1e6, n=int(len(y)),
               accuracy=float((pred == y).mean()), accuracy_95ci=[float(np.percentile(boots, 2.5)), float(np.percentile(boots, 97.5))],
               top5_accuracy=top5, macro_precision=float(pr.mean()), macro_recall=float(rc.mean()), macro_f1=float(f1.mean()),
               weighted_f1=float(np.average(f1, weights=sup)), ece=float(ece), accuracy_vs_confidence_threshold=cov,
               host_x86_ms_median=1000 * float(np.median(ts)),
               per_class={names[c]: dict(precision=round(float(pr[k]), 3), recall=round(float(rc[k]), 3), f1=round(float(f1[k]), 3), n=int(sup[k]))
                          for k, c in enumerate(present)})
    if group:
        res["group_accuracy"] = float(np.mean([group(a) == group(b) for a, b in zip(y, pred)]))
    json.dump(res, open(out_prefix + ".json", "w"), indent=1)
    cm = confusion_matrix(y, pred, labels=present, normalize="true")
    try:
        import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
        n = len(present); fig, ax = plt.subplots(figsize=(max(8, n * 0.22), max(7, n * 0.2)))
        ax.imshow(cm, cmap="Greens", vmin=0, vmax=1)
        ax.set_xticks(range(n)); ax.set_yticks(range(n))
        lab = [names[c][:28] for c in present]
        ax.set_xticklabels(lab, rotation=90, fontsize=6); ax.set_yticklabels(lab, fontsize=6)
        ax.set_xlabel("predicted"); ax.set_ylabel("true"); ax.set_title(f"{res['model']}: acc {res['accuracy']:.3f}, macro-F1 {res['macro_f1']:.3f}")
        fig.tight_layout(); fig.savefig(out_prefix + "_confusion.png", dpi=150); plt.close(fig)
    except Exception as e:
        print("no plot", e)
    print(json.dumps({k: v for k, v in res.items() if k != "per_class"}, indent=1))
    return res
