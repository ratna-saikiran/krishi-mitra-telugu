"""Full report for the disease classifier on PlantVillage test (lab) and
PlantDoc test (field, never trained on). python ml/eval_disease_report.py OUT PD_TEST"""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from metrics_report import evaluate_tflite
from plantdoc_map import PD2PV
OUT, PD_TEST = sys.argv[1], sys.argv[2]
MODELS = sys.argv[3].split(",") if len(sys.argv) > 3 else ["classifier_fp32.tflite", "classifier_dyn8.tflite", "classifier_int8.tflite"]
labels = [l.strip() for l in open(f"{OUT}/labels.txt") if l.strip()]
pv = [(p, labels.index(p.split("/")[-2])) for p in json.load(open(f"{OUT}/split.json"))["test"]]
pd = [(os.path.join(PD_TEST, d, f), labels.index(lab)) for d, lab in PD2PV.items() if os.path.isdir(os.path.join(PD_TEST, d))
      for f in sorted(os.listdir(os.path.join(PD_TEST, d)))]
crop = lambda i: labels[i].split("___")[0]
os.makedirs(f"{OUT}/report", exist_ok=True)
for m in MODELS:
    if not os.path.exists(f"{OUT}/{m}"): continue
    for name, items in (("plantvillage", pv), ("plantdoc", pd)):
        evaluate_tflite(f"{OUT}/{m}", items, labels, f"{OUT}/report/{m.split('.')[0]}_{name}", group=crop)
