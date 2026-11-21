"""Builds app/assets/advisory_en.json and advisory_hi.json from advisory_te.json.
Every Telugu string is looked up in ml/i18n/advisory_strings.json (curated
English/Hindi translations); pest names of the form "<group> (<Latin name>)"
are translated by group. Fails if any string has no translation, so the three
files always cover the same classes with the same doses."""
import json, os, re, sys

HERE = os.path.dirname(__file__)
ASSETS = os.path.join(HERE, "..", "app", "assets")
tr = json.load(open(os.path.join(HERE, "i18n", "advisory_strings.json")))
S, G = tr["strings"], tr["groups"]
TE = re.compile("[ఀ-౿]")


def t(s, lang, missing):
    if s in S: return S[s][lang]
    if s in G: return G[s][lang]
    for g in sorted(G, key=len, reverse=True):  # "<group> (<Latin>)"
        if s.startswith(g + " (") and s.endswith(")") and not TE.search(s[len(g):]):
            return f"{G[g][lang]}{s[len(g):]}"
    missing.add(s)
    return s


def walk(x, lang, missing):
    if isinstance(x, str): return t(x, lang, missing) if TE.search(x) else x
    if isinstance(x, list): return [walk(i, lang, missing) for i in x]
    if isinstance(x, dict): return {k: walk(v, lang, missing) for k, v in x.items()}
    return x


te = json.load(open(os.path.join(ASSETS, "advisory_te.json")))
missing = set()
for lang in ("en", "hi"):
    out = walk(te, lang, missing)
    out["lang"] = lang
    json.dump(out, open(os.path.join(ASSETS, f"advisory_{lang}.json"), "w"), ensure_ascii=False)
if missing:
    print("MISSING translations:", *sorted(missing), sep="\n  "); sys.exit(1)
print("wrote advisory_en.json, advisory_hi.json")
