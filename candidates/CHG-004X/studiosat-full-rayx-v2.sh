#!/usr/bin/env bash
# StudioSat Web — Full Ray-X v2.0
# Safety class: READ-ONLY sobre produção. Único efeito: cria evidências em /tmp.
# Filosofia: IN-PLACE FIRST / NO CONTAINERS / NO DUPLICATE PLATFORM.
# Não reinicia, não recarrega, não instala, não move mídia, não altera configs/units/playlists.

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="2.0"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
HOST="$(hostname -s 2>/dev/null || hostname)"
OUT="/tmp/studiosat-full-rayx-${HOST}-${STAMP}"
ARCHIVE="${OUT}.tar.gz"
ROOT="/srv/tpsmedia/repository/channels"
MTX_API="http://127.0.0.1:9997/v3/paths/list"
REPO="/root/Projeto-StudioSat-Web-Radios-e-TVs-"

RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
TVS=(tvkids tvteens tvviva tvmaisjovem)
CHANNELS=("${RADIOS[@]}" "${TVS[@]}")

mkdir -p "$OUT"/{00-meta,01-host,02-systemd,03-scripts,04-network,05-mediamtx,06-nginx,07-tls,08-samba,09-channels,10-streams,11-security,12-summary,13-final}
chmod 0700 "$OUT"

log(){ printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }
have(){ command -v "$1" >/dev/null 2>&1; }
redact(){
  sed -E \
    -e 's#(rtmp|rtsp|srt|https?)://([^/@:[:space:]]+):([^/@[:space:]]+)@#\1://REDACTED:REDACTED@#gI' \
    -e 's#((pass(word)?|token|secret|api[_-]?key|stream[_-]?key|authorization|bearer)[[:space:]]*[:=][[:space:]]*)[^[:space:]\"]+#\1REDACTED#gI' \
    -e 's#(Authorization:[[:space:]]*(Basic|Bearer)[[:space:]]+)[A-Za-z0-9._~+/=-]+#\1REDACTED#gI' \
    -e 's#([?&](token|key|secret|password|pass)=)[^&[:space:]]+#\1REDACTED#gI'
}
run_txt(){ local dst="$1"; shift; { "$@" 2>&1 || true; } | redact > "$dst"; }
run_shell(){ local dst="$1"; shift; { bash -lc "$*" 2>&1 || true; } | redact > "$dst"; }
safe_copy_text(){ local src="$1" dst="$2"; [[ -r "$src" ]] && { cat "$src" | redact > "$dst"; } || true; }

cat > "$OUT/00-meta/README.txt" <<README
StudioSat Web Full Ray-X v${VERSION}
Host: ${HOST}
UTC: ${STAMP}

OBJETIVO
Fotografar o estado REAL da plataforma existente antes de reavaliar a arquitetura e antes de reiniciar Country.

PRINCIPIOS
- IN-PLACE FIRST
- NO CONTAINERS
- NO DUPLICATE PLATFORM
- TV é observada apenas para compatibilidade/não-regressão; implementação TV pertence à Engenharia TV.

GARANTIA
Este script não executa start/stop/restart/reload/enable/disable, apt, mv/rm sobre produção,
não gera playlist e não edita MediaMTX/NGINX/systemd/mídia. Escreve apenas em ${OUT} e gera ${ARCHIVE}.
README

log "0/13 — checkpoint do repositório"
if [[ -d "$REPO/.git" ]]; then
  run_shell "$OUT/00-meta/git-head.txt" "git -C '$REPO' rev-parse HEAD"
  run_shell "$OUT/00-meta/git-status.txt" "git -C '$REPO' status --short"
  run_shell "$OUT/00-meta/git-log.txt" "git -C '$REPO' log -12 --oneline --decorate"
else
  printf 'REPO_NOT_FOUND=%s\n' "$REPO" > "$OUT/00-meta/git-head.txt"
fi

