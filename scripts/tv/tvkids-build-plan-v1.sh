#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
export LC_ALL=C
umask 022
BASE="/srv/tpsmedia/repository/channels/tvkids"
CAN="${BASE}/canonical"
STATE="${BASE}/state"
PLDIR="${BASE}/playlists"
MANIFEST="${STATE}/ready.manifest.tsv"
CURRENT="${PLDIR}/current.ffconcat"
PREVIOUS="${PLDIR}/previous.ffconcat"
LEGACY="${PLDIR}/playlist.txt"
LOCK="${STATE}/plan.lock"
die(){ echo "FATAL=$*" >&2; exit 1; }
[[ -d "$CAN" ]] || die "CANONICAL_MISSING"
[[ -f "$MANIFEST" ]] || die "READY_MANIFEST_MISSING"
install -d -m 0755 "$PLDIR"
exec 9>"$LOCK"
flock -x 9
tmp="$(mktemp "${PLDIR}/.candidate.XXXXXX")"
legacy_tmp="$(mktemp "${PLDIR}/.playlist.XXXXXX")"
trap 'rm -f -- "${tmp:-}" "${legacy_tmp:-}"' EXIT
printf 'ffconcat version 1.0\n' > "$tmp"
count=0
while IFS=$'\t' read -r expected path; do
    [[ -n "${expected:-}" && -n "${path:-}" ]] || continue
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || die "BAD_HASH_IN_MANIFEST"
    [[ "$path" == "$CAN/"* ]] || die "MANIFEST_PATH_OUTSIDE_CANONICAL:$path"
    [[ -f "$path" ]] || die "MANIFEST_ASSET_MISSING:$path"
    actual="$(sha256sum "$path" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || die "MANIFEST_HASH_MISMATCH:$path"
    esc=${path//\'/\'\\\'\'}
    printf "file '%s'\n" "$esc" >> "$tmp"
    count=$((count+1))
done < "$MANIFEST"
(( count > 0 )) || die "EMPTY_READY_MANIFEST"
probe_tmp="$(mktemp /tmp/tvkids-plan-probe.XXXXXX)"
trap 'rm -f -- "${tmp:-}" "${legacy_tmp:-}" "${probe_tmp:-}"' EXIT
ffprobe -v error -f concat -safe 0 -read_intervals '%+0.2' -show_entries stream=codec_type -of csv=p=0 "$tmp" >"$probe_tmp" 2>/dev/null || die "FFCONCAT_PROBE_FAILED"
grep -qx 'video' "$probe_tmp" || die "VIDEO_STREAM_MISSING"
grep -qx 'audio' "$probe_tmp" || die "AUDIO_STREAM_MISSING"
if [[ -f "$CURRENT" ]] && cmp -s "$CURRENT" "$tmp"; then
    cp -a -- "$CURRENT" "$legacy_tmp"
    mv -f -- "$legacy_tmp" "$LEGACY"
    echo "TVKIDS_PLAN_OK|ITEMS=$count|CHANGED=0|CURRENT=$CURRENT|LEGACY=$LEGACY"
    exit 0
fi
if [[ -f "$CURRENT" ]]; then
    prev_tmp="$(mktemp "${PLDIR}/.previous.XXXXXX")"
    cp -a -- "$CURRENT" "$prev_tmp"
    mv -f -- "$prev_tmp" "$PREVIOUS"
fi
mv -f -- "$tmp" "$CURRENT"
cp -a -- "$CURRENT" "$legacy_tmp"
mv -f -- "$legacy_tmp" "$LEGACY"
sha="$(sha256sum "$CURRENT" | awk '{print $1}')"
echo "TVKIDS_PLAN_OK|ITEMS=$count|CHANGED=1|SHA256=$sha|CURRENT=$CURRENT|LEGACY=$LEGACY"
