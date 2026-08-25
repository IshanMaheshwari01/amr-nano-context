#!/usr/bin/env python3
"""Split a combined isolate FASTA into one file per organism.

The Loman lab distributes the ten Zymo isolate assemblies as a single FASTA.
build_truth_set.py wants one genome per file so it can attribute each expected
ARG to a named organism.

Header formats vary between releases, so inspect first:

    grep '>' refs/Zymo-Isolates-SPAdes-Illumina.fasta | head

then set --pattern to a regex with one capture group naming the organism.
The default assumes the organism name is the first underscore-delimited field.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys
from collections import defaultdict


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fasta", required=True)
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--pattern", default=r"^>([A-Za-z]+_[a-z]+)",
                    help="Regex with one group capturing the organism from the header")
    args = ap.parse_args()

    rx = re.compile(args.pattern)
    out = pathlib.Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)

    buckets: dict[str, list[str]] = defaultdict(list)
    current = None
    unmatched = 0

    with open(args.fasta) as fh:
        for line in fh:
            if line.startswith(">"):
                m = rx.match(line)
                if m:
                    current = m.group(1).replace(" ", "_")
                else:
                    current = None
                    unmatched += 1
            if current:
                buckets[current].append(line)

    if not buckets:
        print("No headers matched. Look at the headers and pass a --pattern that fits:",
              file=sys.stderr)
        print(f"  grep '>' {args.fasta} | head", file=sys.stderr)
        return 1

    for organism, lines in buckets.items():
        path = out / f"{organism}.fasta"
        path.write_text("".join(lines))
        print(f"{organism}: {sum(1 for l in lines if l.startswith('>'))} contigs -> {path}",
              file=sys.stderr)

    if unmatched:
        print(f"warning: {unmatched} headers did not match the pattern and were dropped",
              file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
