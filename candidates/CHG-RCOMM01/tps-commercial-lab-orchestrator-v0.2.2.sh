#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
umask 077

VERSION="0.2.2"
REPO="/root/Projeto-StudioSat-Web-Radios-e-TVs-"
RUNNER_COMMIT="1637fa6e6b1cc551ec48031939ad36038f20733c"
RUNNER_PATH="candidates/CHG-RCOMM01/tps-commercial-lab-auto-v0.2.1.sh"
RUNNER="/root/tps-commercial-lab-auto-v0.2.1.sh"
API="http://127.0.0.1:9997"
LAB_PATH="radioprincipal-commercial-test"
CFG="/etc/tpsmedia/mediamtx/mediamtx.yml"
MTX="/opt/tpsmedia/mediamtx/current/mediamtx"
CHANNELS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
TMP=""
BACKUP=""
ORIG_CFG_SHA=""
LAB_ADDED=0

log(){ printf '[%s] %s\n' "$(date -Is)" "$*"; }
die(){ echo "FAIL: $*" >&2; exit 1; }

public_health(){
  local ch state code
  for ch in "${CHANNELS[@]}"; do
    state="$(systemctl is-active "tps-${ch}-playout.service" 2>/dev/null || true)"
    code="$(curl -sS -L --max-time 6 -o /dev/null -w '%{http_code}' "http://127.0.0.1:8888/${ch}/index.m3u8" 2>/dev/null || true)"
    printf 'PUBLIC %-18s service=%-8s HTTP=%s\n' "$ch" "$state" "$code"
    [[ "$state" == "active" && "$code" == "200" ]] || return 1
  done
}

resources(){
  ps -eo pcpu=,rss=,args= | awk '
    /mediamtx|ffmpeg.*radio(principal|pop|rock|classicas|country)/ {
      cpu += $1; rss += $2
    }
    END { printf "CPU_SUM=%.1f%% RAM_RSS=%.1f MiB\\n", cpu, rss/1024 }'
}

playlist_hashes(){
  local out="$1" ch p
  : > "$out"
  for ch in "${CHANNELS[@]}"; do
    p="/srv/tpsmedia/repository/channels/${ch}/playlists/playlist.txt"
    [[ -f "$p" ]] || die "playlist ausente: $p"
    sha256sum "$p" >> "$out"
  done
}

lab_delete(){
  curl -sS --max-time 5 -X DELETE "${API}/v3/config/paths/delete/${LAB_PATH}" -o /dev/null 2>&1 || true
  LAB_ADDED=0
}

cleanup(){
  local rc=$?
  trap - ERR INT TERM EXIT
  echo
  echo "AUTO_CLEANUP_TRIGGERED rc=$rc"
  if [[ -x "$RUNNER" ]]; then "$RUNNER" rollback >/dev/null 2>&1 || true; fi
  if [[ "$LAB_ADDED" == "1" ]]; then lab_delete; fi
  public_health || true
  exit "$rc"
}

trap cleanup ERR INT TERM

[[ "$EUID" -eq 0 ]] || die "execute como root"
for c in git curl sha256sum tar diff systemctl ps awk "$MTX"; do
  if [[ "$c" == "$MTX" ]]; then [[ -x "$MTX" ]] || die "MediaMTX ausente"; else command -v "$c" >/dev/null 2>&1 || die "dependência ausente: $c"; fi
done
[[ -d "$REPO/.git" ]] || die "repo ausente: $REPO"
[[ -f "$CFG" ]] || die "config ausente: $CFG"
public_health || die "produção não está saudável"
curl -fsS --max-time 5 "${API}/v3/config/paths/list" >/dev/null || die "API MediaMTX indisponível"

TMP="$(mktemp -d /tmp/tps-commercial-lab-orch.XXXXXX)"
ORIG_CFG_SHA="$(sha256sum "$CFG" | awk '{print $1}')"
playlist_hashes "$TMP/playlists.before"

echo "BASELINE_RESOURCES=$(resources)"

