#requires -Version 5.1
param([switch]$SelfTest)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

function Attr([object]$Node,[string]$Name,[string]$Default='') {
    if ($null -eq $Node) { return $Default }
    $p=$Node.PSObject.Properties[$Name]
    if ($null -eq $p) { return $Default }
    return [string]$p.Value
}

function Select-Encoder([string]$StatusXml,[hashtable]$Configs) {
    [xml]$sx=$StatusXml
    $best=$null
    foreach($n in @($sx.Encoders.Encoder)) {
        $idx=[int](Attr $n 'index' '-1')
        if(-not $Configs.ContainsKey($idx)){ continue }
        [xml]$cx=[string]$Configs[$idx]
        $server=Attr $cx.Encoder 'Server'
        $enabled=Attr $cx.Encoder 'Enabled'
        $name=Attr $n 'name'
        $match=($server -match '(?i)(127\.0\.0\.1|localhost):18005(?:/radioprincipal-rb)?(?:$|/)' -or $name -match '(?i)18005|principal')
        if($match){
            $score=0
            if($server -match '(?i):18005/radioprincipal-rb'){ $score+=100 }
            if($server -match '(?i):18005'){ $score+=50 }
            if($enabled -match '^(?i:true|1)$'){ $score+=10 }
            if($name -match '(?i)18005|principal'){ $score+=5 }
            $o=[pscustomobject]@{Index=$idx;Number=$idx+1;Server=$server;Enabled=$enabled;Name=$name;Score=$score}
            if($null -eq $best -or $o.Score -gt $best.Score){$best=$o}
        }
    }
    return $best
}

if($SelfTest){
    $status='<Encoders><Encoder index="0" status="idle" error="" name="96k"/><Encoder index="1" status="off" error="" name="Studio Sat Principal"/></Encoders>'
    $cfg=@{
        0='<Encoder Server="example.org:8000/live" Enabled="True"></Encoder>'
        1='<Encoder Server="127.0.0.1:18005/radioprincipal-rb" Enabled="True"></Encoder>'
    }
    $x=Select-Encoder $status $cfg
    if($null -eq $x -or $x.Index -ne 1 -or $x.Number -ne 2){ throw 'encoder selection selftest failed' }
    Write-Host 'SELFTEST=PASS'
    exit 0
}

if($env:OS -ne 'Windows_NT'){ throw 'WINDOWS_REQUIRED' }

$id=[Security.Principal.WindowsIdentity]::GetCurrent()
$pr=New-Object Security.Principal.WindowsPrincipal($id)
if(-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
    throw 'POWERSHELL_ADMIN_REQUIRED'
}

$Base='C:\StudioSat\RadioV2\radioprincipal'
$Secrets=Join-Path $Base 'prefetch-secrets-v1.json'
$RepairV4=Join-Path $Base 'StudioSat-RadioPrincipal-Sync-Media-Repair-V4.ps1'
$AgentV8=Join-Path $Base 'StudioSat-RadioPrincipal-V8.ps1'
$TaskV8='StudioSat-RadioPrincipal-ControlAgent-V8'
$Endpoint='https://www.radio.studiosatweb.com.br/api/radioboss-sync'
$HostName='ns1.tpsolutions.com.br'

function Secure-To-Plain([Security.SecureString]$v){
    $p=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($v)
    try{return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($p)}
    finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($p)}
}

function Load-Context {
    if(-not(Test-Path -LiteralPath $Secrets)){throw "SECRETS_MISSING=$Secrets"}
    if(-not(Test-Path -LiteralPath $RepairV4)){throw "REPAIR_V4_MISSING=$RepairV4"}
    $raw=Get-Content -LiteralPath $RepairV4 -Raw
    $m=[regex]::Match($raw,'(?m)^\$RbPort\s*=\s*(\d+)\s*$')
    if(-not $m.Success){throw 'RB_PORT_NOT_FOUND'}
    $sec=Get-Content -LiteralPath $Secrets -Raw|ConvertFrom-Json
    $rb=Secure-To-Plain(ConvertTo-SecureString([string]$sec.radio_boss))
    $tok=Secure-To-Plain(ConvertTo-SecureString([string]$sec.token))
    if([string]::IsNullOrWhiteSpace($rb)){throw 'RB_PASSWORD_EMPTY'}
    if([string]::IsNullOrWhiteSpace($tok)){throw 'NS1_TOKEN_EMPTY'}
    return [pscustomobject]@{Port=[int]$m.Groups[1].Value;RB=$rb;Token=$tok}
}

