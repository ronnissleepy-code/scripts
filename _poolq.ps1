# throwaway: ask supportxmr (all keyless) for the payout rule + network stats
$W = '46Md49vuZSSDDG5e2FhStfYxszzfDgnjH6gU2YU8zHrS5QihNkwb5PFNTHCkPhoKpG3k6zGP1SpeTRVgVDZFFQQuCetBqU6'
$o = 'c:\Users\Patrick\OneDrive\Desktop\test1\_pool2.txt'
Set-Content -Encoding ASCII $o "SUPPORTXMR QUERY"
Add-Content -Encoding ASCII $o ("utc=" + (Get-Date).ToUniversalTime().ToString('u'))

$urls = @(
    "https://www.supportxmr.com/api/network/stats",
    "https://www.supportxmr.com/api/pool/stats",
    "https://www.supportxmr.com/api/pool/config",
    "https://www.supportxmr.com/api/miner/$W/stats",
    "https://www.supportxmr.com/api/miner/$W/payments",
    "https://www.supportxmr.com/api/miner/$W/threshold",
    "https://www.supportxmr.com/api/miner/$W/identifiers"
)
foreach ($u in $urls) {
    Add-Content -Encoding ASCII $o "`n--- $u"
    $body = (curl.exe -sS -m 20 -w "`n[http=%{http_code}]" $u 2>&1) -join "`n"
    if ($body.Length -gt 900) { $body = $body.Substring(0, 900) + " ...[truncated]" }
    Add-Content -Encoding ASCII $o $body
}
Add-Content -Encoding ASCII $o "`n=== done ==="
