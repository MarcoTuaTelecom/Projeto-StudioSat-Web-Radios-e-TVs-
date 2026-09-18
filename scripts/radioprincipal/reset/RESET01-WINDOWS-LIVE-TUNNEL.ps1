$ErrorActionPreference = "Stop"
$Task = "StudioSat-RadioPrincipal-Live"
$Root = "C:\ProgramData\StudioSat\RadioPrincipalLive"
$Key  = "C:\ProgramData\StudioSat\RadioBOSSTunnel\id_ed25519"
$Ssh  = "C:\Windows\System32\OpenSSH\ssh.exe"
$Cmd  = Join-Path $Root "run.cmd"
$Log  = Join-Path $Root "live-tunnel.log"

New-Item -ItemType Directory -Force -Path $Root | Out-Null
if(-not (Test-Path $Key)){ throw "SSH private key not found: $Key" }

$body = @'
@echo off
:loop
echo [%date% %time%] starting Radio Principal live tunnel>>"__LOG__"
"__SSH__" -NT -p 22 ^
  -L 127.0.0.1:18005:127.0.0.1:18005 ^
  -i "__KEY__" ^
  -o BatchMode=yes ^
  -o ExitOnForwardFailure=yes ^
  -o ServerAliveInterval=10 ^
  -o ServerAliveCountMax=3 ^
  -o TCPKeepAlive=yes ^
  -o ConnectTimeout=10 ^
  -o StrictHostKeyChecking=accept-new ^
  studiosat-rb-tunnel@ns1.tpsolutions.com.br >>"__LOG__" 2>&1
echo [%date% %time%] tunnel exited; retrying>>"__LOG__"
timeout /t 3 /nobreak >nul
goto loop
'@
$body=$body.Replace("__LOG__",$Log).Replace("__SSH__",$Ssh).Replace("__KEY__",$Key)
Set-Content -LiteralPath $Cmd -Value $body -Encoding ASCII

Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
  Where-Object { $_.CommandLine -match "127\.0\.0\.1:18005:127\.0\.0\.1:18005" } |
  ForEach-Object {
    Write-Host "STOP_OLD_FORWARD_PID=$($_.ProcessId)"
    try { Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null } catch {}
  }

foreach($old in @("StudioSat-RadioBOSS-NS1-Tunnel","StudioSat-RadioPrincipal-Unified")){
  schtasks.exe /End /TN $old 2>$null | Out-Null
  schtasks.exe /Disable /TN $old 2>$null | Out-Null
}

schtasks.exe /Delete /TN $Task /F 2>$null | Out-Null
$tr='cmd.exe /c "'+$Cmd+'"'
schtasks.exe /Create /TN $Task /SC ONSTART /RU SYSTEM /RL HIGHEST /TR $tr /F | Out-Host
schtasks.exe /Run /TN $Task | Out-Host

$ok=$false
for($i=1;$i -le 20;$i++){
  Start-Sleep -Seconds 1
  if(Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 18005 -State Listen -ErrorAction SilentlyContinue){
    $ok=$true
    Write-Host "LOCAL_18005_LISTEN=YES AFTER=$($i)s"
    break
  }
}
if(-not $ok){
  Write-Host "LOCAL_18005_LISTEN=NO"
  Get-Content $Log -Tail 80 -ErrorAction SilentlyContinue
  exit 20
}
$t=Test-NetConnection 127.0.0.1 -Port 18005 -WarningAction SilentlyContinue
Write-Host "TCP_18005=$($t.TcpTestSucceeded)"
Write-Host "TASK=$Task"
Get-ScheduledTask -TaskName $Task | Select-Object TaskName,State
Write-Host "RADIOBOSS_TARGET=127.0.0.1:18005/radioprincipal-rb"
Write-Host "AUTOSTART=YES"
Write-Host "RESULTADO=RESET01_WINDOWS_TUNNEL_READY"
