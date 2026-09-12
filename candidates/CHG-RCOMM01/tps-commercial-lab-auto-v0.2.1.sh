#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C
umask 077

VERSION="0.2.1"
UNIT="tps-radioprincipal-commercial-test.service"
LAB_PATH="radioprincipal-commercial-test"
API_URL="http://127.0.0.1:9997/v3/paths/list"
HLS_BASE="http://127.0.0.1:8888"
CHANNELS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
LAB_STARTED=0
LAB_TOUCHED=0
WORKDIR=""
BASE=""
READY=""
COMMERCIAL=""
SPOT=""
LAB_PLAYLIST=""
STATE_FILE=""
BACKUP_DIR=""

log(){ printf '[%s] %s\n' "$(date -Is)" "$*"; }
fail(){ printf 'FAIL: %s\n' "$*" >&2; return 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

public_health(){
  local ch code state
  for ch in "${CHANNELS[@]}"; do
    state="$(systemctl is-active "tps-${ch}-playout.service" 2>/dev/null || true)"
    [[ "$state" == "active" ]] || fail "serviço público tps-${ch}-playout.service=$state" || return 1
    code="$(curl -sS -L --max-time 6 -o /dev/null -w '%{http_code}' "${HLS_BASE}/${ch}/index.m3u8" 2>/dev/null || true)"
    [[ "$code" == "200" ]] || fail "HLS público ${ch}=HTTP ${code}" || return 1
    printf 'PUBLIC %-18s service=%-8s HTTP=%s\n' "$ch" "$state" "$code"
  done
}

detect_paths(){
  local prod_playlist
  prod_playlist="$(
    {
      systemctl cat tps-radioprincipal-playout.service 2>/dev/null || true
      ps -eo args= 2>/dev/null | grep -E '[f]fmpeg.*radioprincipal' || true
    } | grep -oE '/[^[:space:]]*/radioprincipal/playlists/playlist\.txt' | tail -n1
  )"
  [[ -n "$prod_playlist" ]] || fail "não consegui descobrir playlist de produção da radioprincipal" || return 1
  BASE="${prod_playlist%/playlists/playlist.txt}"
  READY="${BASE}/ready"
  COMMERCIAL="${BASE}/commercial"
  SPOT="${COMMERCIAL}/ads/TESTE_COMERCIAL_TPS_6S.mp3"
  LAB_PLAYLIST="${COMMERCIAL}/generated/lab-commercial-v0_2.ffconcat"
  STATE_FILE="${COMMERCIAL}/state/lab-commercial-v0_2.state"
  [[ -d "$READY" ]] || fail "diretório ready não existe: $READY" || return 1
  log "BASE detectado: $BASE"
}

capture_public_hashes(){
  local out="$1" ch p
  : > "$out"
  for ch in "${CHANNELS[@]}"; do
    p="${BASE%/radioprincipal}/${ch}/playlists/playlist.txt"
    [[ -f "$p" ]] || fail "playlist pública ausente: $p" || return 1
    sha256sum "$p" >> "$out"
  done
}

verify_public_hashes(){
  local before="$1" now ch p
  now="$(mktemp)"
  for ch in "${CHANNELS[@]}"; do
    p="${BASE%/radioprincipal}/${ch}/playlists/playlist.txt"
    sha256sum "$p" >> "$now"
  done
  if ! diff -u "$before" "$now" >/dev/null; then
    echo "ERRO: playlists públicas mudaram durante o LAB:" >&2
    diff -u "$before" "$now" >&2 || true
    rm -f "$now"
    return 1
  fi
  rm -f "$now"
  echo "PUBLIC_PLAYLISTS_UNCHANGED=PASS"
}

make_backup(){
  local stamp ch p
  stamp="$(date +%Y%m%d-%H%M%S)"
  BACKUP_DIR="/var/backups/studiosat/commercial-lab-v0_2-pre-${stamp}"
  mkdir -p "$BACKUP_DIR"/{playlists,systemd,mediamtx}
  for ch in "${CHANNELS[@]}"; do
    mkdir -p "$BACKUP_DIR/playlists/$ch"
    p="${BASE%/radioprincipal}/${ch}/playlists/playlist.txt"
    cp -a "$p" "$BACKUP_DIR/playlists/$ch/"
    systemctl cat "tps-${ch}-playout.service" > "$BACKUP_DIR/systemd/tps-${ch}-playout.service.txt" 2>/dev/null || true
  done
  cp -a /etc/tpsmedia/mediamtx/mediamtx.yml "$BACKUP_DIR/mediamtx/" 2>/dev/null || true
  find "$BACKUP_DIR" -type f ! -name SHA256SUMS -exec sha256sum {} \; | sort > "$BACKUP_DIR/SHA256SUMS"
  (cd "$BACKUP_DIR" && sha256sum -c SHA256SUMS >/dev/null)
  tar -C "$(dirname "$BACKUP_DIR")" -czf "${BACKUP_DIR}.tar.gz" "$(basename "$BACKUP_DIR")"
  sha256sum "${BACKUP_DIR}.tar.gz"
  echo "BACKUP_PRE_LAB=PASS"
}