function Test-Tcp([string]$Host,[int]$Port,[int]$Timeout=1000){
    $c=New-Object Net.Sockets.TcpClient
    try{
        $ar=$c.BeginConnect($Host,$Port,$null,$null)
        if(-not $ar.AsyncWaitHandle.WaitOne($Timeout)){return $false}
        $c.EndConnect($ar)
        return $true
    }catch{return $false}
    finally{$c.Close()}
}

$c=Load-Context
$pass=[Uri]::EscapeDataString([string]$c.RB)
$rbbase="http://127.0.0.1:$($c.Port)/?pass=$pass"

function RB([string]$Query,[int]$Timeout=5){
    $r=Invoke-WebRequest -UseBasicParsing -Uri "$rbbase&$Query" -TimeoutSec $Timeout
    $body=([string]$r.Content).TrimStart([char]0xFEFF)
    if([string]::IsNullOrWhiteSpace($body)){throw "RB_EMPTY=$Query"}
    return $body
}

function RBCmd([string]$Command){
    $cmd=[Uri]::EscapeDataString($Command)
    return RB "cmd=$cmd" 5
}

$status=RB 'action=status' 5
if($status -notmatch '<Status[\s>]'){throw 'RADIOBOSS_API_BAD_STATUS'}
Write-Host "RADIOBOSS_API=OK PORT=$($c.Port)"

