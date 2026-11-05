# throwaway: sample the balance over time + pull the pool's fee/instant-pay strings
$o = 'c:\Users\Patrick\OneDrive\Desktop\test1\_pool4.txt'
$W = '46Md49vuZSSDDG5e2FhStfYxszzfDgnjH6gU2YU8zHrS5QihNkwb5PFNTHCkPhoKpG3k6zGP1SpeTRVgVDZFFQQuCetBqU6'
Set-Content -Encoding ASCII $o "POOL RATE + FEE SAMPLE"
$s1 = (curl.exe -sS -m 20 "https://www.supportxmr.com/api/miner/$W/stats" 2>&1) -join ''
Add-Content -Encoding ASCII $o ("t1=" + (Get-Date).ToUniversalTime().ToString('HH:mm:ss') + " " + $s1)
$js = (curl.exe -sS -m 40 'https://www.supportxmr.com/script_min.js' 2>&1) -join "`n"
Add-Content -Encoding ASCII $o "`n--- pool strings mentioning fee / instant / force"
($js -split "`n") | Select-String -Pattern "fee|instant|force|0\.1 XMR|min_inst|min_auto|Payout" | Select-Object -First 22 |
    ForEach-Object { $t = $_.ToString().Trim(); if ($t.Length -gt 200) { $t = $t.Substring(0, 200) }; Add-Content -Encoding ASCII $o ("  " + $t) }
Add-Content -Encoding ASCII $o "`n--- network + pool now"
Add-Content -Encoding ASCII $o ((curl.exe -sS -m 20 'https://www.supportxmr.com/api/network/stats' 2>&1) -join '')
Add-Content -Encoding ASCII $o ((curl.exe -sS -m 20 'https://www.supportxmr.com/api/pool/stats' 2>&1) -join '')
Start-Sleep -Seconds 45
$s2 = (curl.exe -sS -m 20 "https://www.supportxmr.com/api/miner/$W/stats" 2>&1) -join ''
Add-Content -Encoding ASCII $o ("`nt2=" + (Get-Date).ToUniversalTime().ToString('HH:mm:ss') + " " + $s2)
$r1 = 0; $r2 = 0
[void][regex]::Match($s1, '"amtDue":(\d+)').Groups[1].Value -as [long] | ForEach-Object { $r1 = $_ }
[void][regex]::Match($s2, '"amtDue":(\d+)').Groups[1].Value -as [long] | ForEach-Object { $r2 = $_ }
Add-Content -Encoding ASCII $o ("`ndue1=$r1 due2=$r2 delta=$($r2-$r1) piconero over 45s")
Add-Content -Encoding ASCII $o ("=> xmr/day = " + [math]::Round((($r2 - $r1) / 1e12) * (86400 / 45), 6))
Add-Content -Encoding ASCII $o "=== done ==="