log "1/13 — host, recursos e pacotes"
run_txt "$OUT/01-host/date-utc.txt" date -u
run_txt "$OUT/01-host/hostnamectl.txt" hostnamectl
run_txt "$OUT/01-host/uname.txt" uname -a
safe_copy_text /etc/os-release "$OUT/01-host/os-release.txt"
run_txt "$OUT/01-host/uptime.txt" uptime
run_txt "$OUT/01-host/free.txt" free -h
run_txt "$OUT/01-host/df.txt" df -hT
run_txt "$OUT/01-host/df-inodes.txt" df -hi
run_txt "$OUT/01-host/lsblk.txt" lsblk -o NAME,SIZE,FSTYPE,FSVER,TYPE,MOUNTPOINTS
run_txt "$OUT/01-host/mount.txt" mount
safe_copy_text /etc/fstab "$OUT/01-host/fstab.redacted.txt"
run_txt "$OUT/01-host/lscpu.txt" lscpu
run_txt "$OUT/01-host/nproc.txt" nproc
run_shell "$OUT/01-host/load.txt" "cat /proc/loadavg; grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo"
if have vmstat; then run_txt "$OUT/01-host/vmstat.txt" vmstat 1 5; fi
if have iostat; then run_txt "$OUT/01-host/iostat.txt" iostat -xz 1 3; fi
if have top; then run_shell "$OUT/01-host/top-batch.txt" "COLUMNS=220 top -b -n1 | head -n 80"; fi

for cmd in ffmpeg ffprobe nginx certbot curl jq mediamtx liquidsoap ffplayout icecast2 docker podman git; do
  if have "$cmd"; then
    case "$cmd" in
      ffmpeg|ffprobe) run_shell "$OUT/01-host/version-${cmd}.txt" "command -v '$cmd'; '$cmd' -version 2>&1 | head -n 30" ;;
      nginx) run_shell "$OUT/01-host/version-${cmd}.txt" "command -v '$cmd'; '$cmd' -v 2>&1" ;;
      *) run_shell "$OUT/01-host/version-${cmd}.txt" "command -v '$cmd'; '$cmd' --version 2>&1 | head -n 30" ;;
    esac
  else
    printf 'NOT_FOUND\n' > "$OUT/01-host/version-${cmd}.txt"
  fi
done
if have dpkg-query; then
  run_shell "$OUT/01-host/packages-relevant.txt" "dpkg-query -W -f='\${Package}\t\${Version}\n' 2>/dev/null | grep -Ei 'ffmpeg|nginx|mediamtx|liquidsoap|ffplayout|icecast|certbot|samba|docker|podman|gstreamer' | sort"
fi
run_shell "$OUT/01-host/processes-media.txt" "ps -eo user,pid,ppid,ni,pcpu,pmem,rss,vsz,etime,lstart,args --sort=pid | grep -Ei 'ffmpeg|mediamtx|nginx|liquidsoap|ffplayout|icecast|tps-|studiosat-' | grep -v grep"

log "2/13 — systemd exato das 9 stations e Core"
printf 'station\tdomain\tunit\tload\tactive\tsub\tpid\tstart_timestamp\thas_execstartpre\n' > "$OUT/12-summary/stations-systemd.tsv"
for ch in "${CHANNELS[@]}"; do
  domain=radio; [[ "$ch" == tv* ]] && domain=tv
  unit="tps-${ch}-playout.service"
  cdir="$OUT/09-channels/$ch"; mkdir -p "$cdir"/{systemd,media,playlist,probe,logs}
  run_shell "$cdir/systemd/cat.txt" "systemctl cat '$unit'"
  run_shell "$cdir/systemd/show.txt" "systemctl show '$unit' -p Id -p Names -p LoadState -p ActiveState -p SubState -p MainPID -p User -p Group -p ExecStart -p ExecStartPre -p ExecMainStartTimestamp -p Restart -p RestartUSec -p MemoryCurrent -p MemoryMax -p CPUUsageNSec -p CPUQuotaPerSecUSec -p FragmentPath -p DropInPaths -p UnitFileState"
  run_shell "$cdir/systemd/status.txt" "systemctl status '$unit' --no-pager --full"
  run_shell "$cdir/systemd/journal-500.txt" "journalctl -u '$unit' -n 500 --no-pager -o short-iso"
  run_shell "$cdir/systemd/deps.txt" "systemctl list-dependencies '$unit' --all --no-pager"
  load="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
  active="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
  sub="$(systemctl show "$unit" -p SubState --value 2>/dev/null || true)"
  pid="$(systemctl show "$unit" -p MainPID --value 2>/dev/null || true)"
  started="$(systemctl show "$unit" -p ExecMainStartTimestamp --value 2>/dev/null || true)"
  esp="$(systemctl show "$unit" -p ExecStartPre --value 2>/dev/null || true)"
  haspre=no; [[ -n "$esp" ]] && haspre=yes
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ch" "$domain" "$unit" "$load" "$active" "$sub" "$pid" "$started" "$haspre" >> "$OUT/12-summary/stations-systemd.tsv"
  if [[ "${pid:-0}" =~ ^[0-9]+$ && "${pid:-0}" -gt 0 && -r "/proc/$pid/cmdline" ]]; then
    tr '\0' ' ' < "/proc/$pid/cmdline" | redact > "$cdir/systemd/mainpid-cmdline.txt" || true
    run_shell "$cdir/systemd/process-tree.txt" "ps -eo pid,ppid,user,pcpu,pmem,etime,args --forest | awk 'NR==1 || \$1==$pid || \$2==$pid'"
    if have lsof; then run_shell "$cdir/systemd/lsof-mainpid.txt" "lsof -nP -p '$pid' | head -n 500"; fi
  fi