# Rebuild exactly one 18005 SSH local forward.
$existing=Get-CimInstance Win32_Process -Filter "Name='ssh.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like '*127.0.0.1:18005:127.0.0.1:18005*' }
foreach($p in @($existing)){
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Milliseconds 800

$candidates=@(
    [pscustomobject]@{Key='C:\ProgramData\StudioSat\RadioBOSSTunnel\id_ed25519';User='studiosat-rb-tunnel'},
    [pscustomobject]@{Key='C:\StudioSat\RadioV2\radioprincipal\keys\prefetch_ed25519';User='studiosat-tunnel'}
)

$tunnel=$null
foreach($cand in $candidates){
    if(-not(Test-Path -LiteralPath $cand.Key)){continue}
    $args=@(
        '-NT','-p','22',
        '-L','127.0.0.1:18005:127.0.0.1:18005',
        '-i',$cand.Key,
        '-o','BatchMode=yes',
        '-o','ExitOnForwardFailure=yes',
        '-o','ServerAliveInterval=10',
        '-o','ServerAliveCountMax=3',
        '-o','TCPKeepAlive=yes',
        '-o','ConnectTimeout=10',
        '-o','StrictHostKeyChecking=accept-new',
        "$($cand.User)@$HostName"
    )
    $proc=Start-Process -FilePath 'ssh.exe' -ArgumentList $args -WindowStyle Hidden -PassThru
    $ok=$false
    for($i=0;$i-lt20;$i++){
        Start-Sleep -Milliseconds 500
        if(Test-Tcp '127.0.0.1' 18005 700){$ok=$true;break}
        if($proc.HasExited){break}
    }
    if($ok){
        $tunnel=[pscustomobject]@{Pid=$proc.Id;User=$cand.User;Key=$cand.Key}
        break
    }
    try{Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue}catch{}
}
if($null -eq $tunnel){throw 'SSH_TUNNEL_18005_NOT_READY'}
Write-Host "TUNNEL_18005=READY PID=$($tunnel.Pid) USER=$($tunnel.User)"

# Find the actual RadioBOSS encoder that targets the Studio Sat tunnel.
[xml]$encStatus=RB 'action=encoderstatus' 5
$configs=@{}
foreach($n in @($encStatus.Encoders.Encoder)){
    $idx=[int](Attr $n 'index' '-1')
    if($idx -ge 0){
        try{$configs[$idx]=RB "action=getencoder&id=$idx" 5}catch{}
    }
}
$target=Select-Encoder ([string]$encStatus.OuterXml) $configs
if($null -eq $target){throw 'RADIOBOSS_ENCODER_18005_NOT_FOUND'}
Write-Host "ENCODER_TARGET=ID$($target.Index) NUMBER=$($target.Number) SERVER=$($target.Server)"

# Force Audio Mix and a clean reconnect of only the Studio Sat encoder.
[void](RBCmd 'setencodersource 0')
try{[void](RBCmd ("disconnect "+$target.Number))}catch{}
Start-Sleep -Seconds 1
[void](RBCmd ("connect "+$target.Number))

$encoderActive=$false
for($i=0;$i-lt30;$i++){
    Start-Sleep -Seconds 1
    [xml]$es=RB 'action=encoderstatus' 5
    $node=@($es.Encoders.Encoder)|Where-Object{[int](Attr $_ 'index' '-1') -eq $target.Index}|Select-Object -First 1
    if($null -ne $node){
        $st=Attr $node 'status'
        $er=Attr $node 'error'
        Write-Host "ENCODER_STATUS=$st ERROR=$er"
        if($st -match '^(?i:active|connected)$' -and [string]::IsNullOrWhiteSpace($er)){
            $encoderActive=$true
            break
        }
    }
}
if(-not $encoderActive){throw 'RADIOBOSS_ENCODER_DID_NOT_CONNECT'}

# Verify current playback before restarting control sync.
[xml]$pbXml=RB 'action=playbackinfo' 5
$currentFn=Attr $pbXml.Info.CurrentTrack.TRACK 'FILENAME'
$playlistPos=Attr $pbXml.Info.Playback 'playlistpos'
$posMs=Attr $pbXml.Info.Playback 'pos'
if([string]::IsNullOrWhiteSpace($currentFn)){throw 'RADIOBOSS_CURRENT_EMPTY'}
Write-Host "RADIOBOSS_CURRENT=$currentFn"
Write-Host "RADIOBOSS_PLAYLISTPOS=$playlistPos"
Write-Host "RADIOBOSS_POS_MS=$posMs"

# Restart the V8 control agent so playback + playlist are pushed immediately.
$task=Get-ScheduledTask -TaskName $TaskV8 -ErrorAction SilentlyContinue
if($null -ne $task){
    try{Enable-ScheduledTask -TaskName $TaskV8|Out-Null}catch{}
    try{Stop-ScheduledTask -TaskName $TaskV8 -ErrorAction SilentlyContinue}catch{}
    Start-Sleep -Milliseconds 500
    Start-ScheduledTask -TaskName $TaskV8
    Write-Host 'CONTROL_AGENT_V8=TASK_RESTARTED'
}elseif(Test-Path -LiteralPath $AgentV8){
    Start-Process powershell.exe -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden',
        '-File',$AgentV8,'-Agent'
    ) -WindowStyle Hidden|Out-Null
    Write-Host 'CONTROL_AGENT_V8=PROCESS_STARTED'
}else{
    throw 'CONTROL_AGENT_V8_NOT_FOUND'
}

$headers=@{Authorization="Bearer $($c.Token)"}
$syncOk=$false
for($i=0;$i-lt30;$i++){
    Start-Sleep -Seconds 1
    try{
        $st=Invoke-RestMethod -Uri "$Endpoint/v1/state/radioprincipal" -Headers $headers -TimeoutSec 6
        $pb=$st.current.playback
        if($null -ne $pb){
            $received=[DateTimeOffset]::Parse([string]$pb.received_at_utc)
            $age=([DateTimeOffset]::UtcNow-$received).TotalSeconds
            $p=$pb.payload
            if($null -ne $p.data){$p=$p.data}
            $fn=[string]$p.current.FILENAME
            Write-Host ("SYNC_PLAYBACK_AGE_SEC={0:N1} CURRENT={1}" -f $age,$fn)
            if($age -le 10 -and -not [string]::IsNullOrWhiteSpace($fn)){
                $syncOk=$true
                break
            }
        }
    }catch{}
}
if(-not $syncOk){throw 'RADIOBOSS_CONTROL_SYNC_NOT_FRESH'}

Write-Host 'RADIOBOSS_ENCODER=ACTIVE'
Write-Host 'RADIOBOSS_CONTROL_SYNC=FRESH'
Write-Host 'RESULTADO=WINDOWS_RADIOBOSS_LIVE_AND_CONTROL_REPAIRED'
