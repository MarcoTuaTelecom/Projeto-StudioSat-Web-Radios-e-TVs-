#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

RADIOS=(radiopop radiorock radioclassicas radiocountry)
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/root/studiosat-backups/RESET02-${TS}"
REPORT="$BK/REPORT.txt"
mkdir -p "$BK"
exec > >(tee "$REPORT") 2>&1

unit_of(){ echo "tps-$1-playout.service"; }
playlist_of(){ echo "/srv/tpsmedia/repository/channels/$1/playlists/playlist.txt"; }

validate_playlist(){
  python3 - "$1" <<'PY'
import os,sys
p=sys.argv[1]
lines=open(p,encoding='utf-8',errors='replace').read().splitlines()
refs=[]
for line in lines:
    line=line.strip()
    if not line.startswith('file '): continue
    x=line[5:].strip()
    if len(x)>=2 and x[0] in "\"'" and x[-1]==x[0]:
        x=x[1:-1]
    x=x.replace("'\\''","'")
    refs.append(x)
print("ITEMS="+str(len(refs)))
missing=[x for x in refs if not os.path.isfile(x)]
print("MISSING="+str(len(missing)))
for x in missing[:10]: print("MISSING_REF="+x)
if len(refs)<2 or missing:
    raise SystemExit(20)
PY
}

