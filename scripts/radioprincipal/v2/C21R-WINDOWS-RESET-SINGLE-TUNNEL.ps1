$ErrorActionPreference = "Stop"

$Task = "StudioSat-RadioBOSS-NS1-Tunnel"
$Root = "C:\ProgramData\StudioSat\RadioBOSSTunnel"
$Key  = Join-Path $Root "id_ed25519"
$Log  = Join-Path $Root "tunnel.log"

Write-Host "=============================================================="
Write-Host " C21R - RADIOBOSS SINGLE TUNNEL RECOVERY"
Write-Host "=============================================================="

Write-Host "===== BEFORE ====="
Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
  Where-Object {
    $_.CommandLine -match "studiosat-rb-tunnel@ns1\.tpsolutions\.com\.br" -or
    $_.CommandLine -match "127\.0\.0\.1:18005:127\.0\.0\.1:18005" -or
    $_.CommandLine -like "*RadioBOSSTunnel*"
  } |
  Select-Object ProcessId,CommandLine |
  Format-List

Write-Host "===== STOP OLD TUNNEL INSTANCE ====="
schtasks.exe /End /TN $Task 2>$null | Out-Null

Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
  Where-Object {
    $_.CommandLine -match "studiosat-rb-tunnel@ns1\.tpsolutions\.com\.br" -or
    $_.CommandLine -match "127\.0\.0\.1:18005:127\.0\.0\.1:18005" -or
    $_.CommandLine -like "*RadioBOSSTunnel*"
  } |
  ForEach-Object {
    Write-Host "KILL_TUNNEL_PID=$($_.ProcessId)"
    Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null
  }

Start-Sleep -Seconds 2

Write-Host "===== START ONE WATCHDOG ====="
schtasks.exe /Run /TN $Task | Out-Host

$ready=$false
for($i=1;$i -le 20;$i++){
  Start-Sleep -Seconds 1
  $l = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 18005 -State Listen -ErrorAction SilentlyContinue
  if($l){
    Write-Host "LOCAL_18005_LISTEN=YES AFTER=$($i)s"
    $ready=$true
    break
  }
  Write-Host "WAIT_LOCAL_18005=$($i)s"
}
if(-not $ready){
  Write-Host "LOCAL_18005_LISTEN=NO"
  Get-Content $Log -Tail 60 -ErrorAction SilentlyContinue
  exit 20
}

Write-Host "===== AFTER ====="
$procs = Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
  Where-Object {
    $_.CommandLine -match "studiosat-rb-tunnel@ns1\.tpsolutions\.com\.br" -or
    $_.CommandLine -match "127\.0\.0\.1:18005:127\.0\.0\.1:18005" -or
    $_.CommandLine -like "*RadioBOSSTunnel*"
  }

$procs | Select-Object ProcessId,CommandLine | Format-List
Write-Host "TUNNEL_SSH_PROCESS_COUNT=$($procs.Count)"

$test=Test-NetConnection 127.0.0.1 -Port 18005 -WarningAction SilentlyContinue
Write-Host "TCP_18005=$($test.TcpTestSucceeded)"

Write-Host "===== LOG ====="
Get-Content $Log -Tail 30 -ErrorAction SilentlyContinue

if($test.TcpTestSucceeded){
  Write-Host "RESULTADO=C21R_SINGLE_TUNNEL_READY"
}else{
  Write-Host "RESULTADO=C21R_TUNNEL_FAILED"
  exit 21
}
