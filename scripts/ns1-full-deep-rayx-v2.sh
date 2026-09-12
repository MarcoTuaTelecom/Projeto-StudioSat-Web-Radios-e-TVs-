#!/usr/bin/env bash
# Nome: ns1-full-deep-rayx-v2.sh
# Versão: 2.0
# Owner: Core
# Safety class: read-only
# Change ID: OBS-NS1-RAYX-20260912
# Propósito: raio-X completo e profundo do NS1 antes de qualquer mutação TV/Rádio.
# Pré-condições: executar como root no NS1; código local sincronizado com GitHub.
# Rollback/remoção: não se aplica à produção; o script grava somente em /tmp.
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
umask 077

MODE="${1:---deep}"
[[ "$MODE" == --deep || "$MODE" == --standard ]] || { echo "usage: $0 [--deep|--standard]" >&2; exit 64; }
DEEP=0; [[ "$MODE" == --deep ]] && DEEP=1
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'FATAL=RUN_AS_ROOT' >&2; exit 77; }

REPO="/root/Projeto-StudioSat-Web-Radios-e-TVs-"
CORE="$REPO/scripts/studiosat-core-preflight.sh"
[[ -d "$REPO/.git" && -f "$CORE" ]] || { echo 'FATAL=REPO_OR_CORE_PREFLIGHT_MISSING' >&2; exit 2; }
cd "$REPO"
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main 2>/dev/null || true)" ]] || { echo 'FATAL=GIT_NOT_SYNCED_WITH_ORIGIN_MAIN' >&2; exit 3; }
for f in scripts/studiosat-core-preflight.sh scripts/ns1-full-deep-rayx-v2.sh; do
  [[ -f "$f" ]] || { echo "FATAL=MISSING_REPO_FILE:$f" >&2; exit 4; }
  [[ "$(sha256sum "$f"|awk '{print $1}')" == "$(git show "HEAD:$f"|sha256sum|awk '{print $1}')" ]] || { echo "FATAL=REPO_FILE_DRIFT:$f" >&2; exit 5; }
done
bash -n "$CORE"
bash -n "$0"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
HOST="$(hostname -s 2>/dev/null || hostname)"
OUT="/tmp/ns1-rayx-deep-${HOST}-${STAMP}"
SHARE="$OUT/shareable"
PRIVATE="$OUT/private"
ARCHIVE="/tmp/ns1-rayx-deep-${HOST}-${STAMP}.shareable.tar.gz"
mkdir -p "$SHARE"/{core,concurrency,runtime,live,public,media,deep,git,summary} "$PRIVATE"/{configs,scripts,playlists}
chmod 0700 "$OUT" "$PRIVATE"
exec > >(tee "$SHARE/REPORT.txt") 2>&1

