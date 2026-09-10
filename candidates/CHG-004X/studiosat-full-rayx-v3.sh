#!/usr/bin/env bash
# StudioSat Web — FULL RAY-X v3.1
# Objetivo: inventário técnico exaustivo e somente leitura do host StudioSat Web.
# Safety: NÃO reinicia/recarrega serviços, NÃO instala/remove pacotes, NÃO altera config/mídia.
# Únicos efeitos: cria evidências em /tmp e realiza probes de leitura limitados.

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="3.1"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
HOST="$(hostname -s 2>/dev/null || hostname)"
OUT="/tmp/studiosat-full-rayx-v3-${HOST}-${STAMP}"
ARCHIVE="${OUT}.tar.gz"
ROOT="/srv/tpsmedia/repository/channels"
REPO="/root/Projeto-StudioSat-Web-Radios-e-TVs-"
MTX_API="http://127.0.0.1:9997/v3"

RADIOS=(radioprincipal radiopop radiorock radioclassicas radiocountry)
TVS=(tvkids tvteens tvviva tvmaisjovem)
CHANNELS=("${RADIOS[@]}" "${TVS[@]}")

mkdir -p "$OUT"/{00-meta,01-host,02-tools-packages,03-services,04-routines,05-processes,06-network,07-filesystems,08-configs,09-nginx-sites,10-dns-tls,11-mediamtx,12-samba-ingest,13-stations,14-media-inventory,15-playlists,16-streams,17-speed,18-security,19-summary,20-final}
chmod 0700 "$OUT"

log(){ printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }
have(){ command -v "$1" >/dev/null 2>&1; }
redact(){
  sed -E \
    -e 's#(rtmp|rtsp|srt|https?)://([^/@:[:space:]]+):([^/@[:space:]]+)@#\1://REDACTED:REDACTED@#gI' \
    -e 's#((pass(word)?|passwd|token|secret|api[_-]?key|stream[_-]?key|authorization|bearer|credential|private[_-]?key)[[:space:]]*[:=][[:space:]]*)[^[:space:]\"]+#\1REDACTED#gI' \
    -e 's#(Authorization:[[:space:]]*(Basic|Bearer)[[:space:]]+)[A-Za-z0-9._~+/=-]+#\1REDACTED#gI' \
    -e 's#([?&](token|key|secret|password|pass|auth)=)[^&[:space:]]+#\1REDACTED#gI'
}
run_txt(){ local dst="$1"; shift; { "$@" 2>&1 || true; } | redact > "$dst"; }
run_shell(){ local dst="$1"; shift; { bash -lc "$*" 2>&1 || true; } | redact > "$dst"; }
safe_text(){ local src="$1" dst="$2"; [[ -r "$src" ]] && { cat "$src" 2>/dev/null | redact > "$dst"; } || true; }
sanitize_name(){ printf '%s' "$1" | sed -E 's#[^A-Za-z0-9._-]+#_#g'; }

cat > "$OUT/00-meta/README.txt" <<README
StudioSat Web FULL RAY-X v${VERSION}
Host: ${HOST}
UTC: ${STAMP}

ESCOPO EXAUSTIVO
- host/hardware/recursos/discos/mounts;
- todas as ferramentas/pacotes instalados detectáveis por dpkg/snap e versões de runtimes comuns;
- todos os serviços systemd carregados/ativos/falhos/habilitados e detalhes dos ativos/falhos;
- rotinas agendadas: timers, cron, anacron, at, init/rc.local e logrotate;
- todos os processos, executáveis, CWDs, árvore, consumo e sockets;
- filesystem relevante e diretórios em uso;
- scripts/configurações TPS/StudioSat;
- MediaMTX completo: unit, config sanitizada, API, paths/sessões/listeners/metrics quando disponíveis;
- NGINX completo: config sanitizada, sites, server_name, roots, aliases, proxies, listeners;
- DNS/TLS e HTTP/HTTPS de todos os domínios/subdomínios descobertos no NGINX/Certbot;
- Samba/ingest;
- nove emissoras: units, processos, origem real, playlists, conteúdo, formatos, tamanhos, ffprobe de TODOS os assets locais;
- saídas: MediaMTX tracks, HLS, RTSP/RTMP probes limitados, endpoints públicos;
- velocidade/latência: HTTP, HLS manifest/segment, taxa real de download e contadores de rede;
- segurança local e permissões relevantes.

GARANTIA OPERACIONAL
Este coletor não executa start/stop/restart/reload/enable/disable, apt install/remove/upgrade,
não gera playlists, não move/apaga mídia e não edita MediaMTX/NGINX/systemd/Samba/TLS.
Os únicos arquivos criados ficam em ${OUT} e ${ARCHIVE}.

OBSERVAÇÃO
Probes ffprobe/curl são limitados por timeout. Inventariar todos os assets pode demorar conforme a biblioteca,
mas não realiza decode integral nem transcode.
README

log "00/20 — checkpoint Git"
if [[ -d "$REPO/.git" ]]; then
  run_shell "$OUT/00-meta/git-head.txt" "git -C '$REPO' rev-parse HEAD"
  run_shell "$OUT/00-meta/git-status.txt" "git -C '$REPO' status --short"
  run_shell "$OUT/00-meta/git-log.txt" "git -C '$REPO' log -20 --oneline --decorate"
  run_shell "$OUT/00-meta/git-remote.txt" "git -C '$REPO' remote -v"
else
  printf 'REPO_NOT_FOUND=%s\n' "$REPO" > "$OUT/00-meta/git-head.txt"
fi

log "01/20 — host/hardware/recursos"
run_txt "$OUT/01-host/date-utc.txt" date -u
run_txt "$OUT/01-host/hostnamectl.txt" hostnamectl
run_txt "$OUT/01-host/uname.txt" uname -a
safe_text /etc/os-release "$OUT/01-host/os-release.txt"
run_txt "$OUT/01-host/uptime.txt" uptime
run_txt "$OUT/01-host/free.txt" free -h
run_txt "$OUT/01-host/df.txt" df -hT
run_txt "$OUT/01-host/df-inodes.txt" df -hi
run_txt "$OUT/01-host/lsblk.txt" lsblk -o NAME,MAJ:MIN,SIZE,ROTA,FSTYPE,FSVER,TYPE,MOUNTPOINTS
run_txt "$OUT/01-host/findmnt.txt" findmnt -a
run_txt "$OUT/01-host/mount.txt" mount
safe_text /etc/fstab "$OUT/01-host/fstab.redacted.txt"
run_txt "$OUT/01-host/lscpu.txt" lscpu
run_txt "$OUT/01-host/nproc.txt" nproc
run_shell "$OUT/01-host/load-memory.txt" "cat /proc/loadavg; grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree|Dirty|Writeback):' /proc/meminfo"
run_shell "$OUT/01-host/kernel-cmdline.txt" "cat /proc/cmdline"
if have lspci; then run_txt "$OUT/01-host/lspci.txt" lspci -nnk; fi
if have lsusb; then run_txt "$OUT/01-host/lsusb.txt" lsusb; fi
if have vmstat; then run_txt "$OUT/01-host/vmstat.txt" vmstat 1 5; fi
if have iostat; then run_txt "$OUT/01-host/iostat.txt" iostat -xz 1 3; fi
if have top; then run_shell "$OUT/01-host/top.txt" "COLUMNS=240 top -b -n1 | head -n 120"; fi
run_shell "$OUT/01-host/dmesg-errors.txt" "dmesg --level=err,warn 2>/dev/null | tail -n 500"

