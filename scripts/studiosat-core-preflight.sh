#!/usr/bin/env bash
# StudioSat Web Core Preflight v1.0
# Somente leitura sobre a producao. O unico efeito e criar arquivos de diagnostico em /tmp.
# Nao instala, nao reinicia, nao recarrega, nao move midia e nao altera configuracoes.

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="1.0"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
HOST="$(hostname -s 2>/dev/null || hostname)"
OUT="/tmp/studiosat-core-preflight-${HOST}-${STAMP}"
ARCHIVE="${OUT}.tar.gz"

CHANNELS=(
  radioprincipal radiopop radiorock radioclassicas radiocountry
  tvkids tvteens tvviva tvmaisjovem
)

mkdir -p "$OUT"/{system,systemd,network,mediamtx,nginx,tls,channels,media,logs,web,security,summary}
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

run_txt(){
  local dst="$1"; shift
  { "$@" 2>&1 || true; } | redact > "$dst"
}

run_shell(){
  local dst="$1"; shift
  { bash -lc "$*" 2>&1 || true; } | redact > "$dst"
}

section(){ log "$*"; }

section "StudioSat Core Preflight v${VERSION}: iniciando coleta somente leitura em ${HOST}"
cat > "$OUT/README.txt" <<README
StudioSat Web Core Preflight v${VERSION}
Host: ${HOST}
UTC: ${STAMP}

ESCOPO
- 5 radios: radioprincipal, radiopop, radiorock, radioclassicas, radiocountry
- 4 TVs: tvkids, tvteens, tvviva, tvmaisjovem
- Core compartilhado: systemd, MediaMTX, NGINX, TLS, listeners, processos, paths, HLS e arvore de midia

GARANTIA OPERACIONAL
Este script foi desenhado para somente leitura sobre a producao.
Ele NAO executa apt, systemctl start/stop/restart/reload/enable/disable,
nginx reload, edicao de arquivos, mv/rm/chmod/chown em configuracao ou midia.
O unico efeito esperado e criar este diretorio em /tmp e um tar.gz ao final.

SEGREDOS
Saidas textuais passam por redacao de padroes comuns de senha/token/stream-key.
Ainda assim, trate o pacote como documento tecnico interno.
README

section "Coletando baseline do host"
run_txt "$OUT/system/date.txt" date -u
run_txt "$OUT/system/hostnamectl.txt" hostnamectl
run_txt "$OUT/system/uname.txt" uname -a
[[ -r /etc/os-release ]] && cp /etc/os-release "$OUT/system/os-release.txt" || true
run_txt "$OUT/system/uptime.txt" uptime
run_txt "$OUT/system/free.txt" free -h
run_txt "$OUT/system/df.txt" df -hT
run_txt "$OUT/system/lsblk.txt" lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINTS
run_txt "$OUT/system/nproc.txt" nproc
run_txt "$OUT/system/lscpu.txt" lscpu
run_txt "$OUT/system/load-proc.txt" cat /proc/loadavg
run_txt "$OUT/system/meminfo-selected.txt" bash -lc "grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo"
run_txt "$OUT/system/ipcs.txt" ipcs -u

for cmd in ffmpeg ffprobe nginx certbot curl jq docker liquidsoap icecast2 ffplayout mediamtx; do
  if have "$cmd"; then
    run_shell "$OUT/system/version-${cmd}.txt" "command -v '$cmd'; '$cmd' --version 2>&1 | head -n 20"
  else
    printf 'NOT_FOUND\n' > "$OUT/system/version-${cmd}.txt"
  fi
done

if have dpkg-query; then
  run_shell "$OUT/system/packages-media.txt" "dpkg-query -W -f='\${Package}\t\${Version}\n' 2>/dev/null | grep -Ei 'ffmpeg|nginx|mediamtx|liquidsoap|icecast|docker|certbot|ffplayout|gstreamer' | sort"
fi

