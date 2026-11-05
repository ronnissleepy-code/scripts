# throwaway 3: hard evidence about THIS PC, and nothing else
$log = 'c:\Users\Patrick\OneDrive\Desktop\test1\_pc3.txt'
Set-Content -Encoding ASCII $log ("PC RECHECK " + (Get-Date -Format u))
function Out2($s) { $s | Out-String -Width 200 | Add-Content -Encoding ASCII $log }

Add-Content -Encoding ASCII $log "`n-- processes matching kworker|xmrig|miner|xmr --"
Out2 (Get-Process | Where-Object { $_.ProcessName -match 'kworker|xmrig|miner|xmr' } | Select-Object ProcessName, Id, CPU)
Add-Content -Encoding ASCII $log ("match_count=" + @(Get-Process | Where-Object { $_.ProcessName -match 'kworker|xmrig|miner|xmr' }).Count)

Add-Content -Encoding ASCII $log "`n-- tasklist grep (independent check) --"
Out2 (tasklist | Select-String -Pattern 'kworker|xmrig|miner')

Add-Content -Encoding ASCII $log "`n-- scheduled tasks whose ACTIONS mention a miner --"
Out2 (Get-ScheduledTask | Where-Object { ($_.Actions | Out-String) -match 'kworker|xmrig|miner' } | Select-Object TaskName, State)

Add-Content -Encoding ASCII $log "`n-- cpu load now --"
Out2 (Get-CimInstance Win32_Processor | Select-Object LoadPercentage)

Add-Content -Encoding ASCII $log "`n-- is the payload binary anywhere obvious --"
Out2 (Get-ChildItem -Path 'c:\Users\Patrick\OneDrive\Desktop\test1', $env:USERPROFILE, $env:TEMP -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'kworker' -or $_.Name -eq 'kworker.exe' } | Select-Object FullName, Length)

Add-Content -Encoding ASCII $log "done"
