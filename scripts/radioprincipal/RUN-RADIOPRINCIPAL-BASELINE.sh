#!/usr/bin/env bash
# Nome: RUN-RADIOPRINCIPAL-BASELINE.sh
# Versão: 1.0 / 2026-09-17
# Owner: Rádio
# Safety class: read-only
# Change ID: RADIOPRINCIPAL-NS1-C03
# Propósito: baixar, verificar e executar a versão canônica do XRAY V2 da Rádio Principal no NS1.
# Pré-condições: root no NS1, acesso HTTPS ao GitHub, curl e python3; RadioBOSS operando normalmente.
# Rollback/remoção: remover /root/RUN-RADIOPRINCIPAL-BASELINE.sh e /root/STUDIOSAT-RADIOPRINCIPAL-FULL-XRAY-V2.sh.

set -Eeuo pipefail

# Studio Sat / Rádio Principal / NS1
# Executor reproduzível do XRAY V2 registrado no GitHub.
# Segurança: baixa a versão canônica, valida o Git blob SHA aprovado e só então executa.
# O XRAY é read-only, exceto pela criação do relatório em /root e corpos HTTP temporários.

REPO="MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-"
BRANCH="reorg/project-context-v2"
XRAY_REPO_PATH="scripts/radioprincipal/STUDIOSAT-RADIOPRINCIPAL-FULL-XRAY-V2.sh"
XRAY_LOCAL="/root/STUDIOSAT-RADIOPRINCIPAL-FULL-XRAY-V2.sh"
EXPECTED_GIT_BLOB_SHA="5128ecfb411bb4244cac7b383a2fef62bfc68aac"
OBSERVE_SECONDS="${OBSERVE_SECONDS:-90}"
MODE="run"

usage() {
  cat <<'EOF'
Uso:
  /root/RUN-RADIOPRINCIPAL-BASELINE.sh
  /root/RUN-RADIOPRINCIPAL-BASELINE.sh --download-only
  /root/RUN-RADIOPRINCIPAL-BASELINE.sh --local

Opções:
  --download-only  Baixa/valida/instala o XRAY, mas não executa.
  --local          Não baixa do GitHub; valida e executa a cópia local já instalada.

Variável opcional:
  OBSERVE_SECONDS=90   Janela de observação do XRAY (mínimo efetivo no XRAY: 30s).
EOF
}

case "${1:-}" in
  "") ;;
  --download-only) MODE="download-only" ;;
  --local) MODE="local" ;;
  -h|--help) usage; exit 0 ;;
  *) echo "ERRO: opção inválida: $1" >&2; usage >&2; exit 2 ;;
esac

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERRO: execute como root." >&2
  exit 1
fi

for cmd in python3 sha256sum bash install mktemp; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "ERRO: comando obrigatório ausente: $cmd" >&2
    exit 3
  }
done

fetch_from_github() {
  command -v curl >/dev/null 2>&1 || {
    echo "ERRO: curl não está instalado; use --local se o XRAY já estiver em $XRAY_LOCAL" >&2
    return 4
  }

  local encoded_ref api_url tmp_json tmp_script api_blob_sha got_blob_sha got_sha256
  encoded_ref="$(python3 - "$BRANCH" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=''))
PY
)"
  api_url="https://api.github.com/repos/${REPO}/contents/${XRAY_REPO_PATH}?ref=${encoded_ref}"
  tmp_json="$(mktemp /root/.radioprincipal-xray-api.XXXXXX.json)"
  tmp_script="$(mktemp /root/.radioprincipal-xray.XXXXXX.sh)"
  trap 'rm -f "${tmp_json:-}" "${tmp_script:-}"' RETURN

  echo "GITHUB_REPO=$REPO"
  echo "GITHUB_BRANCH=$BRANCH"
  echo "GITHUB_PATH=$XRAY_REPO_PATH"
  echo "DOWNLOAD=INICIANDO"

  curl -fLsS \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    "$api_url" -o "$tmp_json"

  api_blob_sha="$(python3 - "$tmp_json" "$tmp_script" <<'PY'
import base64, json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, 'r', encoding='utf-8') as f:
    obj = json.load(f)
content = obj.get('content')
encoding = obj.get('encoding')
blob_sha = obj.get('sha')
if encoding != 'base64' or not isinstance(content, str) or not isinstance(blob_sha, str):
    raise SystemExit('ERRO: resposta inesperada da API do GitHub')
raw = base64.b64decode(content)
with open(dst, 'wb') as f:
    f.write(raw)
print(blob_sha)
PY
)"

  got_blob_sha="$(python3 - "$tmp_script" <<'PY'
