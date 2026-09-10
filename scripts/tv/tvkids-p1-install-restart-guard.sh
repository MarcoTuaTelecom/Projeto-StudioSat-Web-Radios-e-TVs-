#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

UNIT="tps-tvkids-playout.service"
GEN="/usr/local/sbin/tps-generate-playlist"
CH="tvkids"
BASE="/srv/tpsmedia/repository/channels/${CH}"
CAN="${BASE}/canonical"
PL="${BASE}/playlists/playlist.txt"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
BK="/var/backups/studiosat/tvkids-restart-guard-${TS}"
LOG="/tmp/tvkids-restart-guard-${TS}.log"

exec > >(tee "$LOG") 2>&1

die(){ echo "FATAL: $*" >&2; exit 1; }
[[ ${EUID:-$(id -u)} -eq 0 ]] || die "execute como root"
for c in systemctl sha256sum grep awk sed install cp stat readlink mktemp diff find sort bash chmod chown mv basename; do
  command -v "$c" >/dev/null 2>&1 || die "comando ausente: $c"
done

echo "TVKIDS P1 — INSTALL RESTART GUARD"
echo "utc=$TS"
echo

[[ -x "$GEN" ]] || die "gerador não executável: $GEN"
[[ -d "$CAN" ]] || die "canonical ausente: $CAN"
[[ -f "$PL" ]] || die "playlist em disco ausente: $PL"
systemctl is-active --quiet "$UNIT" || die "$UNIT não está active"

PID="$(systemctl show -p MainPID --value "$UNIT")"
[[ "$PID" =~ ^[1-9][0-9]*$ && -d "/proc/$PID" ]] || die "MainPID inválido"
echo "pid=$PID"

