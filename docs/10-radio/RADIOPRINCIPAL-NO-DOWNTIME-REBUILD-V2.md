# Rádio Principal — Reconstrução V2 sem downtime

## Regra absoluta

A partir de 2026-09-18, nenhuma etapa de desenvolvimento, teste, migração, sincronismo ou validação pode interromper a Rádio Principal pública.

Produção congelada durante a reconstrução:

- não reiniciar nem parar `studiosat-radioprincipal-selector.service`;
- não reiniciar nem parar `studiosat-radioprincipal-shadow-ns1.service`;
- não reiniciar `tps-mediamtx.service`;
- não reiniciar Nginx;
- não alterar Harbor 18005;
- não alterar o path público `radioprincipal`;
- não promover candidate diretamente para `radioprincipal-ns1`;
- não apagar mídia existente enquanto houver referência ativa possível.

Qualquer script V2 deve falhar fechado se tentar tocar componentes públicos.

## Arquitetura alvo

### Autoridade

RadioBOSS/local studio continua autoridade editorial.

### Canal de controle

RadioBOSS agent -> NS1:

- playlist efetiva;
- playback atual;
- `playlistpos`;
- `pos_ms`;
- current / next / previous;
- schedule;
- heartbeat;
- librarymanifest;
- metadados;
- referências físicas `H:\...\arquivo.mp3`;
- comandos virtuais como `saytime`.

Reconciliação máxima: 5 segundos. Eventos podem chegar imediatamente.

### Asset plane

Para cada referência física recebida:

1. normalizar a referência;
2. resolver SHA256 se já conhecido;
3. consultar store canônico;
4. se presente: READY;
5. se ausente: requisitar/upload imediato a partir do PC da emissora;
6. validar SHA256;
7. registrar origem e presença;
8. disponibilizar ao execution engine.

Store canônico único:

`/srv/tpsmedia/repository/channels/radioprincipal/mirror-store/`

Nenhuma segunda biblioteca deve ser tratada como autoridade.

### Execution engine V2

Entrada:

- fila efetiva autoritativa;
- playback checkpoints;
- assets locais;
- schedule;
- comandos virtuais.

Saída de laboratório:

`rtmp://127.0.0.1:1935/radioprincipal-v2-shadow`

ou path equivalente isolado.

Funções:

- seguir current + pos_ms;
- reseek por drift;
- continuar localmente quando playback ficar stale;
- executar próximos itens da mesma fila;
- processar hora certa;
- processar temperatura;
- processar comerciais;
- processar vinhetas/chamadas/notícias;
- manter transições e metadados;
- registrar divergência quando asset/comando não estiver pronto.

### Anti-flap

O selector V2 será testado fora da produção.

Contrato:

- falha LIVE: shadow assume;
- retorno LIVE: não retornar imediatamente;
- exigir janela contínua de estabilidade;
- nunca alternar entre conteúdos editoriais diferentes.

### Gate para cutover

Nenhum cutover até todos os itens abaixo passarem simultaneamente:

- 100% dos itens físicos imediatos READY;
- current e next resolvidos;
- shadow acompanhando current + pos_ms;
- drift <= 5 s;
- hora certa validada;
- comerciais validados;
- temperatura validada;
- schedule validado;
- teste de perda de LIVE;
- teste de reconexão;
- anti-flap validado;
- teste contínuo de várias horas;
- comparação RadioBOSS x shadow sem divergência editorial;
- rollback preparado.

## Fases

### V2-1 — congelar produção e mapear
Somente leitura da cadeia pública.

### V2-2 — asset transfer
Ligar missing -> upload automático usando o protocolo real de `studiosat-media-transfer`.

### V2-3 — canonical execution state
Banco único de playlist/fila/playback/schedule/assets.

### V2-4 — execution engine
Player shadow V2 isolado.

### V2-5 — adapters
Hora certa, temperatura, comerciais e demais comandos.

### V2-6 — test selector
Failover e anti-flap somente em path de teste.

### V2-7 — soak test
Teste contínuo sem tocar produção.

### V2-8 — cutover
Mudança única, controlada, com rollback imediato.

## Regra de desenvolvimento

Nenhuma alteração nova será validada diretamente no path público.

Falha em candidate nunca pode interromper o áudio público.