done

for unit in tps-mediamtx.service nginx.service smbd.service nmbd.service; do
  bn="${unit//./_}"
  run_shell "$OUT/02-systemd/${bn}-cat.txt" "systemctl cat '$unit'"
  run_shell "$OUT/02-systemd/${bn}-show.txt" "systemctl show '$unit' -p Id -p LoadState -p ActiveState -p SubState -p MainPID -p User -p Group -p ExecStart -p ExecMainStartTimestamp -p Restart -p FragmentPath -p DropInPaths -p UnitFileState"
  run_shell "$OUT/02-systemd/${bn}-status.txt" "systemctl status '$unit' --no-pager --full"
  run_shell "$OUT/02-systemd/${bn}-journal-300.txt" "journalctl -u '$unit' -n 300 --no-pager -o short-iso"
done
run_shell "$OUT/02-systemd/media-units.txt" "systemctl list-units --type=service --all --no-pager --plain | grep -Ei 'tps|studio|radio|tv|mediamtx|nginx|smb|liquidsoap|ffplayout|icecast'"
run_txt "$OUT/02-systemd/timers.txt" systemctl list-timers --all --no-pager
run_shell "$OUT/02-systemd/relevant-unit-files.txt" "find /etc/systemd/system -maxdepth 4 -type f \( -iname '*tps*' -o -iname '*studio*' -o -iname '*media*' -o -iname '*radio*' -o -iname '*tv*' \) -print | sort"
run_shell "$OUT/02-systemd/relevant-unit-hashes.txt" "find /etc/systemd/system -maxdepth 4 -type f \( -iname '*tps*' -o -iname '*studio*' -o -iname '*media*' -o -iname '*radio*' -o -iname '*tv*' \) -print0 2>/dev/null | sort -z | xargs -0 -r sha256sum"

log "3/13 — scripts TPS/StudioSat, hashes e conteúdo"
run_shell "$OUT/03-scripts/list.txt" "find /usr/local/sbin /usr/local/bin -maxdepth 1 -type f \( -iname 'tps-*' -o -iname '*studiosat*' \) -printf '%p\t%u:%g\t%m\t%s\t%TY-%Tm-%TdT%TH:%TM:%TS\n' 2>/dev/null | sort"
run_shell "$OUT/03-scripts/hashes.txt" "find /usr/local/sbin /usr/local/bin -maxdepth 1 -type f \( -iname 'tps-*' -o -iname '*studiosat*' \) -print0 2>/dev/null | sort -z | xargs -0 -r sha256sum"
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  bn="$(basename "$f" | tr -c 'A-Za-z0-9._-' '_')"
  sed -n '1,2500p' "$f" 2>/dev/null | redact > "$OUT/03-scripts/${bn}.redacted.txt" || true
done < <(find /usr/local/sbin /usr/local/bin -maxdepth 1 -type f \( -iname 'tps-*' -o -iname '*studiosat*' \) 2>/dev/null | sort)

