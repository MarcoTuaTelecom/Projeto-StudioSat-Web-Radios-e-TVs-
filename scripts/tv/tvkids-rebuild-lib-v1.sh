#!/usr/bin/env bash
[[ "${TVKIDS_REBUILD_ORCHESTRATOR:-0}" == 1 ]] || { echo "FATAL=SOURCE_ONLY"; return 1 2>/dev/null || exit 1; }

UNIT="tps-tvkids-playout.service"
BASE="/srv/tpsmedia/repository/channels/tvkids"
CAN="${BASE}/canonical"
STATE="${BASE}/state"
PLDIR="${BASE}/playlists"
ARCHIVE="${BASE}/archive"
GEN="/usr/local/sbin/tps-generate-playlist"
BUILDER="/usr/local/sbin/tps-tvkids-build-plan"
HEALTH="/usr/local/sbin/tps-tvkids-health"
NGCONF="/etc/nginx/conf.d/tps-9-emissoras.conf"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="/tmp/CHG-TVKIDS-001-${TS}"
BACKUP="/var/backups/studiosat/CHG-TVKIDS-001/${TS}"
WORK="${BASE}/lab/rebuild-${TS}"
CANDCAN="${WORK}/canonical"
CANDMAN="${WORK}/ready.manifest.tsv"
NORMALIZER="${SCRIPT_DIR}/tvkids-normalize-asset-v1.sh"
NGPATCHER="${SCRIPT_DIR}/tvkids-nginx-patch-v1.py"
CAND_BUILDER="${SCRIPT_DIR}/tvkids-build-plan-v1.sh"
CAND_HEALTH="${SCRIPT_DIR}/tvkids-health-v1.sh"
MUTATED=0
CAN_SWAPPED=0
NGINX_MUTATED=0
BUILDER_EXISTED=0
HEALTH_EXISTED=0
MANIFEST_EXISTED=0
CURRENT_EXISTED=0
PREVIOUS_EXISTED=0
LEGACY_EXISTED=0

need(){ command -v "$1" >/dev/null 2>&1 || { echo "FATAL=MISSING_TOOL:$1" >&2; exit 70; }; }
for c in systemctl sha256sum ffprobe ffmpeg curl jq nginx grep awk find sort stat readlink tar date ps wc head tail install cp mv rm mkdir flock cmp timeout nice ionice python3 sleep diff chown chmod basename mktemp runuser seq journalctl tr cat; do need "$c"; done
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "FATAL=RUN_AS_ROOT"; exit 77; }

mkdir -p "$OUT" "$BACKUP" "$WORK" "$CANDCAN"
chmod 0700 "$BACKUP"
exec > >(tee "$OUT/REPORT.txt") 2>&1
exec 9>/run/lock/studiosat-production-change.lock
flock -n 9 || { echo "FATAL=ANOTHER_STUDIOSAT_CHANGE_HOLDS_LOCK"; exit 75; }

fail(){ echo "FATAL=$*" >&2; exit 1; }
sha(){ sha256sum "$1" | awk '{print $1}'; }
backup_optional(){ [[ -e "$1" ]] && { cp -a -- "$1" "$2"; return 0; }; return 1; }
restore_optional(){ [[ "$1" == 1 ]] && cp -a -- "$2" "$3" || rm -f -- "$3"; }

rollback(){
  set +e
  echo "=== ROLLBACK CHG-TVKIDS-001 ==="
  if (( NGINX_MUTATED == 1 )); then
    cp -a -- "$BACKUP/nginx.before.conf" "$NGCONF"
    nginx -t && systemctl reload nginx
  fi
  systemctl stop "$UNIT" >/dev/null 2>&1 || true
  if (( CAN_SWAPPED == 1 )); then
    failed_new="${BASE}/lab/failed-${TS}-canonical"
    rm -rf -- "$failed_new" 2>/dev/null || true
    [[ -d "$CAN" ]] && mv -- "$CAN" "$failed_new"
    old_path="$(cat "$BACKUP/canonical.pre-rebuild.path" 2>/dev/null || true)"
    [[ -n "$old_path" && -d "$old_path" ]] && mv -- "$old_path" "$CAN"
  fi
  cp -a -- "$BACKUP/generator.before" "$GEN"
  restore_optional "$BUILDER_EXISTED" "$BACKUP/builder.before" "$BUILDER"
  restore_optional "$HEALTH_EXISTED" "$BACKUP/health.before" "$HEALTH"
  restore_optional "$MANIFEST_EXISTED" "$BACKUP/ready.manifest.before.tsv" "$STATE/ready.manifest.tsv"
  restore_optional "$CURRENT_EXISTED" "$BACKUP/current.before.ffconcat" "$PLDIR/current.ffconcat"
  restore_optional "$PREVIOUS_EXISTED" "$BACKUP/previous.before.ffconcat" "$PLDIR/previous.ffconcat"
  restore_optional "$LEGACY_EXISTED" "$BACKUP/playlist.before.txt" "$PLDIR/playlist.txt"
  systemctl start "$UNIT" >/dev/null 2>&1 || true
  sleep 3
  systemctl show "$UNIT" -p ActiveState -p SubState -p MainPID --no-pager || true
  echo "ROLLBACK=DONE"
}
trap 'rc=$?; if (( rc != 0 && MUTATED == 1 )); then rollback; fi; exit $rc' EXIT

