# V2.1 — isolamento total de sessão HLS no portal

## Sintoma observado em produção

O HLS cru e o player de referência reproduzem corretamente. O portal V2 inicial apresentou, com frequência menor que o legado:

- aceleração aparente;
- desaceleração aparente;
- cortes;
- períodos de silêncio;
- maior incidência imediatamente após trocar de emissora.

## Conclusão de engenharia

O servidor/origem não deve ser modificado para perseguir este sintoma enquanto o mesmo HLS toca corretamente fora do portal.

A primeira versão V2 ainda mantinha o mesmo elemento `<audio>` durante a troca de estação e criava/destroía MediaSource/Hls.js sobre esse elemento. V2.1 remove essa continuidade.

## Nova regra

**Cada estação selecionada recebe uma sessão de mídia inteiramente nova.**

Na troca:

1. incrementa a geração da sessão;
2. interrompe o carregamento HLS anterior;
3. desanexa e destrói o Hls anterior;
4. pausa e invalida o elemento `<audio>` anterior;
5. substitui fisicamente o nó DOM por outro `<audio>`;
6. cria um novo Hls/MediaSource quando necessário;
7. ignora eventos atrasados pertencentes à geração anterior.

## HLS.js

Browsers sem HLS nativo usam HLS.js 1.6.13, a versão já usada na referência web que apresentou reprodução auditivamente boa.

Configuração deliberadamente mínima:

- worker habilitado;
- low latency desabilitada;
- `maxLiveSyncPlaybackRate = 1.0`;
- sem `liveMaxLatencyDuration`;
- sem `recoverMediaError()`;
- sem alterações programáticas de `playbackRate`;
- sem seek de catch-up.

## Telemetria

O portal mostra, sem interferir no áudio:

- playbackRate observado;
- segundos de buffer à frente;
- número da sessão.

Se `playbackRate` mudar de 1.0 sem ação da aplicação, o estado visual registra a velocidade detectada e o console registra erro.

## Critério de aprovação

Comparar, por vários minutos e após múltiplas trocas de estação:

1. `/diag-bypass/`;
2. HLS cru;
3. `/listen-v2/` V2.1.

Não promover V2 enquanto os três não apresentarem comportamento auditivo equivalente.
