# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Stage 1: compila tui-samba (con l'unico default modificato) e tui-users
# ---------------------------------------------------------------------------
ARG GO_IMAGE=golang:bookworm
FROM ${GO_IMAGE} AS build

ARG TUI_SAMBA_REF=v0.2.4
ARG TUI_USERS_REF=v0.2.2
ARG DEFAULT_OWNER=root:users

# I go.mod dei due tool richiedono Go 1.27.x: l'immagine golang usa
# GOTOOLCHAIN=local di default, qui lasciamo che scarichi la versione giusta.
ENV GOTOOLCHAIN=auto \
    CGO_ENABLED=0

RUN git clone --depth 1 --branch "${TUI_SAMBA_REF}" https://github.com/tui-tools/tui-samba.git /src/tui-samba \
 && git clone --depth 1 --branch "${TUI_USERS_REF}" https://github.com/tui-tools/tui-users.git /src/tui-users

# Unica modifica al sorgente: valore proposto nel campo "Owner:group" del form
# di creazione share. Lo script fallisce se la riga non esiste piu'.
COPY build/patch-owner.sh /patch-owner.sh
RUN sh /patch-owner.sh /src/tui-samba/cmd/tui-samba/form.go "${DEFAULT_OWNER}"

RUN cd /src/tui-samba \
 && go build -trimpath -ldflags "-s -w -X main.version=${TUI_SAMBA_REF}+owner" \
      -o /out/tui-samba ./cmd/tui-samba
RUN cd /src/tui-users \
 && go build -trimpath -ldflags "-s -w -X main.version=${TUI_USERS_REF}" \
      -o /out/tui-users ./cmd/tui-users

# ---------------------------------------------------------------------------
# Stage 2: immagine finale
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ENV LANG=C.UTF-8

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      samba smbclient iproute2 procps tini acl \
 && rm -rf /var/lib/apt/lists/*

# Ogni nuovo utente: gruppo principale "users" (GID 100), shell nologin,
# nessun gruppo privato. useradd legge questi due file.
RUN sed -i 's/^USERGROUPS_ENAB.*/USERGROUPS_ENAB no/' /etc/login.defs \
 && grep -q '^USERGROUPS_ENAB no' /etc/login.defs \
 && printf '%s\n' \
      'GROUP=100' 'HOME=/home' 'INACTIVE=-1' 'EXPIRE=' \
      'SHELL=/usr/sbin/nologin' 'SKEL=/etc/skel' 'CREATE_MAIL_SPOOL=no' \
      > /etc/default/useradd \
 && useradd probe \
 && test "$(id -g probe)" = "100" \
 && getent passwd probe | grep -q ':/usr/sbin/nologin$' \
 && userdel probe

# Copie "di partenza" delle cartelle che finiscono nel volume /config.
RUN mkdir -p /usr/share/samba-tui/seed \
 && cp -a /etc/samba /usr/share/samba-tui/seed/etc-samba \
 && cp -a /var/lib/samba /usr/share/samba-tui/seed/var-lib-samba

COPY smb.conf /usr/share/samba-tui/smb.conf
RUN testparm -s /usr/share/samba-tui/smb.conf > /dev/null

COPY --from=build /out/tui-samba /out/tui-users /usr/local/bin/
COPY config/tui.toml /etc/tui-samba/config.toml
COPY config/tui.toml /etc/tui-users/config.toml
COPY scripts/systemctl /usr/bin/systemctl
COPY scripts/guida /usr/local/bin/guida
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/banner.txt /usr/local/share/samba-tui/banner.txt
COPY scripts/bashrc.snippet /tmp/bashrc.snippet

RUN cat /tmp/bashrc.snippet >> /etc/bash.bashrc \
 && rm /tmp/bashrc.snippet \
 && chmod 755 /usr/bin/systemctl /usr/local/bin/guida /entrypoint.sh

EXPOSE 445

ENTRYPOINT ["tini", "--", "/entrypoint.sh"]
