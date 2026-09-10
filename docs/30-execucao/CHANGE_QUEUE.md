# StudioSat Web — Change Queue

Regra: **uma alteração ativa por vez no host de produção**. Engenharia de TV e Rádio podem preparar artefatos em paralelo, mas mudanças no Core ou no host entram nesta fila.

| ID | Mudança | Dono | Estado inicial | Gate |
|---|---|---|---|---|
| CHG-000 | Freeze operacional | Core | READY | Produção estável |
| CHG-001 | Core preflight somente leitura | Core | READY | Pacote + hash gerados |
| CHG-002 | Channels Registry real | Core | BLOCKED por CHG-001 | 9 canais mapeados |
| CHG-003 | Core Contract v0.1 | Core + TV + Rádio | DRAFT | Aprovação conjunta |
| CHG-004 | Health read-only dos 9 canais | Core | BLOCKED por CHG-002/003 | Health real disponível |
| CHG-005 | Incidentes P0 do legado | Domínio responsável | BLOCKED por CHG-004 | Sem regressão |
| CHG-006 | TVKIDS canonical/TVLAB | TV | BLOCKED | Zero DTS no lab |
| CHG-007 | TVKIDS cutover | TV + Core | BLOCKED | 24 h saudável |
| CHG-008 | Country Radio LAB | Rádio | BLOCKED | A/V + áudio-only aprovados |
| CHG-009 | Country live/fallback/shadow | Rádio | BLOCKED | Shadow ≥24 h |
| CHG-010 | Core Compatibility Gate | Core | BLOCKED | 1 TV + 1 Rádio compatíveis |
| CHG-011 | Country cutover | Rádio + Core | BLOCKED | 24–72 h saudável |
| CHG-012+ | Migração rádios restantes | Rádio + Core | BLOCKED | Uma por vez |
| CHG-020+ | Migração TVs restantes | TV + Core | BLOCKED | Uma por vez |
| CHG-030 | Control Plane funcional | Core | FUTURE | Engines comprovados |
| CHG-040 | CDN / HA | Core | FUTURE | Capacidade/criticidade |
| CHG-050 | Retirada do legado | Core + domínios | FUTURE | Estabilidade + rollback preservado |

## Regras de uma Change

Toda mudança deve registrar:

- objetivo;
- arquivos afetados;
- diff/candidate;
- responsável;
- janela;
- pré-condições;
- comandos;
- validação antes;
- validação depois;
- métricas antes/depois;
- rollback;
- resultado;
- timestamp.

Nenhuma mudança Core pode ser aprovada apenas por um domínio.
