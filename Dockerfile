# syntax=docker/dockerfile:1

# I binari di tui-samba e tui-users sono gia' compilati in bin/<arch>/
# (si rigenerano con build/rebuild-binaries.sh).
FROM debian:bookworm-slim

ARG TARGETARCH
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

COPY bin/${TARGETARCH}/tui-samba bin/${TARGETARCH}/tui-users /usr/local/bin/
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
