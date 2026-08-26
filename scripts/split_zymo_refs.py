#!/usr/bin/env python3
"""Split the Loman lab Zymo isolate FASTA into one file per organism.

The combined FASTA labels contigs with a two-letter organism prefix:

    >lf_contig1 NODE_1_length_115148_cov_630.208

Files have to come out named with the full organism, not the prefix, because
build_truth_set.py takes expected_host from the filename stem and
validate_resistome.py matches that against Kraken2's taxon names at genus level.
A file called lf.fasta would compare genus 'lf' against 'Lactobacillus' and score
every host attribution wrong.

    split_zymo_refs.py --fasta refs/Zymo-Isolates-SPAdes-Illumina.fasta \\
        --outdir refs/per_organism

Unrecognised prefixes are a hard error rather than a warning: silently dropping
a genome would quietly shrink the truth set and inflate apparent precision.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
from collections import defaultdict

# ZymoBIOMICS Microbial Community Standard (D6300): eight bacteria, two yeasts.
ZYMO_PREFIXES = {
    "bs": "Bacillus_subtilis",
    "cn": "Cryptococcus_neoformans",
    "ec": "Escherichia_coli",
    "ef": "Enterococcus_faecalis",
    "lf": "Lactobacillus_fermentum",
    "lm": "Listeria_monocytogenes",
    "pa": "Pseudomonas_aeruginosa",
    "sa": "Staphylococcus_aureus",
    "sc": "Saccharomyces_cerevisiae",
    "se": "Salmonella_enterica",
    # Some releases spell these out differently.
    "bsub": "Bacillus_subtilis",
    "lmono": "Listeria_monocytogenes",
    "styphi": "Salmonella_enterica",
}

HEADER_RX = re.compile(r"^>([A-Za-z]+?)_contig", re.IGNORECASE)


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--fasta", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--list-only", action="store_true",
                    help="Report the prefixes found and exit without writing files")
    args = ap.parse_args()

    counts: dict[str, int] = defaultdict(int)
    buckets: dict[str, list[str]] = defaultdict(list)
    unknown: set[str] = set()
    unmatched_headers = 0
    current: str | None = None

    with open(args.fasta) as fh:
        for line in fh:
            if line.startswith(">"):
                m = HEADER_RX.match(line)
                if not m:
                    unmatched_headers += 1
                    current = None
                    continue
                prefix = m.group(1).lower()
                organism = ZYMO_PREFIXES.get(prefix)
                if organism is None:
                    unknown.add(prefix)
                    current = None
                    continue
                current = organism
                counts[organism] += 1
            if current:
                buckets[current].append(line)

    for organism in sorted(counts):
        print(f"  {organism:32s} {counts[organism]:5d} contigs", file=sys.stderr)

    if unmatched_headers:
        print(f"\n{unmatched_headers} headers did not match the "
              f"'>prefix_contigN' pattern.", file=sys.stderr)

    if unknown:
        print(f"\nERROR: unrecognised organism prefixes: {sorted(unknown)}",
              file=sys.stderr)
        print("Add them to ZYMO_PREFIXES in this script. Dropping them would "
              "shrink the truth set and make precision look better than it is.",
              file=sys.stderr)
        return 1

    if not buckets:
        print("\nERROR: nothing matched. Check the headers:", file=sys.stderr)
        print(f"  grep '>' {args.fasta} | head", file=sys.stderr)
        return 1

    if args.list_only:
        print(f"\n{len(buckets)} organisms found. Rerun without --list-only "
              f"to write them.", file=sys.stderr)
        return 0

    out = pathlib.Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)
    for organism, lines in buckets.items():
        (out / f"{organism}.fasta").write_text("".join(lines))

    print(f"\nWrote {len(buckets)} genomes to {out}", file=sys.stderr)
    if len(buckets) < 8:
        print(f"WARNING: expected at least 8 bacterial genomes, got "
              f"{len(buckets)}. The truth set will be incomplete.",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
