#!/usr/bin/env bash
# Check that every container tag in conf/containers.config still resolves.
#
# Biocontainer tags include a build hash and get removed when a package is
# rebuilt, so a pin that worked last month can 404 today. Finding that out four
# hours into a metaFlye run is expensive; this checks all of them in about
# twenty seconds using `docker manifest inspect`, which queries the registry
# without pulling the image.
#
#   bash scripts/check_containers.sh
#
# For anything missing, it lists the tags that do exist so the fix is a copy
# and paste into conf/containers.config.

set -uo pipefail

CONFIG="${1:-conf/containers.config}"

if [ ! -f "$CONFIG" ]; then
    echo "No such file: $CONFIG" >&2
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "docker not found on PATH" >&2
    exit 1
fi

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'

FAILED=0
declare -a BROKEN=()

echo "Checking container tags in $CONFIG"
echo

while IFS= read -r line; do
    # container_flye = 'quay.io/biocontainers/flye:2.9.5--py310h275bdba_0'
    key=$(echo "$line" | sed -n "s/^[[:space:]]*\(container_[a-z0-9_]*\).*/\1/p")
    image=$(echo "$line" | sed -n "s/.*'\(.*\)'.*/\1/p")
    [ -z "$image" ] && continue

    printf '  %-24s %-58s ' "$key" "$image"

    if docker manifest inspect "$image" >/dev/null 2>&1; then
        printf "${GREEN}ok${NC}\n"
    else
        printf "${RED}MISSING${NC}\n"
        FAILED=$((FAILED + 1))
        BROKEN+=("$image")
    fi
done < <(grep -E "^\s*container_[a-z0-9_]+\s*=" "$CONFIG")

echo

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}All container tags resolve.${NC}"
    exit 0
fi

echo -e "${YELLOW}${FAILED} tag(s) no longer exist. Available alternatives:${NC}"
echo

for image in "${BROKEN[@]}"; do
    repo="${image%%:*}"          # quay.io/biocontainers/bracken
    tool="${repo##*/}"           # bracken
    echo "  $tool"

    api="https://quay.io/api/v1/repository/biocontainers/${tool}/tag/?limit=100&onlyActiveTags=true"
    if ! curl -fsSL "$api" 2>/dev/null | python3 -c "
import json, sys
try:
    tags = json.load(sys.stdin).get('tags', [])
except Exception:
    sys.exit(1)
names = sorted({t['name'] for t in tags if not t['name'].startswith('sha256')}, reverse=True)
for n in names[:8]:
    print(f'    quay.io/biocontainers/${tool}:{n}')
" 2>/dev/null; then
        echo "    (could not reach quay.io; browse https://quay.io/repository/biocontainers/${tool}?tab=tags)"
    fi
    echo
done

echo "Edit conf/containers.config with a working tag, then re-run this script."
echo "Prefer the newest tag for the same tool version where one exists."
exit 1
