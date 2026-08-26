#!/usr/bin/env bash
# Fetch the AMRFinderPlus database once, into a host directory.
#
# The biocontainer ships the binary without a database. Downloading it inside
# each task would mean a different database on every run, so it is pulled once
# here and mounted in. The truth set and the pipeline then use the same version,
# which is what makes the comparison meaningful.

set -euo pipefail

DBDIR="${1:-databases}"
TARGET="$DBDIR/amrfinderplus"
IMAGE="quay.io/biocontainers/ncbi-amrfinderplus:4.0.19--hf69ffd2_0"

mkdir -p "$TARGET"

if [ -d "$TARGET/latest" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "==> Already present at $TARGET/latest. Set FORCE=1 to re-download."
else
    echo "==> Downloading AMRFinderPlus database into $TARGET"
    docker run --rm -u "$(id -u):$(id -g)" \
        -v "$PWD/$TARGET":/usr/local/share/amrfinderplus/data \
        "$IMAGE" \
        amrfinder -u
fi

echo
echo "==> Version in use"
docker run --rm -u "$(id -u):$(id -g)" \
    -v "$PWD/$TARGET":/usr/local/share/amrfinderplus/data \
    "$IMAGE" \
    amrfinder --database_version

echo
echo "Pass this to the pipeline with:  --amrfinder_db $TARGET"
