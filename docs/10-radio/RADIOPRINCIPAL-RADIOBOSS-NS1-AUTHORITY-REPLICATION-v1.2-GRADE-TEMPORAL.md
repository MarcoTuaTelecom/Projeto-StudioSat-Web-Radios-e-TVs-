# Rádio Principal — Adendo v1.2 — Grade Temporal Autônoma no NS1

## Regra incorporada em 2026-09-17

A programação da Rádio Principal é governada por uma **grade temporal autoritativa**, composta por programas, horários, revisões, playlists, schedule e inserções.

O NS1 não pode decidir o programa atual apenas pela playlist mais recente recebida.

## Regra de transição de programa

Se a grade previamente recebida determinar:

```text
19:00 -> programa noturno
```

então, se o RadioBOSS estiver desconectado às 19:00, o NS1 deve:

1. possuir previamente a definição/revisão da programação noturna;
2. possuir localmente os assets necessários;
3. usar o relógio sincronizado do NS1;
4. encerrar/transicionar da programação anterior conforme a regra editorial;
5. iniciar a programação noturna no horário programado;
6. registrar a execução e a transmissão;
7. continuar offline até nova autoridade válida chegar.

A programação da tarde não pode continuar indefinidamente apenas porque foi o último snapshot de playlist recebido.

## Pré-carregamento obrigatório

Enquanto o RadioBOSS estiver conectado, o NS1 deve importar e persistir o horizonte futuro disponível:

- grade/programas futuros;
- playlist definitions;
- schedules;
- eventos de hora certa;
- assets referenciados;
- regras de transição.

O NS1 deve reconciliar a cada no máximo 10 segundos e reagir imediatamente a eventos recebidos.

## Estados de prontidão

Separar obrigatoriamente:

- `REPLICA_COMPLETE`: todos os assets/referências da revisão conhecida estão resolvidos;
- `SOURCE_ONLINE`: origem está conectada e heartbeat está fresco;
- `PLAYBACK_FRESH`: checkpoint de playback está dentro do limite;
- `QUEUE_ALIGNED`: current/next correspondem à sequência conhecida;
- `PROGRAM_GRID_READY`: grade atual e próxima transição estão persistidas;
- `AUTONOMY_READY`: grade futura necessária + assets estão disponíveis para operar desconectado;
- `HOT_READY`: origem online/fresca + réplica completa + fila alinhada.

`REPLICA_COMPLETE` não implica `SOURCE_ONLINE` e não implica `AUTONOMY_READY`.

## Evidência que motivou esta regra

No probe de 2026-09-17 por volta de 19:07 America/Sao_Paulo:

- `playlist.json`: último recebimento aproximadamente 18:20 local;
- `schedule.json`: aproximadamente 18:20 local;
- `librarymanifest.json`: aproximadamente 18:34 local;
- `playback.json`: aproximadamente 17:54 local;
- `heartbeat.json`: aproximadamente 18:43 local, `online=false`.

A réplica possuía 85/85 assets da playlist importada, mas a autoridade temporal estava antiga. Portanto classificar esse estado como `HOT_READY` era incorreto.

## Próximo gate

Antes de ativar o watch contínuo ou alterar o shadow:

1. inspecionar `librarymanifest.data.playlist_definitions`;
2. inspecionar estrutura real de `schedule.json`;
3. localizar programas futuros e horários de transição;
4. provar como a grade noturna é representada;
5. somente então implementar o executor autônomo de grade no candidate.
