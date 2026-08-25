#!/usr/bin/env bash
# Download and subsample the validated mock community data.
#
# ERR3152364 is the Oxford Nanopore GridION run of the ZymoBIOMICS Even
# community (D6300), 3.49M reads, N50 5.3 kbp, released CC BY 4.0 by the
# Loman lab. Known membership is what makes validation possible.
#
#   https://lomanlab.github.io/mockcommunity/
#
# The full file is ~14 Gbp and will not assemble on a laptop. We take a
# subsample large enough to assemble the abundant members well.

set -euo pipefail

ACCESSION="${1:-ERR3152364}"
TARGET_BASES="${2:-1500000000}"   # 1.5 Gbp - roughly 3 to 5 hours of metaFlye on 6 cores
OUTDIR="data"

mkdir -p "$OUTDIR"

echo "==> Resolving $ACCESSION on ENA"
META_URL="https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${ACCESSION}&result=read_run&fields=run_accession,fastq_ftp,fastq_bytes,read_count,base_count&format=tsv"
curl -fsSL "$META_URL" -o "$OUTDIR/${ACCESSION}_meta.tsv"
cat "$OUTDIR/${ACCESSION}_meta.tsv"

FTP=$(awk 'NR==2 {print $2}' "$OUTDIR/${ACCESSION}_meta.tsv" | cut -d';' -f1)
if [ -z "$FTP" ]; then
    echo "Could not resolve a FASTQ URL for $ACCESSION. Check the accession on ENA." >&2
    exit 1
fi

RAW="$OUTDIR/${ACCESSION}.fastq.gz"
if [ ! -f "$RAW" ]; then
    echo "==> Downloading $FTP"
    echo "    This is large. Expect 30-90 minutes on domestic broadband."
    curl -fL --retry 5 -C - "https://${FTP}" -o "$RAW"
else
    echo "==> $RAW already present, skipping download"
fi

SUB="$OUTDIR/zymo_even_sub.fastq.gz"
echo "==> Subsampling to approximately ${TARGET_BASES} bases -> $SUB"

# Head-based subsample. Nanopore runs are roughly time-ordered rather than
# quality-ordered, so taking the head biases slightly towards early reads.
# rasusa would be better if available; this keeps the dependency list short.
python3 - "$RAW" "$SUB" "$TARGET_BASES" <<'PY'
import gzip, sys
src, dst, target = sys.argv[1], sys.argv[2], int(sys.argv[3])
total = 0
kept = 0
with gzip.open(src, "rt") as fin, gzip.open(dst, "wt", compresslevel=4) as fout:
    while total < target:
        head = fin.readline()
        if not head:
            break
        seq  = fin.readline()
        plus = fin.readline()
        qual = fin.readline()
        fout.write(head); fout.write(seq); fout.write(plus); fout.write(qual)
        total += len(seq.strip())
        kept += 1
print(f"kept {kept} reads, {total} bases", file=sys.stderr)
PY

echo
echo "==> Reference genomes for the truth set"
REFS="refs"
mkdir -p "$REFS"
if [ ! -f "$REFS/Zymo-Isolates-SPAdes-Illumina.fasta" ]; then
    echo "    Fetching Loman lab Illumina isolate assemblies (69 MB)"
    curl -fL "http://nanopore.s3.climb.ac.uk/mockcommunity/v2/Zymo-Isolates-SPAdes-Illumina.fasta" \
        -o "$REFS/Zymo-Isolates-SPAdes-Illumina.fasta"
fi

echo
echo "    Inspect the FASTA headers, then split per organism:"
echo "      grep '>' $REFS/Zymo-Isolates-SPAdes-Illumina.fasta | head"
echo "      python3 scripts/split_refs.py --fasta $REFS/Zymo-Isolates-SPAdes-Illumina.fasta --outdir $REFS/per_organism"
echo
echo "Done. Reads at: $SUB"