RUNFD=""
for fd in /proc/"$PID"/fd/*; do
  target="$(readlink "$fd" 2>/dev/null || true)"
  if [[ "$target" == *"/channels/tvkids/playlists/playlist.txt"* ]]; then
    RUNFD="$fd"
    echo "running_playlist_fd=$fd"
    echo "running_playlist_target=$target"
    break
  fi
done
[[ -n "$RUNFD" ]] || die "playlist aberta não localizada no PID $PID"

install -d -m 0700 "$BK"
cp -L -- "$RUNFD" "$BK/playlist.running.before.ffconcat"
cp -a -- "$PL" "$BK/playlist.disk.before.ffconcat"
cp -a -- "$GEN" "$BK/tps-generate-playlist.before"

RUN_SHA="$(sha256sum "$BK/playlist.running.before.ffconcat" | awk '{print $1}')"
DISK_SHA="$(sha256sum "$BK/playlist.disk.before.ffconcat" | awk '{print $1}')"
RUN_FILES="$(grep -c '^file ' "$BK/playlist.running.before.ffconcat" || true)"
RUN_CAN="$(grep -c '/canonical/' "$BK/playlist.running.before.ffconcat" || true)"
RUN_READY="$(grep -c '/ready/' "$BK/playlist.running.before.ffconcat" || true)"
DISK_CAN="$(grep -c '/canonical/' "$BK/playlist.disk.before.ffconcat" || true)"
DISK_READY="$(grep -c '/ready/' "$BK/playlist.disk.before.ffconcat" || true)"

echo "running_sha=$RUN_SHA files=$RUN_FILES canonical=$RUN_CAN ready=$RUN_READY"
echo "disk_sha=$DISK_SHA canonical=$DISK_CAN ready=$DISK_READY"

[[ "$RUN_FILES" -gt 0 ]] || die "running playlist vazia"
[[ "$RUN_CAN" -eq "$RUN_FILES" && "$RUN_READY" -eq 0 ]] || die "running playlist não é 100% canonical; abortando"
[[ "$DISK_READY" -gt 0 ]] || die "playlist em disco já não aponta para ready; estado mudou desde o P0"

EXPECTED="$(mktemp /tmp/tvkids-expected.XXXXXX.ffconcat)"
CANDGEN=""
trap 'rm -f "$EXPECTED" "$CANDGEN" 2>/dev/null || true' EXIT
printf 'ffconcat version 1.0\n' > "$EXPECTED"
count=0
while IFS= read -r -d '' f; do
  [[ "$(basename "$f")" == *teste* || "$(basename "$f")" == *test* ]] && continue
  esc=${f//\'/\'\\\'\'}
  printf "file '%s'\n" "$esc" >> "$EXPECTED"
  count=$((count+1))
done < <(find "$CAN" -maxdepth 1 -type f \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.mp4' -o -iname '*.aac' \) -print0 | sort -z)

EXPECTED_SHA="$(sha256sum "$EXPECTED" | awk '{print $1}')"
echo "canonical_generated_sha=$EXPECTED_SHA files=$count"
[[ "$EXPECTED_SHA" == "$RUN_SHA" ]] || die "canonical gerado difere da playlist no ar; NÃO alterar produção"

grep -Fxq 'MEDIA_ROOT="${BASE}/ready"' "$GEN" || die "linha-base do gerador mudou; revisão manual necessária"
if grep -Fq 'TVKIDS_RESTART_GUARD' "$GEN"; then
  die "guard já existe; não aplicar novamente"
fi

CANDGEN="$(mktemp /tmp/tps-generate-playlist.candidate.XXXXXX)"
awk '
  {
    print
    if ($0 == "MEDIA_ROOT=\"${BASE}/ready\"") {
      print ""
      print "# TVKIDS_RESTART_GUARD: TVKIDS usa somente mídia canonical certificada."
      print "if [[ \"$CH\" == \"tvkids\" ]]; then"
      print "  MEDIA_ROOT=\"${BASE}/canonical\""
      print "fi"
    }
  }
' "$GEN" > "$CANDGEN"

chmod --reference="$GEN" "$CANDGEN"
chown --reference="$GEN" "$CANDGEN"
echo
echo "=== DIFF EXATO DO GERADOR ==="
diff -u "$GEN" "$CANDGEN" || true
echo
bash -n "$CANDGEN" || die "candidate generator falhou bash -n"
[[ "$(grep -c 'TVKIDS_RESTART_GUARD' "$CANDGEN")" -eq 1 ]] || die "candidate generator contém guard inesperado"

echo "Instalando alteração mínima no gerador compartilhado..."
install -o "$(stat -c %U "$GEN")" -g "$(stat -c %G "$GEN")" -m "$(stat -c %a "$GEN")" "$CANDGEN" "${GEN}.new-${TS}"
mv -f -- "${GEN}.new-${TS}" "$GEN"

bash -n "$GEN" || {
  echo "ROLLBACK: sintaxe pós-instalação falhou"
  cp -a -- "$BK/tps-generate-playlist.before" "$GEN"
  exit 2
}

echo "Regenerando SOMENTE a playlist em disco da TVKIDS; processo atual não é reiniciado."
if ! "$GEN" "$CH"; then
  echo "ROLLBACK: gerador TVKIDS falhou"
  cp -a -- "$BK/tps-generate-playlist.before" "$GEN"
  cp -a -- "$BK/playlist.disk.before.ffconcat" "$PL"
  exit 3
fi

NEW_SHA="$(sha256sum "$PL" | awk '{print $1}')"
NEW_FILES="$(grep -c '^file ' "$PL" || true)"
NEW_CAN="$(grep -c '/canonical/' "$PL" || true)"
NEW_READY="$(grep -c '/ready/' "$PL" || true)"
echo "new_disk_sha=$NEW_SHA files=$NEW_FILES canonical=$NEW_CAN ready=$NEW_READY"

if [[ "$NEW_SHA" != "$RUN_SHA" || "$NEW_CAN" -ne "$NEW_FILES" || "$NEW_READY" -ne 0 ]]; then
  echo "ROLLBACK: playlist regenerada não equivale à que está no ar"
  cp -a -- "$BK/tps-generate-playlist.before" "$GEN"
  cp -a -- "$BK/playlist.disk.before.ffconcat" "$PL"
  exit 4
fi

PID_AFTER="$(systemctl show -p MainPID --value "$UNIT")"
[[ "$PID_AFTER" == "$PID" ]] || {
  echo "ATENÇÃO CRÍTICA: PID mudou de $PID para $PID_AFTER durante a operação."
  exit 5
}

cp -a -- "$GEN" "$BK/tps-generate-playlist.after"
cp -a -- "$PL" "$BK/playlist.disk.after.ffconcat"

echo
echo "=== RESULTADO ==="
echo "PASS: gerador TVKIDS agora usa canonical/"
echo "PASS: playlist em disco = playlist atualmente no ar"
echo "PASS: SHA256=$NEW_SHA"
echo "PASS: PID permaneceu $PID"
echo "PASS: nenhum restart/reload/daemon-reload foi executado"
echo
echo "backup_privado=$BK"
echo "log=$LOG"
echo
echo "NÃO reinicie a TVKIDS ainda. O próximo passo é localizar e eliminar os DTS."
