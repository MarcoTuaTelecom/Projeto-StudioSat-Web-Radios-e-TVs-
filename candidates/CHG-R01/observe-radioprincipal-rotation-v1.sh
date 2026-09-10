#!/usr/bin/env bash
# StudioSat Web — observe one complete Radio Principal playlist rotation
# Change: CHG-R01
# READ-ONLY: reads /proc and ready/; writes only /tmp.
set -Eeuo pipefail
IFS=$'\n\t'

UNIT="tps-radioprincipal-playout.service"
READY="/srv/tpsmedia/repository/channels/radioprincipal/ready"
TIMEOUT_SEC="${1:-10800}"
INTERVAL_SEC="${2:-1}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/CHG-R01-radioprincipal-rotation-${STAMP}.tsv"

pid="$(systemctl show "$UNIT" -p MainPID --value)"
[[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 0 ]] || { echo "FATAL=NO_MAINPID" >&2; exit 1; }

mapfile -d '' expected < <(
  find "$READY" -type f \
    \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' \) \
    ! -iname '*teste*' ! -iname '*test*' \
    -print0 | sort -z
)
expected_count="${#expected[@]}"
(( expected_count > 0 )) || { echo "FATAL=NO_ELIGIBLE_MEDIA" >&2; exit 1; }

declare -A seen=()
last=""
start_epoch="$(date +%s)"
printf 'utc\tordinal\tasset\n' > "$OUT"

echo "PID=$pid"
echo "EXPECTED=$expected_count"
echo "OUTPUT=$OUT"

while :; do
  current=""
  for fd in /proc/$pid/fd/*; do
    [[ -e "$fd" ]] || continue
    target="$(readlink -f "$fd" 2>/dev/null || true)"
    case "$target" in
      "$READY"/*) current="$target"; break ;;
    esac
  done

  if [[ -n "$current" && "$current" != "$last" ]]; then
    last="$current"
    if [[ -z "${seen[$current]+x}" ]]; then
      seen["$current"]=1
      ordinal="${#seen[@]}"
      printf '%s\t%d\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ordinal" "$(basename -- "$current")" | tee -a "$OUT"
      if (( ordinal == expected_count )); then
        echo "ROTATION_RESULT=PASS"
        echo "SEEN=$ordinal/$expected_count"
        echo "OUTPUT=$OUT"
        exit 0
      fi
    fi
  fi

  now="$(date +%s)"
  if (( now - start_epoch >= TIMEOUT_SEC )); then
    echo "ROTATION_RESULT=FAIL_TIMEOUT"
    echo "SEEN=${#seen[@]}/$expected_count"
    echo "OUTPUT=$OUT"
    exit 1
  fi
  sleep "$INTERVAL_SEC"
done
