#!/usr/bin/env bash
# StudioSat Web Health Read-Only v0.1-candidate
# Owner: Core
# Safety class: read-only
# Change: CHG-004
# Propósito: medir produto atual sem alterar serviços, configuração ou mídia.

set -Eeuo pipefail
IFS=$'\n\t'

VERSION="0.1-candidate"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/studiosat-health-${STAMP}"
API="http://127.0.0.1:9997/v3/paths/list"

CHANNELS=(radioprincipal radiopop radiorock radioclassicas radiocountry tvkids tvteens tvviva tvmaisjovem)

mkdir -p "$OUT/channels"
chmod 0700 "$OUT"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "FATAL=MISSING_COMMAND:$1" >&2; exit 66; }; }
need curl
need jq
need systemctl
need journalctl

curl -fsS --max-time 5 "$API" > "$OUT/mediamtx-paths.json"
printf 'station\tdomain\tstate\tsystemd\tmediamtx_ready\ttracks\thls_local\thls_fresh\tpublic_root\trecent_errors\trecent_dts\n' > "$OUT/health.tsv"

public_root(){
  case "$1" in
    radioprincipal) printf '%s\n' 'https://radio.studiosatweb.com.br' ;;
    radiopop|radiorock|radioclassicas|radiocountry) printf 'https://%s.studiosatweb.com.br\n' "$1" ;;
    tvkids|tvteens|tvviva|tvmaisjovem) printf 'https://%s.studiosatweb.com.br\n' "$1" ;;
  esac
}

for ch in "${CHANNELS[@]}"; do
  domain="radio"; [[ "$ch" == tv* ]] && domain="tv"
  unit="tps-${ch}-playout.service"
  cdir="$OUT/channels/$ch"; mkdir -p "$cdir"

  sys="$(systemctl is-active "$unit" 2>/dev/null || true)"; [[ -n "$sys" ]] || sys="unknown"
  item="$(jq -c --arg ch "$ch" '.items[]? | select(.name==$ch)' "$OUT/mediamtx-paths.json" | head -n1)"
  if [[ -n "$item" ]]; then
    ready="$(jq -r '.ready // false' <<<"$item")"
    tracks="$(jq -r '[.tracks[]?] | join("+")' <<<"$item")"
  else
    ready="false"; tracks=""
  fi

  manifest="http://127.0.0.1:8888/${ch}/index.m3u8"
  meta="$(curl -sS -L -o "$cdir/hls-1.m3u8" -w '%{http_code}\t%{url_effective}' --max-time 7 "$manifest" 2>"$cdir/hls.err" || true)"
  hcode="${meta%%$'\t'*}"; effective="${meta#*$'\t'}"; printf '%s\n' "$effective" > "$cdir/hls-effective-url.txt"
  [[ "$hcode" == "200" ]] && hls="PASS" || hls="FAIL:${hcode:-000}"

  fresh="SKIP"
  if [[ "$hcode" == "200" && -s "$cdir/hls-1.m3u8" ]]; then
    seq1="$(grep -m1 '^#EXT-X-MEDIA-SEQUENCE:' "$cdir/hls-1.m3u8" | cut -d: -f2 || true)"
    last1="$(grep -Ev '^#|^[[:space:]]*$' "$cdir/hls-1.m3u8" | tail -n1 || true)"
    sleep 3
    curl -fsS -L --max-time 7 "$manifest" > "$cdir/hls-2.m3u8" 2>/dev/null || true
    seq2="$(grep -m1 '^#EXT-X-MEDIA-SEQUENCE:' "$cdir/hls-2.m3u8" | cut -d: -f2 || true)"
    last2="$(grep -Ev '^#|^[[:space:]]*$' "$cdir/hls-2.m3u8" | tail -n1 || true)"
    if [[ "$seq1" != "$seq2" || "$last1" != "$last2" ]]; then fresh="CHANGING"; else fresh="UNCHANGED_3S"; fi
  fi

  root="$(public_root "$ch")"
  pcode="$(curl -sS -L -o /dev/null -w '%{http_code}' --max-time 7 "$root" 2>/dev/null || true)"
  [[ "$pcode" == "200" ]] && pub="PASS" || pub="FAIL:${pcode:-000}"

  journalctl -u "$unit" --since '-15 min' --no-pager -o cat > "$cdir/journal-15m.txt" 2>/dev/null || true
  recent_errors="$(grep -Eic '(^|[^[:alpha:]])(error|fatal|failed|connection refused)([^[:alpha:]]|$)' "$cdir/journal-15m.txt" || true)"
  recent_dts="$(grep -Eic 'non-monotonic dts' "$cdir/journal-15m.txt" || true)"

  state="healthy"
  if [[ "$sys" != "active" || "$ready" != "true" ]]; then state="failed"
  elif [[ "$hls" != "PASS" || "$pub" != "PASS" ]]; then state="degraded"
  elif [[ "$domain" == "tv" && "$recent_dts" -gt 0 ]]; then state="degraded"
  elif [[ "$recent_errors" -gt 0 ]]; then state="degraded"
  fi

  jq -n --arg station_id "$ch" --arg domain "$domain" --arg state "$state" --arg systemd "$sys" --argjson mediamtx_ready "$ready" --arg tracks "$tracks" --arg hls "$hls" --arg hls_fresh "$fresh" --arg public_root "$pub" --argjson recent_errors "${recent_errors:-0}" --argjson recent_dts "${recent_dts:-0}" '{station_id:$station_id,domain:$domain,state:$state,systemd:$systemd,mediamtx_ready:$mediamtx_ready,tracks:$tracks,output_freshness:{hls:$hls,freshness:$hls_fresh},public_root:$public_root,errors:{recent_count:$recent_errors,non_monotonic_dts:$recent_dts},schema_version:"STUDIOSAT-HEALTH-1"}' > "$cdir/health.json"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ch" "$domain" "$state" "$sys" "$ready" "$tracks" "$hls" "$fresh" "$pub" "$recent_errors" "$recent_dts" >> "$OUT/health.tsv"
done

jq -s '{schema_version:"STUDIOSAT-HEALTH-1",generated_at_utc:"'"$(date -u +%FT%TZ)"'",stations:.}' "$OUT"/channels/*/health.json > "$OUT/health.json"

echo
if command -v column >/dev/null 2>&1; then column -t -s $'\t' "$OUT/health.tsv"; else cat "$OUT/health.tsv"; fi
echo
echo "RESULT_JSON=$OUT/health.json"
echo "RESULT_TSV=$OUT/health.tsv"
echo "READ_ONLY=YES"
