# samba-tui

Un server Samba in un container Ubuntu 26.04 LTS, gestibile interamente da terminale con due TUI: [tui-users](https://github.com/tui-tools/tui-users) per utenti e gruppi Unix e [tui-samba](https://github.com/tui-tools/tui-samba) per account Samba e share. Nessuna interfaccia web, nessun systemd, due soli volumi.

Nato per condividere cartelle di lavoro (per esempio le collection di [Bruno](https://www.usebruno.com/)) fra più persone con un server centrale: chi salva un file lo rende subito disponibile agli altri, senza push o pull.

> **Stato del progetto:** l'immagine è stata costruita e provata (Docker Desktop su Mac, `docker compose`, `smbclient`, Finder): avvio, persistenza dopo il riavvio, gruppi e utenti, scrittura da più utenti di gruppi diversi, sola lettura e rifiuto degli utenti non ammessi. Non provati: client Windows, Office reale, host Linux di produzione. I punti aperti sono in [`ANALISI.md`](ANALISI.md). Anche tui-users e tui-samba sono software molto giovane (beta) e il TUI mostra `(untested)` accanto alla versione di Samba.

## Cosa fa

- Ubuntu 26.04 LTS con Samba 4.23 (solo SMB2+, porta 445, nessun accesso guest).
- Gestione da terminale: `tui-users` e `tui-samba`, già configurati per girare come root nel container.
- Due volumi: `/config` (configurazione Samba, database delle password, account Unix) e `/shares` (la cartella padre di tutte le share).
- Nuovi file e cartelle ereditano gruppo e permessi dalla share che li contiene.
- Ogni nuovo utente ha `users` come gruppo principale, shell `nologin` e nessuna password Unix.
- Un messaggio iniziale con la procedura compare nei log (`docker logs`) e a ogni `docker exec -it samba bash`.
- Log di Samba su `docker logs` (`log level = 3`, ruotati dal compose: 10 MB x 3). Livello modificabile a caldo: `smbcontrol all debug N`.
- File di sistema inutili (`Thumbs.db`, `desktop.ini`, `.DS_Store`, `._*`) rifiutati dal server. I lock di Office `~$*` no, servono per l'avviso "file in uso".

## Requisiti

- Docker con Compose v2. Con la build dal sorgente serve internet (immagini `golang` e `ubuntu`, pacchetti Samba, clone dei due tool da GitHub); con l'immagine già pronta (vedi sotto) non serve niente. Con `docker run` (senza compose) aggiungi `--init`.
- Un filesystem che supporti proprietari e permessi Unix per `config/` e `shares/` (non NTFS, exFAT o share di rete montate senza `chown`).
  - Il bind mount (`./config`, `./shares`) funziona su host **Linux** con un filesystem Unix (ext4, xfs, btrfs, zfs) o dentro WSL2. Su macOS e su Windows con cartelle `C:\` il filesystem condiviso non rispetta owner, gruppo e setgid: i nuovi file escono `root:root` e il gruppo `users` non viene ereditato (ok solo per prove rapide). Per i dati reali usa **volumi Docker con nome** (`volumes: [samba-config:/config, samba-shares:/shares]` + sezione `volumes:`), che funzionano ovunque.
  - Con SELinux (Fedora, RHEL) aggiungi `:z` ai bind mount.
- La porta 445 libera sull'host. Sul Mac che ospita il server, Finder e Cmd+K non si collegano alla 445 locale: per le prove pubblica `127.0.0.2:445:445` dopo `sudo ifconfig lo0 alias 127.0.0.2` (si azzera al riavvio) e collegati a `smb://utente@127.0.0.2`. Da un altro computer non serve.

## Avvio

```bash
git clone <questo repository> samba-tui
cd samba-tui
docker compose up -d --build
docker logs samba            # mostra il messaggio iniziale
docker exec -it samba bash   # entra e usa tui-users / tui-samba / guida
```

## Uso

L'ordine conta: gruppo, utente Unix, account Samba, share.

| Cosa | Dove | Come |
|---|---|---|
| Gruppo | `tui-users` | `tab` fino ai gruppi, poi `n`. Nomi minuscoli. |
| Utente Unix | `tui-users` | `n`; "Groups" con il suo gruppo di livello; **"Create home" = no**. |
| Account Samba | `tui-samba` | `2` (Accounts), `a`, imposta la password SMB. |
| Share | `tui-samba` | `1` (Shares), `n`, vedi sotto. |
| Eliminare un utente | entrambi | prima `x` in `tui-samba` (Accounts), poi `D` in `tui-users`. |

Campi del form di una nuova share:

| Campo | Valore |
|---|---|
| Path | `/shares/<nome>`, sempre un path **nuovo** |
| Create the path | sì |
| Owner:group | `root:users` (già compilato) |
| Valid users | gruppi ammessi, es. `@amministrazione @dipendenti` |
| Write list | gruppi che possono scrivere, con "Read only" = sì; oppure vuoto con "Read only" = no |
| Create mask / Directory mask | `0664` / `0775` (default del form; ignorate perché i permessi sono ereditati) |

tui-samba non modifica le cartelle già esistenti: se un path esiste, owner e mode restano quelli che ha.

## Collegarsi dai client

- Windows: `\\<host>\<share>` (o "Connetti unità di rete").
- macOS: `smb://<host>/<share>`.
- Linux: `sudo mount -t cifs //<host>/<share> /mnt/<share> -o username=<utente>`.

Si accede con il nome dell'utente e la password impostata in tui-samba. Se più persone modificano lo stesso file contemporaneamente, vince l'ultimo salvataggio.

## Configurazione della build

Argomenti del Dockerfile (`docker compose build --build-arg NOME=valore`):

| Argomento | Default | Significato |
|---|---|---|
| `TUI_SAMBA_REF` | `v0.2.4` | tag di tui-samba da compilare |
| `TUI_USERS_REF` | `v0.2.2` | tag di tui-users da compilare |
| `DEFAULT_OWNER` | `root:users` | valore proposto in "Owner:group" |
| `GO_IMAGE` | `golang:bookworm` | immagine usata per compilare |

Se cambi i tag, la build si ferma con un errore chiaro quando la riga da modificare in `form.go` non esiste più.

## Immagine già pronta (senza internet)

Per costruire l'immagine e salvarla in un file (default `linux/amd64`, cartella `dist/`):

```
sh build/export-image.sh [cartella] [piattaforma]
```

Sul server: `docker load < samba-tui-amd64.tar.gz`, poi `docker compose up -d` (senza `--build`). Con `docker run` aggiungi `--init`.

## Persistenza

Tutto ciò che conta sta nei due volumi montati su `/config` e `/shares` (nel compose di esempio le cartelle `config/` e `shares/`):

- `config/samba/` è `/etc/samba` (compreso `smb.conf` e `tui-samba.d/`).
- `config/var-lib-samba/` è `/var/lib/samba` (database delle password Samba).
- `config/accounts/` contiene copie di `passwd`, `group`, `shadow`, `gshadow`, `subuid`, `subgid`, aggiornate entro 2 secondi da ogni modifica e ripristinate a ogni avvio.

Fai il backup di entrambe le cartelle insieme: gli account Samba hanno senso solo con gli utenti Unix corrispondenti.

## Sicurezza

- Samba è l'unico controllo di accesso: le cartelle sono aperte ai membri di `users` a livello di filesystem. Va bene finché nessuno accede ai file in altri modi (shell nel container, altri servizi).
- Non esporre la porta 445 su internet: usa una rete fidata o una VPN.
- `config/` contiene hash delle password: proteggila come un backup di credenziali.

## Test

```bash
tests/test-scripts.sh [percorso/di/tui-samba/cmd/tui-samba/form.go]
```

Verifica sintassi degli script, persistenza degli account, `systemctl` finto e (se passi `form.go`) la patch del default.

## Struttura

```
Dockerfile           build in due stadi (compila i tool, poi Ubuntu 26.04 + Samba)
docker-compose.yml   un servizio, due volumi
smb.conf             configurazione di partenza (solo al primo avvio)
config/tui.toml      configurazione comune dei due tool (sudo = "")
scripts/             entrypoint, finto systemctl, messaggio iniziale
build/               patch del default di tui-samba, export-image.sh
tests/               test senza Docker
ANALISI.md           analisi: funzionamento, scelte, rischi
```

## Crediti

tui-samba e tui-users sono di [tui-tools](https://github.com/tui-tools) (licenza MIT) e vengono compilati dal loro sorgente durante la build.