section "Mapeando processos e servicos dos nove canais"
run_shell "$OUT/system/processes-media.txt" "ps -eo user,pid,ppid,ni,pcpu,pmem,etime,args --sort=pid | grep -Ei 'ffmpeg|mediamtx|nginx|liquidsoap|icecast|ffplayout|tps-|studiosat-' | grep -v grep"
run_shell "$OUT/systemd/media-units-all.txt" "systemctl list-units --type=service --all --no-pager --plain | grep -Ei 'tps|studio|radio|tv|mediamtx|nginx|liquidsoap|icecast|ffplayout'"
run_shell "$OUT/systemd/media-unit-files.txt" "systemctl list-unit-files --type=service --no-pager | grep -Ei 'tps|studio|radio|tv|mediamtx|nginx|liquidsoap|icecast|ffplayout'"
run_txt "$OUT/systemd/timers-all.txt" systemctl list-timers --all --no-pager
run_shell "$OUT/systemd/slices.txt" "systemctl list-units --type=slice --all --no-pager | grep -Ei 'tps|media|radio|tv'"

printf 'channel\tdomain\texpected_unit\tload_state\tactive_state\tsub_state\tmain_pid\texec_start\n' > "$OUT/summary/channels.tsv"

for ch in "${CHANNELS[@]}"; do
  domain="radio"; [[ "$ch" == tv* ]] && domain="tv"
  cdir="$OUT/channels/$ch"; mkdir -p "$cdir"
  expected="tps-${ch}-playout.service"
  unit=""
  if systemctl cat "$expected" >/dev/null 2>&1; then
    unit="$expected"
  else
    unit="$(systemctl list-unit-files --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -Ei "(${ch}).*(playout|radio|tv)|((playout|radio|tv).*)${ch}" | head -n1 || true)"
  fi

  if [[ -n "$unit" ]]; then
    run_shell "$cdir/unit-cat.txt" "systemctl cat '$unit'"
    run_shell "$cdir/unit-show.txt" "systemctl show '$unit' -p Id -p Names -p LoadState -p ActiveState -p SubState -p MainPID -p User -p Group -p ExecStart -p ExecStartPre -p Restart -p RestartUSec -p MemoryCurrent -p MemoryMax -p CPUUsageNSec -p CPUQuotaPerSecUSec -p FragmentPath -p DropInPaths"
    run_shell "$cdir/status.txt" "systemctl status '$unit' --no-pager --full"
    run_shell "$cdir/journal-200.txt" "journalctl -u '$unit' -n 200 --no-pager -o short-iso"
    load="$(systemctl show "$unit" -p LoadState --value 2>/dev/null || true)"
    active="$(systemctl show "$unit" -p ActiveState --value 2>/dev/null || true)"
    sub="$(systemctl show "$unit" -p SubState --value 2>/dev/null || true)"
    pid="$(systemctl show "$unit" -p MainPID --value 2>/dev/null || true)"
    execs="$(systemctl show "$unit" -p ExecStart --value 2>/dev/null | tr '\t\n' '  ' | redact || true)"
  else
    printf 'UNIT_NOT_FOUND\n' > "$cdir/unit-cat.txt"
    load="not-found"; active="unknown"; sub="unknown"; pid="0"; execs=""
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ch" "$domain" "${unit:-$expected}" "$load" "$active" "$sub" "$pid" "$execs" >> "$OUT/summary/channels.tsv"
done

run_shell "$OUT/systemd/systemd-config-tree.txt" "find /etc/systemd/system -maxdepth 3 -type f \( -iname '*tps*' -o -iname '*studio*' -o -iname '*media*' -o -iname '*radio*' -o -iname '*tv*' \) -print | sort"
run_shell "$OUT/systemd/systemd-dependency-mediamtx.txt" "systemctl list-dependencies mediamtx.service --all --no-pager"
run_shell "$OUT/systemd/systemd-reverse-mediamtx.txt" "systemctl list-dependencies mediamtx.service --reverse --all --no-pager"
run_shell "$OUT/system/tps-scripts-list.txt" "find /usr/local/sbin /usr/local/bin -maxdepth 1 -type f \( -iname 'tps-*' -o -iname '*studiosat*' \) -printf '%p\t%u:%g\t%m\t%s bytes\t%TY-%Tm-%Td %TH:%TM:%TS\n' 2>/dev/null | sort"

