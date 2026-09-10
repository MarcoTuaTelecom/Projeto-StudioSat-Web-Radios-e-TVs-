# StudioSat Web — Change Queue

Regra: **uma alteração ativa por vez no host de produção**. Engenharia de TV e Rádio podem preparar artefatos em paralelo, mas mudanças no Core ou no host entram nesta fila.

Protocolo obrigatório: `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`.

Último checkpoint de revisão antes da próxima execução: `docs/40-stage-reports/CHG-000-2026-09-10-revisao-repositorio.md`.

| ID | Mudança | Dono | Estado atual | Gate |
|---|---|---|---|---|
| CHG-000 | Freeze operacional + protocolo de coordenação | Core | **IN EFFECT / REVIEW PASS** | manter até autorização de cada change |
| CHG-001 | Core preflight somente leitura | Core | **READY — PRÓXIMA AÇÃO NO HOST** | pacote + hash gerados; produção inalterada |
| CHG-002 | Channels Registry real | Core | BLOCKED por CHG-001 | 9 canais mapeados com evidência atual |
| CHG-003 | Core Contract v0.1 | Core + TV + Rádio | **CORE+TV ACCEPTED; validação final da Engenharia Rádio pendente** | aceite dos três domínios antes dos labs executáveis |
| CHG-004 | Health read-only dos 9 canais | Core | BLOCKED por CHG-002/003 | health real disponível |
| CHG-005 | Incidentes P0 do legado | Domínio responsável | BLOCKED por CHG-004 | sem regressão e stage report fechado |
| CHG-006 | TVKIDS canonical/TVLAB | TV | BLOCKED | zero DTS no lab + stage report |
| CHG-007 | TVKIDS cutover | TV + Core | BLOCKED | 24 h saudável + rollback preservado |
| CHG-008 | Country Radio LAB | Rádio | BLOCKED | A/V + áudio-only aprovados |
| CHG-009 | Country live/fallback/shadow | Rádio | BLOCKED | shadow ≥24 h |
| CHG-010 | Core Compatibility Gate | Core | BLOCKED | 1 TV + 1 Rádio compatíveis; MediaMTX/NGINX/ingress/naming/health revisados |
| CHG-011 | Country cutover | Rádio + Core | BLOCKED | 24–72 h saudável |
| CHG-012+ | Migração rádios restantes | Rádio + Core | BLOCKED | uma por vez |
| CHG-020+ | Migração TVs restantes | TV + Core | BLOCKED | uma por vez |
| CHG-030 | Control Plane funcional | Core | FUTURE | engines comprovados |
| CHG-040 | CDN / HA | Core | FUTURE | capacidade/criticidade |
| CHG-050 | Retirada do legado | Core + domínios | FUTURE | estabilidade + rollback preservado |

## Estados permitidos

```text
DRAFT
BLOCKED
READY
EXECUTING
VERIFYING
PASS
FAIL
ROLLED_BACK
DONE
```

Apenas uma change pode estar em `EXECUTING` no host de produção.

## Regras de uma Change

Toda mudança deve registrar:

- objetivo;
- baseline commit do GitHub;
- arquivos afetados;
- hashes antes/depois;
- diff/candidate;
- responsável;
- janela;
- pré-condições;
- comandos planejados;
- comandos realmente executados;
- validação antes;
- validação depois;
- métricas antes/depois;
- correções de scripts ocorridas;
- versão final dos scripts no GitHub;
- rollback;
- resultado;
- timestamps;
- Stage Report sanitizado.

Nenhuma mudança Core pode ser aprovada apenas por um domínio.

## Gate de sincronização

Antes de mudar qualquer estado para `READY` ou `EXECUTING`:

1. reler `main`;
2. comparar mudanças desde o último checkpoint;
3. verificar trabalho publicado por TV e Rádio;
4. confirmar ausência de conflito em Core/host;
5. atualizar plano e rollback se necessário.

Depois de `VERIFYING`, a change só vira `DONE` quando documentação, scripts finais e Stage Report estiverem publicados e o `main` tiver sido relido novamente.
