#!/bin/sh
# Costruisce l'immagine e la salva in un file, per portarla su un server senza
# internet (o per pubblicarla).
# Uso (dalla radice del progetto): sh build/export-image.sh [cartella] [piattaforma]
#   cartella     dove scrivere il file (default: dist/)
#   piattaforma  default linux/amd64
# Sul server: docker load < samba-tui-<arch>.tar.gz && docker compose up -d
set -eu
cd "$(dirname "$0")/.."

out=${1:-dist}
platform=${2:-linux/amd64}
arch=${platform#*/}
mkdir -p "$out"

docker buildx build --platform "$platform" --load -t samba-tui:latest .
docker save samba-tui:latest | gzip > "$out/samba-tui-$arch.tar.gz"
ls -l "$out/samba-tui-$arch.tar.gz"
