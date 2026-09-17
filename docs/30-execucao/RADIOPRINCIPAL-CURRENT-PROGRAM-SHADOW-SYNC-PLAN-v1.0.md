# Rádio Principal — Current Program Shadow Sync Plan v1.0

## Objetivo

Implantar e validar, sem alterar a saída pública, a réplica operacional da programação atualmente ativa no RadioBOSS para o NS1.

O teste deve funcionar independentemente do nome exato ou quantidade de itens da programação ativa.

## Princípio

A programação exibida no RadioBOSS é apenas a interface humana. A prova técnica deve partir da autoridade machine-readable recebida pelo NS1 e normalizada pelo `RadioBOSSAdapter`.

Contagens históricas anteriores ao contrato atual não são gate.

## Fase 0 — somente leitura

Capturar simultaneamente:

- programa/grade ativa;
- playlist/queue recebida;
- schedule;
- playback;
- heartbeat;
- library manifest;
- estado Harbor;
- estado shadow;
- estado selector;
- path público.

Nenhuma mudança no selector ou path público.

## Fase 1 — banco candidate separado

Criar um banco candidate separado da produção, inicialmente SQLite WAL.

Persistir:

```text
stations
source_systems
external_refs
programs
program_grids
program_grid_revisions
program_slots
works
assets
asset_versions
asset_presence
playlist_instances
playlist_revisions
playlist_items
schedule_events
execution_plans
execution_plan_items
playback_checkpoints
sync_runs
transfer_jobs
execution_overrides
```

## Fase 2 — importer/normalizer

A cada evento recebido e, no máximo, a cada 10 segundos:

1. ler autoridade atual;
2. normalizar IDs externos para IDs Studio Sat;
3. calcular hashes semânticos;
4. criar nova revisão somente se houver mudança real;
5. atualizar checkpoint de playback;
6. reconciliar assets;
7. priorizar downloads faltantes;
8. calcular estado de prontidão.

Se nada mudou semanticamente, registrar `NO_OP` e não criar nova revisão.

## Fase 3 — montar execution plan

A fila efetiva deve representar:

```text
program/grid
+ playlist revision
+ schedule
+ inserts
+ overrides/manual/live
= execution plan
```

Cada item deve resolver para:

- canonical item id;
- canonical asset/version;
- external source ref;
- posição/ordem;
- horário absoluto quando aplicável;
- tipo editorial;
- status de presença local.

## Fase 4 — shadow sem publicação pública

O player candidate deve seguir o RadioBOSS usando playback/checkpoint como autoridade:

- resolver item atual;
- localizar asset local;
- calcular posição esperada;
- manter shadow alinhado;
- comparar item/posição periodicamente;
- não tocar no selector de produção.

Registrar por amostra:

```text
SOURCE_ITEM
SOURCE_POS_MS
SHADOW_ITEM
SHADOW_POS_MS
DELTA_MS
QUEUE_REVISION
READY_STATE
```

## Fase 5 — hora certa/schedule

Eventos com hora absoluta devem ser pré-carregados e disparados pelo relógio local sincronizado do NS1.

O ciclo de 10 segundos atualiza mudanças de schedule, mas não é o relógio de disparo.

Provar:

- timezone correto;
- NTP/chrony saudável;
- drift dentro do limite;
- evento existente antes do horário;
- execução no instante previsto.

## Fase 6 — prontidão

Estados propostos:

```text
NOT_READY
SYNCING
HOT_READY
DEGRADED
DIVERGED
OFFLINE_AUTONOMOUS
```

`HOT_READY` exige pelo menos:

- programa/grade resolvido;
- execution plan válido;
- item atual resolvido;
- próximos itens críticos locais;
- schedule válido;
- playback fresco;
- shadow alinhado dentro do limite;
- ausência de asset crítico faltante.

## Fase 7 — teste de desconexão somente após HOT_READY

Somente após validação do candidate:

1. planejar janela de teste;
2. registrar checkpoint antes da falha;
3. simular perda do estúdio de maneira controlada;
4. confirmar continuidade do mesmo item/posição;
5. confirmar sequência subsequente idêntica ao plano autoritativo;
6. confirmar eventos de hora certa/schedule;
7. restaurar estúdio;
8. exigir estabilidade antes do failback;
9. auditar toda a sequência.

## Critério de sucesso desta etapa

Antes de qualquer cutover, o NS1 deve conseguir demonstrar:

```text
PROGRAM_RESOLVED=YES
EXECUTION_PLAN_VALID=YES
SEMANTIC_SYNC_INTERVAL_MAX_SECONDS=10
CRITICAL_ASSETS_READY=YES
PLAYBACK_CHECKPOINT_FRESH=YES
SHADOW_ITEM_MATCH=YES
SHADOW_POSITION_WITHIN_LIMIT=YES
SCHEDULE_READY=YES
PUBLIC_PATH_UNCHANGED=YES
```
