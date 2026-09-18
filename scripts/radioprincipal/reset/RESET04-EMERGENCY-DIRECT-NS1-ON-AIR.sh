#!/usr/bin/env bash
set -Eeuo pipefail

MEDIAMTX='tps-mediamtx.service'
NGINX='nginx.service'
SHADOW='studiosat-radioprincipal-shadow-ns1.service'
SELECTOR='studiosat-radioprincipal-selector.service'
BRIDGE='studiosat-radioprincipal-emergency-direct.service'
UNIT="/etc/systemd/system/$BRIDGE"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/root/studiosat-backups/RESET04-${TS}"
mkdir -p "$BK"

probe(){
  timeout 7 ffprobe -v error -rw_timeout 4000000 \
    -show_entries stream=codec_name -of csv=p=0 "$1" 2>/dev/null | grep -q .
}

echo "=============================================================="
echo " RESET04 - EMERGENCY DIRECT ON-AIR FROM NS1 SHADOW"
echo "=============================================================="
echo "BACKUP=$BK"

echo "===== 1. CORE ====="
for u in "$MEDIAMTX" "$NGINX" "$SHADOW"; do
  st="$(systemctl is-active "$u" 2>/dev/null || true)"
  echo "$u=$st"
  if [ "$st" != active ]; then
    systemctl start "$u"
    sleep 2
  fi
done

echo "===== 2. REQUIRE READY SHADOW ====="
if ! probe 'rtmp://127.0.0.1:1935/radioprincipal-ns1'; then
  echo "SHADOW_NOT_READY_RESTARTING"
  systemctl restart "$SHADOW"
  for i in $(seq 1 20); do
    sleep 1
    if probe 'rtmp://127.0.0.1:1935/radioprincipal-ns1'; then
      echo "SHADOW_RTMP=READY AFTER=${i}s"
      break
    fi
  done
fi

if ! probe 'rtmp://127.0.0.1:1935/radioprincipal-ns1'; then
  echo "FATAL=SHADOW_RTMP_NOT_READY"
  echo "NO_PUBLIC_CHANGE=YES"
  exit 20
fi
echo "SHADOW_RTMP=READY"

echo "===== 3. SAVE CURRENT SELECTOR STATE ====="
systemctl cat "$SELECTOR" >"$BK/selector.unit.txt" 2>&1 || true
systemctl is-enabled "$SELECTOR" >"$BK/selector.enabled.txt" 2>&1 || true
systemctl is-active "$SELECTOR" >"$BK/selector.active.txt" 2>&1 || true
[ -f /etc/studiosat/radioprincipal-selector.liq ] &&
  cp -a /etc/studiosat/radioprincipal-selector.liq "$BK/" || true

echo "===== 4. INSTALL EMERGENCY DIRECT BRIDGE ====="
cat >"$UNIT" <<'EOF'
[Unit]
Description=Studio Sat Radio Principal emergency direct NS1 shadow to public
After=network-online.target tps-mediamtx.service studiosat-radioprincipal-shadow-ns1.service
Requires=tps-mediamtx.service studiosat-radioprincipal-shadow-ns1.service
Conflicts=studiosat-radioprincipal-selector.service

[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/bin/ffmpeg -hide_banner -loglevel warning -nostdin -rw_timeout 5000000 -i rtmp://127.0.0.1:1935/radioprincipal-ns1 -map 0:a:0 -vn -af aresample=48000:async=1:first_pts=0 -c:a aac -profile:a aac_low -b:a 128k -ar 48000 -ac 2 -flvflags no_duration_filesize -f flv rtmp://127.0.0.1:1935/radioprincipal
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

echo "===== 5. CUTOVER ====="
systemctl disable --now "$SELECTOR" 2>/dev/null || systemctl stop "$SELECTOR" || true
systemctl enable --now "$BRIDGE"

echo "===== 6. PUBLIC RTMP ====="
pub=0
for i in $(seq 1 30); do
  sleep 1
  if probe 'rtmp://127.0.0.1:1935/radioprincipal'; then
    pub=1
    echo "PUBLIC_RTMP=READY AFTER=${i}s"
    break
  fi
done

if [ "$pub" -ne 1 ]; then
  echo "PUBLIC_RTMP=NOT_READY_ROLLBACK"
  systemctl disable --now "$BRIDGE" 2>/dev/null || true
  systemctl enable "$SELECTOR" 2>/dev/null || true
  systemctl restart "$SELECTOR" || true
  echo "ROLLBACK=APPLIED"
  exit 30
fi

echo "===== 7. HLS ====="
hls=0
for i in $(seq 1 20); do
  if timeout 6 curl -fsS http://127.0.0.1:8888/radioprincipal/index.m3u8 2>/dev/null | grep -q '^#EXTM3U'; then
    hls=1
    echo "PUBLIC_HLS=READY AFTER=${i}s"
    break
  fi
  sleep 1
done

if [ "$hls" -ne 1 ]; then
  echo "PUBLIC_HLS=NOT_READY_ROLLBACK"
  systemctl disable --now "$BRIDGE" 2>/dev/null || true
  systemctl enable "$SELECTOR" 2>/dev/null || true
  systemctl restart "$SELECTOR" || true
  echo "ROLLBACK=APPLIED"
  exit 31
fi

echo "===== 8. FINAL ====="
echo "BRIDGE=$(systemctl is-active "$BRIDGE" 2>/dev/null || true)"
echo "SELECTOR=$(systemctl is-active "$SELECTOR" 2>/dev/null || true)"
echo "SHADOW=$(systemctl is-active "$SHADOW" 2>/dev/null || true)"
echo "MEDIAMTX=$(systemctl is-active "$MEDIAMTX" 2>/dev/null || true)"
echo "NGINX=$(systemctl is-active "$NGINX" 2>/dev/null || true)"
echo "PUBLIC_SOURCE=NS1_SHADOW_DIRECT"
echo "RADIOPRINCIPAL_ON_AIR=YES"
echo "RESULTADO=RESET04_EMERGENCY_ON_AIR"
echo "ROLLBACK_DIR=$BK"
