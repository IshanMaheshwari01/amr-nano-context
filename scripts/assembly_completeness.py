#!/usr/bin/env python3
"""How much of each community member actually assembled?

Recall varies a lot between organisms in this sample. Two explanations fit:
either the gene callers behave differently on different genomes, or some members
simply assembled worse than others and their genes were never there to find.

This measures the second. Each contig carries a Kraken2 taxonomic label and a
length, so summing length by genus and comparing against the known genome size
gives a rough completeness per organism. If completeness tracks recall, the
losses are an assembly problem rather than a calling problem.

Rough on purpose: contigs assigned above genus level are excluded, so totals are
conservative, and a chimeric contig contributes all its length to one genus.

    python scripts/assembly_completeness.py
"""

import glob
import sys

import pandas as pd

# ZymoBIOMICS D6300 reference genome sizes, megabases.
GENOME_MB = {
    "Bacillus": 4.05,
    "Enterococcus": 2.85,
    "Escherichia": 4.88,
    "Lactobacillus": 1.91,
    "Limosilactobacillus": 1.91,  # L. fermentum was reclassified
    "Listeria": 2.99,
    "Pseudomonas": 6.79,
    "Salmonella": 4.76,
    "Staphylococcus": 2.73,
}

# L. fermentum was reclassified to Limosilactobacillus, so a database may report
# either. Count them as one organism rather than reporting a spurious absence.
ALIASES = {"Lactobacillus": "Limosilactobacillus"}


def genus(name: str) -> str:
    name = name.strip()
    if not name or name.startswith(("unclassified", "root")):
        return ""
    return name.split()[0]


def main() -> int:
    k2 = glob.glob("results/*/*contigs.kraken2.out.txt") + glob.glob(
        "results/**/*contigs.kraken2.out.txt", recursive=True
    )
    info = glob.glob("results/assembly/*assembly_info.txt")
    if not k2 or not info:
        print("Could not find Kraken2 contig output or Flye assembly_info under "
              "results/. Run from the project root after a completed run.",
              file=sys.stderr)
        return 1

    rows = []
    with open(k2[0]) as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) >= 3:
                rows.append({"contig": parts[1], "genus": genus(parts[2])})
    tax = pd.DataFrame(rows)

    flye = pd.read_csv(info[0], sep="\t", dtype=str)
    flye.columns = [c.lstrip("#").strip() for c in flye.columns]
    flye = flye.rename(columns={"seq_name": "contig", "length": "len",
                                "cov.": "cov", "circ.": "circ"})
    flye["len"] = pd.to_numeric(flye["len"], errors="coerce")
    flye["cov"] = pd.to_numeric(flye["cov"], errors="coerce")

    m = tax.merge(flye[["contig", "len", "cov", "circ"]], on="contig", how="left")
    m = m[m["genus"] != ""]

    agg = m.groupby("genus").agg(
        contigs=("contig", "count"),
        assembled_mb=("len", lambda s: round(s.sum() / 1e6, 2)),
        median_cov=("cov", "median"),
        circular=("circ", lambda s: (s.astype(str).str.upper() == "Y").sum()),
    )
    agg["expected_mb"] = agg.index.map(GENOME_MB)
    agg = agg[agg["expected_mb"].notna()].copy()
    agg["completeness"] = (agg["assembled_mb"] / agg["expected_mb"]).round(3)

    print("Assembly completeness per community member")
    print(agg.sort_values("completeness").to_string())

    seen = set(agg.index) | {ALIASES[g] for g in agg.index if g in ALIASES} \
           | {g for g, a in ALIASES.items() if a in agg.index}
    missing = sorted(set(GENOME_MB) - seen)
    if missing:
        print(f"\nNo contigs assigned to: {', '.join(missing)}")
        print("Either they did not assemble, or Kraken2 placed their contigs "
              "above genus level.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
