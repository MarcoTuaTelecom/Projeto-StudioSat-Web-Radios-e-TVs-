#!/usr/bin/env bash
# Nome: deploy-tv-player-v2.sh
# Versão: 1.1
# Owner: TV + Core
# Safety class: dispatcher
# Change ID: CHG-TVKIDS-WEB-003
# Propósito: compatibilidade; encaminha o deploy antigo para a implantação isolada e segura da TVKIDS.
set -Eeuo pipefail
IFS=$'\n\t'
REPO="/root/Projeto-StudioSat-Web-Radios-e-TVs-"
TARGET="$REPO/scripts/tv/deploy-tvkids-player-v2-isolated.sh"
[[ -f "$TARGET" ]] || { echo FATAL=ISOLATED_TVKIDS_DEPLOY_MISSING >&2; exit 2; }
exec bash "$TARGET" "$@"
