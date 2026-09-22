#!/usr/bin/env bash
set -Eeuo pipefail

REPO="https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-.git"
BRANCH="feature/studiosat-v2-rust-native"
DST="/root/studiosat-v2-src"

[[ $EUID -eq 0 ]] || { echo "Execute como root." >&2; exit 1; }

for c in git curl nginx systemctl python3; do
  command -v "$c" >/dev/null || { echo "Comando ausente: $c" >&2; exit 1; }
done

if [[ -d "$DST/.git" ]]; then
  git -C "$DST" fetch origin "$BRANCH"
  git -C "$DST" checkout "$BRANCH"
  git -C "$DST" reset --hard "origin/$BRANCH"
else
  rm -rf "$DST"
  git clone --branch "$BRANCH" --single-branch "$REPO" "$DST"
fi

cd "$DST/StudioSAT-V2"
bash deploy/bootstrap-toolchain.sh
bash deploy/build-web.sh
bash deploy/install-ns1.sh
bash deploy/smoke-test.sh

echo "V2_URL=https://www.radio.studiosatweb.com.br/listen-v2/"
echo "REFERENCE=https://radio.studiosatweb.com.br/diag-bypass/"
