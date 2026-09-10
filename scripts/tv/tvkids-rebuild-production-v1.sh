#!/usr/bin/env bash
# StudioSat Web — CHG-TVKIDS-001
# TVKIDS production rebuild orchestrator v1.0
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
PARTS=(
  "$SCRIPT_DIR/tvkids-rebuild-lib-v1.sh"
  "$SCRIPT_DIR/tvkids-rebuild-media-v1.sh"
  "$SCRIPT_DIR/tvkids-rebuild-cutover-v1.sh"
  "$SCRIPT_DIR/tvkids-rebuild-public-v1.sh"
)
HELPERS=(
  "$SCRIPT_DIR/tvkids-build-plan-v1.sh"
  "$SCRIPT_DIR/tvkids-health-v1.sh"
  "$SCRIPT_DIR/tvkids-normalize-asset-v1.sh"
  "$SCRIPT_DIR/tvkids-nginx-patch-v1.py"
)

cd "$REPO"
git fetch origin main --quiet
HEAD_SHA="$(git rev-parse HEAD)"
ORIGIN_SHA="$(git rev-parse origin/main)"
printf 'CHG-TVKIDS-001\nHEAD=%s\nORIGIN=%s\n' "$HEAD_SHA" "$ORIGIN_SHA"
[[ "$HEAD_SHA" == "$ORIGIN_SHA" ]] || { echo "FATAL=GIT_NOT_SYNCED"; exit 1; }

for f in "${PARTS[@]}" "${HELPERS[@]}" "$0"; do
  rel="${f#$REPO/}"
  [[ -f "$f" ]] || { echo "FATAL=MISSING_REPO_FILE:$rel"; exit 1; }
  local_sha="$(sha256sum "$f" | awk '{print $1}')"
  git_sha="$(git show "HEAD:$rel" | sha256sum | awk '{print $1}')"
  [[ "$local_sha" == "$git_sha" ]] || { echo "FATAL=REPO_FILE_DRIFT:$rel"; exit 1; }
done
for f in "${PARTS[@]}" "${HELPERS[@]:0:3}"; do bash -n "$f"; done
python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "${HELPERS[3]}"

TVKIDS_REBUILD_ORCHESTRATOR=1
source "${PARTS[0]}"
source "${PARTS[1]}"
source "${PARTS[2]}"
source "${PARTS[3]}"
