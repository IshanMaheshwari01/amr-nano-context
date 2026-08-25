#!/usr/bin/env python3
"""Join ARG calls to contig context.

Takes the five per-sample tables the pipeline produces and emits one row per
resistance gene carrying: the gene, its drug class, the contig it sits on,
whether that contig looks chromosomal or plasmid-borne, and the organism the
contig was assigned to.

The mobility call is a heuristic and is labelled as such in the output. It
combines the geNomad plasmid score with Flye's circularity flag, because a
short circular contig in a metagenome assembly is usually a plasmid and
geNomad on its own misses small ones.
"""

from __future__ import annotations

import argparse
import json
import sys

import pandas as pd

# AMRFinderPlus renamed several columns at v4. Accept either spelling rather
# than pinning to one and failing silently on the other.
AMR_COLUMN_ALIASES = {
    "gene": ["Element symbol", "Gene symbol"],
    "name": ["Element name", "Sequence name"],
    "contig": ["Contig id"],
    "start": ["Start"],
    "stop": ["Stop"],
    "strand": ["Strand"],
    "klass": ["Class"],
    "subclass": ["Subclass"],
    "pct_cov": ["% Coverage of reference", "% Coverage of reference sequence"],
    "pct_id": ["% Identity to reference", "% Identity to reference sequence"],
    "method": ["Method"],
}


def resolve_columns(df: pd.DataFrame) -> dict[str, str]:
    """Map our internal names onto whichever spelling this AMRFinder version used."""
    resolved = {}
    for key, candidates in AMR_COLUMN_ALIASES.items():
        for c in candidates:
            if c in df.columns:
                resolved[key] = c
                break
    missing = [k for k in ("gene", "contig") if k not in resolved]
    if missing:
        raise SystemExit(
            f"AMRFinderPlus output is missing required column(s) {missing}. "
            f"Columns present: {list(df.columns)}"
        )
    return resolved


def read_amrfinder(path: str) -> pd.DataFrame:
    df = pd.read_csv(path, sep="\t", dtype=str).fillna("")
    if df.empty:
        return pd.DataFrame(
            columns=["gene", "name", "contig", "start", "stop", "strand",
                     "klass", "subclass", "pct_cov", "pct_id", "method"]
        )
    cols = resolve_columns(df)
    out = pd.DataFrame({k: df[v] for k, v in cols.items()})
    for c in ("pct_cov", "pct_id"):
        if c in out.columns:
            out[c] = pd.to_numeric(out[c], errors="coerce")
        else:
            out[c] = pd.NA
    return out


def read_abricate(path: str) -> pd.DataFrame:
    """Second opinion from CARD. Used only to flag agreement, not to add calls."""
    try:
        df = pd.read_csv(path, sep="\t", dtype=str, comment=None)
    except pd.errors.EmptyDataError:
        return pd.DataFrame(columns=["contig", "gene_card"])
    df.columns = [c.lstrip("#") for c in df.columns]
    if "GENE" not in df.columns or "SEQUENCE" not in df.columns:
        return pd.DataFrame(columns=["contig", "gene_card"])
    return pd.DataFrame({"contig": df["SEQUENCE"], "gene_card": df["GENE"]})


def read_genomad(path: str) -> pd.DataFrame:
    df = pd.read_csv(path, sep="\t", dtype=str)
    if df.empty or "seq_name" not in df.columns:
        return pd.DataFrame(columns=["contig", "chromosome_score", "plasmid_score", "virus_score"])
    out = df.rename(columns={"seq_name": "contig"})
    for c in ("chromosome_score", "plasmid_score", "virus_score"):
        out[c] = pd.to_numeric(out.get(c), errors="coerce")
    return out[["contig", "chromosome_score", "plasmid_score", "virus_score"]]


def read_kraken_contigs(path: str) -> pd.DataFrame:
    """Kraken2 --use-names output: C/U, seqid, taxon name (taxid), length, LCA map."""
    rows = []
    with open(path) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3:
                continue
            rows.append({
                "contig": parts[1],
                "host_taxon": parts[2].strip(),
                "classified": parts[0] == "C",
            })
    if not rows:
        return pd.DataFrame(columns=["contig", "host_taxon", "classified"])
    return pd.DataFrame(rows)


def read_flye_info(path: str) -> pd.DataFrame:
    df = pd.read_csv(path, sep="\t", dtype=str)
    df.columns = [c.lstrip("#").strip() for c in df.columns]
    rename = {"seq_name": "contig", "length": "contig_len", "cov.": "contig_cov", "circ.": "circular"}
    df = df.rename(columns={k: v for k, v in rename.items() if k in df.columns})
    keep = [c for c in ("contig", "contig_len", "contig_cov", "circular", "repeat") if c in df.columns]
    out = df[keep].copy()
    for c in ("contig_len", "contig_cov"):
        if c in out.columns:
            out[c] = pd.to_numeric(out[c], errors="coerce")
    return out


