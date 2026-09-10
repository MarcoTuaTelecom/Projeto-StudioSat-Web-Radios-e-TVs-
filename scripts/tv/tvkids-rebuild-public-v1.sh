#!/usr/bin/env bash
[[ "${TVKIDS_REBUILD_ORCHESTRATOR:-0}" == 1 ]] || { echo "FATAL=SOURCE_ONLY"; return 1 2>/dev/null || exit 1; }

if (( ROOT_BAD == 1 )); then
  cp -a -- "$NGCAND" "${NGCONF}.new-${TS}"
  mv -f -- "${NGCONF}.new-${TS}" "$NGCONF"
  NGINX_MUTATED=1
  nginx -t
  systemctl reload nginx
  sleep 2
  echo "nginx_tvkids_alias_fix=PASS"
fi

bash "$HEALTH" | tee "$OUT/tvkids-health.post.txt"
grep -q '^TVKIDS_PRODUCT_HEALTH=PASS$' "$OUT/tvkids-health.post.txt" || fail "PRODUCT_HEALTH_FAILED"

sleep 5
START_TS="$(systemctl show "$UNIT" -p ExecMainStartTimestamp --value)"
journalctl -u "$UNIT" --since "$START_TS" --no-pager -o short-iso > "$OUT/tvkids-journal.post.txt" || true
POST_DTS="$(grep -Eic 'non[- ]?monoton(ic|ous).*DTS|DTS.*out of order|non monotonically increasing dts' "$OUT/tvkids-journal.post.txt" || true)"
POST_FATAL="$(grep -Eic 'Invalid data|No start code|Impossible to open|Connection refused|segfault|core dump|Conversion failed' "$OUT/tvkids-journal.post.txt" || true)"
echo "post_dts=$POST_DTS post_fatal=$POST_FATAL"
[[ "$POST_DTS" -eq 0 ]] || fail "DTS_PRESENT_AFTER_REBUILD"
[[ "$POST_FATAL" -eq 0 ]] || fail "FATAL_MEDIA_ERROR_AFTER_REBUILD"

printf 'unit\tpid\n' > "$OUT/pids.post.tsv"
for u in tps-radioprincipal-playout.service tps-radiopop-playout.service tps-radiorock-playout.service tps-radioclassicas-playout.service tps-radiocountry-playout.service tps-tvkids-playout.service tps-tvteens-playout.service tps-tvviva-playout.service tps-tvmaisjovem-playout.service tps-mediamtx.service; do
  printf '%s\t%s\n' "$u" "$(systemctl show "$u" -p MainPID --value 2>/dev/null || true)" >> "$OUT/pids.post.tsv"
done
awk -F '\t' 'NR==FNR{pre[$1]=$2;next} $1!="tps-tvkids-playout.service" && pre[$1]!=$2 {print "UNEXPECTED_PID_CHANGE=" $1; bad=1} END{exit bad}' "$OUT/pids.pre.tsv" "$OUT/pids.post.tsv" \
  || fail "OTHER_STATION_OR_MEDIAMTX_PID_CHANGED"

{
  echo "generator_sha=$(sha "$GEN")"
  echo "builder_sha=$(sha "$BUILDER")"
  echo "health_sha=$(sha "$HEALTH")"
  echo "manifest_sha=$(sha "$STATE/ready.manifest.tsv")"
  echo "current_plan_sha=$(sha "$PLDIR/current.ffconcat")"
  echo "legacy_plan_sha=$(sha "$PLDIR/playlist.txt")"
  echo "canonical_count=$(find "$CAN" -maxdepth 1 -type f -iname '*.mp4' | wc -l)"
  echo "normalized=$USE_NORMALIZED"
  echo "tvkids_pid_pre=$PID_PRE"
  echo "tvkids_pid_post=$PID_POST"
} | tee "$OUT/final-identities.txt"

tar -C /tmp -czf "/tmp/CHG-TVKIDS-001-${TS}.shareable.tar.gz" "CHG-TVKIDS-001-${TS}"
sha256sum "/tmp/CHG-TVKIDS-001-${TS}.shareable.tar.gz" | tee "/tmp/CHG-TVKIDS-001-${TS}.shareable.tar.gz.sha256"

trap - EXIT
echo "CHG_TVKIDS_001_RESULT=PASS"
echo "TVKIDS_PRODUCT=HEALTHY"
echo "shareable=/tmp/CHG-TVKIDS-001-${TS}.shareable.tar.gz"
echo "sha256=/tmp/CHG-TVKIDS-001-${TS}.shareable.tar.gz.sha256"
echo "private_backup=$BACKUP"
