#!/usr/bin/env bash
# C14 - replace legacy shadow with playback-synced shadow, gated + rollback.
set -euo pipefail
UNIT='studiosat-radioprincipal-shadow-ns1.service'
SRC='/opt/studiosat/radio-v2/radioprincipal-shadow/playback-synced-shadow.py'
REPO_URL='https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/production/playback-synced-shadow.py'
BK="/root/studiosat-backups/C14-$(date -u +%Y%m%dT%H%M%SZ)"
STATUS='/var/lib/studiosat/radio-v2/candidates/radioprincipal-authority-replica/status.json'
mkdir -p "$BK" /opt/studiosat/radio-v2/radioprincipal-shadow
systemctl cat "$UNIT" > "$BK/$UNIT.before.txt"
cp -a /etc/systemd/system/$UNIT "$BK/$UNIT" 2>/dev/null || true

echo '===== PRECHECK ====='
python3 - "$STATUS" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding='utf-8'))
r=d.get('readiness',{});f=d.get('freshness',{})
print('STATUS='+str(d.get('status')))
print('SOURCE_ONLINE='+str(f.get('source_online')))
print('PLAYBACK_FRESH='+str(f.get('playback_fresh')))
print('CURRENT_ITEM_READY='+str(r.get('current_item_ready')))
print('ITEMS='+str(d.get('items'))+' AVAILABLE='+str(d.get('available'))+' MISSING='+str(d.get('missing')))
if not r.get('current_item_ready'): raise SystemExit('ERRO=CURRENT_NOT_READY')
if d.get('missing') not in (0,None): raise SystemExit('ERRO=PLAYLIST_HAS_MISSING')
PY

curl -fsSL "$REPO_URL" -o "$SRC"
chmod 0755 "$SRC"
python3 -m py_compile "$SRC"
echo 'PY_COMPILE=OK'

cat > /etc/systemd/system/$UNIT <<EOF
[Unit]
Description=Studio Sat RadioPrincipal playback-synced NS1 shadow C14
After=network-online.target tps-mediamtx.service studiosat-radioprincipal-authority-candidate.service
Requires=tps-mediamtx.service
Wants=studiosat-radioprincipal-authority-candidate.service

[Service]
Type=simple
User=root
Group=root
Environment=SS_STREAM=rtmp://127.0.0.1:1935/radioprincipal-ns1
Environment=SS_POLL=0.5
Environment=SS_MAX_DRIFT=4
Environment=SS_STALE=10
ExecStart=/usr/bin/python3 $SRC
Restart=always
RestartSec=1
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ReadOnlyPaths=/var/lib/studiosat/radio-v2/candidates/radioprincipal-authority-replica /srv/tpsmedia/repository/channels/radioprincipal

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl restart "$UNIT"

ok=0
for i in $(seq 1 12); do
  sleep 1
  if timeout 6 ffprobe -v error -rw_timeout 4000000 -show_entries stream=codec_name -of default=nw=1:nk=1 rtmp://127.0.0.1:1935/radioprincipal-ns1 2>/dev/null | grep -q .; then ok=1;break;fi
done
if [ "$ok" -ne 1 ]; then
  echo 'C14_FAIL=SHADOW_NOT_PUBLISHING'
  cp -a "$BK/$UNIT" /etc/systemd/system/$UNIT 2>/dev/null || true
  systemctl daemon-reload
  systemctl restart "$UNIT" || true
  journalctl -u "$UNIT" -n 80 --no-pager
  exit 20
fi

echo 'SHADOW_SYNCED_RTMP=READY'
journalctl -u "$UNIT" --since '45 seconds ago' --no-pager | tail -50
echo 'RESULTADO=C14_SHADOW_PLAYBACK_SYNCED'
echo "BACKUP=$BK"