while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  bn="$(basename "$f" | tr -c 'A-Za-z0-9._-' '_')"
  { sed -n '1,1200p' "$f" 2>/dev/null || true; } | redact > "$OUT/system/script-${bn}.txt"
done < <(find /usr/local/sbin /usr/local/bin -maxdepth 1 -type f \( -name 'tps-*' -o -name '*studiosat*' \) 2>/dev/null | sort)

section "Coletando listeners, rotas e firewall em modo leitura"
run_txt "$OUT/network/ss-lntup.txt" ss -lntup
run_txt "$OUT/network/ss-lnuap.txt" ss -lnuap
run_txt "$OUT/network/ip-addr.txt" ip -br addr
run_txt "$OUT/network/ip-route.txt" ip route
run_txt "$OUT/network/resolv.conf.txt" cat /etc/resolv.conf
if have ufw; then run_txt "$OUT/security/ufw-status.txt" ufw status verbose; fi
if have iptables; then run_txt "$OUT/security/iptables-filter.txt" iptables -S; fi
if have nft; then run_txt "$OUT/security/nft-ruleset.txt" nft list ruleset; fi

section "Mapeando MediaMTX sem alterar configuracao"
run_shell "$OUT/mediamtx/process.txt" "ps -eo user,pid,ppid,etime,args | grep -i '[m]ediamtx'"
run_shell "$OUT/mediamtx/listeners.txt" "ss -lntup | grep -E ':(1935|8000|8001|8189|8554|8888|8889|8890|8892|8893|9997|9998)\\b'"
run_shell "$OUT/mediamtx/config-candidates.txt" "find /etc /opt /usr/local -maxdepth 5 -type f \( -iname 'mediamtx.yml' -o -iname 'mediamtx.yaml' -o -iname '*mediamtx*.yml' -o -iname '*mediamtx*.yaml' \) -print 2>/dev/null | sort -u"
while IFS= read -r cfg; do
  [[ -f "$cfg" ]] || continue
  bn="$(printf '%s' "$cfg" | sed 's#^/##; s#[/ ]#_#g')"
  { cat "$cfg" 2>/dev/null || true; } | redact > "$OUT/mediamtx/config-${bn}.redacted.txt"
done < "$OUT/mediamtx/config-candidates.txt"

if have curl; then
  for endpoint in 'http://127.0.0.1:9997/v3/paths/list' 'http://127.0.0.1:9997/v3/config/global/get' 'http://127.0.0.1:9997/v3/config/paths/list' 'http://127.0.0.1:9998/metrics'; do
    name="$(echo "$endpoint" | sed -E 's#https?://##; s#[/:?&=]#_#g')"
    { curl -fsS --max-time 4 "$endpoint" 2>&1 || true; } | redact > "$OUT/mediamtx/api-${name}.txt"
  done
fi

section "Mapeando NGINX e identidade publica"
if have nginx; then
  run_txt "$OUT/nginx/nginx-t.txt" nginx -t
  { nginx -T 2>&1 || true; } | redact > "$OUT/nginx/nginx-T.redacted.txt"
  run_shell "$OUT/nginx/server-names.txt" "nginx -T 2>&1 | grep -E '^[[:space:]]*server_name[[:space:]]+' | sed 's/#.*//' | sort -u"
  run_shell "$OUT/nginx/proxy-pass.txt" "nginx -T 2>&1 | grep -E '^[[:space:]]*(proxy_pass|return 30[1278]|location|server_name|listen)[[:space:]]'"
else
  printf 'NGINX_NOT_FOUND\n' > "$OUT/nginx/nginx-t.txt"
fi

section "Mapeando TLS e renovacao"
if have certbot; then
  run_txt "$OUT/tls/certbot-certificates.txt" certbot certificates
  run_txt "$OUT/tls/certbot-renew-dry-run-NOT_EXECUTED.txt" printf '%s\n' 'NOT_EXECUTED: dry-run pode fazer conexoes e renovacoes simuladas; executar apenas em fase autorizada.'
else
  printf 'CERTBOT_NOT_FOUND\n' > "$OUT/tls/certbot-certificates.txt"
