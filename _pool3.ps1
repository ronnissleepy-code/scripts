# throwaway: supportxmr min-payout / payout schedule, from their own assets
$o = 'c:\Users\Patrick\OneDrive\Desktop\test1\_pool3.txt'
Set-Content -Encoding ASCII $o "SUPPORTXMR RULES QUERY"
function A($s) { Add-Content -Encoding ASCII $o $s }

$h = (curl.exe -sS -m 25 'https://www.supportxmr.com/' 2>&1) -join "`n"
A ("root_bytes=" + $h.Length)
$js = [regex]::Matches($h, 'src="([^"]+\.[a-z]+[^"]*)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
A ("script_srcs=" + ($js -join ' | '))
$css = [regex]::Matches($h, 'href="([^"]+\.css[^"]*)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
A ("css_hrefs=" + ($css -join ' | '))

$n = 0
foreach ($j in $js) {
    if ($n -ge 3) { break }
    if ($j -notmatch '\.js') { continue }
    $u = if ($j -match '^https?://') { $j } else { 'https://www.supportxmr.com/' + $j.TrimStart('/') }
    A "`n--- bundle $u"
    $b = (curl.exe -sS -m 45 $u 2>&1) -join "`n"
    A ("bytes=" + $b.Length)
    $hits = ($b -split "`n") | Select-String -Pattern 'min_?[Pp]ayout|minimum|0\.1 XMR|threshold|payout' |
            Select-Object -First 20
    foreach ($x in $hits) {
        $t = $x.ToString().Trim()
        if ($t.Length -gt 260) { $t = $t.Substring(0, 260) }
        A ("  " + $t)
    }
    $n++
}

foreach ($u in @('https://www.supportxmr.com/api/pool/payments',
                 'https://www.supportxmr.com/api/pool/blocks',
                 'https://www.supportxmr.com/api/miner/46Md49vuZSSDDG5e2FhStfYxszzfDgnjH6gU2YU8zHrS5QihNkwb5PFNTHCkPhoKpG3k6zGP1SpeTRVgVDZFFQQuCetBqU6/stats')) {
    A "`n--- $u"
    $r = (curl.exe -sS -m 20 -w " [http=%{http_code}]" $u 2>&1) -join "`n"
    if ($r.Length -gt 300) { $r = $r.Substring(0, 300) }
    A $r
}
A "`n=== done ==="