log "4/13 — rede, listeners e firewall local"
run_txt "$OUT/04-network/ss-lntup.txt" ss -lntup
run_txt "$OUT/04-network/ss-lnuap.txt" ss -lnuap
run_txt "$OUT/04-network/ip-addr.txt" ip -br addr
run_txt "$OUT/04-network/ip-route.txt" ip route
safe_copy_text /etc/resolv.conf "$OUT/04-network/resolv.conf.txt"
if have ufw; then run_txt "$OUT/11-security/ufw-status.txt" ufw status verbose; fi
if have iptables; then run_txt "$OUT/11-security/iptables-S.txt" iptables -S; fi
if have nft; then run_txt "$OUT/11-security/nft-ruleset.txt" nft list ruleset; fi

log "5/13 — MediaMTX real"
run_shell "$OUT/05-mediamtx/process.txt" "ps -eo user,pid,ppid,pcpu,pmem,etime,args | grep -i '[m]ediamtx'"
run_shell "$OUT/05-mediamtx/listeners.txt" "ss -lntup | grep -E ':(1935|8000|8001|8189|8554|8888|8889|8890|8892|8893|9997|9998)\\b'"
run_shell "$OUT/05-mediamtx/config-candidates.txt" "find /etc /opt /usr/local -maxdepth 6 -type f \( -iname 'mediamtx.yml' -o -iname 'mediamtx.yaml' -o -iname '*mediamtx*.yml' -o -iname '*mediamtx*.yaml' \) -print 2>/dev/null | sort -u"
while IFS= read -r cfg; do
  [[ -f "$cfg" ]] || continue
  bn="$(printf '%s' "$cfg" | sed 's#^/##; s#[/ ]#_#g')"
  sha256sum "$cfg" > "$OUT/05-mediamtx/config-${bn}.sha256.txt" 2>/dev/null || true
  cat "$cfg" 2>/dev/null | redact > "$OUT/05-mediamtx/config-${bn}.redacted.txt" || true
done < "$OUT/05-mediamtx/config-candidates.txt"
if have curl; then
  for endpoint in \
    'http://127.0.0.1:9997/v3/paths/list' \
    'http://127.0.0.1:9997/v3/config/global/get' \
    'http://127.0.0.1:9997/v3/config/paths/list' \
    'http://127.0.0.1:9998/metrics'; do
    name="$(echo "$endpoint" | sed -E 's#https?://##; s#[/:?&=]#_#g')"
    { curl -fsS --max-time 5 "$endpoint" 2>&1 || true; } | redact > "$OUT/05-mediamtx/api-${name}.txt"
  done
fi

log "6/13 — NGINX e rotas públicas"
if have nginx; then
  run_txt "$OUT/06-nginx/nginx-t.txt" nginx -t
  { nginx -T 2>&1 || true; } | redact > "$OUT/06-nginx/nginx-T.redacted.txt"
  run_shell "$OUT/06-nginx/server-names.txt" "nginx -T 2>&1 | grep -E '^[[:space:]]*server_name[[:space:]]+' | sed 's/#.*//' | sort -u"
  run_shell "$OUT/06-nginx/routes.txt" "nginx -T 2>&1 | grep -E '^[[:space:]]*(listen|server_name|location|proxy_pass|return 30[1278])[[:space:]]'"
  run_shell "$OUT/06-nginx/sites-enabled.txt" "find -L /etc/nginx/sites-enabled -maxdepth 1 -type f -printf '%p -> %l\n' 2>/dev/null | sort"
  run_shell "$OUT/06-nginx/config-hashes.txt" "find /etc/nginx -type f \( -name '*.conf' -o -path '/etc/nginx/sites-*/*' \) -print0 2>/dev/null | sort -z | xargs -0 -r sha256sum"
fi

