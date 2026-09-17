#!/usr/bin/env bash
set -euo pipefail

SHADOW='studiosat-radioprincipal-shadow-ns1.service'
SELECTOR='studiosat-radioprincipal-selector.service'
MAP='/var/lib/studiosat/radio-v2/stations/radioprincipal/current/media-map.json'

probe_rtmp() {
  local url="$1"
  timeout 8 ffprobe -v error -rw_timeout 5000000 -show_entries stream=codec_name -of default=nw=1:nk=1 "$url" 2>/dev/null | grep -q .
}

[ "$(id -u)" -eq 0 ] || { echo 'ERRO=EXECUTE_COMO_ROOT'; exit 1; }
command -v ffprobe >/dev/null || { echo 'ERRO=FFPROBE_AUSENTE'; exit 2; }

printf '%s\n' '=============================================================='
printf '%s\n' ' C13 - RESTAURAR RADIOPRINCIPAL NO AR'
printf '%s\n' '=============================================================='

echo '===== 1. VALIDAR MAPA ATUAL ====='
python3 - "$MAP" <<'PY'
import json,sys,os
p=sys.argv[1]
if not os.path.isfile(p): raise SystemExit('ERRO=MEDIA_MAP_AUSENTE')
d=json.load(open(p,encoding='utf-8'))
print('GENERATION='+str(d.get('generation')))
print('TRACKS='+str(len(d.get('tracks') or [])))
print('AVAILABLE='+str(d.get('available_count')))
print('MISSING='+str(d.get('missing_count')))
if not (d.get('tracks') and d.get('missing_count') in (0,None)):
    raise SystemExit('ERRO=MEDIA_MAP_NAO_PRONTO')
PY

echo
echo '===== 2. GARANTIR SHADOW NS1 ====='
systemctl reset-failed "$SHADOW" || true
systemctl restart "$SHADOW"

ready=0
for i in $(seq 1 12); do
  sleep 1
  if probe_rtmp 'rtmp://127.0.0.1:1935/radioprincipal-ns1'; then
    ready=1
    echo "NS1_RTMP_READY=YES AFTER=${i}s"
    break
  fi
  echo "WAIT_NS1_RTMP=${i}s"
done

if [ "$ready" -ne 1 ]; then
  echo 'NS1_RTMP_READY=NO'
  echo '===== SHADOW STATUS ====='
  systemctl status "$SHADOW" --no-pager -l || true
  echo '===== SHADOW JOURNAL ====='
  journalctl -u "$SHADOW" --since '3 minutes ago' --no-pager | tail -100 || true
  exit 20
fi

echo
echo '===== 3. REARMAR SELECTOR ====='
systemctl reset-failed "$SELECTOR" || true
systemctl restart "$SELECTOR"

pub=0
for i in $(seq 1 12); do
  sleep 1
  if probe_rtmp 'rtmp://127.0.0.1:1935/radioprincipal'; then
    pub=1
    echo "PUBLIC_RTMP_READY=YES AFTER=${i}s"
    break
  fi
  echo "WAIT_PUBLIC_RTMP=${i}s"
done

if [ "$pub" -ne 1 ]; then
  echo 'PUBLIC_RTMP_READY=NO'
  echo '===== SELECTOR STATUS ====='
  systemctl status "$SELECTOR" --no-pager -l || true
  echo '===== SELECTOR JOURNAL ====='
  journalctl -u "$SELECTOR" --since '3 minutes ago' --no-pager | tail -120 || true
  exit 21
fi

echo
echo '===== 4. HLS ====='
if timeout 8 curl -fsS 'http://127.0.0.1:8888/radioprincipal/index.m3u8' | head -20; then
  echo 'PUBLIC_HLS=READY'
else
  echo 'PUBLIC_HLS=NOT_READY'
fi

echo
echo '===== 5. FONTES / SELECTOR ====='
ss -tnp state established 2>/dev/null | grep -E ':18005|:1935' | tail -40 || true
journalctl -u "$SELECTOR" --since '2 minutes ago' --no-pager | grep -Ei 'Switch to|radioprincipal_rb_harbor|radioprincipal_ns1_rtmp|Feeding|Error' | tail -80 || true

echo
echo '===== 6. ESTADO FINAL ====='
systemctl is-active "$SHADOW" || true
systemctl is-active "$SELECTOR" || true

echo 'RADIOPRINCIPAL_ON_AIR=YES'
echo 'RESULTADO=C13_RESTORE_OK'
