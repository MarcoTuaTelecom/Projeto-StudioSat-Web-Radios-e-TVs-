#!/usr/bin/env bash
# Studio Sat RadioPrincipal V2 no-downtime guard.
set -euo pipefail

PROTECTED_UNITS=(
  studiosat-radioprincipal-selector.service
  studiosat-radioprincipal-shadow-ns1.service
  tps-mediamtx.service
  nginx.service
)

case "${1:-}" in
  status)
    echo "NO_DOWNTIME_GUARD=ENFORCED"
    for u in "${PROTECTED_UNITS[@]}"; do
      echo "$u=$(systemctl is-active "$u" 2>/dev/null || true)"
    done
    ;;
  assert-safe-path)
    p="${2:-}"
    case "$p" in
      radioprincipal|radioprincipal-ns1)
        echo "DENY=PRODUCTION_PATH:$p"; exit 40;;
      radioprincipal-v2-*|radioprincipal-test*)
        echo "ALLOW=ISOLATED_PATH:$p";;
      *)
        echo "DENY=UNKNOWN_PATH:$p"; exit 41;;
    esac
    ;;
  assert-no-public-unit)
    u="${2:-}"
    for x in "${PROTECTED_UNITS[@]}"; do
      [ "$u" = "$x" ] && { echo "DENY=PROTECTED_UNIT:$u"; exit 42; }
    done
    echo "ALLOW=NON_PRODUCTION_UNIT:$u"
    ;;
  *)
    echo "USAGE: $0 status | assert-safe-path <path> | assert-no-public-unit <unit>"
    exit 2
    ;;
esac