log "7/13 — TLS/Certbot sem renovação"
if have certbot; then run_txt "$OUT/07-tls/certificates.txt" certbot certificates; fi
run_shell "$OUT/07-tls/timers.txt" "systemctl list-timers --all --no-pager | grep -i certbot"
run_shell "$OUT/07-tls/unit-files.txt" "systemctl list-unit-files --no-pager | grep -i certbot"
run_shell "$OUT/07-tls/letsencrypt-tree.txt" "find /etc/letsencrypt -maxdepth 3 -type f ! -name 'privkey*.pem' -printf '%p\t%u:%g\t%m\t%s\n' 2>/dev/null | sort"
printf 'NOT_EXECUTED: certbot renew --dry-run\n' > "$OUT/07-tls/renew-dry-run-NOT-EXECUTED.txt"

log "8/13 — Samba/ingest atual"
run_shell "$OUT/08-samba/processes.txt" "ps -eo user,pid,ppid,etime,args | grep -Ei '[s]mbd|[n]mbd|[w]inbind'"
run_shell "$OUT/08-samba/listeners.txt" "ss -lntup | grep -E ':(137|138|139|445)\\b'"
if have testparm; then run_shell "$OUT/08-samba/testparm-s.redacted.txt" "testparm -s 2>&1"; fi
if have smbstatus; then run_shell "$OUT/08-samba/smbstatus.redacted.txt" "smbstatus 2>&1"; fi
safe_copy_text /etc/samba/smb.conf "$OUT/08-samba/smb.conf.redacted.txt"

log "9/13 — árvore, playlists e mídia das 9 stations"
printf 'station\tdomain\troot_exists\tready_eligible\tready_files\tcanonical_files\tincoming_files\tplaylist_sha256\n' > "$OUT/12-summary/media.tsv"
for ch in "${CHANNELS[@]}"; do
  domain=radio; [[ "$ch" == tv* ]] && domain=tv
  cdir="$OUT/09-channels/$ch"
  root="$ROOT/$ch"
  if [[ ! -d "$root" ]]; then
    printf '%s\t%s\tno\t0\t0\t0\t0\tNA\n' "$ch" "$domain" >> "$OUT/12-summary/media.tsv"
    continue
  fi
  run_shell "$cdir/media/root-stat.txt" "stat '$root'"
  run_shell "$cdir/media/tree-depth2.txt" "find '$root' -maxdepth 2 -printf '%y\t%p\t%u:%g\t%m\t%s\t%TY-%Tm-%TdT%TH:%TM:%TS\n' | sort | head -n 4000"
  run_shell "$cdir/media/dir-sizes.txt" "du -h --max-depth=2 '$root' 2>/dev/null | sort -h"
  run_shell "$cdir/media/symlinks.txt" "find '$root' -maxdepth 3 -type l -printf '%p -> %l\n' | sort"
  run_shell "$cdir/media/hardlinks.txt" "find '$root' -maxdepth 3 -type f -links +1 -printf '%i\t%n\t%p\n' | sort -n"
  for sub in incoming quarantine canonical ready playlists state graphics logs archive; do
    p="$root/$sub"
    if [[ -d "$p" ]]; then
      run_shell "$cdir/media/${sub}-files.txt" "find '$p' -maxdepth 2 -type f -printf '%p\t%s\t%TY-%Tm-%TdT%TH:%TM:%TS\n' | sort | head -n 5000"
    else
      printf 'DIR_NOT_FOUND=%s\n' "$p" > "$cdir/media/${sub}-files.txt"
    fi
  done
  ready_all="$(find "$root/ready" -maxdepth 1 -type f 2>/dev/null | wc -l || true)"
  canon_all="$(find "$root/canonical" -maxdepth 1 -type f 2>/dev/null | wc -l || true)"
  incoming_all="$(find "$root/incoming" -maxdepth 1 -type f 2>/dev/null | wc -l || true)"
  eligible="$(find "$root/ready" -maxdepth 1 -type f \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.mp4' -o -iname '*.aac' \) ! -iname '*teste*' ! -iname '*test*' 2>/dev/null | wc -l || true)"
  playlist="$root/playlists/playlist.txt"
  psha="NA"
  if [[ -f "$playlist" ]]; then
    sha256sum "$playlist" > "$cdir/playlist/playlist.sha256.txt" || true
    psha="$(sha256sum "$playlist" | awk '{print $1}' || true)"
    sed -n '1,5000p' "$playlist" | redact > "$cdir/playlist/playlist.txt"
    awk -F"'" '/^[[:space:]]*file[[:space:]]+/ {print $2}' "$playlist" > "$cdir/playlist/references.txt" 2>/dev/null || true
    : > "$cdir/playlist/references-missing.txt"
    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      [[ -e "$ref" ]] || printf '%s\n' "$ref" >> "$cdir/playlist/references-missing.txt"
    done < "$cdir/playlist/references.txt"
  else
    printf 'PLAYLIST_NOT_FOUND=%s\n' "$playlist" > "$cdir/playlist/playlist.txt"
  fi
  run_shell "$cdir/playlist/all-playlists.txt" "find '$root/playlists' -maxdepth 2 -type f -printf '%p\t%s\t%TY-%Tm-%TdT%TH:%TM:%TS\n' 2>/dev/null | sort"
  printf '%s\t%s\tyes\t%s\t%s\t%s\t%s\t%s\n' "$ch" "$domain" "$eligible" "$ready_all" "$canon_all" "$incoming_all" "$psha" >> "$OUT/12-summary/media.tsv"

  if have ffprobe; then
    mapfile -t samples < <( { find "$root/ready" -maxdepth 1 -type f 2>/dev/null; find "$root/canonical" -maxdepth 1 -type f 2>/dev/null; } | grep -Ei '\.(mp3|m4a|mp4|aac|mov|mkv|ts)$' | sort -u | head -n 3 )
    idx=0
    for f in "${samples[@]:-}"; do
      [[ -f "$f" ]] || continue
      idx=$((idx+1))
      printf '%s\n' "$f" > "$cdir/probe/sample-${idx}.path.txt"
      timeout 8 ffprobe -v error -show_entries format=filename,format_name,duration,size,bit_rate:stream=index,codec_type,codec_name,profile,width,height,pix_fmt,r_frame_rate,avg_frame_rate,time_base,sample_rate,channels,channel_layout,bit_rate -of json "$f" > "$cdir/probe/sample-${idx}.ffprobe.json" 2>"$cdir/probe/sample-${idx}.ffprobe.err" || true
    done
  fi
