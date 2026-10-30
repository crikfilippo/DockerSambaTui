#!/bin/bash
# Prove senza Docker: logica dell'entrypoint, systemctl finto, patch del sorgente.
# Uso: tests/test-scripts.sh [percorso/di/form.go di tui-samba]
set -eu

HERE=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FALLITO: $*" >&2; exit 1; }
ok()   { echo "ok - $*"; }

# 1. sintassi
for f in scripts/entrypoint.sh scripts/systemctl scripts/guida build/patch-owner.sh; do
  bash -n "$HERE/$f" || fail "sintassi $f"
done
ok "sintassi degli script"

# 2. entrypoint: persistenza degli account
export CONF="$TMP/config" ETC_DIR="$TMP/etc" SEED="$TMP/seed"
mkdir -p "$CONF/accounts" "$ETC_DIR" "$SEED/etc-samba"
echo "root:x:0:0" > "$ETC_DIR/passwd"
echo "root:x:0:"  > "$ETC_DIR/group"
echo "root:*:1"   > "$ETC_DIR/shadow"
echo "root:!::"   > "$ETC_DIR/gshadow"
: > "$ETC_DIR/subuid"; : > "$ETC_DIR/subgid"
# shellcheck source=/dev/null
. "$HERE/scripts/entrypoint.sh"

sync_accounts
[ "$(cat "$CONF/accounts/passwd")" = "root:x:0:0" ] || fail "primo sync"
ok "primo avvio: account copiati nel volume"

echo "anna:x:1000:100" >> "$ETC_DIR/passwd"
sync_accounts
grep -q '^anna:' "$CONF/accounts/passwd" || fail "sync dopo modifica"
ok "modifica in /etc propagata al volume"

# nuovo container: /etc torna com'era nell'immagine
echo "root:x:0:0" > "$ETC_DIR/passwd"
restore_accounts
grep -q '^anna:' "$ETC_DIR/passwd" || fail "restore"
ok "riavvio: account ripristinati dal volume"

# 3. persist_dir
mkdir -p "$TMP/live-parent"
echo seed > "$SEED/etc-samba/smb.conf"
persist_dir "$TMP/live-parent/samba" "$CONF/samba" "$SEED/etc-samba"
[ -L "$TMP/live-parent/samba" ] || fail "link non creato"
echo modificato > "$TMP/live-parent/samba/smb.conf"
persist_dir "$TMP/live-parent/samba" "$CONF/samba" "$SEED/etc-samba"
[ "$(cat "$CONF/samba/smb.conf")" = "modificato" ] || fail "persist_dir ha sovrascritto il volume"
ok "persist_dir: link creato e contenuto del volume preservato al riavvio"

# 4. systemctl finto (pgrep simulato)
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/pgrep"; chmod +x "$TMP/bin/pgrep"
run_sc() { PATH="$TMP/bin:$PATH" sh "$HERE/scripts/systemctl" show "$1" \
  --property=LoadState --property=ActiveState --property=UnitFileState; }
run_sc smb.service | grep -q '^LoadState=not-found$' || fail "smb.service"
run_sc smbd.service | grep -q '^ActiveState=inactive$' || fail "smbd inattivo"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/pgrep"
run_sc smbd.service | grep -q '^ActiveState=active$' || fail "smbd attivo"
ok "systemctl finto: smb.service assente, smbd.service segue il processo"

# 5. patch del sorgente (solo se passato form.go)
if [ "${1:-}" ]; then
  cp "$1" "$TMP/form.go"
  sh "$HERE/build/patch-owner.sh" "$TMP/form.go" root:users
  grep -q 'f.values\[fieldOwner\] = "root:users"' "$TMP/form.go" || fail "patch"
  if sh "$HERE/build/patch-owner.sh" "$TMP/form.go" root:users 2>/dev/null; then
    fail "la patch doveva fallire su un file gia' modificato"
  fi
  ok "patch del default Owner:group (e fallimento se la riga manca)"
fi

echo "Tutti i test superati."
