# StudioSat Web — Change Queue

Regra: **uma alteração ativa por vez no host de produção**. Engenharia de TV e Rádio podem preparar artefatos em paralelo, mas mudanças no Core ou no host entram nesta fila.

Protocolo obrigatório: `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`.

Diretriz de prioridade vigente: `docs/95-conciliacoes/2026-09-10-diretriz-radio-first-e-integracao-tv.md`.

Handoff para TV: `docs/00-core/SHARED_FOUNDATION_HANDOFF_TO_TV_v0.1.md`.

Última evidência Core: `docs/40-stage-reports/CHG-001-2026-09-10-core-preflight.md`.

Matriz de risco atual: `docs/90-evidencias/P0_P1_P2_2026-09-10.md`.

## Trilha crítica atual — Rádio-first

| ID | Mudança | Dono | Estado atual | Gate |
|---|---|---|---|---|
| CHG-000 | Freeze operacional + protocolo de coordenação | Core | **IN EFFECT** | manter até autorização explícita de cada change |
| CHG-001 | Core preflight somente leitura | Core | **DONE / PASS** | evidência íntegra; Stage Report publicado |
| CHG-002 | Channels Registry real | Core | **DONE / PASS** | `registry/channels-registry.yaml` publicado |
| CHG-003 | Core Contract v0.1 | Core + TV + Rádio | **DONE / ACCEPTED** | Core, Engenharia TV e Engenharia Rádio aceitos |
| CHG-004 | Health read-only dos 9 canais | Core | **READY — PRÓXIMA AÇÃO NO HOST** | health real disponível sem mutação; regressão TV apenas observada, não corrigida |
| CHG-005R | Recuperação legado Radio Rock | Rádio + Core | **BLOCKED por CHG-004** | Rock active + MediaMTX ready + output validado; sem restart loop |
| CHG-005S | P0 segurança compartilhada (Samba/firewall) | Core | **BLOCKED / investigação separada** | mapear clientes e GCP/VPC antes de candidate |
| CHG-008A | Country LAB — estrutura/canonical/corpus | Rádio + Core | **BLOCKED por CHG-004/005R** | LAB isolado, sem tocar produção |
| CHG-008B | Country LAB — RadioEngineAdapter + A/V + áudio-only | Rádio | BLOCKED | dual rendition aprovada |
| CHG-009A | Country fallback/metadata/failure tests | Rádio | BLOCKED | falhas controladas sem impacto externo |
| CHG-009B | Country live locutor/câmera | Rádio + Core | BLOCKED | ingress/auth/ACL/fallback aprovados |
| CHG-009C | Country shadow ≥24h | Rádio | BLOCKED | estabilidade + métricas |
| CHG-010 | Core Compatibility Gate | Core + Rádio + TV | BLOCKED | MediaMTX/NGINX/ingress/naming/health/rollback compatíveis com os dois domínios |
| CHG-011 | Country cutover | Rádio + Core | BLOCKED | 24–72 h saudável + rollback preservado |
| CHG-012 | Pop migration | Rádio + Core | BLOCKED | station própria aprovada |
| CHG-013 | Clássicas migration | Rádio + Core | BLOCKED | station própria aprovada |
| CHG-014 | Rock migration | Rádio + Core | BLOCKED | station própria aprovada |
| CHG-015 | Principal migration | Rádio + Core | BLOCKED | exceção de gerador resolvida; station aprovada |

## Trilha TV — responsabilidade exclusiva da Engenharia TV

As changes TV não são pré-condição da trilha Rádio. Elas permanecem na mesma fila de host para impedir concorrência física.

| ID | Mudança | Dono | Estado atual | Gate |
|---|---|---|---|---|
| CHG-006 | TVKIDS canonical/TVLAB | TV | **TV-OWNED / SCHEDULED BY CORE QUEUE** | zero DTS no lab + Stage Report; não reiniciar produção por modernização antes do gate |
| CHG-007 | TVKIDS cutover | TV + Core | BLOCKED | 24 h saudável + rollback preservado |
| CHG-020+ | TVTEENS/TVVIVA/TVMAISJOVEM | TV + Core | BLOCKED | uma por vez |

## Futuro comum

| ID | Mudança | Dono | Estado atual | Gate |
|---|---|---|---|---|
| CHG-030 | Control Plane funcional | Core | FUTURE | adapters/engines comprovados |
| CHG-040 | CDN / HA | Core | FUTURE | capacidade/criticidade |
| CHG-050 | Retirada do legado | Core + domínios | FUTURE | estabilidade + rollback preservado |

## Interlocks ativos

1. **NÃO REINICIAR TVs por modernização neste momento.** O gerador global atual foi modificado depois do start dos quatro processos TV e hoje usa `ready/`; um restart pode reconstruir a playlist com conteúdo diferente do que está no ar.
2. **Radio Rock continua failed.** A recuperação será CHG-005R; não mascarar com restart loop.
3. **Samba possui achado P0 sanitizado.** Não publicar detalhes; mapear clientes e firewall GCP/VPC antes da contenção.
4. **MediaMTX não deve ser endurecido ainda.** Listeners/auth precisam ser confrontados com publishers reais, live Rádio/TV e firewall de nuvem.
5. **TVKIDS está DEGRADED por DTS** no baseline, porém a correção pertence à Engenharia TV.
6. Resultados `HLS FAIL:302` e `RTMP FAIL` de rádio do preflight v1.0 eram limitações de probe, não prova de outage.
7. Nenhuma decisão Core criada pela trilha Rádio pode obrigar a Engenharia TV a reescrever o Core; seguir o Shared Foundation Handoff.

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

Toda mudança deve registrar objetivo, baseline commit, arquivos/hashes, candidate/diff, responsável, janela, pré-condições, comandos planejados e realmente executados, validação antes/depois, métricas, correções, versão final dos scripts, rollback, resultado, timestamps e Stage Report sanitizado.

## Gate de sincronização

Antes de mudar qualquer estado para `READY` ou `EXECUTING`:

1. reler `main`;
2. comparar mudanças desde o último checkpoint;
3. verificar trabalho publicado por TV e Rádio;
4. confirmar ausência de conflito em Core/host;
5. atualizar plano e rollback se necessário.

Depois de `VERIFYING`, a change só vira `DONE` quando documentação, scripts finais e Stage Report estiverem publicados e o `main` tiver sido relido novamente.
