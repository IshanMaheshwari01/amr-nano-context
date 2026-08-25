#!/usr/bin/env python3
"""Take the first N bases of a gzipped FASTQ arriving on stdin.

The point is to avoid downloading 14 GB to keep 1.5 Gbp of it. Piping curl
through this decompresses on the fly and exits once the target is met, at which
point curl gets SIGPIPE and stops. Roughly a tenth of the transfer.

    curl -fL "https://$FTP" | take_bases.py 1500000000 data/zymo_even_sub.fastq.gz

Reads are taken from the head of the file rather than at random. Nanopore runs
are written in roughly time order, so this biases slightly towards early reads,
which tend to be longer and better quality. Documented rather than corrected:
random subsampling would need the whole file, which is the thing being avoided.
"""

from __future__ import annotations

import gzip
import signal
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2

    target = int(sys.argv[1])
    dest = sys.argv[2]

    # Exit quietly when the reader goes away rather than dumping a traceback.
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)

    total = 0
    reads = 0
    last_report = 0
    truncated = False

    # The output file is written and closed properly whatever happens, so a
    # dropped connection leaves a short but valid FASTQ rather than a corrupt one.
    with gzip.open(sys.stdin.buffer, "rt") as fin, \
         gzip.open(dest, "wt", compresslevel=4) as fout:
        try:
            while total < target:
                head = fin.readline()
                if not head:
                    print(f"\ninput ended before the target was reached: "
                          f"{total} bases from {reads} reads", file=sys.stderr)
                    break
                seq = fin.readline()
                plus = fin.readline()
                qual = fin.readline()
                if not qual:
                    print("\ntruncated record at end of stream, dropped",
                          file=sys.stderr)
                    truncated = True
                    break

                fout.write(head)
                fout.write(seq)
                fout.write(plus)
                fout.write(qual)

                total += len(seq.strip())
                reads += 1

                if total - last_report >= 100_000_000:
                    pct = 100.0 * total / target
                    print(f"\r  {total/1e9:.2f} Gbp / {target/1e9:.2f} Gbp "
                          f"({pct:.0f}%), {reads} reads", end="", file=sys.stderr)
                    last_report = total

        except (EOFError, gzip.BadGzipFile, OSError) as exc:
            # Almost always a dropped connection: curl died and the gzip stream
            # stopped before its end-of-stream marker. Everything already written
            # is intact, so report it and let the caller decide whether to retry.
            truncated = True
            print(f"\nstream ended mid-record ({type(exc).__name__}): "
                  f"kept {reads} reads, {total} bases", file=sys.stderr)

    if truncated and total < target:
        pct = 100.0 * total / target
        print(f"\nINCOMPLETE: {total/1e9:.2f} Gbp of {target/1e9:.2f} Gbp "
              f"({pct:.0f}%). {dest} is valid but short. Re-run to start over, "
              f"or lower the target and use what is there.", file=sys.stderr)
        return 1

    print(f"\ndone: {reads} reads, {total} bases -> {dest}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