log "02/20 — ferramentas, runtimes e pacotes"
if have dpkg-query; then
  run_shell "$OUT/02-tools-packages/dpkg-all.tsv" "dpkg-query -W -f='\${Package}\t\${Version}\t\${Architecture}\t\${db:Status-Abbrev}\n' 2>/dev/null | sort"
  run_shell "$OUT/02-tools-packages/dpkg-count.txt" "dpkg-query -W -f='\${Package}\n' 2>/dev/null | wc -l"
fi
if have apt-mark; then run_txt "$OUT/02-tools-packages/apt-manual.txt" apt-mark showmanual; fi
if have snap; then run_txt "$OUT/02-tools-packages/snap-list.txt" snap list; fi
if have flatpak; then run_txt "$OUT/02-tools-packages/flatpak-list.txt" flatpak list; fi
if have python3; then run_shell "$OUT/02-tools-packages/python-packages.txt" "python3 --version; python3 -m pip list 2>/dev/null || true"; fi
if have npm; then run_shell "$OUT/02-tools-packages/npm-global.txt" "npm --version; npm -g ls --depth=0 2>/dev/null || true"; fi
if have gem; then run_shell "$OUT/02-tools-packages/gems.txt" "ruby --version 2>/dev/null || true; gem list 2>/dev/null || true"; fi
TOOLS=(bash sh systemctl journalctl ffmpeg ffprobe nginx apache2 apache2ctl caddy haproxy certbot curl wget jq yq openssl git rsync rclone socat nc ncat iperf3 samba smbd smbclient testparm mediamtx liquidsoap ffplayout icecast2 python3 pip3 node npm php java javac go rustc cargo gcc g++ clang make cmake perl ruby sqlite3 mysql psql redis-server redis-cli docker podman lsof strace tcpdump tshark dig host nslookup file exiftool inotifywait screen tmux)
printf 'tool\tpath\tversion_first_line\n' > "$OUT/19-summary/tools.tsv"
for tool in "${TOOLS[@]}"; do
  if have "$tool"; then
    path="$(command -v "$tool" 2>/dev/null || true)"
    ver="$({ timeout 4 "$tool" --version 2>&1 || timeout 4 "$tool" -version 2>&1 || timeout 4 "$tool" -V 2>&1 || true; } | head -n1 | tr '\t' ' ' | redact)"
    printf '%s\t%s\t%s\n' "$tool" "$path" "$ver" >> "$OUT/19-summary/tools.tsv"
  else
    printf '%s\tNOT_FOUND\t\n' "$tool" >> "$OUT/19-summary/tools.tsv"
  fi
done

log "03/20 — todos os serviços systemd"
run_txt "$OUT/03-services/all-services.txt" systemctl list-units --type=service --all --no-pager --plain
run_txt "$OUT/03-services/running-services.txt" systemctl list-units --type=service --state=running --no-pager --plain
run_txt "$OUT/03-services/failed-services.txt" systemctl --failed --type=service --no-pager --plain
run_txt "$OUT/03-services/all-service-files.txt" systemctl list-unit-files --type=service --no-pager --plain
run_txt "$OUT/03-services/all-sockets.txt" systemctl list-units --type=socket --all --no-pager --plain
run_txt "$OUT/03-services/all-path-units.txt" systemctl list-units --type=path --all --no-pager --plain
run_txt "$OUT/03-services/all-mount-units.txt" systemctl list-units --type=mount --all --no-pager --plain
run_txt "$OUT/03-services/all-targets.txt" systemctl list-units --type=target --all --no-pager --plain
mapfile -t SERVICE_UNITS < <(systemctl list-units --type=service --all --no-legend --plain 2>/dev/null | awk '$3=="active" || $3=="failed" || $4=="running" || $4=="exited" || $4=="failed" {print $1}' | sort -u)
mkdir -p "$OUT/03-services/details"
for unit in "${SERVICE_UNITS[@]:-}"; do
  [[ -n "$unit" ]] || continue
  bn="$(sanitize_name "$unit")"
  run_shell "$OUT/03-services/details/${bn}.show.txt" "systemctl show '$unit' -p Id -p Description -p LoadState -p ActiveState -p SubState -p UnitFileState -p MainPID -p ControlPID -p User -p Group -p WorkingDirectory -p RootDirectory -p ExecStart -p ExecStartPre -p ExecStartPost -p ExecReload -p ExecStop -p Restart -p RestartUSec -p FragmentPath -p DropInPaths -p MemoryCurrent -p MemoryMax -p CPUUsageNSec -p TasksCurrent -p TasksMax"
  run_shell "$OUT/03-services/details/${bn}.cat.txt" "systemctl cat '$unit'"
  run_shell "$OUT/03-services/details/${bn}.status.txt" "systemctl status '$unit' --no-pager --full"
done

log "04/20 — rotinas automáticas/agendamentos"
run_txt "$OUT/04-routines/systemd-timers.txt" systemctl list-timers --all --no-pager
run_shell "$OUT/04-routines/timer-files.txt" "systemctl list-unit-files --type=timer --no-pager --plain"
mkdir -p "$OUT/04-routines/timer-details"
mapfile -t TIMER_UNITS < <(systemctl list-unit-files --type=timer --no-legend --plain 2>/dev/null | awk '{print $1}' | sort -u)
for unit in "${TIMER_UNITS[@]:-}"; do
  [[ -n "$unit" ]] || continue
  bn="$(sanitize_name "$unit")"
  run_shell "$OUT/04-routines/timer-details/${bn}.cat.txt" "systemctl cat '$unit'"
  run_shell "$OUT/04-routines/timer-details/${bn}.show.txt" "systemctl show '$unit' -p Id -p LoadState -p ActiveState -p UnitFileState -p NextElapseUSecRealtime -p LastTriggerUSec -p Triggers -p FragmentPath -p DropInPaths"
