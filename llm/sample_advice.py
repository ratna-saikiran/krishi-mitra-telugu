"""Run the exported .pte on a few real pipeline outputs (same prompt as
app/lib/advisory/prompt.dart) to check Telugu quality, prompt length in
tokens and host-side speed. Used in CI after export; results go in the report.

python llm/sample_advice.py --pte X.pte --tokenizer tokenizer.model --params params.json
"""
import argparse, json, os, re, subprocess, sys, time
from pytorch_tokenizers import get_tokenizer

ap = argparse.ArgumentParser()
ap.add_argument("--pte", required=True); ap.add_argument("--tokenizer", required=True)
ap.add_argument("--params", required=True); ap.add_argument("--out", default="llm_samples.json")
ap.add_argument("--max_len", type=int, default=1536)
a = ap.parse_args()
db = json.load(open(os.path.join(os.path.dirname(__file__), "..", "app", "assets", "advisory_te.json")))

SYSTEM = ("You are a friendly agricultural extension officer in Andhra Pradesh and Telangana. "
          "Reply ONLY in simple Telugu script. Use ONLY the facts given. "
          "Never invent chemical names or doses; copy doses exactly as given. Keep it short.")
TASK = ("Using the facts above, write advice for the farmer in Telugu as 4 short bullet points: "
        "1) what the problem is, 2) what to do today, 3) the spray with exact dose (if any), 4) how to prevent it next time.")

def prompt(label, level, lesion):
    e = db["classes"][label]
    steps = db["severity_generic"][level] + e["steps"][level]
    facts = (f"పంట: {e['crop_te']} ({e['crop_en']})\nసమస్య: {e['disease_te']} ({e['disease_en']})\n"
             f"తీవ్రత: {db['severity_te'][level]} ({level}), ఆకు దెబ్బతిన్న భాగం {lesion}%\n"
             f"కారణం: {e['cause_te']}\nధృవీకరించిన చర్యలు:\n" + "".join(f"- {s}\n" for s in steps) +
             f"నివారణ: {' '.join(e['prevention_te'])}\n")
    return ("<|start_header_id|>system<|end_header_id|>\n\n" + SYSTEM + "<|eot_id|>"
            "<|start_header_id|>user<|end_header_id|>\n\n" + facts + "\n" + TASK + "<|eot_id|>"
            "<|start_header_id|>assistant<|end_header_id|>\n\n"), facts

def telugu_ratio(t):
    letters = [c for c in t if c.isalpha()]
    return sum("ఀ" <= c <= "౿" for c in letters) / max(1, len(letters))

tok = get_tokenizer(a.tokenizer)
cases = [("Tomato___Early_blight", "moderate", 18), ("Tomato___Late_blight", "urgent", 35),
         ("Corn_(maize)___Common_rust_", "mild", 6), ("Tomato___Tomato_Yellow_Leaf_Curl_Virus", "urgent", 28)]
res = []
for label, level, lesion in cases:
    p, facts = prompt(label, level, lesion)
    n_prompt = len(tok.encode(p, bos=True, eos=False))
    n_facts_words = len(facts.split())
    t = time.time()
    r = subprocess.run([sys.executable, "-m", "executorch.examples.models.llama.runner.native", "--model", "llama3_2",
                        "--pte", a.pte, "--tokenizer", a.tokenizer, "--params", a.params, "--prompt", p,
                        "--temperature", "0", "-kv", "--max_len", str(a.max_len)], capture_output=True, text=True)
    dt = time.time() - t
    out = r.stdout.split("Response:", 1)[-1].strip()
    out = re.sub(r"<\|.*?\|>", "", out).strip()
    n_out = len(tok.encode(out, bos=False, eos=False))
    nums_ok = all(m in facts for m in re.findall(r"\d+(?:\.\d+)?", re.sub(r"(?m)^\s*\d+[\).]", "", out)))
    res.append(dict(label=label, level=level, prompt_tokens=n_prompt, facts_words=n_facts_words,
                    tokens_per_telugu_word=round(n_prompt / max(1, n_facts_words), 2), output_tokens=n_out,
                    host_seconds=round(dt, 1), telugu_ratio=round(telugu_ratio(out), 2), numbers_grounded=nums_ok,
                    output=out, stderr_tail=r.stderr[-400:] if r.returncode else ""))
    print(json.dumps(res[-1], ensure_ascii=False, indent=1), flush=True)
json.dump(res, open(a.out, "w"), ensure_ascii=False, indent=1)
