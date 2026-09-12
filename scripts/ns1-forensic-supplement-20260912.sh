#!/usr/bin/env bash
# Nome: ns1-forensic-supplement-20260912.sh
# Versão: 1.0
# Owner: Core
# Safety class: read-only
# Change ID: OBS-NS1-FORENSIC-20260912
# Propósito: fechar lacunas do raio-X profundo sem alterar produção.
# Pré-condições: root no NS1; Git sincronizado.
# Rollback/remoção: não se aplica; escreve somente em /tmp.
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
umask 077

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'FATAL=RUN_AS_ROOT' >&2; exit 77; }
REPO='/root/Projeto-StudioSat-Web-Radios-e-TVs-'
SELF='scripts/ns1-forensic-supplement-20260912.sh'
cd "$REPO"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main 2>/dev/null || true)" ]] || { echo 'FATAL=GIT_NOT_SYNCED' >&2; exit 2; }
[[ "$(sha256sum "$SELF"|awk '{print $1}')" == "$(git show "HEAD:$SELF"|sha256sum|awk '{print $1}')" ]] || { echo 'FATAL=SCRIPT_DRIFT' >&2; exit 3; }
bash -n "$SELF"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/ns1-forensic-supplement-${TS}"
SHARE="$OUT/shareable"
PRIVATE="$OUT/private"
ARCHIVE="/tmp/ns1-forensic-supplement-${TS}.shareable.tar.gz"
mkdir -p "$SHARE"/{incident,apt,portal,identities,systemd,summary} "$PRIVATE"
chmod 0700 "$OUT" "$PRIVATE"
exec > >(tee "$SHARE/REPORT.txt") 2>&1

redact(){
  sed -E \
    -e 's#(rtmp|rtsp|srt|https?)://([^/@:[:space:]]+):([^/@[:space:]]+)@#\1://REDACTED:REDACTED@#gI' \
    -e 's#((pass(word)?|token|secret|api[_-]?key|stream[_-]?key|authorization|bearer)[[:space:]]*[:=][[:space:]]*)[^[:space:]\"]+#\1REDACTED#gI' \
    -e 's#(Authorization:[[:space:]]*(Basic|Bearer)[[:space:]]+)[A-Za-z0-9._~+/=-]+#\1REDACTED#gI' \
    -e 's#([?&](token|key|secret|password|pass)=)[^&[:space:]]+#\1REDACTED#gI'
}
copy_text_redacted(){ local src="$1" dst="$2"; [[ -r "$src" ]] && redact < "$src" > "$dst" || printf 'NOT_AVAILABLE\n' > "$dst"; }
run(){ local dst="$1"; shift; { "$@" 2>&1 || true; } | redact > "$dst"; }
runsh(){ local dst="$1"; shift; { bash -lc "$*" 2>&1 || true; } | redact > "$dst"; }

SINCE='2026-09-12 06:45:00 UTC'
UNTIL='2026-09-12 07:10:00 UTC'
RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
ALL=(radioprincipal radiopop radiorock radioclassicas radiocountry tvkids tvteens tvviva tvmaisjovem)

echo "NS1 FORENSIC SUPPLEMENT v1.0 UTC=$TS"
echo "window=$SINCE -> $UNTIL"

echo '=== A. mutation interlock / current PIDs ==='
ps -eo pid,ppid,etimes,user,args --sort=pid | grep -E 'apply-(radio|tv)|restore-five-radios|tvkids-rebuild-production|systemctl +(restart|reload|start|stop)|nginx +-s|apt(|-get) +(install|upgrade)|dpkg +-i' | grep -v -E 'grep -E|ns1-forensic-supplement' > "$SHARE/incident/mutating-now.txt" || true
systemctl list-jobs --no-pager > "$SHARE/incident/systemd-jobs-now.txt" 2>&1 || true
[[ ! -s "$SHARE/incident/mutating-now.txt" ]] || { echo 'FATAL=MUTATION_CURRENTLY_ACTIVE'; exit 75; }
printf 'station\tpid\tactive\n' > "$SHARE/summary/pids.tsv"
for ch in "${ALL[@]}"; do u="tps-${ch}-playout.service"; printf '%s\t%s\t%s\n' "$ch" "$(systemctl show "$u" -p MainPID --value 2>/dev/null || true)" "$(systemctl is-active "$u" 2>/dev/null || true)" >> "$SHARE/summary/pids.tsv"; done