done

log "10/13 — streams locais, MediaMTX, HLS freshness e endpoints públicos"
printf 'station\tdomain\tsystemd\tmtx_ready\ttracks\thls_http\thls_fresh\tpublic_http\n' > "$OUT/12-summary/streams.tsv"
if curl -fsS --max-time 5 "$MTX_API" > "$OUT/10-streams/mediamtx-paths.json" 2>"$OUT/10-streams/mediamtx-paths.err"; then :; else true; fi
public_url(){
  case "$1" in
    radioprincipal) printf '%s' 'https://radio.studiosatweb.com.br' ;;
    radiopop) printf '%s' 'https://radiopop.studiosatweb.com.br' ;;
    radiorock) printf '%s' 'https://radiorock.studiosatweb.com.br' ;;
    radioclassicas) printf '%s' 'https://radioclassicas.studiosatweb.com.br' ;;
    radiocountry) printf '%s' 'https://radiocountry.studiosatweb.com.br' ;;
    tvkids) printf '%s' 'https://tvkids.studiosatweb.com.br' ;;
    tvteens) printf '%s' 'https://tvteens.studiosatweb.com.br' ;;
    tvviva) printf '%s' 'https://tvviva.studiosatweb.com.br' ;;
    tvmaisjovem) printf '%s' 'https://tvmaisjovem.studiosatweb.com.br' ;;
  esac
}
for ch in "${CHANNELS[@]}"; do
  domain=radio; [[ "$ch" == tv* ]] && domain=tv
  cdir="$OUT/09-channels/$ch"
  sys="$(systemctl is-active "tps-${ch}-playout.service" 2>/dev/null || true)"
  item=""
  if [[ -s "$OUT/10-streams/mediamtx-paths.json" ]] && have jq; then item="$(jq -c --arg ch "$ch" '.items[]? | select(.name==$ch)' "$OUT/10-streams/mediamtx-paths.json" | head -n1)"; fi
  ready=false; tracks=""
  if [[ -n "$item" ]]; then
    ready="$(jq -r '.ready // false' <<<"$item")"
    tracks="$(jq -r '[.tracks[]?] | join("+")' <<<"$item")"
    printf '%s\n' "$item" > "$cdir/probe/mediamtx-path.json"
  fi
  manifest="http://127.0.0.1:8888/${ch}/index.m3u8"
  hcode="$(curl -sS -L -o "$cdir/probe/hls-1.m3u8" -w '%{http_code}' --max-time 8 "$manifest" 2>"$cdir/probe/hls.err" || true)"
  fresh=SKIP
  if [[ "$hcode" == 200 && -s "$cdir/probe/hls-1.m3u8" ]]; then
    sleep 2
    curl -fsS -L --max-time 8 "$manifest" > "$cdir/probe/hls-2.m3u8" 2>/dev/null || true
    if cmp -s "$cdir/probe/hls-1.m3u8" "$cdir/probe/hls-2.m3u8"; then fresh=UNCHANGED_2S; else fresh=CHANGING; fi
  fi
  pub="$(public_url "$ch")"
  pcode="$(curl -sS -L -o /dev/null -w '%{http_code}' --max-time 8 "$pub" 2>/dev/null || true)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ch" "$domain" "$sys" "$ready" "$tracks" "${hcode:-000}" "$fresh" "${pcode:-000}" >> "$OUT/12-summary/streams.tsv"
