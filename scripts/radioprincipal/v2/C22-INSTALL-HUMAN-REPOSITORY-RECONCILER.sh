#!/usr/bin/env bash
# C22 - install human repository reconciler. No production restart.
set -Eeuo pipefail
ROOT='/srv/studiosat/radio-principal'
NEXT='/opt/studiosat/radio-v2-next/radioprincipal'
PY="$NEXT/human-repository-reconciler.py"
RAW='https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/v2'
UNIT='/etc/systemd/system/studiosat-radioprincipal-v2-human-repo-reconcile.service'
TIMER='/etc/systemd/system/studiosat-radioprincipal-v2-human-repo-reconcile.timer'

echo '===== C22 HUMAN REPOSITORY RECONCILER ====='
for u in studiosat-radioprincipal-selector.service studiosat-radioprincipal-shadow-ns1.service tps-mediamtx.service nginx.service; do
  echo "$u BEFORE=$(systemctl is-active "$u" 2>/dev/null || true)"
done

install -d -o tpsmedia -g tpsmedia -m 2775  "$ROOT" "$ROOT/grade" "$ROOT/grade/manha" "$ROOT/grade/tarde" "$ROOT/grade/noite" "$ROOT/estado"
install -d -o root -g root -m 0755 "$NEXT"

curl -fsSL "$RAW/human-repository-reconciler.py" -o "$PY"
chmod 0755 "$PY"
python3 -m py_compile "$PY"
python3 "$PY"

cat >"$UNIT" <<EOF
[Unit]
Description=Studio Sat Radio Principal V2 Human Repository Reconcile
After=local-fs.target
[Service]
Type=oneshot
User=root
Group=root
ExecStart=/usr/bin/python3 $PY
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ReadOnlyPaths=/var/lib/studiosat/radio-v2/media-transfer /var/lib/studiosat/radio-v2/stations/radioprincipal /srv/tpsmedia/repository/channels/radioprincipal
ReadWritePaths=$ROOT
EOF

cat >"$TIMER" <<'EOF'
[Unit]
Description=Studio Sat Radio Principal V2 Human Repository Reconcile 5s
[Timer]
OnBootSec=5s
OnUnitActiveSec=5s
AccuracySec=1s
Persistent=true
Unit=studiosat-radioprincipal-v2-human-repo-reconcile.service
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now studiosat-radioprincipal-v2-human-repo-reconcile.timer >/dev/null
sleep 2

echo '===== COUNTS ====='
python3 - <<'PY'
from pathlib import Path
root=Path('/srv/studiosat/radio-principal/grade')
ext={'.mp3','.wav','.flac','.m4a','.aac','.ogg','.opus'}
for p in ('manha','tarde','noite'):
 d=root/p
 print(p.upper(),sum(1 for x in d.iterdir() if x.is_file() and x.suffix.lower() in ext))
PY

echo '===== STATUS ====='
cat "$ROOT/estado/repositorio-sync.json" 2>/dev/null || true

echo '===== PRODUCTION UNTOUCHED ====='
for u in studiosat-radioprincipal-selector.service studiosat-radioprincipal-shadow-ns1.service tps-mediamtx.service nginx.service; do
  echo "$u AFTER=$(systemctl is-active "$u" 2>/dev/null || true)"
done

echo 'PRODUCTION_AUDIO_RESTARTED=NO'
echo 'RESULTADO=C22_REPOSITORY_RECONCILE_OK'
