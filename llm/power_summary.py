"""Summarise power.csv files: python llm/power_summary.py idle.csv vision.csv llm.csv"""
import csv, sys, statistics as st
for f in sys.argv[1:]:
    rows = list(csv.DictReader(open(f)))
    w = [abs(int(r["current_uA"])) * int(r["voltage_uV"]) / 1e12 for r in rows if r["current_uA"].lstrip("-").isdigit()]
    t = (int(rows[-1]["t_ms"]) - int(rows[0]["t_ms"])) / 1000
    print(f"{f}: mean {st.mean(w):.2f} W, peak {max(w):.2f} W over {t:.0f} s, energy {st.mean(w)*t:.1f} J")