done

log "11/13 — DNS público conhecido e resolução"
if have getent; then
  for h in radio.studiosatweb.com.br www.radio.studiosatweb.com.br radiopop.studiosatweb.com.br radiorock.studiosatweb.com.br radioclassicas.studiosatweb.com.br radiocountry.studiosatweb.com.br tvkids.studiosatweb.com.br tvteens.studiosatweb.com.br tvviva.studiosatweb.com.br tvmaisjovem.studiosatweb.com.br; do
    run_shell "$OUT/04-network/dns-${h}.txt" "getent ahosts '$h' | head -n 20"
  done
fi

log "12/13 — resumo automático"
{
  echo "StudioSat Web Full Ray-X v${VERSION}"
  echo "Host: $HOST"
  echo "UTC: $STAMP"
  echo
  echo "== SYSTEMD =="
  cat "$OUT/12-summary/stations-systemd.tsv"
  echo
  echo "== MEDIA =="
  cat "$OUT/12-summary/media.tsv"
  echo
  echo "== STREAMS =="
  cat "$OUT/12-summary/streams.tsv"
  echo
  echo "== IMPORTANT RULE =="
  echo "No restart or config change was performed by this script."
} > "$OUT/12-summary/SUMMARY.txt"

log "13/13 — estado final e integridade"
run_txt "$OUT/13-final/date-utc.txt" date -u
run_txt "$OUT/13-final/uptime.txt" uptime
run_txt "$OUT/13-final/free.txt" free -h
run_txt "$OUT/13-final/df-root.txt" df -hT /
run_shell "$OUT/13-final/systemd-final.tsv" "for s in radioprincipal radiopop radiorock radioclassicas radiocountry tvkids tvteens tvviva tvmaisjovem; do printf '%s\\t' \"\$s\"; systemctl is-active \"tps-\${s}-playout.service\" || true; done"

( cd "$OUT" && find . -type f ! -name SHA256SUMS.txt -print0 | sort -z | xargs -0 sha256sum ) > "$OUT/SHA256SUMS.txt"
tar -C "$(dirname "$OUT")" -czf "$ARCHIVE" "$(basename "$OUT")"
sha256sum "$ARCHIVE" > "${ARCHIVE}.sha256"
chmod 0600 "$ARCHIVE" "${ARCHIVE}.sha256" || true

cat <<DONE

RAYX_VERSION=${VERSION}
READ_ONLY=YES
RESULT_DIR=${OUT}
ARCHIVE=${ARCHIVE}
ARCHIVE_SHA256=${ARCHIVE}.sha256
SUMMARY=${OUT}/12-summary/SUMMARY.txt

PRÓXIMO PASSO:
1) NÃO reinicie Country ainda.
2) Envie o .tar.gz e o .sha256 para análise privada.
3) Depois do diagnóstico, o projeto inteiro será reavaliado e a Change Queue será reescrita com base no estado real.
DONE
