#!/usr/bin/env bash
# Fetch the two reference databases the pipeline needs.
#
# Kraken2 Standard-8: capped at 8 GB so it fits in laptop RAM. The full
# Standard database needs ~100 GB and will not run on a desktop.
#
# geNomad: ~1.5 GB.

set -euo pipefail

DBDIR="${1:-databases}"
mkdir -p "$DBDIR"

echo "==> Kraken2 Standard-8"
echo "    Current download links live at https://benlangmead.github.io/aws-indexes/k2"
echo "    The filename carries a build date, so check the page for the newest one."
echo
K2_URL="${K2_URL:-}"
if [ -z "$K2_URL" ]; then
    echo "    Set K2_URL to the 'Standard-8' .tar.gz link from that page, then re-run:"
    echo "      K2_URL='https://genome-idx.s3.amazonaws.com/kraken/k2_standard_08gb_YYYYMMDD.tar.gz' \\"
    echo "        bash scripts/02_get_databases.sh"
else
    mkdir -p "$DBDIR/k2_standard_08gb"
    curl -fL --retry 5 -C - "$K2_URL" -o "$DBDIR/k2_standard_08gb.tar.gz"
    tar -xzf "$DBDIR/k2_standard_08gb.tar.gz" -C "$DBDIR/k2_standard_08gb"
    echo "    Kraken2 DB ready at $DBDIR/k2_standard_08gb"
fi

echo
echo "==> geNomad database"
if [ ! -d "$DBDIR/genomad_db" ]; then
    docker run --rm -v "$PWD/$DBDIR":/db \
        quay.io/biocontainers/genomad:1.8.0--pyhdfd78af_0 \
        genomad download-database /db
    echo "    geNomad DB ready at $DBDIR/genomad_db"
else
    echo "    Already present at $DBDIR/genomad_db"
fi

echo
echo "Disk check:"
du -sh "$DBDIR"/* 2>/dev/null || true