fi
run_shell "$OUT/tls/certbot-unit-files.txt" "systemctl list-unit-files --no-pager | grep -i certbot"
run_shell "$OUT/tls/certbot-timers.txt" "systemctl list-timers --all --no-pager | grep -i certbot"
run_shell "$OUT/tls/letsencrypt-tree.txt" "find /etc/letsencrypt -maxdepth 3 -type f -printf '%p\t%TY-%Tm-%Td %TH:%TM:%TS\n' 2>/dev/null | sort"

section "Inventariando repositorio dos nove canais sem modificar arquivos"
ROOT="/srv/tpsmedia/repository/channels"
if [[ -d "$ROOT" ]]; then
  run_shell "$OUT/media/channel-dirs.txt" "find '$ROOT' -maxdepth 2 -mindepth 1 -type d -printf '%p\n' | sort"
  for ch in "${CHANNELS[@]}"; do
    cdir="$OUT/channels/$ch"
    base="$ROOT/$ch"
    if [[ -d "$base" ]]; then
      run_shell "$cdir/media-tree.txt" "find '$base' -maxdepth 2 -type d -printf '%p\n' | sort"
      {
        for d in ready canonical incoming quarantine archive playlists state logs; do
          p="$base/$d"
          if [[ -d "$p" ]]; then
            printf '%s\t' "$d"
            find "$p" -maxdepth 1 -type f 2>/dev/null | wc -l
          fi
        done
      } > "$cdir/media-counts.txt"
      run_shell "$cdir/media-du.txt" "du -sh '$base' '$base'/* 2>/dev/null | sort -h"
      run_shell "$cdir/media-files-sample.txt" "find '$base' -maxdepth 2 -type f -printf '%p\t%s\t%TY-%Tm-%Td %TH:%TM:%TS\n' 2>/dev/null | sort | head -n 250"
      run_shell "$cdir/playlists.txt" "find '$base' -maxdepth 3 -type f \( -iname '*.txt' -o -iname '*.ffconcat' -o -iname '*.m3u' -o -iname '*.m3u8' -o -iname '*.json' \) -print 2>/dev/null | sort"
      if have ffprobe; then
        mapfile -t samples < <(find "$base/canonical" "$base/ready" -maxdepth 1 -type f 2>/dev/null | head -n 3 || true)
        idx=0
        for f in "${samples[@]:-}"; do
          [[ -f "$f" ]] || continue
          idx=$((idx+1))
          { timeout 8 ffprobe -v error -show_entries stream=index,codec_type,codec_name,profile,width,height,pix_fmt,r_frame_rate,avg_frame_rate,time_base,sample_rate,channels,channel_layout,disposition -show_entries format=format_name,duration,start_time,bit_rate -of json "$f" 2>&1 || true; } | redact > "$cdir/ffprobe-file-${idx}.json"
          printf '%s\n' "$f" > "$cdir/ffprobe-file-${idx}.path.txt"
        done
      fi
    else
      printf 'CHANNEL_DIRECTORY_NOT_FOUND: %s\n' "$base" > "$cdir/media-tree.txt"
    fi
  done
else
  printf 'ROOT_NOT_FOUND: %s\n' "$ROOT" > "$OUT/media/channel-dirs.txt"
fi

section "Testando de forma passiva os streams locais atuais"
printf 'channel\trtmp_probe\thls_http\thls_fresh\n' > "$OUT/summary/streams.tsv"
for ch in "${CHANNELS[@]}"; do
  cdir="$OUT/channels/$ch"
  rtmp="SKIP"; hls="SKIP"; fresh="SKIP"
  if have ffprobe; then
    if timeout 6 ffprobe -v error -rw_timeout 4000000 -show_entries stream=codec_type,codec_name,width,height,r_frame_rate,sample_rate,channels -of compact=p=0:nk=1 "rtmp://127.0.0.1:1935/$ch" > "$cdir/rtmp-ffprobe.txt" 2>&1; then
      rtmp="PASS"
    else
      rtmp="FAIL"
      redact < "$cdir/rtmp-ffprobe.txt" > "$cdir/rtmp-ffprobe.redacted.txt" || true
      mv -f "$cdir/rtmp-ffprobe.redacted.txt" "$cdir/rtmp-ffprobe.txt" 2>/dev/null || true
    fi
  fi
  if have curl; then
    manifest="http://127.0.0.1:8888/$ch/index.m3u8"
    code="$(curl -sS -o "$cdir/hls-index.m3u8" -w '%{http_code}' --max-time 5 "$manifest" 2>"$cdir/hls-curl.err" || true)"
    [[ "$code" == "200" ]] && hls="PASS" || hls="FAIL:${code:-000}"
    if [[ -s "$cdir/hls-index.m3u8" ]]; then
      sleep 2
      second="$cdir/hls-index-2.m3u8"
      curl -fsS --max-time 5 "$manifest" > "$second" 2>/dev/null || true
      if ! cmp -s "$cdir/hls-index.m3u8" "$second"; then fresh="CHANGING"; else fresh="UNCHANGED_2S"; fi
    fi
  fi
  printf '%s\t%s\t%s\t%s\n' "$ch" "$rtmp" "$hls" "$fresh" >> "$OUT/summary/streams.tsv"
