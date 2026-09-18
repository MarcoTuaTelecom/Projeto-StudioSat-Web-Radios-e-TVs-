#!/usr/bin/env bash
set -Eeuo pipefail
OUT="${1:-/root/STUDIOSAT-SOFTWARE-COMPAT-$(date -u +%Y%m%dT%H%M%SZ).txt}"
exec > >(tee "$OUT") 2>&1
echo "UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "HOST=$(hostname -f 2>/dev/null || hostname)"
echo "READ_ONLY=YES"

echo "===== OS ====="
cat /etc/os-release 2>/dev/null || true
uname -a

echo "===== BINARIES ====="
for c in liquidsoap ffmpeg ffprobe nginx python3 node npm ssh sshd sqlite3 git curl; do
  echo "--- $c ---"
  command -v "$c" || true
  case "$c" in
    liquidsoap) "$c" --version 2>&1 || true ;;
    ffmpeg|ffprobe) "$c" -version 2>&1 | head -12 || true ;;
    nginx) "$c" -V 2>&1 || true ;;
    ssh|sshd) "$c" -V 2>&1 || true ;;
    *) "$c" --version 2>&1 | head -5 || true ;;
  esac
done

echo "===== MEDIAMTX ====="
if [ -x /opt/tpsmedia/mediamtx/current/mediamtx ]; then
  /opt/tpsmedia/mediamtx/current/mediamtx --version 2>&1 || true
  sha256sum /opt/tpsmedia/mediamtx/current/mediamtx || true
fi

echo "===== PACKAGES ====="
dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' 2>/dev/null |
grep -Ei 'liquidsoap|ffmpeg|nginx|openssh|python3|sqlite' || true

echo "===== PRODUCTION HASHES ====="
for f in \
 /etc/studiosat/radioprincipal-selector.liq \
 /etc/studiosat/radioprincipal-selector.env \
 /etc/tpsmedia/mediamtx/mediamtx.yml \
 /usr/local/sbin/tps-playout-radio
do
  [ -e "$f" ] || continue
  stat -Lc 'MODE=%a OWNER=%U:%G SIZE=%s MTIME=%y PATH=%n' "$f" || true
  sha256sum "$f" || true
done

echo "===== ACTIVE RADIO SERVICES ====="
systemctl list-units --all --no-pager |
grep -Ei 'radioprincipal|radioboss|radiopop|radiorock|radioclassicas|radiocountry|mediamtx' || true

echo "===== LIQUIDSOAP CHECK CURRENT ====="
if [ -f /etc/studiosat/radioprincipal-selector.liq ]; then
  set -a
  [ -f /etc/studiosat/radioprincipal-selector.env ] && . /etc/studiosat/radioprincipal-selector.env
  set +a
  timeout 45 liquidsoap --check /etc/studiosat/radioprincipal-selector.liq 2>&1 || true
fi

echo "RESULTADO=SOFTWARE_COMPAT_AUDIT_COMPLETE"
echo "REPORT=$OUT"