find_candidate(){
  local ch="$1"
  local current
  current="$(playlist_of "$ch")"
  local current_sha=''
  [ -f "$current" ] && current_sha="$(sha256sum "$current" | awk '{print $1}')"
  python3 - "$ch" "$current" "$current_sha" <<'PY'
import os,sys,hashlib
from datetime import datetime,timezone
ch,current,current_sha=sys.argv[1:]
roots=[
  '/root/studiosat-backups',
  '/var/backups/studiosat',
  f'/srv/tpsmedia/repository/channels/{ch}/playlists',
  f'/srv/tpsmedia/repository/channels/{ch}',
]
start=datetime(2026,9,16,tzinfo=timezone.utc).timestamp()
end=datetime(2026,9,18,tzinfo=timezone.utc).timestamp()

def sha(p):
    h=hashlib.sha256()
    with open(p,'rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    return h.hexdigest()

def valid(p):
    try: lines=open(p,encoding='utf-8',errors='replace').read().splitlines()
    except Exception: return False
    refs=[]
    for line in lines:
        line=line.strip()
        if not line.startswith('file '): continue
        x=line[5:].strip()
        if len(x)>=2 and x[0] in "\"'" and x[-1]==x[0]: x=x[1:-1]
        x=x.replace("'\\''","'")
        refs.append(x)
    return len(refs)>=2 and all(os.path.isfile(x) for x in refs)

cand=[]
for root in roots:
    if not os.path.isdir(root): continue
    for dp,dn,fn in os.walk(root):
        if '/mirror-store' in dp or '/objects/' in dp or '/incoming/' in dp:
            dn[:] = []
            continue
        for n in fn:
            low=n.lower()
            if 'playlist' not in low: continue
            if not (low.endswith('.txt') or '.txt.' in low or low.endswith('.m3u') or '.m3u.' in low or 'before' in low or 'backup' in low or 'bak' in low):
                continue
            p=os.path.join(dp,n)
            try: st=os.stat(p)
            except OSError: continue
            if not (start <= st.st_mtime < end): continue
            if os.path.realpath(p)==os.path.realpath(current): continue
            try: s=sha(p)
            except Exception: continue
            if current_sha and s==current_sha: continue
            if valid(p): cand.append((st.st_mtime,p,s))
cand.sort(reverse=True)
for mt,p,s in cand[:20]:
    print(f"CANDIDATE|{int(mt)}|{s}|{p}")
if cand:
    print("SELECTED="+cand[0][1])
PY
}

echo "=============================================================="
echo " RESET02 - RESTORE LATEST VALID 17/16 RADIO PLAYLISTS"
echo "=============================================================="
echo "BACKUP=$BK"
echo "RADIOPRINCIPAL_POLICY=KEEP_RADIOBOSS"

echo "===== CURRENT SNAPSHOT ====="
for ch in "${RADIOS[@]}"; do
  pl="$(playlist_of "$ch")"
  u="$(unit_of "$ch")"
  mkdir -p "$BK/$ch"
  [ -f "$pl" ] && cp -a "$pl" "$BK/$ch/playlist.current.before.txt"
  systemctl cat "$u" >"$BK/$ch/unit.before.txt" 2>&1 || true
  echo "--- $ch ---"
  echo "SERVICE=$(systemctl is-active "$u" 2>/dev/null || true)"
  if [ -f "$pl" ]; then
    echo "CURRENT_MTIME=$(stat -c '%y' "$pl")"
    echo "CURRENT_SHA=$(sha256sum "$pl" | awk '{print $1}')"
    echo "CURRENT_ITEMS=$(grep -c '^file ' "$pl" || true)"
  else
    echo "CURRENT_PLAYLIST=MISSING"
  fi
done

echo "===== DISCOVER 17/16 RESTORE POINTS ====="
declare -A SELECTED
for ch in "${RADIOS[@]}"; do
  echo "--- $ch ---"
  out="$(find_candidate "$ch" || true)"
  echo "$out"
  sel="$(printf '%s\n' "$out" | sed -n 's/^SELECTED=//p' | head -1)"
  SELECTED["$ch"]="$sel"
done

found=0
for ch in "${RADIOS[@]}"; do
  [ -n "${SELECTED[$ch]:-}" ] && found=$((found+1))
done
echo "RESTORE_POINTS_FOUND=$found/4"

if [ "$found" -eq 0 ]; then
  echo "RESULTADO=RESET02_NO_VALID_16_17_RESTORE_POINT_FOUND"
  echo "NO_CHANGES=YES"
  exit 30
fi

echo "===== APPLY ONE STATION AT A TIME ====="
for ch in "${RADIOS[@]}"; do
  cand="${SELECTED[$ch]:-}"
  if [ -z "$cand" ]; then
    echo "$ch=SKIP_NO_RESTORE_POINT"
    continue
  fi

  pl="$(playlist_of "$ch")"
  u="$(unit_of "$ch")"
  echo "--- RESTORE $ch ---"
  echo "SOURCE=$cand"
  validate_playlist "$cand"

  cp -a "$cand" "$pl"
  if [ -f "$BK/$ch/playlist.current.before.txt" ]; then
    chown --reference="$BK/$ch/playlist.current.before.txt" "$pl" 2>/dev/null || true
    chmod --reference="$BK/$ch/playlist.current.before.txt" "$pl" 2>/dev/null || true
  fi

  systemctl restart "$u"

  active=0
  for i in $(seq 1 20); do
    sleep 1
    if systemctl is-active --quiet "$u"; then active=1; break; fi
  done
  if [ "$active" -ne 1 ]; then
    echo "$ch=SERVICE_FAILED_ROLLBACK"
    cp -a "$BK/$ch/playlist.current.before.txt" "$pl"
    systemctl restart "$u" || true
    continue
  fi

  ready=0
  for i in $(seq 1 30); do
    sleep 1
    if curl -fsS "http://127.0.0.1:9997/v3/paths/get/$ch" 2>/dev/null | grep -q '"ready":true'; then
      ready=1; break
    fi
  done
  if [ "$ready" -ne 1 ]; then
    echo "$ch=MEDIAMTX_NOT_READY_ROLLBACK"
    cp -a "$BK/$ch/playlist.current.before.txt" "$pl"
    systemctl restart "$u" || true
    continue
  fi

  hls=0
  for i in $(seq 1 20); do
    if timeout 5 curl -fsS "http://127.0.0.1:8888/$ch/index.m3u8" 2>/dev/null | grep -q '^#EXTM3U'; then
      hls=1; break
    fi
    sleep 1
  done
  if [ "$hls" -ne 1 ]; then
    echo "$ch=HLS_NOT_READY_ROLLBACK"
    cp -a "$BK/$ch/playlist.current.before.txt" "$pl"
    systemctl restart "$u" || true
    continue
  fi

  echo "$ch=RESTORED_OK"
done

echo "===== RADIO PRINCIPAL UNTOUCHED ====="
echo "SELECTOR=$(systemctl is-active studiosat-radioprincipal-selector.service 2>/dev/null || true)"
grep -nE 'program = fallback|\[rb' /etc/studiosat/radioprincipal-selector.liq 2>/dev/null || true
echo "RADIOPRINCIPAL_STATIC_PLAYLIST_RESTORE=NO"

echo "===== FINAL MATRIX ====="
for ch in "${RADIOS[@]}"; do
  echo -n "$ch "
  echo -n "service=$(systemctl is-active "$(unit_of "$ch")" 2>/dev/null || true) "
  echo -n "items=$(grep -c '^file ' "$(playlist_of "$ch")" 2>/dev/null || true) "
  curl -fsS "http://127.0.0.1:9997/v3/paths/get/$ch" 2>/dev/null |
    python3 -c 'import json,sys; d=json.load(sys.stdin); print("ready="+str(d.get("ready")).lower())' 2>/dev/null || echo "ready=unknown"
done

echo "RESULTADO=RESET02_RESTORE_ATTEMPT_COMPLETE"
echo "REPORT=$REPORT"
