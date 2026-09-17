#!/usr/bin/env bash
# Nome: RUN-AUTHORITY-REPLICA-CANDIDATE.sh
# Versão: 1.1 / 2026-09-17
# Owner: Rádio
# Safety class: candidate-write-isolated
# Change ID: RADIOPRINCIPAL-NS1-C04
# Propósito: baixar, validar, auto-testar e executar a réplica autoritativa candidate sem tocar no caminho público.
set -euo pipefail

REPO='MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-'
BRANCH='reorg/project-context-v2'
PATH_REPO='scripts/radioprincipal/candidate/authority-replica-candidate.py'
EXPECTED_BLOB='16604dd88421950747ad7c66a264b29f8552710c'
URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}/${PATH_REPO}"
TARGET='/root/authority-replica-candidate.py'
CAND='/var/lib/studiosat/radio-v2/candidates/radioprincipal-authority-replica'
MODE="${1:---once}"

[ "$(id -u)" -eq 0 ] || { echo 'ERRO: execute como root.' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'ERRO: python3 ausente.' >&2; exit 2; }
command -v curl >/dev/null || { echo 'ERRO: curl ausente.' >&2; exit 2; }

blob_sha() {
  python3 - "$1" <<'PY'
import hashlib, pathlib, sys
b=pathlib.Path(sys.argv[1]).read_bytes()
print(hashlib.sha1(b"blob "+str(len(b)).encode()+b"\0"+b).hexdigest())
PY
}

fetch_validate() {
  local tmp
  tmp="$(mktemp /root/.authority-replica.XXXXXX.py)"
  trap 'rm -f "${tmp:-}"' RETURN
  echo "DOWNLOAD=$URL"
  curl -fsSL "$URL" -o "$tmp"
  local got
  got="$(blob_sha "$tmp")"
  echo "EXPECTED_GIT_BLOB=$EXPECTED_BLOB"
  echo "DOWNLOADED_GIT_BLOB=$got"
  [ "$got" = "$EXPECTED_BLOB" ] || { echo 'ERRO: blob divergente; nada executado.' >&2; exit 10; }
  python3 -m py_compile "$tmp"
  echo 'PY_COMPILE=OK'
  python3 "$tmp" --self-test
  echo 'SELF_TEST=OK'
  install -m 0700 "$tmp" "$TARGET"
  echo "INSTALLED=$TARGET"
}

show_status() {
  if [ -f "$CAND/status.json" ]; then
    echo '================ CANDIDATE STATUS ================'
    python3 -m json.tool "$CAND/status.json"
  else
    echo "STATUS_FILE_AUSENTE=$CAND/status.json"
  fi
}

case "$MODE" in
  --once)
    fetch_validate
    echo 'RUN_MODE=ONCE'
    "$TARGET"
    show_status
    ;;
  --watch)
    fetch_validate
    echo 'RUN_MODE=WATCH INTERVAL=10s'
    echo 'CTRL+C encerra somente o candidate; produção não é alterada.'
    exec "$TARGET" --watch --interval 10
    ;;
  --status)
    show_status
    ;;
  --self-test-only)
    fetch_validate
    ;;
  *)
    echo "Uso: $0 [--once|--watch|--status|--self-test-only]" >&2
    exit 64
    ;;
esac
