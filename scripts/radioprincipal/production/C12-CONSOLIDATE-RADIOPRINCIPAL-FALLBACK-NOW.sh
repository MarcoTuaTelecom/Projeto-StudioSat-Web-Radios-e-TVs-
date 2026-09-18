#!/usr/bin/env bash
# Nome: C12-CONSOLIDATE-RADIOPRINCIPAL-FALLBACK-NOW.sh
# Versão: 1.0 / 2026-09-17
# Owner: Rádio
# Change: RADIOPRINCIPAL-NS1-C12
# Objetivo: eliminar concorrência de playout legado/stage, forçar o fallback NS1 a usar
# a playlist atual do RadioBOSS e atualizar o media-map a cada 5s.
# Não apaga mídia. Não reinicia MediaMTX nem selector.
set -euo pipefail

BASE='/var/lib/studiosat/radio-v2/stations/radioprincipal'
MAP="$BASE/current/media-map.json"
CAND='/var/lib/studiosat/radio-v2/candidates/radioprincipal-authority-replica/status.json'
SYNC='/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current'
STORE='/srv/tpsmedia/repository/channels/radioprincipal/mirror-store'
TIMER='/etc/systemd/system/studiosat-radioprincipal-mirror-controller.timer'
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/root/studiosat-backups/C12-$STAMP"

[ "$(id -u)" -eq 0 ] || { echo 'ERRO=EXECUTE_COMO_ROOT'; exit 1; }

mkdir -p "$BK"

echo '=============================================================='
echo ' C12 - CONSOLIDAR FALLBACK RADIOPRINCIPAL'
echo '=============================================================='
echo "UTC=$STAMP"
echo "BACKUP=$BK"

echo
echo '===== 1. BACKUP CONFIG ATUAL ====='
for u in   studiosat-radioprincipal-mirror-controller.timer   studiosat-radioprincipal-shadow-ns1.service   studiosat-radioprincipal-selector.service   studiosat-radioprincipal-v8-stage.service   studiosat-radioprincipal-v8-production.service   studiosat-radioprincipal-v8-live-ingress.service
do
  systemctl cat "$u" > "$BK/$u.txt" 2>&1 || true
done
[ -L "$BASE/current" ] && readlink -f "$BASE/current" > "$BK/current-target.txt" || true
[ -f "$MAP" ] && cp -a "$MAP" "$BK/media-map.before.json"

echo 'BACKUP=OK'

echo
echo '===== 2. DESABILITAR PLAYOUTS ANTIGOS NAO-PRODUTIVOS ====='
for u in   studiosat-radioprincipal-v8-stage.service   studiosat-radioprincipal-v8-production.service   studiosat-radioprincipal-v8-live-ingress.service
do
  systemctl disable --now "$u" >/dev/null 2>&1 || true
  echo "$u=$(systemctl is-active "$u" 2>/dev/null || true)/$(systemctl is-enabled "$u" 2>/dev/null || true)"
done

echo
echo '===== 3. MIRROR CONTROLLER PASSA PARA 5s ====='
cat > "$TIMER" <<'EOF'
[Unit]
Description=Studio Sat radioprincipal canonical RadioBOSS mirror refresh 5s

[Timer]
OnBootSec=5s
OnUnitActiveSec=5s
AccuracySec=1s
Persistent=true
Unit=studiosat-radioprincipal-mirror-controller.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now studiosat-radioprincipal-mirror-controller.timer >/dev/null
systemctl restart studiosat-radioprincipal-mirror-controller.timer

echo
echo '===== 4. FORCAR RECONSTRUCAO COM SNAPSHOT ATUAL ====='
systemctl start studiosat-radioprincipal-mirror-controller.service
sleep 2

journalctl -u studiosat-radioprincipal-mirror-controller.service   --since '1 minute ago' --no-pager | tail -40

echo
echo '===== 5. VALIDAR LISTA CANDIDATE X FALLBACK ====='
python3 - "$CAND" "$MAP" "$STORE" <<'PY'
import json,sys,os
cand,mapf,store=sys.argv[1:]
if not os.path.isfile(cand):
    raise SystemExit("ERRO=CANDIDATE_STATUS_AUSENTE")
if not os.path.isfile(mapf):
    raise SystemExit("ERRO=MEDIA_MAP_AUSENTE")

c=json.load(open(cand,encoding='utf-8'))
m=json.load(open(mapf,encoding='utf-8'))
tracks=m.get('tracks') or []

print("CANDIDATE_STATUS="+str(c.get('status')))
print("CANDIDATE_ITEMS="+str(c.get('items')))
print("CANDIDATE_AVAILABLE="+str(c.get('available')))
print("CANDIDATE_MISSING="+str(c.get('missing')))
print("FALLBACK_GENERATION="+str(m.get('generation')))
print("FALLBACK_TRACKS="+str(len(tracks)))
print("FALLBACK_AVAILABLE="+str(m.get('available_count')))
print("FALLBACK_MISSING="+str(m.get('missing_count')))

bad=[]
for i,t in enumerate(tracks):
    p=str(t.get('path') or '')
    if p and not p.startswith(store.rstrip('/')+'/'):
        bad.append((i,p))
print("NON_CANONICAL_PATHS="+str(len(bad)))
for i,p in bad[:10]:
    print("NON_CANONICAL[%d]=%s"%(i,p))

ci=c.get('items')
fm=len(tracks)
cm=c.get('missing')
mm=m.get('missing_count')
ok=(isinstance(ci,int) and ci==fm and (cm in (0,None)) and (mm in (0,None)) and not bad)
print("LIST_COUNTS_MATCH="+str(ci==fm))
print("CANONICAL_STORE_ONLY="+str(not bad))
print("FALLBACK_MAP_READY="+str(ok))
if not ok:
    raise SystemExit(20)
PY

echo
echo '===== 6. RECARREGAR SOMENTE O SHADOW COM MAPA ATUAL ====='
systemctl restart studiosat-radioprincipal-shadow-ns1.service
sleep 3
systemctl is-active --quiet studiosat-radioprincipal-shadow-ns1.service
echo 'SHADOW_NS1=ACTIVE'

echo
echo '===== 7. ESTADO DOS UNICOS COMPONENTES DE AUDIO ====='
for u in   studiosat-radioprincipal-shadow-ns1.service   studiosat-radioprincipal-selector.service   studiosat-radioprincipal-v8-stage.service   studiosat-radioprincipal-v8-production.service   studiosat-radioprincipal-v8-live-ingress.service
do
  echo "$u ACTIVE=$(systemctl is-active "$u" 2>/dev/null || true) ENABLED=$(systemctl is-enabled "$u" 2>/dev/null || true)"
done

echo
echo '===== 8. TIMER 5s ====='
systemctl list-timers studiosat-radioprincipal-mirror-controller.timer --no-pager || true

echo
echo '===== 9. SELECTOR ULTIMOS 60s ====='
journalctl -u studiosat-radioprincipal-selector.service   --since '60 seconds ago' --no-pager |
  grep -Ei 'Switch to|radioprincipal_rb_harbor|radioprincipal_ns1_rtmp|New metadata' |
  tail -60 || true

echo
echo 'RESULTADO=C12_FALLBACK_CONSOLIDADO'
echo "ROLLBACK_BACKUP=$BK"