def call_mobility(row, plasmid_score: float, max_plasmid_len: int) -> tuple[str, str]:
    """Return (call, reason). Deliberately conservative - 'ambiguous' is a valid answer."""
    ps = row.get("plasmid_score")
    cs = row.get("chromosome_score")
    circ = str(row.get("circular", "")).upper().startswith("Y")
    length = row.get("contig_len")

    if pd.notna(ps) and ps >= plasmid_score:
        return "plasmid", f"genomad plasmid score {ps:.2f}"
    if circ and pd.notna(length) and length <= max_plasmid_len:
        return "plasmid", f"circular contig of {int(length)} bp"
    if pd.notna(cs) and cs >= plasmid_score:
        return "chromosome", f"genomad chromosome score {cs:.2f}"
    if pd.notna(length) and length > max_plasmid_len:
        return "chromosome", f"contig length {int(length)} bp exceeds plasmid threshold"
    return "ambiguous", "no confident signal"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--sample", required=True)
    ap.add_argument("--amrfinder", required=True)
    ap.add_argument("--abricate", required=True)
    ap.add_argument("--genomad", required=True)
    ap.add_argument("--kraken-contigs", required=True)
    ap.add_argument("--flye-info", required=True)
    ap.add_argument("--min-id", type=float, default=90.0)
    ap.add_argument("--min-cov", type=float, default=60.0)
    ap.add_argument("--plasmid-score", type=float, default=0.7)
    ap.add_argument("--max-plasmid-len", type=int, default=500000)
    ap.add_argument("--out", required=True)
    ap.add_argument("--out-mqc", required=True)
    ap.add_argument("--out-summary", required=True)
    args = ap.parse_args()

    amr = read_amrfinder(args.amrfinder)

    n_raw = len(amr)
    if not amr.empty:
        keep = pd.Series(True, index=amr.index)
        if amr["pct_id"].notna().any():
            keep &= amr["pct_id"].fillna(0) >= args.min_id
        if amr["pct_cov"].notna().any():
            keep &= amr["pct_cov"].fillna(0) >= args.min_cov
        amr = amr[keep].copy()

    genomad = read_genomad(args.genomad)
    kraken = read_kraken_contigs(args.kraken_contigs)
    flye = read_flye_info(args.flye_info)
    card = read_abricate(args.abricate)

    merged = amr
    for other in (genomad, flye, kraken):
        if not other.empty:
            merged = merged.merge(other, on="contig", how="left")

    if merged.empty:
        merged = pd.DataFrame(columns=[
            "gene", "klass", "subclass", "contig", "start", "stop", "pct_id",
            "pct_cov", "contig_len", "contig_cov", "circular", "plasmid_score",
            "chromosome_score", "host_taxon",
        ])

    # Agreement flag: did CARD also call something on this contig?
    card_by_contig = set(card["contig"]) if not card.empty else set()
    merged["card_agrees"] = merged["contig"].isin(card_by_contig)

    calls = merged.apply(
        lambda r: call_mobility(r, args.plasmid_score, args.max_plasmid_len),
        axis=1, result_type="expand"
    ) if not merged.empty else pd.DataFrame(columns=[0, 1])

    merged["mobility"] = calls[0] if not merged.empty else []
    merged["mobility_evidence"] = calls[1] if not merged.empty else []
    merged["sample"] = args.sample

    ordered = [
        "sample", "gene", "klass", "subclass", "pct_id", "pct_cov",
        "contig", "contig_len", "contig_cov", "circular",
        "mobility", "mobility_evidence", "plasmid_score", "chromosome_score",
        "host_taxon", "card_agrees", "start", "stop", "method",
    ]
    ordered = [c for c in ordered if c in merged.columns]
    final = merged[ordered].rename(columns={"klass": "drug_class"})
    final.to_csv(args.out, sep="\t", index=False)

    # Compact table for MultiQC
    mqc_cols = [c for c in ("sample", "gene", "drug_class", "contig", "mobility", "host_taxon") if c in final.columns]
    final[mqc_cols].to_csv(args.out_mqc, sep="\t", index=False)

    summary = {
        "sample": args.sample,
        "args_called_raw": int(n_raw),
        "args_after_filter": len(final),
        "unique_genes": int(final["gene"].nunique()) if "gene" in final.columns else 0,
        "on_plasmid": int((final["mobility"] == "plasmid").sum()) if "mobility" in final.columns else 0,
        "on_chromosome": int((final["mobility"] == "chromosome").sum()) if "mobility" in final.columns else 0,
        "ambiguous": int((final["mobility"] == "ambiguous").sum()) if "mobility" in final.columns else 0,
        "host_assigned": int(final["host_taxon"].notna().sum()) if "host_taxon" in final.columns else 0,
        "thresholds": {
            "min_identity": args.min_id,
            "min_coverage": args.min_cov,
            "plasmid_score": args.plasmid_score,
            "max_plasmid_len": args.max_plasmid_len,
        },
    }
    with open(args.out_summary, "w") as fh:
        json.dump(summary, fh, indent=2)

    print(f"[{args.sample}] {summary['args_after_filter']} ARGs kept of {n_raw} called; "
          f"{summary['on_plasmid']} plasmid, {summary['on_chromosome']} chromosome, "
          f"{summary['ambiguous']} ambiguous", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
