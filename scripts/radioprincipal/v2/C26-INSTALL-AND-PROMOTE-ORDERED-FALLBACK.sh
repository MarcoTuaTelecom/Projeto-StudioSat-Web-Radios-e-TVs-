#!/usr/bin/env bash
set -Eeuo pipefail

APP='/opt/studiosat/radio-v2-next/radioprincipal/ordered-authoritative-shadow.py'
RAW='https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/v2'
TEST_UNIT='/etc/systemd/system/studiosat-radioprincipal-v2-ordered-shadow-test.service'
PUB_UNIT='/etc/systemd/system/studiosat-radioprincipal-shadow-ns1.service'
PUBLIC_SERVICE='studiosat-radioprincipal-shadow-ns1.service'
TEST_SERVICE='studiosat-radioprincipal-v2-ordered-shadow-test.service'
STATE='/srv/studiosat/radio-principal/estado/ordered-shadow-status.json'
BK="/root/studiosat-backups/C26-$(date -u +%Y%m%dT%H%M%SZ)"
PROMOTE="${PROMOTE:-yes}"

mkdir -p "$BK" "$(dirname "$APP")" /srv/studiosat/radio-principal/estado
[ -f "$PUB_UNIT" ] && cp -a "$PUB_UNIT" "$BK/public-shadow.before.service"
systemctl cat "$PUBLIC_SERVICE" >"$BK/public-shadow.before.cat.txt" 2>&1 || true

echo '===== C26 ORDERED AUTHORITATIVE FALLBACK ====='
echo "BACKUP=$BK"
echo "PROMOTE=$PROMOTE"

curl -fsSL "$RAW/ordered-authoritative-shadow.py" -o "$APP"
chmod 0755 "$APP"
python3 -m py_compile "$APP"
echo 'PY_COMPILE=OK'

cat >"$TEST_UNIT" <<EOF
[Unit]
Description=Studio Sat Radio Principal V2 Ordered Shadow Test
After=network-online.target tps-mediamtx.service studiosat-radioboss-sync.service
Requires=tps-mediamtx.service

[Service]
Type=simple
User=root
Group=root
Environment=SS_STREAM=rtmp://127.0.0.1:1935/radioprincipal-v2-shadow-hotfix
Environment=SS_POLL=0.25
Environment=SS_STALE=10
Environment=SS_MAX_DRIFT=4
ExecStart=/usr/bin/python3 $APP
Restart=always
RestartSec=1
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ReadOnlyPaths=/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current /var/lib/studiosat/radio-v2/media-transfer /srv/studiosat/radio-principal/grade
ReadWritePaths=/srv/studiosat/radio-principal/estado

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now "$TEST_SERVICE" >/dev/null

ok=0
for i in $(seq 1 20); do
  sleep 1
  if timeout 5 ffprobe -v error -rw_timeout 3000000 -show_entries stream=codec_name -of csv=p=0 \
    rtmp://127.0.0.1:1935/radioprincipal-v2-shadow-hotfix 2>/dev/null | grep -q .; then
    ok=1
    echo "TEST_SHADOW_READY=YES AFTER=${i}s"
    break
  fi
done

if [ "$ok" -ne 1 ]; then
  echo 'TEST_SHADOW_READY=NO'
  cat "$STATE" 2>/dev/null || true
  journalctl -u "$TEST_SERVICE" --since '2 minutes ago' --no-pager | tail -100 || true
  exit 30
fi

echo '===== TEST STATUS ====='
cat "$STATE" 2>/dev/null || true

if [ "$PROMOTE" != yes ]; then
  echo 'PROMOTION=SKIPPED'
  echo 'RESULTADO=C26_TEST_READY'
  exit 0
fi

echo '===== RADIOBOSS HARBOR GATE ====='
if ! ss -tn state established 2>/dev/null | grep -q ':18005'; then
  echo 'PROMOTION=BLOCKED_HARBOR_NOT_ESTABLISHED'
  echo 'RESULTADO=C26_TEST_READY_NOT_PROMOTED'
  exit 31
fi
echo 'HARBOR_ESTABLISHED=YES'

echo '===== PROMOTE ONLY SHADOW FALLBACK ====='
cat >"$PUB_UNIT" <<EOF
[Unit]
Description=Studio Sat Radio Principal ordered authoritative NS1 fallback C26
After=network-online.target tps-mediamtx.service studiosat-radioboss-sync.service
Requires=tps-mediamtx.service

[Service]
Type=simple
User=root
Group=root
Environment=SS_STREAM=rtmp://127.0.0.1:1935/radioprincipal-ns1
Environment=SS_POLL=0.25
Environment=SS_STALE=10
Environment=SS_MAX_DRIFT=4
ExecStart=/usr/bin/python3 $APP
Restart=always
RestartSec=1
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ReadOnlyPaths=/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current /var/lib/studiosat/radio-v2/media-transfer /srv/studiosat/radio-principal/grade
ReadWritePaths=/srv/studiosat/radio-principal/estado

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl restart "$PUBLIC_SERVICE"

pubok=0
for i in $(seq 1 15); do
  sleep 1
  if timeout 5 ffprobe -v error -rw_timeout 3000000 -show_entries stream=codec_name -of csv=p=0 \
    rtmp://127.0.0.1:1935/radioprincipal-ns1 2>/dev/null | grep -q .; then
    pubok=1
    echo "ORDERED_FALLBACK_READY=YES AFTER=${i}s"
    break
  fi
done

if [ "$pubok" -ne 1 ]; then
  echo 'ORDERED_FALLBACK_READY=NO_ROLLBACK'
  if [ -f "$BK/public-shadow.before.service" ]; then
    cp -a "$BK/public-shadow.before.service" "$PUB_UNIT"
    systemctl daemon-reload
    systemctl restart "$PUBLIC_SERVICE" || true
  fi
  exit 40
fi

echo '===== SELECTOR / PRODUCTION NOT RESTARTED ====='
echo "SELECTOR=$(systemctl is-active studiosat-radioprincipal-selector.service 2>/dev/null || true)"
echo "MEDIAMTX=$(systemctl is-active tps-mediamtx.service 2>/dev/null || true)"
echo "NGINX=$(systemctl is-active nginx.service 2>/dev/null || true)"
echo "PUBLIC_SHADOW=$(systemctl is-active "$PUBLIC_SERVICE" 2>/dev/null || true)"

echo 'LEGACY_RANDOM_SHADOW=REPLACED'
echo 'RADIOBOSS_PRIORITY_UNCHANGED=YES'
echo 'RESULTADO=C26_ORDERED_FALLBACK_PROMOTED'