echo '=== B. exact system journal around coordinated 06:58 event ==='
journalctl --since "$SINCE" --until "$UNTIL" --no-pager -o short-iso 2>&1 | redact > "$SHARE/incident/journal-all-0645-0710.txt"
runsh "$SHARE/incident/journal-focused.txt" "journalctl --since '$SINCE' --until '$UNTIL' --no-pager -o short-iso | grep -Ei 'systemd\[1\]|nginx|tps-|mediamtx|apt|unattended|needrestart|dpkg|package|daemon-reload|reload|restart|shutdown|reboot'"
run "$SHARE/incident/last-x.txt" last -x
run "$SHARE/incident/who.txt" who

# sudo/auth evidence can identify an operator command without relying on shell history.
runsh "$SHARE/incident/sudo-journal.txt" "journalctl --since '$SINCE' --until '$UNTIL' --no-pager -o short-iso _COMM=sudo"
for f in /var/log/auth.log /var/log/auth.log.1; do
  [[ -r "$f" ]] || continue
  grep -Ei 'Sep 12 06:(4[5-9]|5[0-9])|Sep 12 07:0[0-9]' "$f" | grep -Ei 'sudo|COMMAND=|sshd|session opened|session closed' | redact >> "$SHARE/incident/auth-window.txt" || true
done
[[ -f "$SHARE/incident/auth-window.txt" ]] || printf 'NO_AUTH_WINDOW_DATA\n' > "$SHARE/incident/auth-window.txt"

echo '=== C. apt/unattended-upgrades/dpkg evidence ==='
run "$SHARE/apt/apt-daily-upgrade-status.txt" systemctl status apt-daily-upgrade.service --no-pager --full
runsh "$SHARE/apt/apt-daily-upgrade-journal.txt" "journalctl -u apt-daily-upgrade.service --since '$SINCE' --until '$UNTIL' --no-pager -o short-iso"
runsh "$SHARE/apt/unattended-journal.txt" "journalctl --since '$SINCE' --until '$UNTIL' --no-pager -o short-iso | grep -Ei 'unattended|apt.systemd.daily|needrestart|packagekit|dpkg'"
copy_text_redacted /var/log/apt/history.log "$SHARE/apt/history.log"
copy_text_redacted /var/log/apt/term.log "$SHARE/apt/term.log"
copy_text_redacted /var/log/dpkg.log "$SHARE/apt/dpkg.log"
for f in /var/log/unattended-upgrades/unattended-upgrades.log /var/log/unattended-upgrades/unattended-upgrades-dpkg.log /var/log/unattended-upgrades/unattended-upgrades-shutdown.log; do copy_text_redacted "$f" "$SHARE/apt/$(basename "$f")"; done
for f in /etc/apt/apt.conf.d/20auto-upgrades /etc/apt/apt.conf.d/50unattended-upgrades /etc/needrestart/needrestart.conf; do [[ -e "$f" ]] && copy_text_redacted "$f" "$SHARE/apt/$(echo "$f"|tr '/' '_')"; done
runsh "$SHARE/apt/packages-restart-tools.txt" "dpkg-query -W -f='\${Package}\t\${Version}\n' 2>/dev/null | grep -Ei 'unattended-upgrades|needrestart|update-notifier|apt'"

echo '=== D. filesystem mtimes around incident ==='
runsh "$SHARE/identities/systemd-nginx-mtimes.txt" "find /etc/systemd/system /etc/nginx/conf.d /usr/local/sbin -maxdepth 4 -type f -newermt '2026-09-12 05:30:00 UTC' ! -newermt '2026-09-12 07:10:01 UTC' -printf '%TY-%Tm-%TdT%TH:%TM:%TSZ\t%p\t%u:%g\t%m\t%s bytes\n' | sort"
runsh "$SHARE/identities/systemd-all-relevant.txt" "find /etc/systemd/system -maxdepth 4 -type f \( -iname '*tps*' -o -iname '*studio*' -o -iname '*radio*' -o -iname '*tv*' -o -iname '*media*' -o -iname '*nginx*' \) -printf '%TY-%Tm-%TdT%TH:%TM:%TSZ\t%p\n' | sort"
runsh "$SHARE/identities/nginx-current-sha.txt" "find /etc/nginx -type f -print0 | sort -z | xargs -0 sha256sum"
runsh "$SHARE/identities/tps-current-sha.txt" "find /usr/local/sbin -maxdepth 1 -type f \( -name 'tps-*' -o -name 'studiosat-*' \) -print0 | sort -z | xargs -0 sha256sum"