# O LAB deve estar ausente antes de começar; não removemos nada desconhecido.
LAB_GET_CODE="$(curl -sS --max-time 5 -o /dev/null -w '%{http_code}' "${API}/v3/config/paths/get/${LAB_PATH}" 2>/dev/null || true)"
[[ "$LAB_GET_CODE" != "200" ]] || die "path LAB já existe; abortando para não remover configuração desconhecida"

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/var/backups/studiosat/commercial-lab-orchestrator-v0_2_2-pre-${STAMP}"
mkdir -p "$BACKUP/playlists"
cp -a "$CFG" "$BACKUP/mediamtx.yml"
for ch in "${CHANNELS[@]}"; do
  cp -a "/srv/tpsmedia/repository/channels/${ch}/playlists/playlist.txt" "$BACKUP/playlists/${ch}.playlist.txt"
done
find "$BACKUP" -type f ! -name SHA256SUMS -exec sha256sum {} \; | sort > "$BACKUP/SHA256SUMS"
(cd "$BACKUP" && sha256sum -c SHA256SUMS >/dev/null)
[[ "$(sha256sum "$BACKUP/mediamtx.yml" | awk '{print $1}')" == "$ORIG_CFG_SHA" ]] || die "backup da configuração não reproduz o SHA original"
"$MTX" --validate-conf="$BACKUP/mediamtx.yml" >/dev/null 2>&1 || die "backup da configuração não valida"
tar -C "$(dirname "$BACKUP")" -czf "${BACKUP}.tar.gz" "$(basename "$BACKUP")"
sha256sum "${BACKUP}.tar.gz"
echo "BACKUP_AND_RESTORE_VALIDATION=PASS"

# Adiciona SOMENTE um path de runtime. O arquivo mediamtx.yml não é alterado.
log "adicionando path LAB apenas na Control API"
curl -fsS --max-time 5 -X POST \
  -H 'Content-Type: application/json' \
  -d '{"source":"publisher"}' \
  "${API}/v3/config/paths/add/${LAB_PATH}" >/dev/null
LAB_ADDED=1
curl -fsS --max-time 5 "${API}/v3/config/paths/get/${LAB_PATH}" >/dev/null || die "path LAB não apareceu na API"
[[ "$(sha256sum "$CFG" | awk '{print $1}')" == "$ORIG_CFG_SHA" ]] || die "arquivo MediaMTX foi alterado inesperadamente"
public_health || die "produção degradou após adicionar path LAB"
echo "RUNTIME_LAB_PATH=PASS"

# Busca e valida o runner já testado.
git -C "$REPO" fetch --quiet origin "$RUNNER_COMMIT"
[[ "$(git -C "$REPO" rev-parse FETCH_HEAD)" == "$RUNNER_COMMIT" ]] || die "commit do runner incorreto"
git -C "$REPO" show "${RUNNER_COMMIT}:${RUNNER_PATH}" > "$RUNNER"
chmod 700 "$RUNNER"
bash -n "$RUNNER"
"$RUNNER" selftest

# O runner faz precheck, backup, cria playlist LAB, transmite, valida HLS/AAC e deixa o LAB ativo no sucesso.
"$RUNNER" run

echo "LAB_RESOURCES=$(resources)"
public_health || die "produção degradou durante LAB"

# Encerra LAB, depois remove apenas o path runtime criado acima.
"$RUNNER" rollback
lab_delete
sleep 1

[[ "$(sha256sum "$CFG" | awk '{print $1}')" == "$ORIG_CFG_SHA" ]] || die "SHA do mediamtx.yml mudou"
playlist_hashes "$TMP/playlists.after"
diff -u "$TMP/playlists.before" "$TMP/playlists.after" >/dev/null || die "alguma playlist pública mudou"
public_health || die "produção não saudável no final"

trap - ERR INT TERM

echo "PUBLIC_PLAYLISTS_UNCHANGED=PASS"
echo "MEDIAMTX_CONFIG_FILE_UNCHANGED=PASS"
echo "RUNTIME_LAB_PATH_REMOVED=PASS"
echo "TPS_COMMERCIAL_LAB_ORCHESTRATOR_V0_2_2=PASS"
echo "PRODUCAO_PUBLICA=INTACTA"