import hashlib, sys
b = open(sys.argv[1], 'rb').read()
print(hashlib.sha1((f"blob {len(b)}\0").encode() + b).hexdigest())
PY
)"
  got_sha256="$(sha256sum "$tmp_script" | awk '{print $1}')"

  echo "API_GIT_BLOB_SHA=$api_blob_sha"
  echo "DOWNLOADED_GIT_BLOB_SHA=$got_blob_sha"
  echo "EXPECTED_GIT_BLOB_SHA=$EXPECTED_GIT_BLOB_SHA"
  echo "DOWNLOADED_SHA256=$got_sha256"

  if [[ "$api_blob_sha" != "$EXPECTED_GIT_BLOB_SHA" || "$got_blob_sha" != "$EXPECTED_GIT_BLOB_SHA" ]]; then
    echo "ERRO: o XRAY no GitHub não corresponde ao blob aprovado. Nada será executado." >&2
    echo "Revise a mudança e atualize o executor antes de rodar uma nova versão." >&2
    return 5
  fi

  bash -n "$tmp_script"
  install -o root -g root -m 0700 "$tmp_script" "$XRAY_LOCAL"
  echo "INSTALLED=$XRAY_LOCAL"
  echo "DOWNLOAD=OK"
}

validate_local() {
  [[ -f "$XRAY_LOCAL" ]] || {
    echo "ERRO: XRAY local não encontrado: $XRAY_LOCAL" >&2
    exit 6
  }

  local got_blob_sha got_sha256
  got_blob_sha="$(python3 - "$XRAY_LOCAL" <<'PY'
import hashlib, sys
b = open(sys.argv[1], 'rb').read()
print(hashlib.sha1((f"blob {len(b)}\0").encode() + b).hexdigest())
PY
)"
  got_sha256="$(sha256sum "$XRAY_LOCAL" | awk '{print $1}')"
  echo "LOCAL_XRAY=$XRAY_LOCAL"
  echo "LOCAL_GIT_BLOB_SHA=$got_blob_sha"
  echo "EXPECTED_GIT_BLOB_SHA=$EXPECTED_GIT_BLOB_SHA"
  echo "LOCAL_SHA256=$got_sha256"

  if [[ "$got_blob_sha" != "$EXPECTED_GIT_BLOB_SHA" ]]; then
    echo "ERRO: o XRAY local não corresponde à versão registrada/aprovada." >&2
    exit 7
  fi

  bash -n "$XRAY_LOCAL"
  echo "LOCAL_VALIDATION=OK"
}

latest_report() {
  find /root -maxdepth 1 -type f -name 'XRAY-RADIOPRINCIPAL-NS1-V2-*.txt' \
    -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-
}

echo "============================================================"
echo " STUDIO SAT - RADIOPRINCIPAL / NS1 BASELINE"
echo " WORKSTREAM=RADIOPRINCIPAL-NS1"
echo " UTC_START=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo " HOST=$(hostname -f 2>/dev/null || hostname)"
echo " MODE=$MODE"
echo "============================================================"

if [[ "$MODE" != "local" ]]; then
  fetch_from_github
fi

validate_local

if [[ "$MODE" == "download-only" ]]; then
  echo "RESULTADO=XRAY_INSTALADO_E_VALIDADO"
  exit 0
fi

BEFORE="$(latest_report || true)"

echo
cat <<'EOF'
ATENÇÃO DURANTE O XRAY:
- deixe o RadioBOSS tocar normalmente;
- não pressione Next, Pause ou Stop;
- não reinicie serviços;
- não altere selector, Harbor, MediaMTX ou Nginx.
EOF

echo
echo "EXECUTANDO_XRAY=SIM"
echo "OBSERVE_SECONDS=$OBSERVE_SECONDS"

set +e
OBSERVE_SECONDS="$OBSERVE_SECONDS" bash "$XRAY_LOCAL"
RC=$?
set -e

AFTER="$(latest_report || true)"

echo
echo "============================================================"
echo " XRAY ENCERRADO"
echo " EXIT_CODE=$RC"

if [[ -n "$AFTER" && -f "$AFTER" ]]; then
  echo "REPORT=$AFTER"
  echo "REPORT_SHA256=$(sha256sum "$AFTER" | awk '{print $1}')"
  ln -sfn "$AFTER" /root/XRAY-RADIOPRINCIPAL-LATEST.txt
  echo "LATEST_LINK=/root/XRAY-RADIOPRINCIPAL-LATEST.txt"
  if [[ -n "$BEFORE" && "$BEFORE" == "$AFTER" ]]; then
    echo "WARNING=nenhum novo nome de relatório foi detectado"
  fi
else
  echo "REPORT=NAO_LOCALIZADO"
fi

echo "============================================================"
exit "$RC"