precheck(){
  local s
  log "PRECHECK v${VERSION}"
  [[ "${EUID}" -eq 0 ]] || fail "execute como root" || return 1
  for x in systemctl systemd-run curl ffmpeg ffprobe sha256sum tar ps grep sed find timeout ss diff seq mktemp cp chown chmod mv id; do
    have "$x" || fail "dependência ausente: $x" || return 1
  done
  detect_paths
  id tpsmedia >/dev/null 2>&1 || fail "usuário tpsmedia não existe" || return 1
  for s in tps-mediamtx.service nginx.service bind9.service; do
    [[ "$(systemctl is-active "$s" 2>/dev/null || true)" == "active" ]] || fail "$s não está active" || return 1
  done
  curl -fsS --max-time 5 "$API_URL" >/dev/null || fail "API MediaMTX indisponível em $API_URL" || return 1
  ss -lnt 2>/dev/null | grep -Eq '[:.]1935[[:space:]]' || fail "RTMP 1935 não está LISTEN" || return 1
  public_health
  echo "PRECHECK=PASS"
}

ensure_layout(){
  mkdir -p "$COMMERCIAL"/{ads,generated,state,logs}
  chown -R tpsmedia:tpsmedia "$COMMERCIAL"
}

ensure_spot(){
  if [[ -f "$SPOT" ]]; then
    ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of default=nw=1 "$SPOT" >/dev/null \
      || fail "spot técnico existente é inválido" || return 1
    log "spot técnico existente preservado: $SPOT"
    return 0
  fi
  log "criando spot técnico de 6s"
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i 'sine=frequency=880:duration=6:sample_rate=48000' \
    -filter_complex 'pan=stereo|c0=c0|c1=c0,volume=0.20' \
    -c:a libmp3lame -b:a 192k -ar 48000 -ac 2 "$SPOT"
  chown tpsmedia:tpsmedia "$SPOT"
  chmod 0644 "$SPOT"
  ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate,channels -of default=nw=1 "$SPOT" >/dev/null \
    || fail "spot técnico recém-criado falhou no ffprobe" || return 1
  echo "created_spot=1" > "$STATE_FILE"
}

ffconcat_escape(){
  local s="$1"
  printf '%s' "${s//\'/\'\\\'\'}"
}