done

section "Registrando endpoints publicos conhecidos sem alterar DNS"
cat > "$OUT/web/known-endpoints.txt" <<'ENDPOINTS'
https://www.radio.studiosatweb.com.br
https://radio.studiosatweb.com.br
https://www.tvkids.studiosatweb.com.br
https://www.tvkidsweb.studiosatweb.com.br
ENDPOINTS
if have curl; then
  while IFS= read -r url; do
    [[ "$url" =~ ^https?:// ]] || continue
    key="$(echo "$url" | sed -E 's#https?://##; s#[/:]#_#g')"
    { curl -k -sS -I --max-time 7 "$url" 2>&1 || true; } | redact > "$OUT/web/head-${key}.txt"
  done < "$OUT/web/known-endpoints.txt"
fi

section "Verificando servicos auxiliares que podem participar do ingest"
run_shell "$OUT/security/samba-processes.txt" "ps -eo user,pid,etime,args | grep -Ei '[s]mbd|[n]mbd|[s]amba'"
run_shell "$OUT/security/samba-listeners.txt" "ss -lntup | grep -E ':(139|445)\\b'"
if have testparm; then run_txt "$OUT/security/samba-testparm.txt" testparm -s; fi

section "Gerando resumo do preflight"
{
  echo "StudioSat Web Core Preflight v${VERSION}"
  echo "Host: ${HOST}"
  echo "UTC: ${STAMP}"
  echo
  echo "== CHANNELS =="
  column -t -s $'\t' "$OUT/summary/channels.tsv" 2>/dev/null || cat "$OUT/summary/channels.tsv"
  echo
  echo "== STREAMS LOCAL =="
  column -t -s $'\t' "$OUT/summary/streams.tsv" 2>/dev/null || cat "$OUT/summary/streams.tsv"
  echo
  echo "== LISTENERS CORE =="
  grep -E ':(22|80|443|139|445|1935|8000|8001|8189|8554|8888|8889|8890|8892|8893|9997|9998)\\b' "$OUT/network/ss-lntup.txt" 2>/dev/null || true
  echo
  echo "== ALERTAS DE LEITURA =="
  grep -RniE 'failed|non-monotonic|connection refused|fatal|no_ready_media|error' "$OUT/channels" --include='*.txt' 2>/dev/null | head -n 120 || true
  echo
  echo "NOTA: nenhuma conclusao automatica de alteracao foi aplicada. O pacote deve ser analisado antes da proxima fase."
} | redact > "$OUT/SUMMARY.txt"

(
  cd "$OUT"
  find . -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS.txt
)

chmod -R go-rwx "$OUT" 2>/dev/null || true
tar -C "$(dirname "$OUT")" -czf "$ARCHIVE" "$(basename "$OUT")"
chmod 0600 "$ARCHIVE"
sha256sum "$ARCHIVE" > "${ARCHIVE}.sha256"

section "Concluido. Nenhum servico foi alterado."
printf '\nPACOTE: %s\nHASH:   %s\n\n' "$ARCHIVE" "${ARCHIVE}.sha256"
printf 'Envie os dois arquivos para analise: o .tar.gz e o .sha256.\n'