echo '=== E. prove portal/public Radio HLS using the CORRECT routes ==='
printf 'host\tstation\turl\thttp1\thttp2\tm3u8_1\tm3u8_2\tchanged\n' > "$SHARE/summary/portal-hls.tsv"
for ch in "${RADIOS[@]}"; do
  # Primary portal route /hls/<station>/index.m3u8
  host='www.radio.studiosatweb.com.br'; url="https://${host}/hls/${ch}/index.m3u8"; a="$SHARE/portal/${ch}-portal-1.m3u8"; b="$SHARE/portal/${ch}-portal-2.m3u8"
  c1="$(curl -kLsS --connect-timeout 4 --max-time 15 -o "$a" -w '%{http_code}' "$url" || true)"; sleep 3; c2="$(curl -kLsS --connect-timeout 4 --max-time 15 -o "$b" -w '%{http_code}' "$url" || true)"
  m1=NO; m2=NO; grep -q '^#EXTM3U' "$a" 2>/dev/null && m1=YES; grep -q '^#EXTM3U' "$b" 2>/dev/null && m2=YES; changed=NO; ! cmp -s "$a" "$b" 2>/dev/null && changed=YES
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$host" "$ch" "$url" "$c1" "$c2" "$m1" "$m2" "$changed" >> "$SHARE/summary/portal-hls.tsv"
done

# Local MediaMTX route, following redirects, to close collector-v2 false negative.
printf 'station\thttp1\thttp2\tm3u8_1\tm3u8_2\tchanged\n' > "$SHARE/summary/local-hls-follow.tsv"
for ch in "${ALL[@]}"; do a="$SHARE/portal/${ch}-local-1.m3u8"; b="$SHARE/portal/${ch}-local-2.m3u8"; u="http://127.0.0.1:8888/${ch}/index.m3u8"; c1="$(curl -LsS --connect-timeout 3 --max-time 10 -o "$a" -w '%{http_code}' "$u" || true)"; sleep 2; c2="$(curl -LsS --connect-timeout 3 --max-time 10 -o "$b" -w '%{http_code}' "$u" || true)"; m1=NO;m2=NO; grep -q '^#EXTM3U' "$a" 2>/dev/null && m1=YES; grep -q '^#EXTM3U' "$b" 2>/dev/null && m2=YES; changed=NO; ! cmp -s "$a" "$b" 2>/dev/null && changed=YES; printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ch" "$c1" "$c2" "$m1" "$m2" "$changed" >> "$SHARE/summary/local-hls-follow.tsv"; done

echo '=== F. preserve immutable Radio webroot identities ==='
for root in /var/www/studiosat-radio-player /var/www/studiosat-radio-portal /var/www/studiosat-radio/current; do
  name="$(echo "$root"|sed 's#^/##;s#/#_#g')"
  if [[ -d "$root" ]]; then find "$root" -type f -print0 | sort -z | xargs -0 sha256sum > "$SHARE/identities/${name}.sha256" 2>/dev/null || true; find "$root" -type f -printf '%p\t%s\t%TY-%Tm-%TdT%TH:%TM:%TS\n' | sort > "$SHARE/identities/${name}.files.txt"; else echo MISSING > "$SHARE/identities/${name}.files.txt"; fi
done

echo '=== G. summary / package ==='
{
  echo "git_head=$(git rev-parse HEAD)"
  echo "git_origin=$(git rev-parse origin/main)"
  echo "window=$SINCE -> $UNTIL"
  echo "production_mutations_by_script=0"
  echo 'next_action=ANALYZE_ONLY'
} | tee "$SHARE/summary/identity.txt"

tar -C "$OUT" -czf "$ARCHIVE" shareable
sha256sum "$ARCHIVE" | tee "${ARCHIVE}.sha256"
echo 'NS1_FORENSIC_RESULT=COLLECTED'
echo "shareable=$ARCHIVE"
echo "sha256=${ARCHIVE}.sha256"
echo "private_local=$PRIVATE"
