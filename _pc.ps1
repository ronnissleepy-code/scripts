# throwaway: is ANYTHING mining on this Windows PC?
$log = 'c:\Users\Patrick\OneDrive\Desktop\test1\_pc.txt'
function W($s) { $s | Out-String -Width 300 | Add-Content -Encoding ASCII $log }

Set-Content -Encoding ASCII $log "=== 1. processes matching miner/WSL names ==="
Get-Process | Where-Object { $_.ProcessName -match 'kworker|xmrig|miner|xmr|wsl|wslhost|wslservice' } |
    Select-Object ProcessName, Id, CPU, @{n='MemMB';e={[int]($_.WS/1MB)}}, Path |
    Sort-Object -Property CPU -Descending | Format-Table -AutoSize | W

Set-Content -Encoding ASCII $log "=== 2. top 12 by CPU time ==="
Get-Process | Sort-Object CPU -Descending | Select-Object -First 12 ProcessName, Id, CPU |
    Format-Table -AutoSize | W

Set-Content -Encoding ASCII $log "=== 3. command lines mentioning kworker/xmrig/pool/stratum ==="
Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -match 'kworker|xmrig|supportxmr|stratum|\.sysd' } |
    Select-Object ProcessId, Name, CommandLine | Format-List | W

Set-Content -Encoding ASCII $log "=== 4. scheduled tasks (name or action) ==="
Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskName -match 'kworker|miner|xmr' -or ($_.Actions | Out-String) -match 'kworker|xmrig' } |
    Select-Object TaskName, State | Format-Table -AutoSize | W

Set-Content -Encoding ASCII $log "=== 5. services ==="
Get-Service | Where-Object { $_.Name -match 'kworker|xmr|miner' -or $_.DisplayName -match 'kworker|xmr' } |
    Select-Object Name, Status, StartType, DisplayName | Format-Table -AutoSize | W

Set-Content -Encoding ASCII $log "=== 6. autostart: Run keys ==="
W 'HKCU:'
W (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue |
    Select-Object * -Exclude PS* | Format-List)
W 'HKLM:'
W (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue |
    Select-Object * -Exclude PS* | Format-List)
W 'startup folder:'
W (Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" -ErrorAction SilentlyContinue | Select-Object Name)
W 'runonce:'
W (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -ErrorAction SilentlyContinue | Select-Object * -Exclude PS* | Format-List)

Set-Content -Encoding ASCII $log "=== 7. WSL ==="
W (wsl.exe -l -v 2>&1)

Set-Content -Encoding ASCII $log "=== 8. kworker/xmrig files under home and repo (depth 3) ==="
Get-ChildItem -Path $env:USERPROFILE, 'c:\Users\Patrick\OneDrive\Desktop\test1' -Recurse -Depth 3 -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'kworker|xmrig|\.sysd|miner' } |
    Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize | W

Set-Content -Encoding ASCII $log "=== 9. established outbound sockets with owning process ==="
$own = @{}
Get-Process | ForEach-Object { $own[[int]$_.Id] = $_.ProcessName }
Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
    Where-Object { $_.RemoteAddress -notmatch '^(127\.|::1|192\.168\.|10\.)' } |
    Select-Object @{n='Proc';e={$own[[int]$_.OwningProcess]}}, LocalPort, RemoteAddress, RemotePort, State |
    Sort-Object Proc | Format-Table -AutoSize | W

Set-Content -Encoding ASCII $log "=== 10. pool DNS ==="
W (Resolve-DnsName pool.supportxmr.com -ErrorAction SilentlyContinue | Select-Object Name, IPAddress -First 4 |
    Format-Table -AutoSize)

Add-Content -Encoding ASCII $log "=== done $([DateTime]::UtcNow.ToString('u')) ==="
