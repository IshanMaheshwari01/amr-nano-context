#!/usr/bin/env python3
"""Score a recovered resistome against a known one.

Two metrics, because they measure different things:

  gene recovery      did the pipeline find the resistance genes that are there?
                     precision / recall / F1 over unique gene symbols

  host attribution   of the genes it found, did it assign them to the right
                     organism? This is the metric that a short-read resistome
                     profile cannot produce at all, so it is the one worth
                     reporting.

Both are reported for AMR elements alone and for everything AMRFinderPlus --plus
returns. The distinction matters: --plus also reports STRESS (metal and biocide
tolerance) and VIRULENCE elements. Those are worth having, but they are not
resistance genes, and scoring them inside a figure called "resistome recall"
measures the wrong thing.
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


def build_type_map(truth: pd.DataFrame, obs: pd.DataFrame) -> dict[str, str]:
    """Element type per normalised gene, preferring the truth set's label.

    A gene the pipeline called but the truth set does not contain has no truth
    label, so its own reported type is used. Without that fallback every spurious
    call would be typeless and silently excluded from the per-type figures.
    """
    types: dict[str, str] = {}
    for frame in (obs, truth):
        if "element_type" not in frame.columns:
            continue
        for gene, etype in zip(frame["gene_norm"], frame["element_type"]):
            if gene and isinstance(etype, str) and etype.strip():
                types[gene] = etype.strip().upper()
    return types


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

    # Same calculation restricted to each element type.
    type_map = build_type_map(truth, obs)
    per_type = {}
    for etype in sorted({t for t in type_map.values()}):
        t_sub = {g for g in truth_genes if type_map.get(g) == etype}
        o_sub = {g for g in obs_genes if type_map.get(g) == etype}
        per_type[etype] = prf(
            len(o_sub & t_sub), len(o_sub - t_sub), len(t_sub - o_sub)
        )
        per_type[etype]["missed"] = sorted(t_sub - o_sub)

    # Host attribution, scored only on genes we correctly found.
    truth_host = (
        truth.assign(g=truth["gene_norm"])
        .groupby("g")["expected_host"]
        .apply(lambda s: {genus(x) for x in s})
        .to_dict()
    )

    rows = []
    correct_host = wrong_host = no_host = 0
    amr_correct = amr_scored = 0
    for _, r in obs.iterrows():
        gn = r["gene_norm"]
        if gn not in tp:
            continue
        is_amr = type_map.get(gn) == "AMR"
        assigned = genus(r.get("host_taxon", ""))
        expected = truth_host.get(gn, set())
        if not assigned or assigned in ("unclassified", "root"):
            verdict = "unassigned"
            no_host += 1
        elif assigned in expected:
            verdict = "correct"
            correct_host += 1
            if is_amr:
                amr_correct += 1
                amr_scored += 1
        else:
            verdict = "incorrect"
            wrong_host += 1
            if is_amr:
                amr_scored += 1
        rows.append({
            "gene": r.get("gene", ""),
            "gene_norm": gn,
            "element_type": type_map.get(gn, ""),
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
        outcome.append({"gene_norm": g, "outcome": "recovered",
                        "type": type_map.get(g, "")})
    for g in sorted(fn):
        outcome.append({"gene_norm": g, "outcome": "missed",
                        "type": type_map.get(g, "")})
    for g in sorted(fp):
        outcome.append({"gene_norm": g, "outcome": "spurious",
                        "type": type_map.get(g, "")})
    outcome_df = pd.DataFrame(outcome)

    report = outcome_df.merge(detail, on="gene_norm", how="left")
    report.insert(0, "sample", args.sample)
    report.to_csv(args.out, sep="\t", index=False)

    metrics = {
        "sample": args.sample,
        # Headline. AMR elements only, which is what "resistome" means.
        "amr_only": {
            "gene_recovery": per_type.get("AMR", prf(0, 0, 0)),
            "host_attribution": {
                "scored": amr_scored,
                "correct": amr_correct,
                "accuracy": round(amr_correct / amr_scored, 4) if amr_scored else 0.0,
            },
        },
        # Everything AMRFinderPlus --plus returns, including stress and virulence.
        "all_elements": {
            "gene_recovery": gene_metrics,
            "host_attribution": {
                "scored": scored,
                "correct": correct_host,
                "incorrect": wrong_host,
                "unassigned": no_host,
                "accuracy": host_accuracy,
            },
        },
        "by_element_type": per_type,
        "missed_genes": sorted(fn),
        "spurious_genes": sorted(fp),
    }
    with open(args.out_json, "w") as fh:
        json.dump(metrics, fh, indent=2)

    print(json.dumps(metrics, indent=2), file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
