# Rádio Principal — C09 — Shadow síncrono ≤5s e failover sem alternância

Data: 2026-09-17
Workstream: RADIOPRINCIPAL-NS1

## Regra operacional definitiva

RadioBOSS/local studio é a autoridade editorial. O NS1 deve manter um shadow executável da fila efetiva do RadioBOSS com reconciliação completa em no máximo 5 segundos, além de processar imediatamente eventos/checkpoints recebidos.

O shadow não pode reproduzir uma playlist independente ou antiga.

## Estado que deve ser replicado

- playlist/fila efetiva;
- item atual;
- `playlistpos`;
- `pos_ms`;
- próximo item;
- schedule;
- itens dinâmicos/virtuais;
- comerciais e inserções;
- hora certa;
- temperatura quando representada pela autoridade/função correspondente;
- assets físicos necessários;
- metadados e transições.

## Failover

Quando o áudio LIVE do RadioBOSS falhar:

1. selector deve entregar o shadow NS1;
2. shadow deve estar no mesmo item da autoridade;
3. posição de retomada deve ser derivada do último checkpoint fresco `pos_ms`, compensado pelo tempo transcorrido;
4. diferença alvo entre autoridade e shadow: <=5s antes do failover, com reseek quando necessário;
5. o shadow continua a fila efetiva e schedule como se a origem ainda estivesse operando.

## Anti-flap

O selector não pode alternar continuamente RadioBOSS/NS1 durante microquedas.

- falha LIVE: takeover rápido pelo shadow;
- retorno do RadioBOSS: somente após janela contínua de estabilidade;
- durante a janela de recuperação, NS1 permanece no ar e continua sincronizado;
- ao retornar ao LIVE, handoff deve ocorrer sem trocar para conteúdo editorial divergente.

Valores iniciais candidatos:
- reconciliação autoritativa: 5s;
- playback freshness: 10s;
- heartbeat freshness: 15s;
- estabilidade mínima antes de retornar ao RadioBOSS: 15s.

A janela final de retorno deve ser validada em teste, mas não pode ser zero.

## Assets

Ao detectar referência física inexistente no NS1:

- consultar índice local;
- se ausente, iniciar transferência imediatamente;
- prioridade máxima para current/next/próximos itens;
- não aguardar outro ciclo de playlist;
- assets já existentes não são retransmitidos.

Itens virtuais como `saytime=...` não são tratados como MP3 faltantes; são comandos executáveis/adapters.

## Gate de produção

Não promover novo shadow até provar:

- current/next alinhados;
- current asset ready;
- fila efetiva atual;
- schedule atual;
- comandos virtuais reconhecidos;
- assets imediatos disponíveis;
- takeover em mesmo item/posição;
- ausência de alternância entre conteúdos divergentes.

O sistema legado `mirror-playout.py` que usa `matched_index` não satisfaz sozinho este contrato.
