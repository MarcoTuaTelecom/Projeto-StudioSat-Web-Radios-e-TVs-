#!/usr/bin/env bash
set -Eeuo pipefail
SELECTOR='studiosat-radioprincipal-selector.service'
MEDIAMTX='tps-mediamtx.service'
NGINX='nginx.service'
BACKUP="/root/studiosat-backups/RESET01-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BACKUP"
probe(){ timeout 6 ffprobe -v error -rw_timeout 3500000 -show_entries stream=codec_name -of csv=p=0 "$1" 2>/dev/null | grep -q .; }

echo '=============================================================='
echo ' RESET-01 - RADIO PRINCIPAL / RADIOBOSS MINIMAL RECOVERY'
echo '=============================================================='

systemctl cat "$SELECTOR" >"$BACKUP/selector.service.txt" 2>&1 || true
[ -f /etc/studiosat/radioprincipal-selector.liq ] && cp -a /etc/studiosat/radioprincipal-selector.liq "$BACKUP/" || true
echo "BACKUP=$BACKUP"

for u in "$MEDIAMTX" "$NGINX"; do
  a="$(systemctl is-active "$u" 2>/dev/null || true)"
  echo "$u=$a"
  if [ "$a" != active ]; then
    echo "STARTING=$u"
    systemctl start "$u"
    sleep 2
  fi
done

sa="$(systemctl is-active "$SELECTOR" 2>/dev/null || true)"
echo "SELECTOR=$sa"
if [ "$sa" != active ]; then
  systemctl reset-failed "$SELECTOR" 2>/dev/null || true
  systemctl start "$SELECTOR"
  sleep 4
fi

if ! ss -ltn 2>/dev/null | grep -q ':18005'; then
  echo 'ERRO=HARBOR_18005_NOT_LISTENING'
  systemctl status "$SELECTOR" --no-pager -l || true
  journalctl -u "$SELECTOR" --since '5 minutes ago' --no-pager | tail -160 || true
  exit 20
fi
echo 'HARBOR_LISTEN=YES'

est=0
for i in $(seq 1 60); do
  if ss -tn state established 2>/dev/null | grep -q ':18005'; then
    est=1
    echo "HARBOR_ESTABLISHED=YES AFTER=${i}s"
    break
  fi
  [ $((i%10)) -eq 0 ] && echo "WAITING_RADIOBOSS_TUNNEL=${i}s"
  sleep 1
done
if [ "$est" -ne 1 ]; then
  echo 'ERRO=RADIOBOSS_NOT_CONNECTED_TO_HARBOR'
  echo 'ACTION=RUN_RESET01_WINDOWS_TUNNEL_ON_RADIOBOSS_PC'
  exit 21
fi

rb=0
for i in $(seq 1 45); do
  recent="$(journalctl -u "$SELECTOR" --since '90 seconds ago' --no-pager 2>/dev/null | grep 'Switch to' | tail -1 || true)"
  echo "LATEST_SWITCH=$recent"
  if echo "$recent" | grep -q 'radioprincipal_rb_harbor'; then
    rb=1
    break
  fi
  sleep 1
done
if [ "$rb" -ne 1 ]; then
  echo 'RADIOBOSS_CONNECTED_BUT_NOT_SELECTED=YES'
  echo 'RESTARTING_SELECTOR_ONCE_TO_REEVALUATE_PRIORITY'
  systemctl restart "$SELECTOR"
  sleep 6
fi

public=0
for i in $(seq 1 20); do
  if probe 'rtmp://127.0.0.1:1935/radioprincipal'; then
    public=1
    echo "PUBLIC_RTMP=READY AFTER=${i}s"
    break
  fi
  sleep 1
done
if [ "$public" -ne 1 ]; then
  echo 'ERRO=PUBLIC_RTMP_NOT_READY'
  journalctl -u "$SELECTOR" --since '5 minutes ago' --no-pager | tail -220 || true
  exit 22
fi

journalctl -u "$SELECTOR" --since '5 minutes ago' --no-pager | grep -Ei 'Switch to|radioprincipal_rb_harbor|New metadata|Feeding stopped|Error while reading' | tail -120 || true
latest="$(journalctl -u "$SELECTOR" --since '5 minutes ago' --no-pager 2>/dev/null | grep 'Switch to' | tail -1 || true)"
if echo "$latest" | grep -q 'radioprincipal_rb_harbor'; then
  echo 'PUBLIC_SOURCE=RADIOBOSS'
else
  echo 'WARNING=PUBLIC_READY_BUT_LATEST_SOURCE_NOT_CONFIRMED_RADIOBOSS'
fi

if timeout 8 curl -fsS http://127.0.0.1:8888/radioprincipal/index.m3u8 | head -20; then
  echo 'PUBLIC_HLS=READY'
else
  echo 'PUBLIC_HLS=NOT_READY'
fi

echo 'RESULTADO=RESET01_RADIOBOSS_RECOVERY_COMPLETE'
