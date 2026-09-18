$ErrorActionPreference = "Stop"

$OldTask = "StudioSat-RadioBOSS-NS1-Tunnel"
$Task = "StudioSat-RadioPrincipal-Unified"
$Root = "C:\ProgramData\StudioSat\RadioPrincipalUnified"
$Key = "C:\ProgramData\StudioSat\RadioBOSSTunnel\id_ed25519"
$Ssh = "C:\Windows\System32\OpenSSH\ssh.exe"
$Bat = Join-Path $Root "run.cmd"
$Log = Join-Path $Root "tunnel.log"

New-Item -ItemType Directory -Force -Path $Root | Out-Null

$cmd = @'
@echo off
:loop
echo [%date% %time%] starting unified tunnel>>"__LOG__"
"__SSH__" -NT -p 22 ^
  -L 127.0.0.1:18005:127.0.0.1:18005 ^
  -L 127.0.0.1:18796:127.0.0.1:8796 ^
  -i "__KEY__" ^
  -o BatchMode=yes ^
  -o ExitOnForwardFailure=yes ^
  -o ServerAliveInterval=10 ^
  -o ServerAliveCountMax=3 ^
  -o TCPKeepAlive=yes ^
  -o ConnectTimeout=10 ^
  -o StrictHostKeyChecking=accept-new ^
  studiosat-rb-tunnel@ns1.tpsolutions.com.br >>"__LOG__" 2>&1
echo [%date% %time%] tunnel ended, retrying>>"__LOG__"
timeout /t 3 /nobreak >nul
goto loop
'@
$cmd = $cmd.Replace("__LOG__",$Log).Replace("__SSH__",$Ssh).Replace("__KEY__",$Key)
Set-Content -LiteralPath $Bat -Value $cmd -Encoding ASCII

Write-Host "===== STOP OLD TUNNEL TASK ====="
schtasks.exe /End /TN $OldTask 2>$null | Out-Null
schtasks.exe /Disable /TN $OldTask 2>$null | Out-Null

Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
  Where-Object { $_.CommandLine -match "127\.0\.0\.1:18005:127\.0\.0\.1:18005" } |
  ForEach-Object {
    try {
      Write-Host "KILL_OLD_SSH_PID=$($_.ProcessId)"
      Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null
    } catch {}
  }

Write-Host "===== INSTALL UNIFIED AUTOSTART ====="
schtasks.exe /Delete /TN $Task /F 2>$null | Out-Null
$tr = 'cmd.exe /c "' + $Bat + '"'
schtasks.exe /Create /TN $Task /SC ONSTART /RU SYSTEM /RL HIGHEST /TR $tr /F | Out-Host
schtasks.exe /Run /TN $Task | Out-Host

$ready=$false
for($i=1;$i -le 20;$i++){
  Start-Sleep -Seconds 1
  $l=Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 18005 -State Listen -ErrorAction SilentlyContinue
  if($l){
    $ready=$true
    Write-Host "LOCAL_18005_LISTEN=YES AFTER=$($i)s"
    break
  }
}
if(-not $ready){
  Write-Host "LOCAL_18005_LISTEN=NO"
  Get-Content $Log -Tail 80 -ErrorAction SilentlyContinue
  exit 20
}

Write-Host "===== RADIOBOSS TARGET ====="
Write-Host "127.0.0.1:18005/radioprincipal-rb"

Write-Host "===== TASK ====="
Get-ScheduledTask -TaskName $Task | Select-Object TaskName,State

Write-Host "===== SSH ====="
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
  Where-Object { $_.CommandLine -match "127\.0\.0\.1:18005:127\.0\.0\.1:18005" } |
  Select-Object ProcessId,CommandLine | Format-List

Write-Host "===== LOG ====="
Get-Content $Log -Tail 40 -ErrorAction SilentlyContinue

Write-Host "OLD_TUNNEL_TASK_DISABLED=YES"
Write-Host "UNIFIED_TUNNEL_AUTOSTART=YES"
Write-Host "RESULTADO=C26_WINDOWS_UNIFIED_TUNNEL_READY"
