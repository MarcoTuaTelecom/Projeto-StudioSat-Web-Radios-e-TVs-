#!/usr/bin/env bash
set -u

SHADOW='studiosat-radioprincipal-shadow-ns1.service'
SELECTOR='studiosat-radioprincipal-selector.service'
MEDIAMTX='tps-mediamtx.service'
UNIT='/etc/systemd/system/studiosat-radioprincipal-shadow-ns1.service'

[ "$(id -u)" -eq 0 ] || { echo 'ERRO=EXECUTE_COMO_ROOT'; exit 1; }

echo '=============================================================='
echo ' C16 - EMERGENCY RESTORE RADIOPRINCIPAL'
echo '=============================================================='

echo '===== 1. RESTAURAR SHADOW LEGADO CONHECIDO ====='
cat > "$UNIT" <<'UNITEOF'
[Unit]
Description=Studio Sat radioprincipal NS1 hot RadioBOSS mirror
After=network-online.target tps-mediamtx.service studiosat-radioprincipal-rb-monitor.service
Requires=tps-mediamtx.service
Wants=studiosat-radioprincipal-rb-monitor.service

[Service]
Type=simple
User=tpsmedia
Group=tpsmedia
ExecStart=/usr/bin/python3 /opt/studiosat/radio-v2/radioprincipal-mirror/mirror-playout.py
Restart=always
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ReadWritePaths=/var/lib/studiosat/radio-v2/stations/radioprincipal/state
ReadOnlyPaths=/var/lib/studiosat/radio-v2/stations/radioprincipal /var/lib/studiosat/radio-v2/media-transfer/incoming /srv/tpsmedia/repository/channels/radioprincipal

[Install]
WantedBy=multi-user.target
UNITEOF

systemctl daemon-reload
systemctl reset-failed "$SHADOW" "$SELECTOR" "$MEDIAMTX" 2>/dev/null || true

echo '===== 2. GARANTIR MEDIAMTX / PORTA 1935 ====='
if ! systemctl is-active --quiet "$MEDIAMTX"; then
  systemctl start "$MEDIAMTX"
fi
sleep 2
if ! ss -ltn | grep -q ':1935'; then
  echo 'MEDIAMTX_1935=NOT_LISTENING_RESTARTING'
  systemctl restart "$MEDIAMTX"
  sleep 3
fi
if ! ss -ltn | grep -q ':1935'; then
  echo 'ERRO=MEDIAMTX_1935_NAO_SUBIU'
  systemctl status "$MEDIAMTX" --no-pager -l || true
  exit 20
fi
echo 'MEDIAMTX_1935=READY'

echo '===== 3. SUBIR SHADOW NS1 ====='
systemctl restart "$SHADOW"
ready=0
for i in $(seq 1 20); do
  sleep 1
  if timeout 5 ffprobe -v error -rw_timeout 3000000 -show_entries stream=codec_name -of default=nw=1:nk=1       rtmp://127.0.0.1:1935/radioprincipal-ns1 2>/dev/null | grep -q .; then
    ready=1
    echo "SHADOW_RTMP=READY AFTER=${i}s"
    break
  fi
  echo "WAIT_SHADOW=${i}s"
done
if [ "$ready" -ne 1 ]; then
  echo 'ERRO=SHADOW_NAO_PUBLICOU'
  systemctl status "$SHADOW" --no-pager -l || true
  journalctl -u "$SHADOW" --since '3 minutes ago' --no-pager | tail -100 || true
  exit 21
fi

echo '===== 4. REARMAR SELECTOR / HARBOR ====='
systemctl restart "$SELECTOR"
public=0
for i in $(seq 1 25); do
  sleep 1
  if timeout 5 ffprobe -v error -rw_timeout 3000000 -show_entries stream=codec_name -of default=nw=1:nk=1       rtmp://127.0.0.1:1935/radioprincipal 2>/dev/null | grep -q .; then
    public=1
    echo "PUBLIC_RTMP=READY AFTER=${i}s"
    break
  fi
  echo "WAIT_PUBLIC=${i}s"
done
if [ "$public" -ne 1 ]; then
  echo 'ERRO=PUBLICO_NAO_PUBLICOU'
  systemctl status "$SELECTOR" --no-pager -l || true
  journalctl -u "$SELECTOR" --since '3 minutes ago' --no-pager | tail -120 || true
  exit 22
fi

echo '===== 5. HLS ====='
if timeout 8 curl -fsS http://127.0.0.1:8888/radioprincipal/index.m3u8 | head -20; then
  echo 'PUBLIC_HLS=READY'
else
  echo 'PUBLIC_HLS=WAITING_OR_NOT_READY'
fi

echo '===== 6. ESTADO FINAL ====='
echo "MEDIAMTX=$(systemctl is-active "$MEDIAMTX" 2>/dev/null || true)"
echo "SHADOW=$(systemctl is-active "$SHADOW" 2>/dev/null || true)"
echo "SELECTOR=$(systemctl is-active "$SELECTOR" 2>/dev/null || true)"
journalctl -u "$SELECTOR" --since '90 seconds ago' --no-pager | grep -Ei 'Switch to|radioprincipal_rb_harbor|radioprincipal_ns1_rtmp|emergency_blank|Feeding|New metadata' | tail -80 || true

echo 'RADIOPRINCIPAL_ON_AIR=YES'
echo 'RESULTADO=C16_EMERGENCY_RESTORE_OK'
