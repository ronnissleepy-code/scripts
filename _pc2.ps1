# throwaway 2: is ANYTHING mining on this Windows PC? (append-only, so nothing is lost)
$log = 'c:\Users\Patrick\OneDrive\Desktop\test1\_pc2.txt'
Set-Content -Encoding ASCII $log "PC MINER AUDIT"
function W($s) { $s | Out-String -Width 300 | Add-Content -Encoding ASCII $log }
function H($s) { Add-Content -Encoding ASCII $log "`n=== $s ===" }

H "1. processes matching miner names"
W (Get-Process | Where-Object { $_.ProcessName -match 'kworker|xmrig|miner|xmr' } |
    Select-Object ProcessName, Id, CPU, @{n='MemMB';e={[int]($_.WS/1MB)}}, Path |
    Sort-Object -Property CPU -Descending | Format-Table -AutoSize)

H "2. top 10 processes by CPU time"
W (Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 ProcessName, Id, CPU | Format-Table -AutoSize)

H "3. process command lines mentioning kworker/xmrig/pool/.sysd"
W (Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -match 'kworker|xmrig|supportxmr|stratum|\.sysd' } |
    Select-Object ProcessId, Name, CommandLine | Format-List)

H "4. scheduled tasks matching kworker/miner/xmr"
W (Get-ScheduledTask -ErrorAction SilentlyContinue |
    Where-Object { $_.TaskName -match 'kworker|miner|xmr' } | Select-Object TaskName, State | Format-Table -AutoSize)

H "5. services matching kworker/miner/xmr"
W (Get-Service | Where-Object { $_.Name -match 'kworker|xmr|miner' } | Select-Object Name, Status, StartType | Format-Table -AutoSize)

H "6. Run / RunOnce / startup folder"
W (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue | Format-List)
W (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue | Format-List)
W (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -ErrorAction SilentlyContinue | Format-List)
W (Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" -ErrorAction SilentlyContinue | Select-Object Name)

H "7. WSL distros"
W (wsl.exe -l -v 2>&1)

H "8. miner files in home (depth 2), temp, and the kit dir"
W (Get-ChildItem -Path $env:USERPROFILE -Recurse -Depth 2 -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^(kworker|xmrig)|\.sysd' } |
    Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize)
W (Get-ChildItem -Path $env:TEMP -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'kworker|xmrig|sysd' } | Select-Object FullName, LastWriteTime)
W (Get-ChildItem -Path 'c:\Users\Patrick\OneDrive\Desktop\test1' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'kworker|xmrig' } | Select-Object Name, Length)

H "9. established non-LAN TCP sockets (a pool socket would show here)"
$own = @{}
Get-Process | ForEach-Object { $own[[int]$_.Id] = $_.ProcessName }
W (Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
    Where-Object { $_.RemoteAddress -notmatch '^(127\.|::1|192\.168\.|10\.|169\.254\.)' } |
    Select-Object @{n='Proc';e={$own[[int]$_.OwningProcess]}}, RemoteAddress, RemotePort |
    Sort-Object Proc -Unique | Format-Table -AutoSize)

Add-Content -Encoding ASCII $log "`n=== done $([DateTime]::UtcNow.ToString('u')) ==="
