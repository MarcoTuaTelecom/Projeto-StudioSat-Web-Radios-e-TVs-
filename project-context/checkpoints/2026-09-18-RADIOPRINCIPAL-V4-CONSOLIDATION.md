# Checkpoint — RADIOPRINCIPAL-NS1 — 2026-09-18

## Motivo

Consolidação imediata do histórico, objetivo, regras de negócio, regras de sistema, acertos, falhas e prioridades após C21/C21R/C22 e antes de validar C24/C25.

## Fonte mestre

`docs/10-radio/RADIOPRINCIPAL-MASTER-DOSSIER-V4.md`

Commit:
`8b4e0b9c8ac26a03c842afe4aa4478655555b9bf`

## Últimos fatos comprovados

- C21: `P1_SAMPLE_STATUS=UNSTABLE`;
- Harbor listener esteve presente, mas established apenas 17,65% das amostras;
- dois `Feeding stopped: Avutil.Error(Invalid data found when processing input)`;
- selector posteriormente mudou para RadioBOSS Harbor quando metadata chegou;
- C21R: listener Windows 18005 voltou e `TCP_18005=True`;
- log C21R ainda continha `connect failed: Connection refused`;
- C22: Manhã 27, Tarde 85, Noite 69;
- C22: zero conflicts;
- C22: `saytime=HoraCertaSegSextManha` apareceu incorretamente como missing source;
- C22: asset físico `98 14 BIS - NOVA MANHÃ.mp3` permaneceu missing;
- produção não foi reiniciada pelo C22.

## Artefatos preparados após o checkpoint operacional

### C23
Shadow V2 isolado, não confirmado instalado/validado.

### C24
Edge Bridge NS1:
- `edge-bridge.py`;
- instalador corrigido commit `d044d61daaabb0ab67b7dc72d3a11a8dd8828059`.

### C25
Agente Windows automático:
- agent commit `71c37252ab46913f82a4c05104c4fe48148a1415`;
- installer commit `e07b3eba1d5dbcbed3cb0251553f3e502737e6ad`.

## Bloqueios

- não fazer cutover;
- não remover shadow legado;
- não apagar stores;
- não reiniciar produção para testar candidate;
- não declarar UI/API final concluída.

## Próximo passo

P1 e P3 em sequência:
1. validar estabilidade end-to-end;
2. instalar/validar C24;
3. instalar/validar C25;
4. provar transferência automática e cobertura real da grade;
5. avançar para canonical queue/execution engine.