done
for p in /etc/crontab /etc/anacrontab /etc/rc.local; do [[ -e "$p" ]] && safe_text "$p" "$OUT/04-routines/$(basename "$p").redacted.txt"; done
run_shell "$OUT/04-routines/cron-tree.txt" "find /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly -maxdepth 2 -type f -printf '%p\t%u:%g\t%m\t%s\t%TY-%Tm-%TdT%TH:%TM:%TS\n' 2>/dev/null | sort"
mkdir -p "$OUT/04-routines/cron-files"
while IFS= read -r f; do [[ -f "$f" ]] || continue; bn="$(echo "$f" | sed 's#^/##; s#[/]#_#g')"; safe_text "$f" "$OUT/04-routines/cron-files/${bn}.redacted.txt"; done < <(find /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly -maxdepth 2 -type f 2>/dev/null | sort)
run_shell "$OUT/04-routines/user-crontabs-list.txt" "find /var/spool/cron /var/spool/cron/crontabs -maxdepth 2 -type f -printf '%p\t%u:%g\t%m\t%s\n' 2>/dev/null | sort"
mkdir -p "$OUT/04-routines/user-crontabs"
while IFS= read -r f; do [[ -f "$f" ]] || continue; bn="$(echo "$f" | sed 's#^/##; s#[/]#_#g')"; safe_text "$f" "$OUT/04-routines/user-crontabs/${bn}.redacted.txt"; done < <(find /var/spool/cron /var/spool/cron/crontabs -maxdepth 2 -type f 2>/dev/null | sort -u)
if have atq; then run_txt "$OUT/04-routines/atq.txt" atq; fi
run_shell "$OUT/04-routines/initd-list.txt" "find /etc/init.d -maxdepth 1 -type f -printf '%f\t%u:%g\t%m\t%s\n' 2>/dev/null | sort"
run_shell "$OUT/04-routines/logrotate-list.txt" "find /etc/logrotate.d -maxdepth 1 -type f -printf '%p\t%u:%g\t%m\t%s\n' 2>/dev/null | sort"

log "05/20 — processos, CWDs, executáveis e FDs"
run_shell "$OUT/05-processes/ps-all.txt" "ps -eo user,pid,ppid,pgid,sid,ni,pri,stat,pcpu,pmem,rss,vsz,etime,lstart,args --sort=pid"
if have pstree; then run_txt "$OUT/05-processes/pstree.txt" pstree -ap; fi
printf 'pid\tuser\tcomm\texe\tcwd\troot\tfd_count\n' > "$OUT/05-processes/process-paths.tsv"
for pdir in /proc/[0-9]*; do
  pid="${pdir##*/}"; [[ -r "$pdir/status" ]] || continue
  uid="$(awk '/^Uid:/{print $2}' "$pdir/status" 2>/dev/null || true)"
  user="$(getent passwd "$uid" 2>/dev/null | cut -d: -f1 || true)"
  comm="$(cat "$pdir/comm" 2>/dev/null || true)"
  exe="$(readlink -f "$pdir/exe" 2>/dev/null || true)"
  cwd="$(readlink -f "$pdir/cwd" 2>/dev/null || true)"
  rootp="$(readlink -f "$pdir/root" 2>/dev/null || true)"
  fdc="$(find "$pdir/fd" -maxdepth 1 -type l 2>/dev/null | wc -l || true)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$pid" "$user" "$comm" "$exe" "$cwd" "$rootp" "$fdc" >> "$OUT/05-processes/process-paths.tsv"
done
run_shell "$OUT/05-processes/media-processes.txt" "ps -eo user,pid,ppid,pcpu,pmem,rss,etime,args --sort=pid | grep -Ei 'ffmpeg|ffprobe|mediamtx|nginx|smbd|tps-|studiosat-|liquidsoap|ffplayout|icecast' | grep -v grep"
if have lsof; then run_shell "$OUT/05-processes/open-media-files.txt" "lsof -nP 2>/dev/null | grep -F '$ROOT/'"; fi

log "06/20 — rede/listeners/conexões"
run_txt "$OUT/06-network/ip-br-addr.txt" ip -br addr
run_txt "$OUT/06-network/ip-route.txt" ip route
run_txt "$OUT/06-network/ip-rule.txt" ip rule
run_txt "$OUT/06-network/ss-lntup.txt" ss -lntup
run_txt "$OUT/06-network/ss-lnuap.txt" ss -lnuap
run_txt "$OUT/06-network/ss-established.txt" ss -ntup state established
run_txt "$OUT/06-network/ss-summary.txt" ss -s
run_shell "$OUT/06-network/resolv.conf.txt" "cat /etc/resolv.conf"
run_shell "$OUT/06-network/hosts.txt" "cat /etc/hosts"
run_txt "$OUT/06-network/neigh.txt" ip neigh
if [[ -r /proc/net/dev ]]; then cp /proc/net/dev "$OUT/17-speed/netdev-before.txt"; sleep 5; cp /proc/net/dev "$OUT/17-speed/netdev-after-5s.txt"; fi

log "07/20 — filesystems/diretórios relevantes"
for base in /srv /var/www /opt /usr/local /etc/nginx /etc/systemd/system; do
  if [[ -e "$base" ]]; then
    bn="$(echo "$base" | sed 's#^/##; s#/#_#g')"
    run_shell "$OUT/07-filesystems/${bn}-du.txt" "du -xhd3 '$base' 2>/dev/null | sort -h | tail -n 1000"
    run_shell "$OUT/07-filesystems/${bn}-tree.txt" "find '$base' -xdev -maxdepth 4 -printf '%y\t%p\t%u:%g\t%m\t%s\t%TY-%Tm-%TdT%TH:%TM:%TS\n' 2>/dev/null | sort"
  fi
done