CHANNELS=(radioprincipal radiopop radiorock radioclassicas radiocountry tvkids tvteens tvviva tvmaisjovem)
have(){ command -v "$1" >/dev/null 2>&1; }
redact(){ sed -E -e 's#(rtmp|rtsp|srt|https?)://([^/@:[:space:]]+):([^/@[:space:]]+)@#\1://REDACTED:REDACTED@#gI' -e 's#((pass(word)?|token|secret|api[_-]?key|stream[_-]?key|authorization|bearer)[[:space:]]*[:=][[:space:]]*)[^[:space:]\"]+#\1REDACTED#gI'; }
log(){ printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
sha(){ sha256sum "$1"|awk '{print $1}'; }
safe(){ printf '%s' "$1"|sed 's#^/##;s#[^A-Za-z0-9._-]#_#g'; }
LOW=(nice -n 19); have ionice && LOW=(nice -n 19 ionice -c3)

cat > "$SHARE/README.txt" <<README
NS1 FULL DEEP RAY-X v2.0 — ${STAMP}
Safety: READ-ONLY against production. It invokes the repository's proven Core Preflight v1.1,
then adds live/public/deep validation. It performs no service restart/reload/start/stop, no package
installation, no production config edit, no media move/delete, and writes diagnostic data only in /tmp.
The private directory contains exact local snapshots and is NOT inside the shareable archive.
README

log 'A. detecting concurrent mutations'
ps -eo pid,ppid,etimes,user,args --sort=pid | grep -E 'apply-(radio|tv)|restore-five-radios|tvkids-rebuild-production|systemctl +(restart|reload|start|stop)|nginx +-s|certbot +renew|apt(|-get) +(install|upgrade)|dpkg +-i' | grep -v -E 'grep -E|ns1-full-deep-rayx' > "$SHARE/concurrency/mutating-processes.txt" || true
systemctl list-jobs --no-pager > "$SHARE/concurrency/systemd-jobs.txt" 2>&1 || true
MUT=0; [[ -s "$SHARE/concurrency/mutating-processes.txt" ]] && MUT=1
if grep -qvE '^No jobs running\.?$|^[[:space:]]*$' "$SHARE/concurrency/systemd-jobs.txt"; then MUT=1; fi
echo "concurrent_mutation_detected=$MUT" | tee "$SHARE/concurrency/status.txt"

log 'B. running proven Core Preflight v1.1 (read-only)'
bash "$CORE" > "$SHARE/core/core-preflight-console.txt" 2>&1
CORE_ARCHIVE="$(find /tmp -maxdepth 1 -type f -name 'studiosat-core-preflight-*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n1 | cut -d' ' -f2- || true)"
[[ -n "$CORE_ARCHIVE" && -f "$CORE_ARCHIVE" ]] || { echo 'FATAL=CORE_PREFLIGHT_ARCHIVE_NOT_FOUND' >&2; exit 6; }
cp -a "$CORE_ARCHIVE" "$SHARE/core/"
sha256sum "$CORE_ARCHIVE" > "$SHARE/core/core-preflight.sha256"
echo "core_archive=$CORE_ARCHIVE" | tee "$SHARE/core/core-preflight.identity.txt"

log 'C. exact runtime identity of all 9 stations'
printf 'station\tactive\tsub\tpid\tstarted\tnrestarts\tmemory\tcpu_nsec\trunning_playlist_sha\tdisk_playlist_sha\tdeleted_fds\n' > "$SHARE/summary/runtime.tsv"
for ch in "${CHANNELS[@]}"; do
  u="tps-${ch}-playout.service"; d="$SHARE/runtime/$ch"; p="$PRIVATE/playlists/$ch"; mkdir -p "$d" "$p"
  systemctl cat "$u" 2>&1 | redact > "$d/unit-cat.txt" || true
  systemctl show "$u" -p ActiveState -p SubState -p MainPID -p ExecMainStartTimestamp -p NRestarts -p User -p Group -p ExecStart -p ExecStartPre -p Restart -p MemoryCurrent -p CPUUsageNSec -p FragmentPath -p DropInPaths 2>&1 | redact > "$d/unit-show.txt" || true
  journalctl -u "$u" --since '-24 hours' --no-pager -o short-iso > "$d/journal-24h.txt" 2>&1 || true
  pid="$(systemctl show "$u" -p MainPID --value 2>/dev/null || true)"; active="$(systemctl show "$u" -p ActiveState --value 2>/dev/null || true)"; sub="$(systemctl show "$u" -p SubState --value 2>/dev/null || true)"; started="$(systemctl show "$u" -p ExecMainStartTimestamp --value 2>/dev/null || true)"; nr="$(systemctl show "$u" -p NRestarts --value 2>/dev/null || true)"; mem="$(systemctl show "$u" -p MemoryCurrent --value 2>/dev/null || true)"; cpu="$(systemctl show "$u" -p CPUUsageNSec --value 2>/dev/null || true)"
  rsha=''; dsha=''; deleted=0
  if [[ "$pid" =~ ^[1-9][0-9]*$ && -d "/proc/$pid" ]]; then
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | redact > "$d/cmdline.txt" || true
    for x in status limits io cgroup smaps_rollup; do cp "/proc/$pid/$x" "$d/proc-$x.txt" 2>/dev/null || true; done
    : > "$d/fds.txt"; runfd=''
    for fd in /proc/"$pid"/fd/*; do t="$(readlink "$fd" 2>/dev/null || true)"; printf '%s\t%s\n' "$fd" "$t" >> "$d/fds.txt"; [[ "$t" == *'(deleted)'* ]] && deleted=$((deleted+1)); [[ "$t" == *"/channels/${ch}/playlists/playlist.txt"* || "$t" == *"/channels/${ch}/playlists/current.ffconcat"* ]] && runfd="$fd"; done
    if [[ -n "$runfd" && -r "$runfd" ]]; then cp -L "$runfd" "$d/running.ffconcat"; cp -L "$runfd" "$p/running.ffconcat"; rsha="$(sha "$d/running.ffconcat")"; fi
  fi
  disk="/srv/tpsmedia/repository/channels/$ch/playlists/playlist.txt"; [[ -f "$disk" ]] && { cp -a "$disk" "$d/disk-playlist.txt"; cp -a "$disk" "$p/disk-playlist.txt"; dsha="$(sha "$disk")"; }
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ch" "$active" "$sub" "$pid" "$started" "$nr" "$mem" "$cpu" "$rsha" "$dsha" "$deleted" >> "$SHARE/summary/runtime.tsv"
done

log 'D. MediaMTX + RTSP + local HLS two-sample freshness'
curl -fsS --connect-timeout 3 --max-time 8 http://127.0.0.1:9997/v3/paths/list > "$SHARE/live/mediamtx-paths.json" 2>/dev/null || printf '{"items":[]}' > "$SHARE/live/mediamtx-paths.json"
printf 'station\tready\trtsp\tlocal_hls_1\tlocal_hls_2\thls_changed\tprobe\n' > "$SHARE/summary/live.tsv"
for ch in "${CHANNELS[@]}"; do
  ready="$(jq -r --arg p "$ch" '.items[]?|select(.name==$p)|.ready' "$SHARE/live/mediamtx-paths.json" 2>/dev/null|head -n1)"; [[ -n "$ready" ]] || ready=missing
  set +e; timeout 15 ffprobe -v error -rtsp_transport tcp -show_entries stream=codec_type,codec_name,width,height,pix_fmt,r_frame_rate,time_base,sample_rate,channels,channel_layout -of compact=p=0:nk=0 "rtsp://127.0.0.1:8554/$ch" > "$SHARE/live/$ch.rtsp.txt" 2> "$SHARE/live/$ch.rtsp.err"; rc=$?; set -e
  r=FAIL; [[ $rc -eq 0 && -s "$SHARE/live/$ch.rtsp.txt" ]] && r=PASS
  c1="$(curl -sS --connect-timeout 3 --max-time 8 -o "$SHARE/live/$ch.hls1.m3u8" -w '%{http_code}' "http://127.0.0.1:8888/$ch/index.m3u8" || true)"
  printf '%s\t%s\t%s\t%s\tPENDING\tPENDING\t%s\n' "$ch" "$ready" "$r" "$c1" "$(tr '\n' ';' < "$SHARE/live/$ch.rtsp.txt")" >> "$SHARE/summary/live.tsv"
done
sleep 8
cp "$SHARE/summary/live.tsv" "$SHARE/summary/live.phase1.tsv"; head -n1 "$SHARE/summary/live.phase1.tsv" > "$SHARE/summary/live.tsv"
tail -n +2 "$SHARE/summary/live.phase1.tsv" | while IFS=$'\t' read -r ch ready r c1 _ _ probe; do c2="$(curl -sS --connect-timeout 3 --max-time 8 -o "$SHARE/live/$ch.hls2.m3u8" -w '%{http_code}' "http://127.0.0.1:8888/$ch/index.m3u8" || true)"; changed=NO; [[ -f "$SHARE/live/$ch.hls1.m3u8" && -f "$SHARE/live/$ch.hls2.m3u8" ]] && ! cmp -s "$SHARE/live/$ch.hls1.m3u8" "$SHARE/live/$ch.hls2.m3u8" && changed=YES; printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ch" "$ready" "$r" "$c1" "$c2" "$changed" "$probe" >> "$SHARE/summary/live.tsv"; done

log 'E. public Radio + TV roots, HLS, DNS and TLS'
HOSTS=(
'radio.studiosatweb.com.br|radioprincipal' 'www.radio.studiosatweb.com.br|radioprincipal' 'radioprincipal.studiosatweb.com.br|radioprincipal' 'www.radioprincipal.studiosatweb.com.br|radioprincipal'
'radiopop.studiosatweb.com.br|radiopop' 'www.radiopop.studiosatweb.com.br|radiopop' 'radiorock.studiosatweb.com.br|radiorock' 'www.radiorock.studiosatweb.com.br|radiorock'
'radioclassicas.studiosatweb.com.br|radioclassicas' 'www.radioclassicas.studiosatweb.com.br|radioclassicas' 'radiocountry.studiosatweb.com.br|radiocountry' 'www.radiocountry.studiosatweb.com.br|radiocountry'
'tvkids.studiosatweb.com.br|tvkids' 'www.tvkids.studiosatweb.com.br|tvkids' 'tvkidsweb.studiosatweb.com.br|tvkids' 'www.tvkidsweb.studiosatweb.com.br|tvkids'
'tvteens.studiosatweb.com.br|tvteens' 'www.tvteens.studiosatweb.com.br|tvteens' 'tvviva.studiosatweb.com.br|tvviva' 'www.tvviva.studiosatweb.com.br|tvviva'
'tvmaisjovem.studiosatweb.com.br|tvmaisjovem' 'www.tvmaisjovem.studiosatweb.com.br|tvmaisjovem')
printf 'host\tstation\thttp\thttps_follow\thls\teffective_url\tcontent_type\n' > "$SHARE/summary/public.tsv"
for hp in "${HOSTS[@]}"; do host="${hp%%|*}"; st="${hp#*|}"; n="$(safe "$host")"; getent ahosts "$host" > "$SHARE/public/$n.dns.txt" 2>&1 || true; http="$(curl -sS --connect-timeout 4 --max-time 12 -o /dev/null -w '%{http_code}' "http://$host/" || true)"; meta="$(curl -kLsS --connect-timeout 4 --max-time 15 -o "$SHARE/public/$n.root.html" -w '%{http_code}\t%{url_effective}\t%{content_type}' "https://$host/" || true)"; https="$(printf '%s' "$meta"|cut -f1)"; eff="$(printf '%s' "$meta"|cut -f2)"; ct="$(printf '%s' "$meta"|cut -f3)"; hls="$(curl -kLsS --connect-timeout 4 --max-time 15 -o "$SHARE/public/$n.hls.m3u8" -w '%{http_code}' "https://$host/$st/index.m3u8" || true)"; printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$host" "$st" "$http" "$https" "$hls" "$eff" "$ct" >> "$SHARE/summary/public.tsv"; if have openssl; then timeout 12 openssl s_client -connect "$host:443" -servername "$host" </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates -serial -fingerprint -sha256 -ext subjectAltName > "$SHARE/public/$n.tls.txt" 2>&1 || true; fi; done

log 'F. exact NGINX/MediaMTX/scripts identities + private snapshots'
nginx -t > "$SHARE/runtime/nginx-t.txt" 2>&1 || true
nginx -T 2>&1 | redact > "$SHARE/runtime/nginx-T.redacted.txt" || true
find /etc/nginx -maxdepth 5 -type f -print0 2>/dev/null | sort -z | xargs -0 -r sha256sum > "$SHARE/runtime/nginx-sha256.txt" 2>/dev/null || true
while IFS= read -r f; do [[ -f "$f" ]] || continue; cp -a "$f" "$PRIVATE/configs/$(safe "$f")" 2>/dev/null || true; done < <(find /etc/nginx /etc/systemd/system -maxdepth 5 -type f 2>/dev/null | sort)
find /etc /opt /usr/local -maxdepth 6 -type f \( -iname '*mediamtx*.yml' -o -iname '*mediamtx*.yaml' \) -print 2>/dev/null | sort > "$SHARE/runtime/mediamtx-configs.txt"
while IFS= read -r f; do [[ -f "$f" ]] || continue; sha256sum "$f" >> "$SHARE/runtime/mediamtx-sha256.txt"; cp -a "$f" "$PRIVATE/configs/$(safe "$f")"; cat "$f" | redact > "$SHARE/runtime/mediamtx-$(safe "$f").redacted.txt"; done < "$SHARE/runtime/mediamtx-configs.txt"
find /usr/local/sbin /usr/local/bin -maxdepth 1 -type f \( -name 'tps-*' -o -name '*studiosat*' \) -print0 2>/dev/null | sort -z | xargs -0 -r sha256sum > "$SHARE/runtime/tps-scripts-sha256.txt"
while IFS= read -r f; do [[ -f "$f" ]] || continue; cp -a "$f" "$PRIVATE/scripts/$(safe "$f")" 2>/dev/null || true; done < <(find /usr/local/sbin /usr/local/bin -maxdepth 1 -type f \( -name 'tps-*' -o -name '*studiosat*' \) 2>/dev/null|sort)

log 'G. media inventory for every station'
printf 'station\tarea\tfiles\tbytes\n' > "$SHARE/summary/media.tsv"
for ch in "${CHANNELS[@]}"; do root="/srv/tpsmedia/repository/channels/$ch"; mkdir -p "$SHARE/media/$ch"; find "$root" -maxdepth 3 -printf '%y\t%p\t%u:%g\t%m\t%s\t%TY-%Tm-%TdT%TH:%TM:%TS\n' 2>/dev/null | sort > "$SHARE/media/$ch/tree.txt"; du -sh "$root" "$root"/* 2>/dev/null | sort -h > "$SHARE/media/$ch/du.txt"; for area in ready canonical incoming quarantine playlists state graphics logs lab archive; do p="$root/$area"; if [[ -d "$p" ]]; then c="$(find "$p" -maxdepth 1 -type f|wc -l)"; b="$(find "$p" -maxdepth 1 -type f -printf '%s\n' 2>/dev/null|awk '{s+=$1}END{print s+0}')"; else c=0;b=0;fi; printf '%s\t%s\t%s\t%s\n' "$ch" "$area" "$c" "$b" >> "$SHARE/summary/media.tsv"; done; done

if (( DEEP == 1 && MUT == 0 )); then
  log 'H. DEEP: SHA256 + ffprobe of every ready/canonical file; full decode of each active playlist (sequential/low priority)'
  for ch in "${CHANNELS[@]}"; do root="/srv/tpsmedia/repository/channels/$ch"; d="$SHARE/deep/$ch"; mkdir -p "$d/probes"; i=0; while IFS= read -r -d '' f; do i=$((i+1)); n="$(printf '%04d' "$i")"; "${LOW[@]}" sha256sum "$f" >> "$d/sha256.txt" 2>>"$d/sha256.err" || true; set +e; timeout 45 "${LOW[@]}" ffprobe -v error -show_format -show_streams -of json "$f" > "$d/probes/$n.json" 2> "$d/probes/$n.err"; rc=$?; set -e; printf '%s\t%s\t%s\n' "$rc" "$f" "$n" >> "$d/probe-index.tsv"; done < <(find "$root/ready" "$root/canonical" -maxdepth 1 -type f -print0 2>/dev/null|sort -z); pl="$SHARE/runtime/$ch/running.ffconcat"; [[ -s "$pl" ]] || pl="$root/playlists/playlist.txt"; if [[ -s "$pl" ]]; then set +e; timeout 3600 "${LOW[@]}" ffmpeg -hide_banner -nostdin -loglevel warning -xerror -threads 1 -f concat -safe 0 -i "$pl" -map 0:v? -map 0:a? -f null - > "$d/decode.stdout" 2> "$d/decode.stderr"; rc=$?; set -e; dts="$(grep -Eic 'non[- ]?monoton(ic|ous).*DTS|DTS.*out of order|non monotonically increasing dts' "$d/decode.stderr"||true)"; errs="$(grep -Eic 'Invalid data|No start code|Impossible to open|corrupt|Conversion failed|Error while decoding|Error submitting|Broken pipe' "$d/decode.stderr"||true)"; printf 'rc=%s\ndts=%s\nmedia_errors=%s\n' "$rc" "$dts" "$errs" > "$d/decode-summary.txt"; fi; done
else
  echo "DEEP_PHASE=SKIPPED concurrent_mutation=$MUT mode=$MODE" | tee "$SHARE/deep/STATUS.txt"
fi

log 'I. host/security/scheduler/fault snapshots not to miss hidden automation'
{ ss -lntup; echo; ss -ntup state established; } > "$SHARE/runtime/sockets.txt" 2>&1 || true
systemctl list-timers --all --no-pager > "$SHARE/runtime/timers.txt" 2>&1 || true
crontab -l > "$SHARE/runtime/root-crontab.txt" 2>&1 || true
crontab -u tpsmedia -l > "$SHARE/runtime/tpsmedia-crontab.txt" 2>&1 || true
journalctl --since '-24 hours' --no-pager -o short-iso | grep -Ei 'tps-|mediamtx|nginx|ffmpeg|Non-monotonic|DTS|Invalid data|Impossible to open|Connection refused|Broken pipe|segfault|core dump|OOM|Killed process' | tail -n 30000 > "$SHARE/runtime/fault-signatures-24h.txt" || true
if have nft; then nft list ruleset > "$SHARE/runtime/nft.txt" 2>&1 || true; fi
if have ufw; then ufw status verbose > "$SHARE/runtime/ufw.txt" 2>&1 || true; fi

log 'J. Git truth + post-run PID stability'
git status --short --branch > "$SHARE/git/status.txt"; git log -30 --date=iso-strict --pretty=format:'%H%x09%ad%x09%an%x09%s' > "$SHARE/git/log.txt"; { echo "HEAD=$(git rev-parse HEAD)"; echo "origin_main=$(git rev-parse origin/main)"; } > "$SHARE/git/identity.txt"
printf 'station\tpid_pre\tpid_post\tchanged\n' > "$SHARE/summary/pid-stability.tsv"
tail -n +2 "$SHARE/summary/runtime.tsv" | while IFS=$'\t' read -r ch active sub pre rest; do post="$(systemctl show "tps-${ch}-playout.service" -p MainPID --value 2>/dev/null||true)"; changed=NO; [[ "$pre" != "$post" ]] && changed=YES; printf '%s\t%s\t%s\t%s\n' "$ch" "$pre" "$post" "$changed" >> "$SHARE/summary/pid-stability.tsv"; done

{
 echo "NS1_RAYX_VERSION=2.0"; echo "UTC=$STAMP"; echo "MODE=$MODE"; echo "CONCURRENT_MUTATION_DETECTED=$MUT"; echo; for f in runtime live public media pid-stability; do echo "===== ${f^^} ====="; column -ts $'\t' "$SHARE/summary/$f.tsv" 2>/dev/null || cat "$SHARE/summary/$f.tsv"; echo; done
} > "$SHARE/summary/MASTER-SUMMARY.txt"

tar -C "$OUT" -czf "$ARCHIVE" shareable
sha256sum "$ARCHIVE" | tee "$ARCHIVE.sha256"
log 'RAY-X COLLECTION COMPLETE — ZERO PRODUCTION MUTATIONS BY THIS SCRIPT'
echo 'NS1_RAYX_RESULT=COLLECTED'
echo "shareable=$ARCHIVE"
echo "sha256=$ARCHIVE.sha256"
echo "private_local=$PRIVATE"
echo "master_summary=$SHARE/summary/MASTER-SUMMARY.txt"
