$ErrorActionPreference = "Stop"

$Root = "C:\ProgramData\StudioSat\RadioPrincipalAgent"
$Agent = Join-Path $Root "StudioSat-RadioPrincipal-Agent.ps1"
$Task = "StudioSat-RadioPrincipal-Agent"
$Url = "https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/v2/StudioSat-RadioPrincipal-Agent.ps1"

New-Item -ItemType Directory -Force -Path $Root | Out-Null
Invoke-WebRequest -Uri $Url -OutFile $Agent -UseBasicParsing

schtasks.exe /Delete /TN $Task /F 2>$null | Out-Null

$Action = 'powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $Agent + '"'
schtasks.exe /Create /TN $Task /SC ONSTART /RU SYSTEM /RL HIGHEST /TR $Action /F | Out-Host
schtasks.exe /Run /TN $Task | Out-Host

Start-Sleep -Seconds 8

Write-Host "===== TASK ====="
Get-ScheduledTask -TaskName $Task | Select-Object TaskName,State

Write-Host "===== STATUS ====="
$Status = Join-Path $Root "status.json"
if(Test-Path $Status){ Get-Content $Status -Raw }

Write-Host "===== LOG ====="
Get-Content (Join-Path $Root "agent.log") -Tail 40 -ErrorAction SilentlyContinue

Write-Host "===== PC LOAD ====="
Get-CimInstance Win32_Process |
  Where-Object { $_.CommandLine -like "*StudioSat-RadioPrincipal-Agent.ps1*" -or $_.CommandLine -like "*127.0.0.1:18796:127.0.0.1:8796*" } |
  Select-Object ProcessId,Name,CommandLine |
  Format-List

Write-Host "RESULTADO=C25_AGENT_INSTALLED"
