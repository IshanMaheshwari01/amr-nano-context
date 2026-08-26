#!/usr/bin/env python3
"""Why were genes missed: filtered out by threshold, or absent from the assembly?

A recall figure on its own does not say which. The two have different fixes: a
gene present in the raw AMRFinderPlus output but below the identity or coverage
threshold points at assembly fragmentation or consensus error, and polishing
would recover it. A gene absent entirely means that region did not assemble at
this depth, and more data is the only remedy.

Run from the project root after a completed run:

    python scripts/diagnose_misses.py
"""
import glob
import json
import sys

import pandas as pd

sys.path.insert(0, "bin")
from validate_resistome import normalise_gene

hits = glob.glob("work/*/*/zymo_even_gridion_amrfinder.tsv")
if not hits:
    sys.exit("No raw AMRFinder output found under work/")
raw = hits[0]

df = pd.read_csv(raw, sep="\t", dtype=str).fillna("")
gcol = "Element symbol" if "Element symbol" in df.columns else "Gene symbol"
covcol = next((c for c in df.columns if c.startswith("% Coverage")), None)
idcol = next((c for c in df.columns if c.startswith("% Identity")), None)

df["gn"] = df[gcol].map(normalise_gene)
df["cov"] = pd.to_numeric(df[covcol], errors="coerce") if covcol else pd.NA
df["pid"] = pd.to_numeric(df[idcol], errors="coerce") if idcol else pd.NA

with open("results/validation/zymo_even_gridion_validation.json") as fh:
    m = json.load(fh)
missed = set(m["missed_genes"])
called = set(df["gn"]) - {""}

filtered = sorted(missed & called)
absent = sorted(missed - called)

print(f"raw AMRFinder calls : {len(df)}")
print(f"missed genes        : {len(missed)}")
print(f"  present in raw output but filtered out : {len(filtered)}")
print(f"  absent from raw output entirely        : {len(absent)}")
print()

if filtered:
    show = [c for c in [gcol, "Type", "Method", "cov", "pid"] if c in df.columns or c in ("cov", "pid")]
    sub = df[df["gn"].isin(filtered)][show].sort_values("cov")
    print("FILTERED OUT (thresholds: cov >= 60, id >= 90)")
    print(sub.to_string(index=False))
    print()

if absent:
    print("ABSENT FROM ASSEMBLY OUTPUT")
    print(", ".join(absent))
