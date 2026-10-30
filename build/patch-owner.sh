#!/bin/sh
# Cambia il valore proposto nel campo "Owner:group" del form di tui-samba.
# Uso: patch-owner.sh <form.go> <owner:group>
set -eu

file=$1
owner=$2
old='f.values\[fieldOwner\] = "root:root"'

if ! grep -q "$old" "$file"; then
  echo "patch-owner: riga da modificare non trovata in $file (cambiata in questa versione di tui-samba?)" >&2
  exit 1
fi

sed -i "s|$old|f.values[fieldOwner] = \"${owner}\"|" "$file"

grep -q "f.values\[fieldOwner\] = \"${owner}\"" "$file"