log "08/20 — arquivos TPS/StudioSat/configs relevantes"
run_shell "$OUT/08-configs/tps-studiosat-files.txt" "find /etc /opt /usr/local /srv -xdev -maxdepth 7 \( -iname '*tps*' -o -iname '*studiosat*' -o -iname '*mediamtx*' \) -printf '%y\t%p\t%u:%g\t%m\t%s\t%TY-%Tm-%TdT%TH:%TM:%TS\n' 2>/dev/null | sort"
run_shell "$OUT/08-configs/usr-local-media-files.txt" "find /usr/local/bin /usr/local/sbin -maxdepth 1 -type f -printf '%p\t%u:%g\t%m\t%s\t%TY-%Tm-%TdT%TH:%TM:%TS\n' 2>/dev/null | sort"
run_shell "$OUT/08-configs/usr-local-media-hashes.txt" "find /usr/local/bin /usr/local/sbin -maxdepth 1 -type f \( -iname 'tps-*' -o -iname '*studiosat*' -o -iname '*media*' \) -print0 2>/dev/null | sort -z | xargs -0 -r sha256sum"
mkdir -p "$OUT/08-configs/scripts"
while IFS= read -r f; do [[ -f "$f" ]] || continue; bn="$(sanitize_name "${f#/}")"; sed -n '1,4000p' "$f" 2>/dev/null | redact > "$OUT/08-configs/scripts/${bn}.redacted.txt" || true; done < <(find /usr/local/bin /usr/local/sbin -maxdepth 1 -type f \( -iname 'tps-*' -o -iname '*studiosat*' -o -iname '*media*' \) 2>/dev/null | sort)

log "09/20 — NGINX, sites e domínios"
if have nginx; then
  run_txt "$OUT/09-nginx-sites/nginx-version.txt" nginx -v
  run_txt "$OUT/09-nginx-sites/nginx-test.txt" nginx -t
  { nginx -T 2>&1 || true; } | redact > "$OUT/09-nginx-sites/nginx-T.redacted.txt"
  run_shell "$OUT/09-nginx-sites/config-files.txt" "find /etc/nginx -type f -printf '%p\t%u:%g\t%m\t%s\t%TY-%Tm-%TdT%TH:%TM:%TS\n' 2>/dev/null | sort"
  run_shell "$OUT/09-nginx-sites/config-hashes.txt" "find /etc/nginx -type f -print0 2>/dev/null | sort -z | xargs -0 -r sha256sum"
  awk '/^[[:space:]]*server_name[[:space:]]+/ {for(i=2;i<=NF;i++){gsub(/;/,"",$i); if($i!="_" && $i!="") print $i}}' "$OUT/09-nginx-sites/nginx-T.redacted.txt" | grep -Ev 'REDACTED|\$' | sort -u > "$OUT/09-nginx-sites/domains.txt" || true
  grep -E '^[[:space:]]*(server_name|listen|root|alias|proxy_pass|fastcgi_pass|return[[:space:]]+30[1278]|location)[[:space:]]' "$OUT/09-nginx-sites/nginx-T.redacted.txt" > "$OUT/09-nginx-sites/routes-summary.txt" || true
else
  printf 'NGINX_NOT_FOUND\n' > "$OUT/09-nginx-sites/nginx-test.txt"; : > "$OUT/09-nginx-sites/domains.txt"
fi
if have apache2ctl; then run_shell "$OUT/09-nginx-sites/apache-vhosts.txt" "apache2ctl -S 2>&1"; fi
if have caddy; then run_shell "$OUT/09-nginx-sites/caddy-info.txt" "caddy version; systemctl cat caddy.service 2>/dev/null || true"; fi
if have haproxy; then run_shell "$OUT/09-nginx-sites/haproxy-info.txt" "haproxy -vv 2>&1 | head -n 100; cat /etc/haproxy/haproxy.cfg 2>/dev/null"; fi
cp "$OUT/09-nginx-sites/domains.txt" "$OUT/09-nginx-sites/domains-from-nginx.txt" 2>/dev/null || true
: > "$OUT/09-nginx-sites/domains-from-certbot.txt"
if have certbot; then certbot certificates 2>/dev/null | awk '/^[[:space:]]*Domains:/ {for(i=2;i<=NF;i++) print $i}' | sed 's/[[:space:]]//g' | grep -v '^$' | sort -u > "$OUT/09-nginx-sites/domains-from-certbot.txt" || true; fi
cat "$OUT/09-nginx-sites/domains-from-nginx.txt" "$OUT/09-nginx-sites/domains-from-certbot.txt" 2>/dev/null | sort -u > "$OUT/09-nginx-sites/domains.txt"
grep -E '^[A-Za-z0-9][A-Za-z0-9._-]*$' "$OUT/09-nginx-sites/domains.txt" > "$OUT/09-nginx-sites/domains-probeable.txt" || true
grep -Ev '^[A-Za-z0-9][A-Za-z0-9._-]*$' "$OUT/09-nginx-sites/domains.txt" > "$OUT/09-nginx-sites/domains-unprobeable.txt" || true

log "10/20 — DNS/TLS/HTTP(S) por domínio"
printf 'domain\tdns_a\tdns_aaaa\thttp_code\thttps_code\thttps_effective\tconnect_s\tttfb_s\ttotal_s\tspeed_Bps\tsize_B\n' > "$OUT/19-summary/domains.tsv"
mkdir -p "$OUT/10-dns-tls/domains"
while IFS= read -r domain; do
  [[ -n "$domain" ]] || continue; [[ "$domain" =~ ^[A-Za-z0-9._-]+$ ]] || continue
  ddir="$OUT/10-dns-tls/domains/$(sanitize_name "$domain")"; mkdir -p "$ddir"
  if have dig; then dig +short A "$domain" > "$ddir/dns-A.txt" 2>&1 || true; dig +short AAAA "$domain" > "$ddir/dns-AAAA.txt" 2>&1 || true; dig +short CNAME "$domain" > "$ddir/dns-CNAME.txt" 2>&1 || true; else getent ahosts "$domain" > "$ddir/getent-ahosts.txt" 2>&1 || true; : > "$ddir/dns-A.txt"; : > "$ddir/dns-AAAA.txt"; fi
  a="$(tr '\n' ',' < "$ddir/dns-A.txt" 2>/dev/null | sed 's/,$//' || true)"; aaaa="$(tr '\n' ',' < "$ddir/dns-AAAA.txt" 2>/dev/null | sed 's/,$//' || true)"
  hmeta="$(curl -sS -L -o /dev/null --max-time 12 -w '%{http_code}\t%{url_effective}\t%{time_connect}\t%{time_starttransfer}\t%{time_total}\t%{speed_download}\t%{size_download}' "http://$domain/" 2>"$ddir/http.err" || true)"
  smeta="$(curl -sS -L -o /dev/null --max-time 15 -w '%{http_code}\t%{url_effective}\t%{time_connect}\t%{time_starttransfer}\t%{time_total}\t%{speed_download}\t%{size_download}' "https://$domain/" 2>"$ddir/https.err" || true)"
  printf '%s\n' "$hmeta" > "$ddir/http-meta.tsv"; printf '%s\n' "$smeta" > "$ddir/https-meta.tsv"
  IFS=$'\t' read -r http_code http_eff http_conn http_ttfb http_total http_speed http_size <<<"$hmeta" || true
  IFS=$'\t' read -r https_code https_eff https_conn https_ttfb https_total https_speed https_size <<<"$smeta" || true
  if have openssl; then timeout 12 bash -lc "echo | openssl s_client -servername '$domain' -connect '$domain:443' 2>/dev/null | openssl x509 -noout -subject -issuer -serial -dates -ext subjectAltName" > "$ddir/tls-cert.txt" 2>&1 || true; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$domain" "$a" "$aaaa" "${http_code:-}" "${https_code:-}" "${https_eff:-}" "${https_conn:-}" "${https_ttfb:-}" "${https_total:-}" "${https_speed:-}" "${https_size:-}" >> "$OUT/19-summary/domains.tsv"
done < "$OUT/09-nginx-sites/domains-probeable.txt"

log "11/20 — MediaMTX completo"
run_shell "$OUT/11-mediamtx/unit-cat.txt" "systemctl cat tps-mediamtx.service"
run_shell "$OUT/11-mediamtx/unit-show.txt" "systemctl show tps-mediamtx.service -p Id -p ActiveState -p SubState -p MainPID -p User -p Group -p ExecStart -p ExecMainStartTimestamp -p Restart -p FragmentPath -p DropInPaths"
run_shell "$OUT/11-mediamtx/status.txt" "systemctl status tps-mediamtx.service --no-pager --full"
run_shell "$OUT/11-mediamtx/journal-1000.txt" "journalctl -u tps-mediamtx.service -n 1000 --no-pager -o short-iso"
run_shell "$OUT/11-mediamtx/process.txt" "ps -eo user,pid,ppid,pcpu,pmem,rss,etime,args | grep -i '[m]ediamtx'"
run_shell "$OUT/11-mediamtx/listeners.txt" "ss -lntup | grep -Ei 'mediamtx|:(1935|8000|8001|8189|8554|8888|8889|8890|8892|8893|9997|9998)\\b'"
run_shell "$OUT/11-mediamtx/config-candidates.txt" "find /etc /opt /usr/local -maxdepth 7 -type f \( -iname 'mediamtx.yml' -o -iname 'mediamtx.yaml' -o -iname '*mediamtx*.yml' -o -iname '*mediamtx*.yaml' \) -print 2>/dev/null | sort -u"
mkdir -p "$OUT/11-mediamtx/configs"
while IFS= read -r cfg; do [[ -f "$cfg" ]] || continue; bn="$(sanitize_name "${cfg#/}")"; sha256sum "$cfg" > "$OUT/11-mediamtx/configs/${bn}.sha256.txt" 2>/dev/null || true; cat "$cfg" 2>/dev/null | redact > "$OUT/11-mediamtx/configs/${bn}.redacted.txt" || true; done < "$OUT/11-mediamtx/config-candidates.txt"
for ep in paths/list config/global/get config/paths/list rtmpconns/list rtspconns/list rtspsessions/list hlsmuxers/list webrtcsessions/list srtconns/list; do name="$(sanitize_name "$ep")"; curl -fsS --max-time 5 "$MTX_API/$ep" 2>&1 | redact > "$OUT/11-mediamtx/api-${name}.txt" || true; done
curl -fsS --max-time 5 http://127.0.0.1:9998/metrics 2>&1 | redact > "$OUT/11-mediamtx/metrics.txt" || true

log "12/20 — Samba/ingest"
run_shell "$OUT/12-samba-ingest/services.txt" "systemctl status smbd.service nmbd.service --no-pager --full"
run_shell "$OUT/12-samba-ingest/listeners.txt" "ss -lntup | grep -E ':(137|138|139|445)\\b'"
if have testparm; then run_shell "$OUT/12-samba-ingest/testparm.txt" "testparm -s 2>&1"; fi
if have smbstatus; then run_txt "$OUT/12-samba-ingest/smbstatus.txt" smbstatus; fi
safe_text /etc/samba/smb.conf "$OUT/12-samba-ingest/smb.conf.redacted.txt"
run_shell "$OUT/12-samba-ingest/samba-shares-paths.txt" "testparm -s 2>/dev/null | grep -E '^[[:space:]]*(path|read only|guest ok|valid users|write list|force user|force group)[[:space:]]*='"

log "13/20 — emissoras, mídia, origem e playlists"
printf 'station\tdomain\tunit_state\tmain_pid\tmedia_files\tmedia_bytes\tready_files\tcanonical_files\tplaylist_exists\tmediamtx_ready\ttracks\n' > "$OUT/19-summary/stations.tsv"
for ch in "${CHANNELS[@]}"; do
  domain=radio; [[ "$ch" == tv* ]] && domain=tv
  base="$ROOT/$ch"; unit="tps-${ch}-playout.service"
  sdir="$OUT/13-stations/$ch"; mkdir -p "$sdir"/{systemd,process,filesystem,playlist,probe}
  idir="$OUT/14-media-inventory/$ch"; mkdir -p "$idir"
  pdir="$OUT/15-playlists/$ch"; mkdir -p "$pdir"
  strdir="$OUT/16-streams/$ch"; mkdir -p "$strdir"
  run_shell "$sdir/systemd/cat.txt" "systemctl cat '$unit'"
  run_shell "$sdir/systemd/show.txt" "systemctl show '$unit' -p Id -p ActiveState -p SubState -p MainPID -p User -p Group -p WorkingDirectory -p ExecStart -p ExecStartPre -p ExecMainStartTimestamp -p Restart -p RestartUSec -p FragmentPath -p DropInPaths -p MemoryCurrent -p CPUUsageNSec"
  run_shell "$sdir/systemd/status.txt" "systemctl status '$unit' --no-pager --full"
  run_shell "$sdir/systemd/journal-1000.txt" "journalctl -u '$unit' -n 1000 --no-pager -o short-iso"
  pid="$(systemctl show "$unit" -p MainPID --value 2>/dev/null || true)"; active="$(systemctl is-active "$unit" 2>/dev/null || true)"
  if [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 0 ]]; then
    tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | redact > "$sdir/process/cmdline.txt" || true
    readlink -f "/proc/$pid/cwd" > "$sdir/process/cwd.txt" 2>/dev/null || true
    readlink -f "/proc/$pid/exe" > "$sdir/process/exe.txt" 2>/dev/null || true
    run_shell "$sdir/process/tree.txt" "ps -eo pid,ppid,user,pcpu,pmem,rss,etime,args --forest | grep -E '(^[[:space:]]*PID|[[:space:]]$pid[[:space:]]|tps-$ch|$ch)'"
    if have lsof; then run_shell "$sdir/process/lsof.txt" "lsof -nP -p '$pid'"; fi
    run_shell "$sdir/process/fds.txt" "for f in /proc/$pid/fd/*; do printf '%s -> ' \"\$f\"; readlink \"\$f\" 2>/dev/null || true; done"
  fi
  if [[ -d "$base" ]]; then
    run_shell "$sdir/filesystem/tree-depth4.txt" "find '$base' -maxdepth 4 -printf '%y\t%p\t%u:%g\t%m\t%s\t%i\t%n\t%TY-%Tm-%TdT%TH:%TM:%TS\n' 2>/dev/null | sort"
    run_shell "$sdir/filesystem/du.txt" "du -ah '$base' 2>/dev/null | sort -h"
    run_shell "$sdir/filesystem/symlinks.txt" "find '$base' -type l -printf '%p -> %l\n' 2>/dev/null | sort"
    run_shell "$sdir/filesystem/hardlinks.txt" "find '$base' -type f -links +1 -printf '%i\t%n\t%p\n' 2>/dev/null | sort"
    run_shell "$sdir/filesystem/permissions.txt" "namei -l '$base' 2>/dev/null || true"
  else
    printf 'MISSING_MEDIA_ROOT=%s\n' "$base" > "$sdir/filesystem/MISSING.txt"
  fi
  printf 'path\tbytes\text\tmime\tmtime\tinode\tlinks\tformat_name\tduration_s\tbit_rate\ta_codec\ta_rate\ta_channels\tv_codec\twidth\theight\tpix_fmt\tr_frame_rate\tavg_frame_rate\n' > "$idir/media.tsv"
  while IFS= read -r -d '' f; do
    size="$(stat -c %s "$f" 2>/dev/null || echo 0)"; ext="${f##*.}"; [[ "$f" == "$ext" ]] && ext=""
    mime="$(file -b --mime-type "$f" 2>/dev/null || true)"; mtime="$(stat -c %y "$f" 2>/dev/null || true)"; inode="$(stat -c %i "$f" 2>/dev/null || true)"; links="$(stat -c %h "$f" 2>/dev/null || true)"
    probe="$(timeout 15 ffprobe -v error -show_entries format=format_name,duration,bit_rate -show_entries stream=codec_type,codec_name,sample_rate,channels,width,height,pix_fmt,r_frame_rate,avg_frame_rate -of json "$f" 2>/dev/null || true)"
    format_name="$(jq -r '.format.format_name // ""' <<<"$probe" 2>/dev/null || true)"; duration="$(jq -r '.format.duration // ""' <<<"$probe" 2>/dev/null || true)"; br="$(jq -r '.format.bit_rate // ""' <<<"$probe" 2>/dev/null || true)"
    ac="$(jq -r '[.streams[]? | select(.codec_type=="audio") | .codec_name][0] // ""' <<<"$probe" 2>/dev/null || true)"; ar="$(jq -r '[.streams[]? | select(.codec_type=="audio") | .sample_rate][0] // ""' <<<"$probe" 2>/dev/null || true)"; ach="$(jq -r '[.streams[]? | select(.codec_type=="audio") | .channels][0] // ""' <<<"$probe" 2>/dev/null || true)"
    vc="$(jq -r '[.streams[]? | select(.codec_type=="video") | .codec_name][0] // ""' <<<"$probe" 2>/dev/null || true)"; vw="$(jq -r '[.streams[]? | select(.codec_type=="video") | .width][0] // ""' <<<"$probe" 2>/dev/null || true)"; vh="$(jq -r '[.streams[]? | select(.codec_type=="video") | .height][0] // ""' <<<"$probe" 2>/dev/null || true)"; pix="$(jq -r '[.streams[]? | select(.codec_type=="video") | .pix_fmt][0] // ""' <<<"$probe" 2>/dev/null || true)"; rfr="$(jq -r '[.streams[]? | select(.codec_type=="video") | .r_frame_rate][0] // ""' <<<"$probe" 2>/dev/null || true)"; afr="$(jq -r '[.streams[]? | select(.codec_type=="video") | .avg_frame_rate][0] // ""' <<<"$probe" 2>/dev/null || true)"
    rel="${f#$base/}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$rel" "$size" "$ext" "$mime" "$mtime" "$inode" "$links" "$format_name" "$duration" "$br" "$ac" "$ar" "$ach" "$vc" "$vw" "$vh" "$pix" "$rfr" "$afr" >> "$idir/media.tsv"
  done < <(find "$base" -type f \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.mp4' -o -iname '*.aac' -o -iname '*.wav' -o -iname '*.flac' -o -iname '*.ogg' -o -iname '*.oga' -o -iname '*.webm' -o -iname '*.mkv' -o -iname '*.mov' -o -iname '*.ts' -o -iname '*.m2ts' -o -iname '*.avi' -o -iname '*.m3u8' \) -print0 2>/dev/null)
  awk -F'\t' 'NR>1{ext[$3]++; bytes[$3]+=$2} END{for(e in ext) printf "%s\t%d\t%.0f\n",e,ext[e],bytes[e]}' "$idir/media.tsv" | sort > "$idir/by-extension.tsv"
  awk -F'\t' 'NR>1{fmt[$8]++} END{for(f in fmt) printf "%s\t%d\n",f,fmt[f]}' "$idir/media.tsv" | sort > "$idir/by-format.tsv"
  run_shell "$idir/count-by-topdir.txt" "find '$base' -type f 2>/dev/null | sed 's#^$base/##' | awk -F/ '{c[\$1]++} END{for(k in c) print k,c[k]}' | sort"
  playlist="$base/playlists/playlist.txt"
  if [[ -f "$playlist" ]]; then
    sha256sum "$playlist" > "$pdir/playlist.sha256.txt" 2>/dev/null || true; stat "$playlist" > "$pdir/playlist.stat.txt" 2>/dev/null || true; cat "$playlist" | redact > "$pdir/playlist.current.redacted.txt" 2>/dev/null || true
    awk '/^[[:space:]]*file[[:space:]]+/ {line=$0; sub(/^[[:space:]]*file[[:space:]]+/,"",line); gsub(/^\047|\047$/,"",line); gsub(/^\"|\"$/,"",line); print line}' "$playlist" > "$pdir/references.txt" 2>/dev/null || true
    : > "$pdir/references-status.tsv"
    while IFS= read -r ref; do [[ -n "$ref" ]] || continue; if [[ -e "$ref" ]]; then printf 'OK\t%s\t%s\t%s\n' "$(stat -c %s "$ref" 2>/dev/null || true)" "$(file -b --mime-type "$ref" 2>/dev/null || true)" "$ref" >> "$pdir/references-status.tsv"; else printf 'MISSING\t0\t\t%s\n' "$ref" >> "$pdir/references-status.tsv"; fi; done < "$pdir/references.txt"
  else
    printf 'PLAYLIST_MISSING=%s\n' "$playlist" > "$pdir/playlist-missing.txt"
  fi
  media_files="$(awk 'END{print NR-1}' "$idir/media.tsv" 2>/dev/null || echo 0)"; media_bytes="$(awk -F'\t' 'NR>1{s+=$2} END{printf "%.0f",s+0}' "$idir/media.tsv" 2>/dev/null || echo 0)"
  ready_files="$(find "$base/ready" -maxdepth 1 -type f 2>/dev/null | wc -l || true)"; canonical_files="$(find "$base/canonical" -maxdepth 1 -type f 2>/dev/null | wc -l || true)"; playlist_exists=no; [[ -f "$playlist" ]] && playlist_exists=yes
  mitem="$(curl -fsS --max-time 5 "$MTX_API/paths/list" 2>/dev/null | jq -c --arg ch "$ch" '.items[]? | select(.name==$ch)' | head -n1 || true)"; printf '%s\n' "$mitem" > "$strdir/mediamtx-path.json"
  mready="$(jq -r '.ready // false' <<<"$mitem" 2>/dev/null || echo false)"; tracks="$(jq -r '[.tracks[]?] | join("+")' <<<"$mitem" 2>/dev/null || true)"
  hls="http://127.0.0.1:8888/$ch/index.m3u8"
  hmeta="$(curl -sS -L -o "$strdir/hls-master.m3u8" --max-time 12 -w '%{http_code}\t%{url_effective}\t%{time_connect}\t%{time_starttransfer}\t%{time_total}\t%{speed_download}\t%{size_download}' "$hls" 2>"$strdir/hls.err" || true)"; printf '%s\n' "$hmeta" > "$strdir/hls-master-meta.tsv"
  if [[ -s "$strdir/hls-master.m3u8" ]]; then
    sleep 4; curl -sS -L -o "$strdir/hls-master-after4s.m3u8" --max-time 12 "$hls" 2>/dev/null || true
    if cmp -s "$strdir/hls-master.m3u8" "$strdir/hls-master-after4s.m3u8"; then printf 'UNCHANGED_4S\n' > "$strdir/hls-freshness.txt"; else printf 'CHANGING\n' > "$strdir/hls-freshness.txt"; fi
    first="$(grep -Ev '^#|^[[:space:]]*$' "$strdir/hls-master.m3u8" | head -n1 || true)"
    if [[ "$first" == *.m3u8* ]]; then baseurl="${hls%/*}/"; curl -sS -L --max-time 12 "${baseurl}${first}" -o "$strdir/hls-media.m3u8" 2>"$strdir/hls-media.err" || true; else cp "$strdir/hls-master.m3u8" "$strdir/hls-media.m3u8" 2>/dev/null || true; fi
    seg="$(grep -Ev '^#|^[[:space:]]*$' "$strdir/hls-media.m3u8" 2>/dev/null | head -n1 || true)"
    if [[ -n "$seg" ]]; then mediaurl="${hls%/*}/$seg"; smeta="$(curl -sS -L -o /dev/null --max-time 20 -w '%{http_code}\t%{url_effective}\t%{time_connect}\t%{time_starttransfer}\t%{time_total}\t%{speed_download}\t%{size_download}' "$mediaurl" 2>"$strdir/hls-segment.err" || true)"; printf '%s\n' "$smeta" > "$strdir/hls-segment-meta.tsv"; fi
  fi
  timeout 15 ffprobe -v error -show_entries format=format_name,duration,bit_rate -show_entries stream=index,codec_type,codec_name,sample_rate,channels,width,height,pix_fmt,r_frame_rate,avg_frame_rate -of json "$hls" > "$strdir/ffprobe-hls.json" 2>"$strdir/ffprobe-hls.err" || true
  timeout 12 ffprobe -v error -rtsp_transport tcp -show_entries format=format_name -show_entries stream=index,codec_type,codec_name,sample_rate,channels,width,height -of json "rtsp://127.0.0.1:8554/$ch" > "$strdir/ffprobe-rtsp.json" 2>"$strdir/ffprobe-rtsp.err" || true
  timeout 12 ffprobe -v error -show_entries format=format_name -show_entries stream=index,codec_type,codec_name,sample_rate,channels,width,height -of json "rtmp://127.0.0.1:1935/$ch" > "$strdir/ffprobe-rtmp.json" 2>"$strdir/ffprobe-rtmp.err" || true
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ch" "$domain" "$active" "${pid:-0}" "$media_files" "$media_bytes" "$ready_files" "$canonical_files" "$playlist_exists" "$mready" "$tracks" >> "$OUT/19-summary/stations.tsv"
done

log "16/20 — endpoints públicos das emissoras"
declare -A ROOT_DOMAINS
ROOT_DOMAINS[radioprincipal]="radio.studiosatweb.com.br radioprincipal.studiosatweb.com.br www.radioprincipal.studiosatweb.com.br"
ROOT_DOMAINS[radiopop]="radiopop.studiosatweb.com.br www.radiopop.studiosatweb.com.br"
ROOT_DOMAINS[radiorock]="radiorock.studiosatweb.com.br www.radiorock.studiosatweb.com.br"
ROOT_DOMAINS[radioclassicas]="radioclassicas.studiosatweb.com.br www.radioclassicas.studiosatweb.com.br"
ROOT_DOMAINS[radiocountry]="radiocountry.studiosatweb.com.br www.radiocountry.studiosatweb.com.br"
ROOT_DOMAINS[tvkids]="tvkids.studiosatweb.com.br www.tvkids.studiosatweb.com.br tvkidsweb.studiosatweb.com.br www.tvkidsweb.studiosatweb.com.br"
ROOT_DOMAINS[tvteens]="tvteens.studiosatweb.com.br www.tvteens.studiosatweb.com.br"
ROOT_DOMAINS[tvviva]="tvviva.studiosatweb.com.br www.tvviva.studiosatweb.com.br"
ROOT_DOMAINS[tvmaisjovem]="tvmaisjovem.studiosatweb.com.br www.tvmaisjovem.studiosatweb.com.br"
printf 'station\tdomain\turl\thttp_code\teffective\tconnect_s\tttfb_s\ttotal_s\tspeed_Bps\tsize_B\n' > "$OUT/19-summary/public-station-endpoints.tsv"
for ch in "${CHANNELS[@]}"; do
  while IFS= read -r domain; do
    [[ -n "$domain" ]] || continue
    for url in "https://$domain/" "https://$domain/$ch/index.m3u8" "https://$domain/hls/$ch/index.m3u8"; do
      meta="$(curl -sS -L -o /dev/null --max-time 15 -w '%{http_code}\t%{url_effective}\t%{time_connect}\t%{time_starttransfer}\t%{time_total}\t%{speed_download}\t%{size_download}' "$url" 2>/dev/null || true)"
      IFS=$'\t' read -r code eff conn ttfb total speed size <<<"$meta" || true
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ch" "$domain" "$url" "${code:-}" "${eff:-}" "${conn:-}" "${ttfb:-}" "${total:-}" "${speed:-}" "${size:-}" >> "$OUT/19-summary/public-station-endpoints.tsv"
    done
  done < <(printf '%s\n' "${ROOT_DOMAINS[$ch]}" | tr ' ' '\n')
done

log "17/20 — métricas de velocidade"
python3 - "$OUT/17-speed/netdev-before.txt" "$OUT/17-speed/netdev-after-5s.txt" > "$OUT/17-speed/netdev-delta-5s.tsv" 2>/dev/null <<'PY' || true
import sys
def parse(p):
    d={}
    try:
        for line in open(p):
            if ':' not in line: continue
            iface,rest=line.split(':',1); vals=rest.split()
            if len(vals)>=9: d[iface.strip()]=(int(vals[0]),int(vals[8]))
    except Exception: pass
    return d
b=parse(sys.argv[1]); a=parse(sys.argv[2])
print('iface\trx_B_5s\ttx_B_5s\trx_Bps\ttx_Bps')
for k in sorted(set(b)|set(a)):
    rb,tb=b.get(k,(0,0)); ra,ta=a.get(k,(0,0))
    print(f'{k}\t{max(0,ra-rb)}\t{max(0,ta-tb)}\t{max(0,ra-rb)/5:.1f}\t{max(0,ta-tb)/5:.1f}')
PY
{
  printf 'station\thttp\teffective\tconnect_s\tttfb_s\ttotal_s\tspeed_Bps\tsize_B\n'
  for ch in "${CHANNELS[@]}"; do f="$OUT/16-streams/$ch/hls-segment-meta.tsv"; if [[ -s "$f" ]]; then printf '%s\t' "$ch"; cat "$f"; else printf '%s\tNO_SEGMENT\n' "$ch"; fi; done
} > "$OUT/17-speed/hls-segment-speeds.tsv"

log "18/20 — segurança local"
if have ufw; then run_txt "$OUT/18-security/ufw.txt" ufw status verbose; fi
if have nft; then run_txt "$OUT/18-security/nft.txt" nft list ruleset; fi
if have iptables; then run_txt "$OUT/18-security/iptables.txt" iptables -S; fi
run_shell "$OUT/18-security/users.txt" "getent passwd"
run_shell "$OUT/18-security/groups.txt" "getent group"
run_shell "$OUT/18-security/sudoers-files.txt" "find /etc/sudoers /etc/sudoers.d -maxdepth 2 -type f -printf '%p\t%u:%g\t%m\t%s\n' 2>/dev/null | sort"
run_shell "$OUT/18-security/world-writable-relevant.txt" "find /srv /var/www /usr/local /etc/nginx /etc/systemd/system -xdev -type f -perm -0002 -printf '%p\t%u:%g\t%m\t%s\n' 2>/dev/null | head -n 5000"
run_shell "$OUT/18-security/suid-sgid-relevant.txt" "find /usr/local /srv /var/www -xdev -type f \( -perm -4000 -o -perm -2000 \) -printf '%p\t%u:%g\t%m\t%s\n' 2>/dev/null | head -n 5000"

log "19/20 — resumos"
run_shell "$OUT/19-summary/file-extension-global.tsv" "find '$ROOT' -type f 2>/dev/null | awk -F. 'NF>1{e=tolower(\$NF); c[e]++} END{for(e in c) print e,c[e]}' | sort"
{ for ch in "${CHANNELS[@]}"; do [[ -d "$ROOT/$ch" ]] && du -sb "$ROOT/$ch" 2>/dev/null || true; done; } > "$OUT/19-summary/channel-sizes.tsv"
run_shell "$OUT/19-summary/active-service-count.txt" "systemctl list-units --type=service --state=running --no-legend | wc -l"
run_shell "$OUT/19-summary/failed-service-count.txt" "systemctl --failed --type=service --no-legend | wc -l"
run_shell "$OUT/19-summary/domain-count.txt" "wc -l < '$OUT/09-nginx-sites/domains.txt'"
run_shell "$OUT/19-summary/listener-count.txt" "ss -lntupH | wc -l"

log "20/20 — integridade e empacotamento"
{
  echo "RAYX_VERSION=$VERSION"; echo "HOST=$HOST"; echo "UTC=$STAMP"; echo "ROOT=$ROOT"; echo "CHANNELS=${CHANNELS[*]}"; echo "READ_ONLY=YES"; echo "NO_CONTAINERS=YES"; echo "NO_SERVICE_RESTART=YES"; echo "MEDIA_INVENTORY=ALL_MATCHING_FILES"; echo "DOMAINS_DISCOVERY=NGINX_AND_CERTBOT"; echo "OUTPUT_PROBES=HLS_RTSP_RTMP_BOUNDED"
} > "$OUT/20-final/SUMMARY.txt"
find "$OUT" -type f ! -path "$OUT/20-final/MANIFEST.sha256" -print0 | sort -z | xargs -0 sha256sum > "$OUT/20-final/MANIFEST.sha256"
(cd /tmp && tar -czf "$ARCHIVE" "$(basename "$OUT")")
sha256sum "$ARCHIVE" > "$ARCHIVE.sha256"
chmod 0600 "$ARCHIVE" "$ARCHIVE.sha256"
cat <<EOF2

FULL_RAYX_COMPLETE=YES
RAYX_VERSION=$VERSION
READ_ONLY=YES
OUTPUT_DIR=$OUT
ARCHIVE=$ARCHIVE
ARCHIVE_SHA256=$ARCHIVE.sha256

VALIDATE:
sha256sum -c "$ARCHIVE.sha256"

NÃO publique o pacote bruto em GitHub público. Envie o .tar.gz e .sha256 para análise privada.
EOF2
