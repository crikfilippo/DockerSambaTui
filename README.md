# samba-tui

Un server Samba in un container Debian, gestibile interamente da terminale con due TUI: [tui-users](https://github.com/tui-tools/tui-users) per utenti e gruppi Unix e [tui-samba](https://github.com/tui-tools/tui-samba) per account Samba e share. Nessuna interfaccia web, nessun systemd, due soli volumi.

Nato per condividere cartelle di lavoro (per esempio le collection di [Bruno](https://www.usebruno.com/)) fra più persone con un server centrale: chi salva un file lo rende subito disponibile agli altri, senza push o pull.

> **Stato del progetto:** i file sono stati scritti e le parti di logica (script, patch del sorgente) sono coperte da test eseguiti senza Docker, ma l'immagine **non è ancora stata costruita né avviata** su un host reale. Vedi [`ANALISI.md`](ANALISI.md) per i punti ancora da verificare. Anche tui-users e tui-samba sono software molto giovane (beta).

## Cosa fa

- Debian 12 con Samba (solo SMB2+, porta 445, nessun accesso guest).
- Gestione da terminale: `tui-users` e `tui-samba`, già configurati per girare come root nel container.
- Due volumi: `/config` (configurazione Samba, database delle password, account Unix) e `/shares` (la cartella padre di tutte le share).
- Nuovi file e cartelle ereditano gruppo e permessi dalla share che li contiene.
- Ogni nuovo utente ha `users` come gruppo principale, shell `nologin` e nessuna password Unix.
- Un messaggio iniziale con la procedura compare nei log (`docker logs`) e a ogni `docker exec -it samba bash`.

## Requisiti

- Docker con Compose v2 e accesso a internet durante la build (solo per l'immagine `debian:bookworm-slim` e i pacchetti Samba). I due tool sono già compilati in `bin/`.
- Un filesystem host che supporti proprietari e permessi Unix per le cartelle `config/` e `shares/` (non NTFS, exFAT o share di rete montate senza `chown`).
- La porta 445 libera sull'host.

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

## Aggiornare i tool

I binari in `bin/amd64/` e `bin/arm64/` sono compilati da `Dockerfile.build` (clona i due tool da GitHub, applica la patch del default "Owner:group" e compila con la toolchain Go richiesta). Per rigenerarli:

```
sh build/rebuild-binaries.sh [--build-arg TUI_SAMBA_REF=vX.Y.Z] [--build-arg TUI_USERS_REF=vX.Y.Z]
```

Argomenti di `Dockerfile.build`: `TUI_SAMBA_REF` (default `v0.2.4`), `TUI_USERS_REF` (`v0.2.2`), `DEFAULT_OWNER` (`root:users`), `GO_IMAGE` (`golang:bookworm`). Se cambi i tag, la build si ferma con un errore chiaro quando la riga da modificare in `form.go` non esiste più. Poi `docker compose up -d --build` e commit di `bin/`.

## Persistenza

Tutto ciò che conta sta in `config/` e `shares/`:

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
Dockerfile           immagine finale (Debian + Samba + binari di bin/)
Dockerfile.build     compila i tool, solo per rigenerare bin/
bin/                 tui-samba e tui-users precompilati (amd64, arm64)
docker-compose.yml   un servizio, due volumi
smb.conf             configurazione di partenza (solo al primo avvio)
config/tui.toml      configurazione comune dei due tool (sudo = "")
scripts/             entrypoint, finto systemctl, messaggio iniziale
build/               patch del default di tui-samba, rebuild-binaries.sh
tests/               test senza Docker
ANALISI.md           analisi: funzionamento, scelte, rischi
```

## Crediti

tui-samba e tui-users sono di [tui-tools](https://github.com/tui-tools) (licenza MIT) e sono compilati dal loro sorgente (`Dockerfile.build`).
