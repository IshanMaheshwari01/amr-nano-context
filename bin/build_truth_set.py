#!/usr/bin/env python3
"""Build an expected-resistome truth set from reference genomes.

The mock community has a known membership, so its resistome is knowable:
run AMRFinderPlus over each member's reference genome and the union of the
calls is what the pipeline should recover from the reads.

Run this once, outside the pipeline, before the validated run.

    build_truth_set.py --genome-dir refs/ --out truth/zymo_expected_resistome.tsv

Requires amrfinder on PATH, or pass --amrfinder-cmd to point at a container.
"""

from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys

import pandas as pd

GENE_COLS = ["Element symbol", "Gene symbol"]
CLASS_COLS = ["Class"]


def pick(df: pd.DataFrame, candidates: list[str]) -> str | None:
    for c in candidates:
        if c in df.columns:
            return c
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--genome-dir", required=True,
                    help="Directory of per-organism FASTA files (one genome per file)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--amrfinder-cmd", default="amrfinder")
    ap.add_argument("--threads", type=int, default=4)
    ap.add_argument("--keep-intermediate", action="store_true")
    args = ap.parse_args()

    gdir = pathlib.Path(args.genome_dir)
    genomes = sorted(
        p for p in gdir.iterdir()
        if p.suffix.lower() in (".fa", ".fasta", ".fna")
    )
    if not genomes:
        raise SystemExit(f"No FASTA files found in {gdir}")

    frames = []
    outdir = pathlib.Path(args.out).parent
    outdir.mkdir(parents=True, exist_ok=True)

    for g in genomes:
        organism = g.stem
        tsv = outdir / f"{organism}_amrfinder.tsv"
        print(f"[truth] {organism}", file=sys.stderr)
        cmd = [
            args.amrfinder_cmd, "--nucleotide", str(g), "--plus",
            "--threads", str(args.threads), "--output", str(tsv),
            "--name", organism,
        ]
        subprocess.run(cmd, check=True)

        df = pd.read_csv(tsv, sep="\t", dtype=str)
        if df.empty:
            continue
        gcol = pick(df, GENE_COLS)
        ccol = pick(df, CLASS_COLS)
        if gcol is None:
            print(f"  no gene column in {tsv}, skipping", file=sys.stderr)
            continue
        frames.append(pd.DataFrame({
            "gene": df[gcol],
            "drug_class": df[ccol] if ccol else "",
            "expected_host": organism,
        }))
        if not args.keep_intermediate:
            tsv.unlink()

    if not frames:
        truth = pd.DataFrame(columns=["gene", "drug_class", "expected_host"])
    else:
        truth = pd.concat(frames, ignore_index=True).drop_duplicates()

    truth.to_csv(args.out, sep="\t", index=False)
    print(f"[truth] {len(truth)} expected ARG/host pairs across {len(genomes)} genomes "
          f"-> {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
