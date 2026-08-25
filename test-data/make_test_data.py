#!/usr/bin/env python3
"""Generate a tiny FASTQ so CI has something to point at.

Real correctness is established by the mock community run, not by this.
This exists only so the stub run has a file to stage.
"""

import gzip
import pathlib
import random

random.seed(42)

out = pathlib.Path(__file__).parent / "stub_reads.fastq.gz"
with gzip.open(out, "wt") as fh:
    for i in range(200):
        length = random.randint(500, 3000)
        seq = "".join(random.choice("ACGT") for _ in range(length))
        qual = "".join(chr(33 + random.randint(8, 20)) for _ in range(length))
        fh.write(f"@read_{i} length={length}\n{seq}\n+\n{qual}\n")

truth = pathlib.Path(__file__).parent / "stub_truth.tsv"
truth.write_text(
    "gene\tdrug_class\texpected_host\n"
    "tet(M)\tTETRACYCLINE\tEnterococcus_faecalis\n"
)

print(f"wrote {out}")
print(f"wrote {truth}")
