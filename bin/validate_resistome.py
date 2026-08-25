#!/usr/bin/env python3
"""Score a recovered resistome against a known one.

Two metrics, because they measure different things:

  gene recovery      did the pipeline find the resistance genes that are there?
                     precision / recall / F1 over unique gene symbols

  host attribution   of the genes it found, did it assign them to the right
                     organism? This is the metric that a short-read resistome
                     profile cannot produce at all, so it is the one worth
                     reporting.
"""

from __future__ import annotations

import argparse
import json
import re
import sys

import pandas as pd


def normalise_gene(g: str) -> str:
    """blaTEM-1B, blaTEM-1, blaTEM all collapse to bla_tem for family-level comparison."""
    if not isinstance(g, str):
        return ""
    g = g.strip().lower()
    g = re.sub(r"[-_](\d+[a-z]*)$", "", g)
    g = re.sub(r"[^a-z0-9]", "", g)
    return g


def genus(taxon: str) -> str:
    """First word of an organism name, lowercased.

    Has to cope with two different conventions arriving in the same comparison:
    Kraken2 writes 'Escherichia coli (taxid 562)', while the truth set takes its
    organism from a filename and so writes 'Escherichia_coli'. Splitting on
    whitespace alone silently makes every comparison fail, which looks like a
    real host-attribution accuracy of zero rather than a bug.
    """
    if not isinstance(taxon, str) or not taxon.strip():
        return ""
    first = re.split(r"[\s_]+", taxon.strip())[0]
    return re.sub(r"[^a-z]", "", first.lower())


def prf(tp: int, fp: int, fn: int) -> dict:
    p = tp / (tp + fp) if (tp + fp) else 0.0
    r = tp / (tp + fn) if (tp + fn) else 0.0
    f = 2 * p * r / (p + r) if (p + r) else 0.0
    return {"true_positives": tp, "false_positives": fp, "false_negatives": fn,
            "precision": round(p, 4), "recall": round(r, 4), "f1": round(f, 4)}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--sample", required=True)
    ap.add_argument("--observed", required=True)
    ap.add_argument("--truth", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--out-json", required=True)
    args = ap.parse_args()

    obs = pd.read_csv(args.observed, sep="\t", dtype=str).fillna("")
    truth = pd.read_csv(args.truth, sep="\t", dtype=str).fillna("")

    obs["gene_norm"] = obs.get("gene", pd.Series(dtype=str)).map(normalise_gene)
    truth["gene_norm"] = truth.get("gene", pd.Series(dtype=str)).map(normalise_gene)

    obs_genes = set(obs["gene_norm"]) - {""}
    truth_genes = set(truth["gene_norm"]) - {""}

    tp = obs_genes & truth_genes
    fp = obs_genes - truth_genes
    fn = truth_genes - obs_genes

    gene_metrics = prf(len(tp), len(fp), len(fn))

    # Host attribution, scored only on genes we correctly found.
    truth_host = (
        truth.assign(g=truth["gene_norm"])
        .groupby("g")["expected_host"]
        .apply(lambda s: {genus(x) for x in s})
        .to_dict()
    )

    rows = []
    correct_host = wrong_host = no_host = 0
    for _, r in obs.iterrows():
        gn = r["gene_norm"]
        if gn not in tp:
            continue
        assigned = genus(r.get("host_taxon", ""))
        expected = truth_host.get(gn, set())
        if not assigned or assigned in ("unclassified", "root"):
            verdict = "unassigned"
            no_host += 1
        elif assigned in expected:
            verdict = "correct"
            correct_host += 1
        else:
            verdict = "incorrect"
            wrong_host += 1
        rows.append({
            "gene": r.get("gene", ""),
            "gene_norm": gn,
            "observed_host": r.get("host_taxon", ""),
            "expected_hosts": ";".join(sorted(expected)) if expected else "",
            "mobility": r.get("mobility", ""),
            "host_verdict": verdict,
        })

    detail = pd.DataFrame(rows)
    scored = correct_host + wrong_host
    host_accuracy = round(correct_host / scored, 4) if scored else 0.0

    # Per-gene outcome table, including the misses.
    outcome = []
    for g in sorted(tp):
        outcome.append({"gene_norm": g, "outcome": "recovered"})
    for g in sorted(fn):
        outcome.append({"gene_norm": g, "outcome": "missed"})
    for g in sorted(fp):
        outcome.append({"gene_norm": g, "outcome": "spurious"})
    outcome_df = pd.DataFrame(outcome)

    report = outcome_df.merge(detail, on="gene_norm", how="left")
    report.insert(0, "sample", args.sample)
    report.to_csv(args.out, sep="\t", index=False)

    metrics = {
        "sample": args.sample,
        "gene_recovery": gene_metrics,
        "host_attribution": {
            "scored": scored,
            "correct": correct_host,
            "incorrect": wrong_host,
            "unassigned": no_host,
            "accuracy": host_accuracy,
        },
        "missed_genes": sorted(fn),
        "spurious_genes": sorted(fp),
    }
    with open(args.out_json, "w") as fh:
        json.dump(metrics, fh, indent=2)

    print(json.dumps(metrics, indent=2), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
