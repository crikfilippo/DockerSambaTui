#!/bin/bash
# Entrypoint: ripristina la configurazione persistente da /config e avvia smbd.
set -eu

CONF="${CONF:-/config}"
SEED="${SEED:-/usr/share/samba-tui}"
ETC_DIR="${ETC_DIR:-/etc}"
ACCOUNTS="passwd group shadow gshadow subuid subgid"

# Copia i file degli account da /etc al volume, solo se sono cambiati.
sync_accounts() {
  local f
  for f in $ACCOUNTS; do
    [ -f "$ETC_DIR/$f" ] || continue
    if ! cmp -s "$ETC_DIR/$f" "$CONF/accounts/$f"; then
      cp -p "$ETC_DIR/$f" "$CONF/accounts/.$f.tmp"
      mv -f "$CONF/accounts/.$f.tmp" "$CONF/accounts/$f"
    fi
  done
}

# Rimette in /etc i file degli account salvati nel volume.
restore_accounts() {
  local f
  for f in $ACCOUNTS; do
    if [ -f "$CONF/accounts/$f" ]; then
      cp -p "$CONF/accounts/$f" "$ETC_DIR/$f"
    fi
  done
  return 0
}

# Sposta una cartella nel volume (copiandola dal seed la prima volta) e al suo
# posto mette un link simbolico.
persist_dir() {
  local live=$1 stored=$2 seed=$3
  if [ ! -d "$stored" ]; then
    cp -a "$seed" "$stored"
  fi
  rm -rf "$live"
  ln -s "$stored" "$live"
}

main() {
  mkdir -p "$CONF/accounts" /shares /run/samba /var/log/samba
  chmod a+rx /shares

  persist_dir /etc/samba "$CONF/samba" "$SEED/seed/etc-samba"
  persist_dir /var/lib/samba "$CONF/var-lib-samba" "$SEED/seed/var-lib-samba"

  if [ ! -f "$CONF/.initialized" ]; then
    install -m 644 "$SEED/smb.conf" /etc/samba/smb.conf
    touch "$CONF/.initialized"
  fi
  mkdir -p /etc/samba/tui-samba.d

  if [ -f "$CONF/accounts/passwd" ]; then
    restore_accounts
  else
    sync_accounts
  fi

  # useradd/usermod riscrivono i file in /etc con un rename, quindi non si
  # possono montare o linkare: si salvano nel volume a ogni cambiamento.
  ( while sleep 2; do sync_accounts || true; done ) &

  cat /usr/local/share/samba-tui/banner.txt
  echo ">>> Avvio di smbd (porta 445). Gestione: docker exec -it samba bash"

  exec smbd --foreground --debug-stdout --no-process-group
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi
