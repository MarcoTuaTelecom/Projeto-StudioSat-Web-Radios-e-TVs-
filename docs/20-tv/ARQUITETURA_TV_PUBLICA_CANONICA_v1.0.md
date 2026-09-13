# StudioSat Web — Arquitetura TV Pública Canônica v1.0

## Objetivo

Substituir a cadeia de correções incrementais de TV por uma arquitetura única, explícita e auditável para TVKIDS, TVTEENS, TVVIVA e TVMAISJOVEM, sem editar a fundação Rádio em produção.

## Princípios obrigatórios

1. **Um único owner NGINX para todos os hostnames TV.** Não pode existir `server_name` TV duplicado em múltiplos arquivos ativos.
2. **Nenhum arquivo NGINX Rádio é alterado.** `studiosat-radio.conf` e `zz-studiosat-radio-portal.conf` são invariantes.
3. **Um único webroot TV canônico:** `/var/www/studiosat-tv/current`.
4. **Um único player TV:** fullscreen, sem layout de portal em torno do vídeo, com HLS contínuo e recuperação interna; a página não deve ser recarregada periodicamente como mecanismo normal de operação.
5. **HLS same-origin:** cada vhost TV publica somente o path de sua própria emissora e faz proxy para `127.0.0.1:8888` preservando a URI (`/tvkids/...`, `/tvteens/...`, etc.).
6. **Autoplay compatível com navegador:** autoplay mudo é tentado imediatamente; áudio e fullscreen real dependem de gesto do usuário quando o navegador assim exigir.
7. **Runtime e web são planos separados.** NGINX/player não reiniciam FFmpeg nem MediaMTX. Recuperação de mídia não depende da publicação web.
8. **Nada de patch em linha de arquivos legados.** Na migração, arquivos NGINX que sejam exclusivamente TV são arquivados e removidos do include ativo; em seguida é instalado o owner canônico. Se um arquivo misturar TV com Rádio ou outro hostname não-TV, a migração aborta.
9. **Health sem falso positivo:** HTTP 200 sozinho não é sucesso. É obrigatório provar owner correto por header, HTML esperado, M3U8 real, freshness do HLS, MediaMTX `ready=true` e invariantes Rádio.
10. **Rollback transacional:** todo arquivo retirado do NGINX ativo, webroot anterior e configuração canônica anterior são copiados antes de qualquer mutação.

## Hostnames oficiais

### TVKIDS
- `tvkids.studiosatweb.com.br`
- `www.tvkids.studiosatweb.com.br`
- `tvkidsweb.studiosatweb.com.br`
- `www.tvkidsweb.studiosatweb.com.br`

### TVTEENS
- `tvteens.studiosatweb.com.br`
- `www.tvteens.studiosatweb.com.br`

### TVVIVA
- `tvviva.studiosatweb.com.br`
- `www.tvviva.studiosatweb.com.br`

### TVMAISJOVEM
- `tvmaisjovem.studiosatweb.com.br`
- `www.tvmaisjovem.studiosatweb.com.br`

## Owner NGINX canônico

Arquivo único:

`/etc/nginx/conf.d/studiosat-tv.conf`

Cada grupo de hostnames possui bloco HTTPS explícito. Não usamos wildcard para as TVs e não dependemos do primeiro/default vhost. O arquivo expõe um header de identidade:

`X-StudioSat-TV-Owner: canonical-v1`

E um header por estação:

`X-StudioSat-TV-Station: tvkids|tvteens|tvviva|tvmaisjovem`

## Webroot canônico

`/var/www/studiosat-tv/current/index.html`

Não são usados `/var/www/emissoras/tv*.html` nem `/var/www/portais/www.tv*.studiosatweb.com.br/index.html` como roots de produção após a migração. Eles podem permanecer arquivados como evidência histórica, mas deixam de participar do NGINX ativo.

## Player

O player é um shell único. Ele escolhe `station_id` pelo hostname e usa a URL HLS same-origin:

`/<station_id>/index.m3u8`

Comportamento:

- viewport 100%;
- vídeo em tela cheia;
- autoplay `muted` imediato;
- primeiro clique/tap: remove mute e solicita Fullscreen API;
- hls.js em versão fixada, nunca `@1` flutuante;
- recovery de network error com `startLoad()`;
- recovery de media error com `recoverMediaError()`;
- rebuild completo da instância HLS somente quando recovery normal falhar;
- watchdog observa progresso do `currentTime` e atualização de manifest/level;
- retorno de background sincroniza novamente com live edge;
- reload de página inteira é último recurso, não heartbeat.

## HLS / MediaMTX

MediaMTX é a origem HLS em `127.0.0.1:8888`. O path público preserva o mesmo nome da station. Exemplo:

`https://tvkidsweb.studiosatweb.com.br/tvkids/index.m3u8`

proxy para:

`http://127.0.0.1:8888/tvkids/index.m3u8`

Não é criado prefixo artificial intermediário e não existe reescrita para paths de Rádio.

## Migração limpa de NGINX

O migrador obtém o `nginx -T` real e descobre quais arquivos carregados possuem qualquer hostname TV. Cada owner é classificado:

- se for o owner canônico: permitido;
- se o arquivo contiver apenas hostnames TV oficiais: ele é arquivado e retirado do include ativo;
- se contiver hostname Rádio ou hostname externo ao conjunto TV oficial: **ABORTA** antes de mutar.

Depois instala o arquivo canônico, executa `nginx -t`, prova que cada hostname TV aparece em um único owner carregado e somente então executa `systemctl reload nginx`.

## Runtime de mídia

O player web não mascara falha de playout. Cada TV precisa, separadamente, satisfazer:

- systemd active;
- MediaMTX `ready=true`;
- H.264 1280x720, 30 fps, yuv420p;
- AAC-LC 48 kHz stereo;
- HLS real e fresh;
- candidate temporal com zero `Non-monotonic DTS` antes de cutover.

Para concatenação, a regra é: stream-copy só é aceito quando o teste temporal completo prova timestamps monotônicos. Quando é necessário re-encode, FFmpeg recomenda o `concat` filter para concatenação com re-encode; o concat demuxer é apropriado para evitar re-encode apenas quando os arquivos/timestamps são compatíveis.

## Invariantes Rádio

Toda change TV registra PRE/POST:

- PID das cinco rádios;
- SHA das cinco playlists;
- PID MediaMTX;
- SHA de `studiosat-radio.conf`;
- SHA de `zz-studiosat-radio-portal.conf`;
- hashes dos três webroots Rádio.

Qualquer diferença cancela a change e dispara rollback TV.

## Estado dos scripts antigos

Os executores `CHG-TVWEB01`, `CHG-TVWEB02`, `CHG-TVKIDS-WEB-003`, `CHG-TV-PLAYER-002` e os patchers de vhost anteriores passam a ser **legado/superseded** quando `CHG-TV-CANON-001` for aplicado com PASS. Não devem continuar coexistindo como owners NGINX ativos.
