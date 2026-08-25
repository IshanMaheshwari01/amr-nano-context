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

SUB="$OUTDIR/zymo_even_sub.fastq.gz"

# Stream rather than download the whole 14 GB file. take_bases.py decompresses on
# the fly and exits once the target is met; curl then gets SIGPIPE and stops. For
# a 1.5 Gbp target that transfers roughly a tenth of the file.
#
# Set FULL_DOWNLOAD=1 to fetch the entire run to disk instead. That is resumable
# with curl -C -, which streaming is not, so it is the better option on a very
# unreliable connection or if you want the whole dataset for later.

if [ -f "$SUB" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "==> $SUB already present. Set FORCE=1 to redo it."
elif [ "${FULL_DOWNLOAD:-0}" = "1" ]; then
    RAW="$OUTDIR/${ACCESSION}.fastq.gz"
    echo "==> Full download to $RAW (resumable)"
    curl -fL --retry 10 --retry-delay 5 --retry-all-errors -C - "https://${FTP}" -o "$RAW"
    echo "==> Subsampling to approximately ${TARGET_BASES} bases"
    python3 scripts/take_bases.py "$TARGET_BASES" "$SUB" < "$RAW"
else
    echo "==> Streaming approximately ${TARGET_BASES} bases into $SUB"
    echo "    Transfers only what is needed. Not resumable: if it drops, re-run."

    ATTEMPT=1
    MAX_ATTEMPTS="${MAX_ATTEMPTS:-5}"
    until curl -fsSL --retry 10 --retry-delay 5 --retry-all-errors \
               --speed-time 60 --speed-limit 10000 "https://${FTP}" \
          | python3 scripts/take_bases.py "$TARGET_BASES" "$SUB"
    do
        if [ "$ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
            echo
            echo "Gave up after $ATTEMPT attempts. $SUB holds whatever was retrieved." >&2
            echo "Options: re-run, lower TARGET_BASES, or use FULL_DOWNLOAD=1 for a" >&2
            echo "resumable transfer." >&2
            exit 1
        fi
        ATTEMPT=$((ATTEMPT + 1))
        echo
        echo "==> Transfer interrupted. Retrying, attempt $ATTEMPT of $MAX_ATTEMPTS."
        sleep 10
    done
fi

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
