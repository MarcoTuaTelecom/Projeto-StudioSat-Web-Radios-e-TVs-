# Projeto StudioSat Web — Rádios e TVs

Repositório mestre do projeto **StudioSat Web**, reunindo a arquitetura comum da plataforma, os domínios de **Radio Studio Sat** e **Televisão**, os runbooks de implantação, a Change Queue, os relatórios de etapa e os scripts aprovados.

## Estado atual

A plataforma existente possui 9 canais configurados: 5 rádios e 4 TVs. O Core Preflight de 2026-09-10 confirmou 8 paths ready e Radio Rock fora do media plane. O estado operacional detalhado deve sempre ser reconfirmado pelo health atual antes de cada mudança.

Regra de evolução:

> **Não reconstruir por cima da produção. Construir ao lado, provar em laboratório, migrar uma emissora por vez e manter rollback imediato.**

## Prioridade atual

A trilha principal desta frente é **Rádio-first**: concluir as cinco emissoras Radio Studio Sat.

A Engenharia de TV continua responsável por TVKIDS, TVTEENS, TVVIVA e TVMAISJOVEM.

O fato de Rádio iniciar a fundação não autoriza criar um Core radio-específico. Todo componente compartilhado deve permitir que TV se conecte depois **sem substituir ou desfazer** configurações validadas.

Diretriz: `docs/95-conciliacoes/2026-09-10-diretriz-radio-first-e-integracao-tv.md`.

Handoff técnico para TV: `docs/00-core/SHARED_FOUNDATION_HANDOFF_TO_TV_v0.1.md`.

## Hierarquia documental

- `docs/00-core/` — arquitetura, CORE CONTRACT, escopo Core e handoff compartilhado para TV.
- `docs/10-radio/` — documentação, aceite do contrato e plano mestre de implementação Radio Studio Sat.
- `docs/20-tv/` — documentação e escopo específico da Engenharia de TV.
- `docs/30-execucao/` — runbook mestre, Change Queue e protocolo rigoroso de execução/sincronização.
- `docs/40-stage-reports/` — registro do que **realmente aconteceu** em cada etapa.
- `docs/90-evidencias/` — relatórios técnicos e evidências sanitizadas de baseline.
- `docs/95-conciliacoes/` — propostas, revisões, acordos e diretrizes entre Core, Rádio e TV.
- `registry/` — contrato/registro real das stations.
- `candidates/` — scripts/configurações ainda não promovidos.
- `scripts/` — versão canônica dos scripts comprovados.

## Documentos normativos de coordenação

1. `docs/00-core/CORE_CONTRACT_v0.1.md`
2. `docs/00-core/CORE_ENGINEERING_SCOPE_v0.1.md`
3. `docs/00-core/SHARED_FOUNDATION_HANDOFF_TO_TV_v0.1.md`
4. `docs/10-radio/RADIO_IMPLEMENTATION_PLAN_v1.0.md`
5. `docs/20-tv/TV_ENGINEERING_SCOPE_v0.1.md`
6. `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`
7. `docs/30-execucao/CHANGE_QUEUE.md`

Antes de cada etapa, todos os responsáveis devem reler o `main` atual e verificar mudanças do outro domínio. Depois de cada etapa, scripts finais, correções, validações e Stage Report precisam ser publicados antes de liberar a próxima.

## Regra de autoridade

### Core StudioSat Web
Responsável por MediaMTX, NGINX/TLS, nomenclatura, channels-registry, contratos de health/eventos, política systemd/slices globais, segurança, ingress/ACL, backup/rollback global, observabilidade, Change Queue e compatibilidade entre domínios.

### Domínio Rádio — trilha principal
Responsável por timeline de rádio, A/V + áudio-only, live de locutor/câmera, metadata, fallback, profile canônico de rádio e engine via `RadioEngineAdapter`.

### Domínio TV — Engenharia TV
Responsável por canonical/QC de TV, continuidade A/V, playlist/scheduler, DTS/timebase, filler, live de TV e engine via `TvEngineAdapter`.

**O Core é comum. Os motores não são.**

## Disciplina de trabalho

```text
PARALELISMO DE ENGENHARIA = SIM
PARALELISMO DE ALTERAÇÃO DO HOST = NÃO
```

TV e Rádio podem preparar candidates, profiles, testes e documentação simultaneamente. Apenas uma Change pode estar em `EXECUTING` no host de produção.

## Ordem operacional atual — trilha Rádio

1. CHG-001 Core Preflight — **DONE/PASS**.
2. CHG-002 Channels Registry real — **DONE/PASS**.
3. CHG-003 Core Contract — **DONE/ACCEPTED por Core + TV + Rádio**.
4. CHG-004 Health read-only — **próxima ação no host**.
5. CHG-005R recuperar Radio Rock no legado.
6. CHG-008A Country LAB: estrutura/canonical/corpus.
7. CHG-008B Country `RadioEngineAdapter`: A/V + áudio-only.
8. CHG-009A fallback/metadata/failure tests.
9. CHG-009B live locutor/câmera.
10. CHG-009C shadow ≥24h.
11. CHG-010 Core Compatibility Gate com TV.
12. CHG-011 Country cutover.
13. Pop → Clássicas → Rock → Principal, uma por vez.

As changes TV continuam na mesma Change Queue, mas não são pré-condição para a trilha Rádio. Nenhuma mudança TV pode executar simultaneamente com mudança Rádio/Core.

## Scripts e correções

Um script que foi corrigido no servidor não pode permanecer apenas no servidor. A versão que efetivamente funcionou deve ser trazida para `scripts/` antes da etapa seguinte, acompanhada de motivo da correção, validação, hashes quando disponíveis, Stage Report e rollback conhecido.

## Segurança

Este repositório é público. Não versionar senhas, tokens, stream keys, chaves privadas, backups privados, dumps com credenciais, `.env` reais, configurações não redigidas ou pacotes brutos de preflight.

## Próxima ação prática

Executar **CHG-004 — Health read-only** somente após `git pull --ff-only`, conferência do HEAD/working tree e `bash -n` do candidate.

Candidate:

```text
candidates/CHG-004/studiosat-health-readonly.sh
```

A saída deve permanecer privada até análise e publicação do Stage Report sanitizado.