build_lab_playlist(){
  LAB_TOUCHED=1
  local -a music=()
  local tmp f
  while IFS= read -r -d '' f; do
    music+=("$f")
    (( ${#music[@]} >= 2 )) && break
  done < <(find "$READY" -maxdepth 1 -type f \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.aac' \) -print0 | sort -z)
  (( ${#music[@]} >= 2 )) || fail "menos de 2 assets de áudio em $READY" || return 1
  for f in "${music[0]}" "$SPOT" "${music[1]}"; do
    ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$f" >/dev/null \
      || fail "asset sem áudio válido: $f" || return 1
  done
  tmp="${LAB_PLAYLIST}.tmp.$$"
  {
    echo 'ffconcat version 1.0'
    printf "file '%s'\n" "$(ffconcat_escape "${music[0]}")"
    printf "file '%s'\n" "$(ffconcat_escape "$SPOT")"
    printf "file '%s'\n" "$(ffconcat_escape "${music[1]}")"
  } > "$tmp"
  chown tpsmedia:tpsmedia "$tmp"
  chmod 0644 "$tmp"
  mv -f "$tmp" "$LAB_PLAYLIST"
  echo "LAB_PLAYLIST=$LAB_PLAYLIST"
  sha256sum "$LAB_PLAYLIST"
}

stop_old_lab(){
  if systemctl status "$UNIT" >/dev/null 2>&1 || systemctl is-active --quiet "$UNIT" 2>/dev/null; then
    log "parando apenas LAB anterior: $UNIT"
    systemctl stop "$UNIT" >/dev/null 2>&1 || true
    systemctl reset-failed "$UNIT" >/dev/null 2>&1 || true
    sleep 1
  fi
}

start_lab(){
  LAB_TOUCHED=1
  log "iniciando LAB paralelo"
  stop_old_lab
  systemd-run \
    --unit="${UNIT%.service}" \
    --property=User=tpsmedia \
    --property=Group=tpsmedia \
    --property=MemoryMax=256M \
    --property=CPUQuota=35% \
    --property=Nice=10 \
    /usr/bin/ffmpeg -hide_banner -loglevel warning -nostdin \
      -re -stream_loop -1 -f concat -safe 0 -i "$LAB_PLAYLIST" \
      -map 0:a:0 -c:a aac -b:a 128k -ar 48000 -ac 2 \
      -f flv "rtmp://127.0.0.1:1935/${LAB_PATH}" >/dev/null
  LAB_STARTED=1
}

wait_lab(){
  local i state code ready_json
  for i in $(seq 1 30); do
    state="$(systemctl is-active "$UNIT" 2>/dev/null || true)"
    if [[ "$state" != "active" ]]; then
      sleep 1
      continue
    fi
    code="$(curl -sS -L --max-time 3 -o /dev/null -w '%{http_code}' "${HLS_BASE}/${LAB_PATH}/index.m3u8" 2>/dev/null || true)"
    if [[ "$code" == "200" ]]; then
      ready_json="$(curl -fsS --max-time 3 "$API_URL" 2>/dev/null || true)"
      if grep -q '"name":"radioprincipal-commercial-test"' <<<"$ready_json" && grep -q '"ready":true' <<<"$ready_json"; then
        echo "LAB_READY_AFTER=${i}s"
        return 0
      fi
      echo "LAB_HLS_READY_AFTER=${i}s"
      return 0
    fi
    sleep 1
  done
  fail "LAB não ficou pronto em 30s"
}

health_lab(){
  local probe code
  [[ "$(systemctl is-active "$UNIT" 2>/dev/null || true)" == "active" ]] || fail "$UNIT não está active" || return 1
  code="$(curl -sS -L --max-time 8 -o /dev/null -w '%{http_code}' "${HLS_BASE}/${LAB_PATH}/index.m3u8" 2>/dev/null || true)"
  [[ "$code" == "200" ]] || fail "HLS LAB HTTP=$code" || return 1
  probe="$(timeout 15 ffprobe -v error -show_entries stream=codec_name,codec_type,sample_rate,channels -of default=nw=1 "${HLS_BASE}/${LAB_PATH}/index.m3u8" 2>/dev/null || true)"
  printf '%s\n' "$probe"
  grep -q '^codec_name=aac$' <<<"$probe" || fail "LAB não está AAC" || return 1
  grep -q '^sample_rate=48000$' <<<"$probe" || fail "LAB não está 48kHz" || return 1
  grep -q '^channels=2$' <<<"$probe" || fail "LAB não está stereo" || return 1
  public_health
  echo "COMMERCIAL_LAB_HEALTH=PASS"
}

rollback_lab(){
  local force="${1:-0}"
  log "ROLLBACK: somente LAB"
  if [[ "$force" == "1" || "$LAB_TOUCHED" == "1" || "$LAB_STARTED" == "1" ]]; then
    systemctl stop "$UNIT" >/dev/null 2>&1 || true
    systemctl reset-failed "$UNIT" >/dev/null 2>&1 || true
    [[ -n "$LAB_PLAYLIST" ]] && rm -f "$LAB_PLAYLIST"
  fi
  public_health
  echo "LAB_ROLLBACK=PASS"
}

on_error(){
  local rc=$?
  trap - ERR
  printf '\nAUTO_ROLLBACK_TRIGGERED rc=%s\n' "$rc" >&2
  if [[ -z "$BASE" ]]; then
    detect_paths >/dev/null 2>&1 || true
  fi
  rollback_lab 0 || true
  exit "$rc"
}

status_mode(){
  precheck
  echo "LAB_UNIT=$(systemctl is-active "$UNIT" 2>/dev/null || true)"
  curl -sS -L --max-time 5 -o /dev/null -w 'LAB_HLS_HTTP=%{http_code}\n' "${HLS_BASE}/${LAB_PATH}/index.m3u8" 2>/dev/null || true
}

selftest(){
  local t a escaped expected
  t="$(mktemp -d)"
  trap 'rm -rf "$t"' RETURN
  a="$t/Ain't Test.mp3"
  : > "$a"
  escaped="$(ffconcat_escape "$a")"
  expected="${a//\'/\'\\\'\'}"
  [[ "$escaped" == "$expected" ]] || { echo "SELFTEST_FAIL escape"; return 1; }
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "SELFTEST_FAIL version"; return 1; }
  echo "SELFTEST=PASS"
}

run_mode(){
  precheck
  trap on_error ERR
  WORKDIR="$(mktemp -d /tmp/tps-commercial-lab-v0_2.XXXXXX)"
  local before="$WORKDIR/public.sha256"
  capture_public_hashes "$before"
  make_backup
  ensure_layout
  ensure_spot
  build_lab_playlist
  start_lab
  wait_lab
  health_lab
  verify_public_hashes "$before"
  trap - ERR
  echo
  echo "========================================"
  echo "TPS_COMMERCIAL_LAB_V0_2=PASS"
  echo "LAB_PATH=${LAB_PATH}"
  echo "LAB_UNIT=${UNIT}"
  echo "PRODUCAO_PUBLICA=INTACTA"
  echo "Para encerrar: $0 rollback"
  echo "========================================"
}

MODE="${1:-run}"
case "$MODE" in
  run) run_mode ;;
  status) status_mode ;;
  rollback) detect_paths; LAB_TOUCHED=1; rollback_lab 1 ;;
  selftest) selftest ;;
  *) echo "Uso: $0 [run|status|rollback|selftest]" >&2; exit 2 ;;
esac
