param([int]$PollSeconds = 5)

$ErrorActionPreference = "Stop"
$Root = "C:\ProgramData\StudioSat\RadioPrincipalAgent"
$Key = "C:\ProgramData\StudioSat\RadioBOSSTunnel\id_ed25519"
$Ssh = "C:\Windows\System32\OpenSSH\ssh.exe"
$HostName = "ns1.tpsolutions.com.br"
$UserName = "studiosat-rb-tunnel"
$BridgePort = 18796
$BridgeBase = "http://127.0.0.1:$BridgePort"
$Log = Join-Path $Root "agent.log"
$CacheFile = Join-Path $Root "hash-cache.clixml"
$StatusFile = Join-Path $Root "status.json"

New-Item -ItemType Directory -Force -Path $Root | Out-Null

function Log([string]$m) {
  $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m
  Add-Content -LiteralPath $Log -Value $line -Encoding UTF8
}

function Save-Status($obj) {
  $obj | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $StatusFile -Encoding UTF8
}

$Cache = @{}
if(Test-Path $CacheFile){
  try {
    $loaded = Import-Clixml -LiteralPath $CacheFile
    if($loaded -is [hashtable]) { $Cache = $loaded }
  } catch {}
}

function Ensure-BridgeTunnel {
  try {
    $r = Invoke-RestMethod -Uri "$BridgeBase/health" -TimeoutSec 2
    if($r.ok){ return $true }
  } catch {}

  Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" |
    Where-Object {
      $_.CommandLine -match "127\.0\.0\.1:18796:127\.0\.0\.1:8796" -and
      $_.CommandLine -match "studiosat-rb-tunnel@ns1\.tpsolutions\.com\.br"
    } |
    ForEach-Object {
      try { Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null } catch {}
    }

  $args = @(
    "-NT",
    "-p","22",
    "-L","127.0.0.1:18796:127.0.0.1:8796",
    "-i",$Key,
    "-o","BatchMode=yes",
    "-o","ExitOnForwardFailure=yes",
    "-o","ServerAliveInterval=10",
    "-o","ServerAliveCountMax=3",
    "-o","TCPKeepAlive=yes",
    "-o","ConnectTimeout=10",
    "-o","StrictHostKeyChecking=accept-new",
    "$UserName@$HostName"
  )
  Start-Process -FilePath $Ssh -ArgumentList $args -WindowStyle Hidden | Out-Null

  for($i=1;$i -le 12;$i++){
    Start-Sleep -Seconds 1
    try {
      $r = Invoke-RestMethod -Uri "$BridgeBase/health" -TimeoutSec 2
      if($r.ok){ Log "BRIDGE_TUNNEL_READY after=$i s"; return $true }
    } catch {}
  }
  Log "BRIDGE_TUNNEL_FAILED"
  return $false
}

function Get-HashCached([string]$Path) {
  $f = Get-Item -LiteralPath $Path -ErrorAction Stop
  $key = $Path.ToLowerInvariant()
  $sig = "$($f.Length):$($f.LastWriteTimeUtc.Ticks)"
  if($Cache.ContainsKey($key) -and $Cache[$key].Sig -eq $sig){
    return $Cache[$key].Sha
  }
  $sha = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  $Cache[$key] = @{ Sig=$sig; Sha=$sha }
  try { $Cache | Export-Clixml -LiteralPath $CacheFile } catch {}
  return $sha
}

function B64([string]$s) {
  return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($s))
}

function Register-Existing([string]$Path,[string]$Sha) {
  $f = Get-Item -LiteralPath $Path
  $body = @{
    sha256 = $Sha
    source_path = $Path
    filename = $f.Name
    media_class = "ACTIVE_PLAYLIST"
  } | ConvertTo-Json -Compress
  $p = @{
    Method = "Post"
    Uri = "$BridgeBase/v1/register/radioprincipal"
    ContentType = "application/json"
    Body = $body
    TimeoutSec = 15
  }
  Invoke-RestMethod @p | Out-Null
}

function Upload-Asset([string]$Path,[string]$Sha) {
  $f = Get-Item -LiteralPath $Path
  $headers = @{
    "X-SHA256" = $Sha
    "X-Filename-B64" = (B64 $f.Name)
    "X-SourcePath-B64" = (B64 $Path)
    "X-Media-Class" = "ACTIVE_PLAYLIST"
  }
  $p = @{
    UseBasicParsing = $true
    Method = "Put"
    Uri = "$BridgeBase/v1/upload/radioprincipal"
    Headers = $headers
    ContentType = "application/octet-stream"
    InFile = $Path
    TimeoutSec = 3600
  }
  Invoke-WebRequest @p | Out-Null
}

Log "AGENT_START poll=$PollSeconds s"
while($true){
  try {
    if(-not (Ensure-BridgeTunnel)){
      Save-Status @{ status="BRIDGE_DOWN"; updated=(Get-Date).ToString("o") }
      Start-Sleep -Seconds $PollSeconds
      continue
    }

    $plan = Invoke-RestMethod -Uri "$BridgeBase/v1/plan/radioprincipal" -TimeoutSec 10
    $missing = @($plan.items | Where-Object { -not $_.virtual -and -not $_.present } | Sort-Object priority,n)

    $uploaded=0
    $registered=0
    $localMissing=0
    $errors=0

    foreach($item in $missing){
      $path = [string]$item.source_path
      if([string]::IsNullOrWhiteSpace($path)){ continue }
      if(-not (Test-Path -LiteralPath $path)){
        $localMissing++
        Log "LOCAL_MISSING pri=$($item.priority) path=$path"
        continue
      }

      try {
        $f = Get-Item -LiteralPath $path
        $sha = Get-HashCached $path
        $check = Invoke-RestMethod -Uri "$BridgeBase/v1/exists/radioprincipal?sha256=$sha&size=$($f.Length)" -TimeoutSec 10
        if($check.present){
          Register-Existing $path $sha
          $registered++
          Log "REGISTERED sha=$sha path=$path"
        } else {
          Log "UPLOAD_START bytes=$($f.Length) pri=$($item.priority) path=$path"
          Upload-Asset $path $sha
          $uploaded++
          Log "UPLOAD_OK sha=$sha path=$path"
        }
      } catch {
        $errors++
        Log "UPLOAD_ERROR path=$path error=$($_.Exception.Message)"
      }

      if($uploaded -ge 8){ break }
    }

    Save-Status @{
      status="RUNNING"
      updated=(Get-Date).ToString("o")
      plan_count=$plan.count
      current_ref=$plan.playback.current_ref
      next_ref=$plan.playback.next_ref
      pending=$missing.Count
      uploaded_this_cycle=$uploaded
      registered_this_cycle=$registered
      local_missing_this_cycle=$localMissing
      errors_this_cycle=$errors
    }
  } catch {
    Log "CYCLE_ERROR $($_.Exception.Message)"
    Save-Status @{ status="ERROR"; updated=(Get-Date).ToString("o"); error=$_.Exception.Message }
  }
  Start-Sleep -Seconds $PollSeconds
}
