#!/bin/sh
# Rigenera bin/<arch>/tui-samba e bin/<arch>/tui-users (amd64 e arm64).
# Uso (dalla radice del progetto): sh build/rebuild-binaries.sh [--build-arg NOME=valore ...]
set -eu
cd "$(dirname "$0")/.."

for arch in amd64 arm64; do
  rm -rf "bin/$arch"
  docker build -f Dockerfile.build --target out \
    --platform "linux/$arch" --output "type=local,dest=bin/$arch" "$@" .
done

ls -l bin/*/
