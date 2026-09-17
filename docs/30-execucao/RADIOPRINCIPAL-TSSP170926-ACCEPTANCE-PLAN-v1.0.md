# Rádio Principal — TSSP170926 Acceptance Plan v1.0

## Objetivo

Validar a implementação da réplica autoritativa `RadioBOSS -> NS1` usando a programação atualmente visível no RadioBOSS: `Tarde Studio Sat Principal (TSSP170926)`.

Este plano é inicialmente **candidate/read-only/shadow**. Não autoriza mudança do caminho público.

## Evidência visual inicial

A captura do operador em 2026-09-17 mostra:

- RadioBOSS Ultimate 7.2.2.0;
- `Tarde Studio Sat Principal (TSSP170926)` ativa;
- 85 faixas indicadas na UI;
- duração total aproximada `5:33:55`;
- reprodução visível de Elton John — `Something About The Way You Look Tonight` por volta de 16:47;
- próximo item visível: Corona — `The Rhythm Of The Night`;
- scheduler habilitado;
- evento futuro às 16:50 na área lateral;
- logs visuais indicando execução de schedule/inserção.

A imagem não prova o conteúdo do snapshot enviado ao NS1. Esta correspondência precisa ser medida.

## Fase 0 — capturar a autoridade sem alterar produção

Coletar e preservar, no mesmo intervalo:

- identificação da playlist ativa no RadioBOSS;
- playlist/fila efetiva completa;
- `schedule.json`;
- `playback.json`;
- `heartbeat.json`;
- `librarymanifest.json`;
- revisão/timestamp da origem;
- lista de assets referenciados;
- estado do Harbor;
- estado `radioprincipal-ns1`;
- saída pública `radioprincipal`.

Resultado obrigatório: conseguir apontar qual objeto machine-readable corresponde à `TSSP170926`.

## Gate A — explicar 85 vs 154

A UI mostra 85 faixas, enquanto o mirror/controller recente observou cerca de 154 itens de mídia.

O teste deve classificar cada número, por exemplo:

- playlist ativa;
- playlist agregada;
- biblioteca referenciada;
- fila efetiva;
- outra coleção.

Gate passa somente com explicação inequívoca e reproduzível.

## Fase 1 — banco candidate no NS1

Criar banco separado da produção, sem tocar no banco/runtime atual.

Entidades mínimas para o candidate:

```text
programs
assets
asset_versions
asset_presence
playlist_instances
playlist_revisions
playlist_items
schedule_events
execution_plans
playback_checkpoints
sync_runs
transfer_jobs
```

A `TSSP170926` deve aparecer como uma instância/revisão identificável.

## Gate B — identidade item a item

Para cada item da programação/fila:

- ordinal/posição;
- título/tipo;
- referência de origem;
- `asset_id` ou estado `UNRESOLVED`;
- duração;
- horário planejado quando aplicável;
- origem playlist/scheduler/manual;
- estado de presença no NS1.

O sistema não pode considerar `READY` um item sem resolução inequívoca de mídia, salvo eventos LIVE explicitamente tipados.

## Fase 2 — reconciliação da biblioteca

Comparar referências da `TSSP170926` com o asset store do NS1.

Classificar:

```text
PRESENT_VALID
MISSING
HASH_MISMATCH
UNRESOLVED
DUPLICATE_LOGICAL
```

Somente `MISSING` ou versão alterada deve gerar transferência.

Não transferir novamente um asset cujo hash canônico já esteja disponível.

## Gate C — janela crítica

Definir janela crítica inicial como:

- item atual;
- todos os itens do programa atual que podem ser alcançados antes de nova reconciliação segura;
- inserções urgentes do scheduler.

Antes de qualquer failover controlado, a janela crítica deve estar 100% `PRESENT_VALID`.

## Fase 3 — shadow guiado pelo playback

O candidate deve receber continuamente:

- item atual;
- posição na playlist;
- `pos_ms`;
- duração;
- estado play/pause;
- próximo item;
- timestamp da fonte.

O candidate calcula qual arquivo local corresponde ao item atual e qual offset deveria estar reproduzindo.

Nesta fase, ainda não muda o selector público.

## Gate D — tracking

Durante período mínimo de observação, comparar repetidamente:

```text
RadioBOSS current item
vs
candidate current item
```

E:

```text
RadioBOSS pos_ms
vs
candidate expected pos_ms
```

Registrar drift, troca de faixa, inserts e revisão da playlist.

Não promover enquanto existirem divergências não explicadas.

## Fase 4 — inserção dinâmica

Usar uma mudança real ou ensaio seguro no RadioBOSS, sem interromper a programação pública, para provar que:

1. novo item aparece na fila/schedule;
2. NS1 detecta alteração;
3. cria nova revisão sem perder a anterior;
4. resolve o asset;
5. se faltar, transfere somente este asset;
6. item passa a READY antes de sua execução sempre que houver tempo operacional suficiente.

## Gate E — execução futura

O NS1 deve persistir programação futura e demonstrar que consegue montar o execution plan mesmo após interromper apenas o fluxo de controle candidate em laboratório.

Este ensaio não deve interromper o RadioBOSS LIVE nem a saída pública.

## Fase 5 — failover controlado

Somente após Gates A-E.

Durante janela aprovada:

1. registrar checkpoint RadioBOSS;
2. provocar perda controlada da fonte LIVE, sem destruir dados;
3. medir tempo de detecção;
4. verificar que shadow assume o mesmo item;
5. medir diferença de posição;
6. observar sequência dos próximos itens;
7. confirmar transmissão pública;
8. restaurar fonte LIVE;
9. exigir hysteresis/estabilidade;
10. realizar failback;
11. produzir relatório completo.

## Evidências obrigatórias por transmissão

Para cada item usado durante o ensaio:

- `transmission_event_id`;
- programa/playlist/revisão;
- `playlist_item_id`;
- `asset_id` e versão;
- título/artista/tipo;
- origem: `RADIOBOSS_LIVE` ou `NS1_SHADOW`;
- início/fim UTC;
- posição inicial no caso de failover;
- selector source;
- confirmação de publicação MediaMTX;
- evidência HLS/entrega quando coletada;
- divergências.

## Critério de sucesso

O teste da `TSSP170926` somente é aprovado quando o NS1 demonstrar que:

- entende qual é a programação ativa;
- possui ou transfere somente as mídias necessárias;
- acompanha o RadioBOSS em tempo real;
- incorpora alterações/inserções;
- consegue continuar a mesma programação sem o computador do estúdio;
- não troca para uma playlist própria;
- mantém trilha de auditoria e proveniência;
- retorna ao RadioBOSS apenas após estabilidade.

## Regra de rollback

Até a aprovação completa, todos os componentes novos permanecem em namespace/path/database candidate. Em caso de erro, parar somente o candidate e preservar o selector/Harbor/MediaMTX/caminho público atuais.