echo "CHG-TVKIDS-001 — REBUILD TVKIDS PRODUCTION CHAIN"
echo "UTC=$TS"
echo "PRIVATE_BACKUP=$BACKUP"

clear=0
for i in $(seq 1 120); do
  ps -eo pid=,ppid=,etimes=,args= > "$OUT/processes.pre.txt"
  grep -E 'apply-(radio|tv)|apply-radioprincipal|CHG-R0[0-9].*apply|systemctl +(restart|reload|stop|start) +(tps-|nginx|studiosat)' "$OUT/processes.pre.txt" \
    | grep -v -E 'grep -E|tvkids-rebuild-production-v1' > "$OUT/mutating-processes.txt" || true
  systemctl list-jobs --no-legend 2>/dev/null > "$OUT/systemd-jobs.txt" || true
  if [[ ! -s "$OUT/mutating-processes.txt" && ! -s "$OUT/systemd-jobs.txt" ]]; then clear=1; break; fi
  echo "concurrency_wait=$((i*5))s"
  sleep 5
done
(( clear == 1 )) || fail "CONCURRENT_MUTATION_DID_NOT_CLEAR_WITHIN_10_MIN"

[[ -d "$CAN" && -f "$GEN" && -f "$NGCONF" ]] || fail "REQUIRED_PRODUCTION_ARTIFACT_MISSING"
[[ "$(systemctl is-active "$UNIT" || true)" == active ]] || fail "TVKIDS_NOT_ACTIVE_PRE"
PID_PRE="$(systemctl show "$UNIT" -p MainPID --value)"
[[ "$PID_PRE" =~ ^[1-9][0-9]*$ && -d "/proc/$PID_PRE" ]] || fail "TVKIDS_PID_INVALID_PRE"

RUNFD=""
for fd in /proc/"$PID_PRE"/fd/*; do
  t="$(readlink "$fd" 2>/dev/null || true)"
  [[ "$t" == *"/channels/tvkids/playlists/playlist.txt"* ]] && { RUNFD="$fd"; break; }
done
[[ -n "$RUNFD" ]] || fail "RUNNING_PLAYLIST_FD_NOT_FOUND"
cp -L -- "$RUNFD" "$BACKUP/playlist.running.before.ffconcat"
RUN_SHA="$(sha "$BACKUP/playlist.running.before.ffconcat")"
RUN_ITEMS="$(grep -c '^file ' "$BACKUP/playlist.running.before.ffconcat" || true)"
RUN_CAN="$(grep -c '/canonical/' "$BACKUP/playlist.running.before.ffconcat" || true)"
[[ "$RUN_ITEMS" -gt 1 && "$RUN_ITEMS" -eq "$RUN_CAN" ]] || fail "ON_AIR_PLAYLIST_NOT_CANONICAL"
echo "pre_pid=$PID_PRE playlist_sha=$RUN_SHA items=$RUN_ITEMS canonical=$RUN_CAN"

cp -a -- "$GEN" "$BACKUP/generator.before"
cp -a -- "$NGCONF" "$BACKUP/nginx.before.conf"
systemctl cat "$UNIT" > "$BACKUP/tvkids-unit.before.txt"
backup_optional "$BUILDER" "$BACKUP/builder.before" && BUILDER_EXISTED=1 || true
backup_optional "$HEALTH" "$BACKUP/health.before" && HEALTH_EXISTED=1 || true
backup_optional "$STATE/ready.manifest.tsv" "$BACKUP/ready.manifest.before.tsv" && MANIFEST_EXISTED=1 || true
backup_optional "$PLDIR/current.ffconcat" "$BACKUP/current.before.ffconcat" && CURRENT_EXISTED=1 || true
backup_optional "$PLDIR/previous.ffconcat" "$BACKUP/previous.before.ffconcat" && PREVIOUS_EXISTED=1 || true
backup_optional "$PLDIR/playlist.txt" "$BACKUP/playlist.before.txt" && LEGACY_EXISTED=1 || true

printf 'unit\tpid\n' > "$OUT/pids.pre.tsv"
for u in tps-radioprincipal-playout.service tps-radiopop-playout.service tps-radiorock-playout.service tps-radioclassicas-playout.service tps-radiocountry-playout.service tps-tvkids-playout.service tps-tvteens-playout.service tps-tvviva-playout.service tps-tvmaisjovem-playout.service tps-mediamtx.service; do
  printf '%s\t%s\n' "$u" "$(systemctl show "$u" -p MainPID --value 2>/dev/null || true)" >> "$OUT/pids.pre.tsv"
done
