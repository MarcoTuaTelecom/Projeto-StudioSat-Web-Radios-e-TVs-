#!/usr/bin/env bash
# C24 - install isolated NS1 edge bridge for one hidden Windows agent.
# Does not restart selector/shadow/MediaMTX/Nginx/Harbor.
set -Eeuo pipefail
APP='/opt/studiosat/radio-v2-next/radioprincipal/edge-bridge.py'
UNIT='/etc/systemd/system/studiosat-radioprincipal-v2-edge-bridge.service'
DROP='/etc/ssh/sshd_config.d/90-studiosat-radioboss-tunnel.conf'
RAW='https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/v2'
BK="/root/studiosat-backups/C24-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BK" "$(dirname "$APP")"
[ -f "$DROP" ] && cp -a "$DROP" "$BK/sshd-dropin.before.conf"

echo '===== C24 NS1 EDGE BRIDGE ====='
for u in studiosat-radioprincipal-selector.service studiosat-radioprincipal-shadow-ns1.service tps-mediamtx.service nginx.service; do
  echo "$u BEFORE=$(systemctl is-active "$u" 2>/dev/null || true)"
done

curl -fsSL "$RAW/edge-bridge.py" -o "$APP"
chmod 0755 "$APP"
python3 -m py_compile "$APP"

cat >"$UNIT" <<EOF
[Unit]
Description=Studio Sat Radio Principal V2 Edge Bridge
After=network.target studiosat-media-transfer.service studiosat-radioboss-sync.service
Requires=studiosat-media-transfer.service studiosat-radioboss-sync.service
[Service]
Type=simple
User=root
Group=root
ExecStart=/usr/bin/python3 $APP
Restart=always
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ReadOnlyPaths=/var/lib/studiosat/radio-v2/radioboss-sync /var/lib/studiosat/radio-v2/media-transfer /etc/studiosat/radio-v2/radioboss-sync-tokens.json
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now studiosat-radioprincipal-v2-edge-bridge.service >/dev/null
sleep 2
curl -fsS http://127.0.0.1:8796/health | python3 -m json.tool

echo '===== EXTEND RESTRICTED SSH PERMITOPEN ====='
if grep -q '^Match User studiosat-rb-tunnel' "$DROP" 2>/dev/null; then
  python3 - "$DROP" <<'PY'
from pathlib import Path
import sys,re
p=Path(sys.argv[1]);s=p.read_text()
lines=s.splitlines();out=[];done=False
for line in lines:
    if re.match(r'^s*PermitOpens+',line):
        out.append('    PermitOpen 127.0.0.1:18005 127.0.0.1:8796')
        done=True
    else: out.append(line)
if not done: out.append('    PermitOpen 127.0.0.1:18005 127.0.0.1:8796')
p.write_text('\n'.join(out)+'\n')
PY
else
  echo 'ERRO=SSHD_DROPIN_NAO_ENCONTRADO'; exit 20
fi
/usr/sbin/sshd -t
systemctl reload ssh.service 2>/dev/null || systemctl reload sshd.service

echo '===== PLAN ====='
curl -fsS http://127.0.0.1:8796/v1/plan/radioprincipal |
python3 - <<'PY'
import json,sys
d=json.load(sys.stdin);items=d.get('items',[])
print('PLAN_COUNT='+str(len(items)))
print('PHYSICAL='+str(sum(not x.get('virtual') for x in items)))
print('PRESENT='+str(sum((not x.get('virtual')) and x.get('present') for x in items)))
print('MISSING='+str(sum((not x.get('virtual')) and not x.get('present') for x in items)))
for x in [z for z in items if (not z.get('virtual')) and not z.get('present')][:20]:
 print('MISSING_REF='+str(x.get('source_path')))
PY

echo '===== PRODUCTION UNTOUCHED ====='
for u in studiosat-radioprincipal-selector.service studiosat-radioprincipal-shadow-ns1.service tps-mediamtx.service nginx.service; do
  echo "$u AFTER=$(systemctl is-active "$u" 2>/dev/null || true)"
done
echo 'RESULTADO=C24_EDGE_BRIDGE_READY'
