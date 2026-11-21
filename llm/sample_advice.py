"""Run the exported .pte on real pipeline outputs to measure Telugu quality,
prompt/answer length in tokens and host-side speed, for three prompt styles:
  te_te: Telugu facts -> Telugu answer (what the app does today)
  en_te: compact English facts -> short Telugu answer (fewer prompt tokens)
  en_en: English facts -> English answer (reference)
python llm/sample_advice.py --pte X.pte --tokenizer tokenizer.model --params params.json
"""
import argparse, json, os, re, sys, time
from types import SimpleNamespace

ap = argparse.ArgumentParser()
ap.add_argument("--pte", required=True); ap.add_argument("--tokenizer", required=True)
ap.add_argument("--params", required=True); ap.add_argument("--out", default="llm_samples.json")
ap.add_argument("--max_new", type=int, default=400)
a = ap.parse_args()
from executorch.examples.models.llama.runner.native import NativeLlamaRunner

db = json.load(open(os.path.join(os.path.dirname(__file__), "..", "app", "assets", "advisory_te.json")))
SYS_TE = ("You are a friendly agricultural extension officer in Andhra Pradesh and Telangana. "
          "Reply ONLY in simple Telugu script. Use ONLY the facts given. Never invent chemical names or doses.")
TASK_TE = ("Using the facts above, write advice for the farmer in Telugu as 4 short bullet points: "
           "1) what the problem is, 2) what to do today, 3) the spray with exact dose (if any), 4) how to prevent it next time.")
TASK_EN_TE = "Write 3 short, simple sentences in Telugu script for the farmer: the problem, what to spray today (exact dose), and prevention."
TASK_EN = "Write 3 short, simple sentences for the farmer: the problem, what to spray today (exact dose), and prevention."

def facts_te(e, level, lesion):
    steps = db["severity_generic"][level] + e["steps"][level]
    return (f"పంట: {e['crop_te']} ({e['crop_en']})\nసమస్య: {e['disease_te']} ({e['disease_en']})\n"
            f"తీవ్రత: {db['severity_te'][level]} ({level}), ఆకు దెబ్బతిన్న భాగం {lesion}%\n"
            f"కారణం: {e['cause_te']}\nధృవీకరించిన చర్యలు:\n" + "".join(f"- {s}\n" for s in steps) +
            f"నివారణ: {' '.join(e['prevention_te'])}\n")

def facts_en(e, level, lesion):
    sp = "; ".join(f"{x['name_en']} {x['dose_per_l']:g} {x['unit']} per litre" for x in e["sprays"][level]) or "no chemical; remove affected plants"
    return (f"Crop: {e['crop_en']}. Problem: {e['disease_en']} ({e['type']}). Severity: {level}, {lesion}% of leaf damaged.\n"
            f"Verified spray: {sp}.\n")

def chat(system, user):
    return ("<|start_header_id|>system<|end_header_id|>\n\n" + system + "<|eot_id|>"
            "<|start_header_id|>user<|end_header_id|>\n\n" + user + "<|eot_id|>"
            "<|start_header_id|>assistant<|end_header_id|>\n\n")

def telugu_ratio(t):
    letters = [c for c in t if c.isalpha()]
    return sum("ఀ" <= c <= "౿" for c in letters) / max(1, len(letters))

runner = NativeLlamaRunner(SimpleNamespace(model="llama3_2", pte=a.pte, tokenizer=a.tokenizer, params=a.params,
                                           tokenizer_config=None, kv_cache=True, max_len=2048, temperature=0.0, prompt=""))
tok = runner.tokenizer
tok.decode_token = lambda t: ""   # streaming print breaks on partial UTF-8 Telugu bytes
def decode(ids):
    return tok.model.decode([i for i in ids if i < 128000]) if hasattr(tok, "model") else tok.decode(ids)

cases = [("Tomato___Early_blight", "moderate", 18), ("Tomato___Late_blight", "urgent", 35),
         ("Rice___Blast", "moderate", 15), ("Cotton___Leaf_curl_virus", "urgent", 30)]
res = []
for label, level, lesion in cases:
    e = db["classes"].get(label)
    if not e: continue
    for style, prompt, facts in (("te_te", chat(SYS_TE, facts_te(e, level, lesion) + "\n" + TASK_TE), facts_te(e, level, lesion)),
                                 ("en_te", chat(SYS_TE, facts_en(e, level, lesion) + TASK_EN_TE), facts_en(e, level, lesion)),
                                 ("en_en", chat("You are a friendly agricultural extension officer. Use only the facts given.", facts_en(e, level, lesion) + TASK_EN), facts_en(e, level, lesion))):
        ids = tok.encode(prompt, bos=True, eos=False)
        t = time.time()
        out_ids = runner.generate(prompt_tokens=ids, max_seq_len=min(2048, len(ids) + a.max_new), temperature=0.0)
        dt = time.time() - t
        out = decode(out_ids).replace("<|eot_id|>", "").strip()
        nums = re.findall(r"\d+(?:\.\d+)?", re.sub(r"(?m)^\s*\d+[\).]", "", out))
        res.append(dict(label=label, level=level, style=style, prompt_tokens=len(ids), output_tokens=len(out_ids),
                        host_seconds=round(dt, 1), host_tok_per_s=round((len(ids) + len(out_ids)) / dt, 1),
                        telugu_ratio=round(telugu_ratio(out), 2), output_chars=len(out),
                        tokens_per_char=round(len(out_ids) / max(1, len(out)), 2),
                        numbers_grounded=all(n in facts for n in nums), output=out))
        print(json.dumps(res[-1], ensure_ascii=False, indent=1), flush=True)
json.dump(res, open(a.out, "w"), ensure_ascii=False, indent=1)
