#!/usr/bin/env python3
"""Break recall down by source organism.

A single recall figure hides where the losses are. If misses are spread evenly
across the community, the cause is probably systematic: consensus accuracy,
thresholds, or the caller. If they concentrate in one or two organisms, the
cause is that organism's assembly, and the question becomes why those genomes
came out worse than the rest.

Run from the project root after a completed run:

    python scripts/recall_by_organism.py
"""

import json
import sys

import pandas as pd

sys.path.insert(0, "bin")
from validate_resistome import normalise_gene

truth = pd.read_csv("truth/zymo_expected_resistome.tsv", sep="\t").fillna("")
truth["gn"] = truth["gene"].map(normalise_gene)

with open("results/validation/zymo_even_gridion_validation.json") as fh:
    m = json.load(fh)
missed = set(m["missed_genes"])

expected = truth.groupby("expected_host")["gn"].nunique()
missing = truth[truth["gn"].isin(missed)].groupby("expected_host")["gn"].nunique()

df = pd.DataFrame({"expected": expected, "missed": missing}).fillna(0).astype(int)
df["recovered"] = df["expected"] - df["missed"]
df["recall"] = (df["recovered"] / df["expected"]).round(3)
print("Per organism, all element types")
print(df.sort_values("recall").to_string())

amr = truth[truth["element_type"] == "AMR"]
ae = amr.groupby("expected_host")["gn"].nunique()
am = amr[amr["gn"].isin(missed)].groupby("expected_host")["gn"].nunique()
d2 = pd.DataFrame({"expected": ae, "missed": am}).fillna(0).astype(int)
d2["recovered"] = d2["expected"] - d2["missed"]
d2["recall"] = (d2["recovered"] / d2["expected"]).round(3)
print("\nPer organism, AMR only")
print(d2.sort_values("recall").to_string())
