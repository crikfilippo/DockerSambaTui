# samba-tui

A Samba server in an Ubuntu 26.04 LTS container, managed entirely from the terminal with two TUIs: [tui-users](https://github.com/tui-tools/tui-users) for Unix users and groups, and [tui-samba](https://github.com/tui-tools/tui-samba) for Samba accounts and shares. No web interface, no systemd, two volumes.

Built to share working folders (for example [Bruno](https://www.usebruno.com/) collections) among several people through a central server: whoever saves a file makes it available to the others immediately, with no push or pull.

> **Project status:** the image has been built and tested (Docker Desktop on Mac, `docker compose`, `smbclient`, Finder): startup, persistence after restart, groups and users, writes by several users in different groups, read-only shares, and rejection of users who are not allowed. Not tested: Windows clients, real Office, a production Linux host. Open points are in [`ANALISI.md`](ANALISI.md) (in Italian). tui-users and tui-samba are also very young software (beta), and the TUI shows `(untested)` next to the Samba version.

## Features

- Ubuntu 26.04 LTS with Samba 4.23 (SMB2+ only, port 445, no guest access).
- Terminal management: `tui-users` and `tui-samba`, already configured to run as root in the container.
- Two volumes: `/config` (Samba configuration, password database, Unix accounts) and `/shares` (the parent folder of all shares).
- New files and folders inherit group and permissions from the share that contains them.
- Every new user has `users` as primary group, the `nologin` shell, and no Unix password.
- A startup message with the procedure appears in the logs (`docker logs`) and in every `docker exec -it samba bash` session (the message is in Italian).
- Samba logs go to `docker logs` (`log level = 3`, rotated by compose: 10 MB x 3). The level can be changed at runtime: `smbcontrol all debug N`.
- Useless system files (`Thumbs.db`, `desktop.ini`, `.DS_Store`, `._*`) are rejected by the server. Office lock files (`~$*`) are not, since they provide the "file in use" warning.

## Requirements

- Docker with Compose v2. The prebuilt image is published for `linux/amd64` and `linux/arm64`. Building from source needs internet access (`golang` and `ubuntu` images, Samba packages, the two tools cloned from GitHub). With plain `docker run` (no compose) add `--init`.
- A filesystem that supports Unix owners and permissions for `config/` and `shares/` (not NTFS, exFAT, or network shares mounted without `chown`).
  - Bind mounts (`./config`, `./shares`) work on **Linux** hosts with a Unix filesystem (ext4, xfs, btrfs, zfs) or inside WSL2. On macOS and on Windows with `C:\` folders the shared filesystem does not honor owner, group and setgid: new files end up `root:root` and the `users` group is not inherited (fine for quick tests only). For real data use **named Docker volumes** (`volumes: [samba-config:/config, samba-shares:/shares]` plus a top-level `volumes:` section), which work everywhere.
  - With SELinux (Fedora, RHEL) add `:z` to the bind mounts.
- Port 445 free on the host. On the Mac that hosts the server, Finder and Cmd+K cannot connect to the local port 445: for tests publish `127.0.0.2:445:445` after `sudo ifconfig lo0 alias 127.0.0.2` (reset at reboot) and connect to `smb://user@127.0.0.2`. Not needed from another computer.

## Quick start

Using the published image:

```bash
git clone https://github.com/crikfilippo/DockerSambaTui.git
cd DockerSambaTui
docker compose up -d          # pulls ghcr.io/crikfilippo/docker-samba-tui:latest
docker logs samba             # shows the startup message
docker exec -it samba bash    # enter and use tui-users / tui-samba / guida
```

Building from source instead: `docker compose up -d --build`.

To pin a version, change `image:` in `docker-compose.yml` to a tag such as `ghcr.io/crikfilippo/docker-samba-tui:0.1.0`.

## Usage

Order matters: group, Unix user, Samba account, share.

| What | Where | How |
|---|---|---|
| Group | `tui-users` | `tab` to the groups screen, then `n`. Lowercase names. |
| Unix user | `tui-users` | `n`; "Groups" with the user's level group; **"Create home" = no**. |
| Samba account | `tui-samba` | `2` (Accounts), `a`, set the SMB password. |
| Share | `tui-samba` | `1` (Shares), `n`, see below. |
| Delete a user | both | first `x` in `tui-samba` (Accounts), then `D` in `tui-users`. |

Fields of the new share form:

| Field | Value |
|---|---|
| Path | `/shares/<name>`, always a **new** path |
| Create the path | yes |
| Owner:group | `root:users` (pre-filled) |
| Valid users | allowed groups, e.g. `@management @staff` |
| Write list | groups that can write, with "Read only" = yes; or empty with "Read only" = no |
| Create mask / Directory mask | `0664` / `0775` (form defaults; ignored because permissions are inherited) |

tui-samba does not modify existing folders: if a path already exists, its owner and mode stay as they are.

## Connecting from clients

- Windows: `\\<host>\<share>` (or "Map network drive").
- macOS: `smb://<host>/<share>`.
- Linux: `sudo mount -t cifs //<host>/<share> /mnt/<share> -o username=<user>`.

Log in with the user name and the password set in tui-samba. If several people edit the same file at the same time, the last save wins.

## Build configuration

Dockerfile arguments (`docker compose build --build-arg NAME=value`):

| Argument | Default | Meaning |
|---|---|---|
| `TUI_SAMBA_REF` | `v0.2.4` | tui-samba tag to build |
| `TUI_USERS_REF` | `v0.2.2` | tui-users tag to build |
| `DEFAULT_OWNER` | `root:users` | value proposed in "Owner:group" |
| `GO_IMAGE` | `golang:bookworm` | image used to compile |

If you change the tags, the build stops with a clear error when the line to patch in `form.go` no longer exists.

## Publishing the image

Multi-architecture build and push to GitHub Container Registry (after `docker login ghcr.io` with a token that has `write:packages`):

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  --label org.opencontainers.image.source=https://github.com/crikfilippo/DockerSambaTui \
  --label org.opencontainers.image.licenses=MIT \
  -t ghcr.io/crikfilippo/docker-samba-tui:0.1.0 \
  -t ghcr.io/crikfilippo/docker-samba-tui:latest \
  --push .
```

## Persistence

Everything that matters is in the two volumes mounted on `/config` and `/shares` (in the sample compose, the `config/` and `shares/` folders):

- `config/samba/` is `/etc/samba` (including `smb.conf` and `tui-samba.d/`).
- `config/var-lib-samba/` is `/var/lib/samba` (Samba password database).
- `config/accounts/` holds copies of `passwd`, `group`, `shadow`, `gshadow`, `subuid`, `subgid`, updated within 2 seconds of every change and restored at every start.

Back up both folders together: Samba accounts only make sense with the matching Unix users.

## Security

- Samba is the only access control: folders are open to members of `users` at the filesystem level. This is fine as long as nobody accesses the files in other ways (shell in the container, other services).
- Do not expose port 445 to the internet: use a trusted network or a VPN.
- `config/` contains password hashes: protect it like a credentials backup.

## Tests

```bash
tests/test-scripts.sh [path/to/tui-samba/cmd/tui-samba/form.go]
```

Checks script syntax, account persistence, the fake `systemctl` and (if you pass `form.go`) the default-owner patch.

## Layout

```
Dockerfile           two-stage build (compiles the tools, then Ubuntu 26.04 + Samba)
docker-compose.yml   one service, two volumes
smb.conf             starting configuration (first start only)
config/tui.toml      shared configuration of the two tools (sudo = "")
scripts/             entrypoint, fake systemctl, startup message
build/               patch for the tui-samba default owner
tests/               tests that run without Docker
ANALISI.md           analysis: how it works, choices, risks (in Italian)
```

## License

MIT, see [`LICENSE`](LICENSE). The image also includes the licenses of the two tools in `/usr/share/doc/samba-tui/`; Samba is GPL (Ubuntu package).

## Credits

tui-samba and tui-users are by [tui-tools](https://github.com/tui-tools) (MIT license) and are compiled from their source during the build.
