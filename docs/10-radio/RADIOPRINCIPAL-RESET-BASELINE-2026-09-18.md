# Rádio Principal — RESET BASELINE 2026-09-18

## Decisão

A frente RADIOPRINCIPAL-NS1 recomeça operacionalmente a partir de uma nova baseline.

Os scripts C12–C26 permanecem preservados como histórico/evidência, porém estão **congelados** e não devem ser executados automaticamente durante o reset.

## Nova sequência

### RESET-00
Raio X completo do NS1, somente leitura.

Artefato:
`scripts/radioprincipal/reset/RESET00-NS1-FULL-XRAY-READONLY.sh`

Objetivo:
- inventariar todos os services/timers;
- listeners/conexões;
- selector/config;
- Harbor 18005;
- RadioBOSS control snapshots;
- playlist real;
- shadow real carregado;
- V2/legado existentes;
- media-transfer DB;
- repositório humano;
- conta SSH/túnel;
- falhas das últimas 12h;
- RTMP/HLS.

### RESET-01
Recuperação mínima do áudio público com RadioBOSS.

NS1:
`scripts/radioprincipal/reset/RESET01-NS1-RECOVER-RADIOBOSS.sh`

Windows:
`scripts/radioprincipal/reset/RESET01-WINDOWS-LIVE-TUNNEL.ps1`

Regra:
- sem reconstruir playlist;
- sem apagar mídia;
- sem promover V2;
- sem limpar legado;
- apenas restabelecer:
  RadioBOSS -> túnel -> Harbor -> selector -> radioprincipal -> HLS.

## Após RESET-01

Somente depois de existir evidência:
- `HARBOR_ESTABLISHED=YES`;
- `PUBLIC_SOURCE=RADIOBOSS`;
- `PUBLIC_RTMP=READY`;
- `PUBLIC_HLS=READY`;

será definida a arquitetura RESET-02 para sincronização/fallback.

## Status

RESET-00 / RESET-01 estão preparados no GitHub.
Ainda não classificá-los como executados/validados até receber evidência do NS1/Windows.
