param(
  [Parameter(Mandatory=$true)]
  [string]$WorkstreamId
)

$ErrorActionPreference = 'Stop'

try {
  $Root = (git rev-parse --show-toplevel 2>$null).Trim()
} catch {
  $Root = (Get-Location).Path
}
if (-not $Root) { $Root = (Get-Location).Path }

$Master    = Join-Path $Root 'project-context/00-MASTER.md'
$Decisions = Join-Path $Root 'project-context/02-DECISIONS.md'
$Bridge    = Join-Path $Root 'project-context/06-CHAT-BRIDGE.md'
$Active    = Join-Path $Root ("project-context/chats/active/{0}.md" -f $WorkstreamId)
$OutDir    = Join-Path $Root 'project-context/generated'
$Ts        = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$Out       = Join-Path $OutDir ("HANDOFF-{0}-{1}.md" -f $WorkstreamId, $Ts)

foreach ($File in @($Master,$Decisions,$Bridge,$Active)) {
  if (-not (Test-Path -LiteralPath $File)) {
    throw "arquivo obrigatorio ausente: $File"
  }
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$Header = @"
# Studio Sat — Chat Handoff Pack

- WORKSTREAM_ID: ``$WorkstreamId``
- generated_utc: ``$Ts``
- repository: ``MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-``

## Instrução para a nova conversa

Você está continuando um workstream existente do projeto Studio Sat.
Não reinicie o projeto e não presuma que a conversa anterior é a fonte oficial.
Leia este pacote, trate o MASTER/DECISIONS/ACTIVE STATE como estado persistente e continue do próximo passo registrado.
Antes de mudanças destrutivas ou cutover, reconfirme o estado vivo.
Ao concluir uma etapa, produza um resumo estruturado para atualizar o arquivo ACTIVE deste workstream.

---

## MASTER

"@

$Parts = @(
  $Header,
  (Get-Content -Raw -LiteralPath $Master),
  "`n---`n`n## DECISIONS`n`n",
  (Get-Content -Raw -LiteralPath $Decisions),
  "`n---`n`n## CHAT BRIDGE`n`n",
  (Get-Content -Raw -LiteralPath $Bridge),
  "`n---`n`n## ACTIVE WORKSTREAM — $WorkstreamId`n`n",
  (Get-Content -Raw -LiteralPath $Active)
)

[System.IO.File]::WriteAllText($Out, ($Parts -join ''), [System.Text.UTF8Encoding]::new($false))

Write-Host "HANDOFF_READY=$Out"
Write-Host ''
Write-Host 'Cole na nova aba:'
Write-Host ''
Write-Host "WORKSTREAM_ID: $WorkstreamId"
Write-Host 'Estou continuando este workstream do Studio Sat. Use o arquivo HANDOFF anexado como estado inicial. Não reinicie etapas já concluídas. Continue do próximo passo registrado e, ao final, gere o bloco de atualização do ACTIVE STATE.'
