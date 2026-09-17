param(
  [Parameter(Mandatory=$true)][string]$WorkstreamId,
  [string]$Repository = '<repo>',
  [string]$Scope = '<uma responsabilidade técnica>'
)

$ErrorActionPreference = 'Stop'

try {
  $Root = (git rev-parse --show-toplevel 2>$null).Trim()
} catch {
  $Root = (Get-Location).Path
}
if (-not $Root) { $Root = (Get-Location).Path }

$Template = Join-Path $Root 'project-context/chats/ACTIVE-TEMPLATE.md'
$Target = Join-Path $Root ("project-context/chats/active/{0}.md" -f $WorkstreamId)

if (-not (Test-Path -LiteralPath $Template)) { throw "template ausente: $Template" }
if (Test-Path -LiteralPath $Target) { throw "workstream ja existe: $Target" }

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target) | Out-Null
$Text = Get-Content -Raw -LiteralPath $Template
$Text = $Text.Replace('<WORKSTREAM_ID>', $WorkstreamId)
$Text = $Text.Replace('<repo>', $Repository)
$Text = $Text.Replace('<uma responsabilidade técnica>', $Scope)
[System.IO.File]::WriteAllText($Target, $Text, [System.Text.UTF8Encoding]::new($false))

Write-Host "WORKSTREAM_CREATED=$Target"
Write-Host 'Revise o arquivo, preencha estado comprovado e commit antes de iniciar a nova aba.'
