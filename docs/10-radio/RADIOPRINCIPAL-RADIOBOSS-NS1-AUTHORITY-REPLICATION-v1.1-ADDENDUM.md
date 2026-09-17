# Rádio Principal — RadioBOSS → NS1 Authority Replication — Addendum v1.1

## Identidade

- Workstream: `RADIOPRINCIPAL-NS1`
- Estação: `radioprincipal`
- Data: `2026-09-17`
- Complementa: `RADIOPRINCIPAL-RADIOBOSS-NS1-AUTHORITY-REPLICATION-v1.0.md`
- Natureza: regra de negócio e regra de sistema; não autoriza cutover.

## 1. Contagens históricas não são gate de aceitação

Diferenças de quantidade observadas em fases anteriores do projeto (por exemplo contagens de playlist, media-map ou uma captura visual parcial) não devem ser usadas isoladamente para aprovar ou reprovar o novo modelo.

A estrutura anterior foi construída antes destas regras de negócio e pode representar objetos diferentes ou estados parciais.

A aceitação passa a ser semântica:

- identificar qual grade/programação está ativa;
- identificar a revisão efetiva vigente;
- reconstruir a ordem executável item a item;
- resolver cada item para um asset/version canônico;
- confirmar disponibilidade local;
- confirmar checkpoint de execução;
- confirmar transmissão pública correspondente.

## 2. Grade de programação é entidade de primeira classe

O banco do NS1 deve registrar cada grade/programação, independente da quantidade de músicas ou duração.

Entidades adicionais/regras:

```text
program_grids
program_grid_revisions
program_slots
program_segments
```

Uma grade pode conter, em qualquer ordem:

- música;
- vinheta;
- dingou;
- chamada de locutor;
- comercial;
- institucional;
- notícia;
- utilidade pública;
- hora certa;
- bloco ao vivo;
- outro conteúdo editorial.

Cada revisão deve permitir responder quantos itens de cada tipo estavam previstos e quais foram efetivamente executados.

## 3. Identidade Studio Sat independente do software de automação

O RadioBOSS é a autoridade operacional atual, mas não pode ser a autoridade final de identidade do acervo.

A identidade canônica pertence ao ecossistema Studio Sat.

O banco deve manter IDs internos estáveis e uma tabela de referências externas:

```text
external_refs
- canonical_entity_type
- canonical_entity_id
- source_system
- source_system_version
- source_namespace
- source_external_id
- first_seen_at
- last_seen_at
- active
```

Exemplo:

```text
StudioSat asset_id = sha256:...
RadioBOSS external_id = ...
```

Se no futuro a emissora trocar RadioBOSS por outro software, um novo adapter associa os IDs do novo sistema aos mesmos IDs canônicos Studio Sat.

Assim a troca do software de estúdio não invalida biblioteca, histórico, grades, auditoria nem prova de transmissão.

## 4. Adapter de origem

Toda automação de estúdio deve entrar por um contrato de adapter:

```text
SourceAutomationAdapter
  -> station identity
  -> active program/grid
  -> playlist/queue
  -> schedule
  -> playback checkpoint
  -> live/manual state
  -> asset references
  -> source provenance
```

Primeira implementação: `RadioBOSSAdapter`.

A lógica do NS1 nunca deve depender diretamente de um formato proprietário sem passar pela normalização do adapter.

## 5. Sincronização: máximo 10 segundos + eventos imediatos

Enquanto a automação de estúdio estiver conectada, o NS1 deve executar uma reconciliação semântica com intervalo máximo de 10 segundos.

Regra:

```text
EVENTO NOVO -> processar imediatamente
E
A CADA <=10 s -> reconciliar autoridade completa
```

A reconciliação de 10 s é uma salvaguarda contra perda de eventos e deve incluir no mínimo:

- programa/grade ativa;
- revisão da playlist/fila;
- schedule;
- estado LIVE/MANUAL/AUTO;
- item atual;
- posição atual;
- próximo(s) item(ns);
- referências de assets;
- presença local dos assets críticos.

## 6. No-op semântico

Cada ciclo não significa criar nova revisão.

Se as chaves semânticas não mudaram:

```text
program/grid id = igual
playlist semantic hash = igual
execution queue semantic hash = igual
schedule semantic hash = igual
asset refs = iguais
```

então:

```text
NO_OP=YES
```

Somente freshness/checkpoint/telemetria são atualizados.

Campos de transporte como `received_at`, envelope timestamp e IP não podem, sozinhos, gerar uma nova revisão editorial.

## 7. Playback é estado de alta frequência

O checkpoint de playback pode e deve chegar com frequência superior à reconciliação de 10 s.

O shadow usa esse fluxo para acompanhar:

- item atual;
- asset/version;
- `pos_ms`;
- estado play/pause;
- timestamp da origem;
- idade do checkpoint.

A reconciliação de 10 s valida que o contexto editorial ao redor do checkpoint continua coerente.

## 8. Hora certa não pode depender do polling de 10 s

Eventos com horário absoluto, especialmente hora certa, devem estar pré-carregados no NS1 e ser executados com base no relógio local sincronizado do servidor.

Requisitos:

- `chrony`/NTP saudável;
- schedule armazenado no NS1;
- timestamp absoluto normalizado;
- timezone da estação explicitamente registrada;
- monitor de drift;
- atualização imediata quando schedule mudar;
- reconciliação no máximo a cada 10 s.

O polling de 10 s serve para descobrir alteração de schedule; ele não é o temporizador de execução do evento.

## 9. Entrada do locutor / operação ao vivo

O locutor pode alterar a execução prevista sem que a definição base da playlist tenha mudado.

O modelo deve registrar estado operacional:

```text
AUTO
MANUAL
LIVE
FALLBACK
```

Uma entrada ao vivo deve gerar `execution_override`/evento equivalente contendo:

- motivo/tipo;
- início;
- fim;
- operador/locutor quando conhecido;
- item que foi interrompido;
- fila antes da intervenção;
- fila após a intervenção;
- regra de retomada determinada pela automação autoritativa.

O NS1 não deve inventar a política de retorno. Ele replica o resultado efetivo informado pela automação.

## 10. Horizonte de autonomia

Se o RadioBOSS possuir 10, 30 ou mais dias de programação futura, o NS1 deve persistir as grades/revisões dentro do horizonte configurado e reconciliar a biblioteca necessária.

Não há duplicação física por ocorrência: milhares de ocorrências podem apontar para um único asset canônico.

O objetivo de autonomia deve ser mensurável:

```text
AUTONOMY_HORIZON_START
AUTONOMY_HORIZON_END
REQUIRED_ASSETS
READY_ASSETS
MISSING_ASSETS
READY_PERCENT
```

O sistema só declara um período como `AUTONOMY_READY` quando todos os assets obrigatórios e regras de execução desse período estiverem localmente resolvidos.

## 11. Prefetch e inserções tardias

Ordem mínima de prioridade de download:

1. item atual ausente;
2. inserção nova que pode tocar imediatamente;
3. próximos itens da fila efetiva;
4. restante do programa atual;
5. próximas grades do dia;
6. restante do horizonte futuro.

Se um novo comercial/chamada for inserido durante a execução, ele entra na reconciliação imediatamente e recebe prioridade segundo sua proximidade de execução.

## 12. Regra final

O NS1 não é um gerador editorial alternativo.

Ele é simultaneamente:

- transmissor público constante;
- réplica operacional da autoridade editorial;
- cache/biblioteca de mídia reconciliada;
- shadow hot-synchronized;
- executor autônomo do último plano autoritativo aceito quando o estúdio fica indisponível;
- sistema de auditoria de execução e transmissão.
