# StudioSat Web — Change Queue

Regra: **uma alteração ativa por vez no host de produção**. Engenharia de TV e Rádio podem preparar documentação/candidates em paralelo, mas apenas uma change pode modificar o host por vez.

Protocolo obrigatório: `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`.

Diretriz vigente: **IN-PLACE FIRST / NO CONTAINERS / NO VMs / NO DUPLICATE PLATFORM**.

## Baseline factual vigente — 2026-09-12

Fonte factual:

```text
docs/90-evidencias/BASELINE_NS1_DEEP_2026-09-12.md
```

Estado confirmado antes da convergência canônica:

- cinco Rádios Studio Sat: **ON-AIR / baseline imutável**;
- sites/player/portal Rádio: **EM PRODUÇÃO / baseline imutável**;
- MediaMTX: compartilhado e saudável para as cinco rádios + TVKIDS;
- TVKIDS: runtime local ativo, 15/15 canonical, com `Non-monotonic DTS` de áudio recorrente na estratégia antiga de concat + stream-copy integral;
- TVTEENS/TVVIVA/TVMAISJOVEM: canonical técnico disponível, porém units falharam no generator legado e TVTEENS provou DTS em teste 3x com stream-copy integral;
- NGINX TV acumulou owners legados de changes anteriores e não pode continuar sendo corrigido por novos patches de `server_name`.

## Decisão arquitetural — 2026-09-12

**ENCERRAR A CADEIA DE REMENDOS TV.**

Documento normativo novo:

```text
docs/20-tv/ARQUITETURA_TV_PUBLICA_CANONICA_v1.0.md
```

A arquitetura canônica separa dois planos:

1. **CHG-TV-CANON-001 — WEB/NGINX**: um único owner NGINX para todos os hostnames TV + um único player fullscreen/resiliente.
2. **CHG-TV-CANON-002 — RUNTIME**: um único playout policy para as quatro TVs, playlist `canonical/` e áudio com timeline gerada por sample-count para eliminar sobreposição AAC nos boundaries, mantendo vídeo em stream-copy.

Os scripts `CHG-TVWEB01`, `CHG-TVWEB02`, `CHG-TVKIDS-WEB-003`, `CHG-TV-PLAYER-002`, `CHG-TV-RESTORE-001` e patchers TV anteriores passam a **LEGADO / SUPERSEDED / NÃO EXECUTAR**. Eles ficam no repositório apenas como histórico/evidência até limpeza posterior.

## Base técnica pesquisada

- NGINX seleciona virtual server por `listen` + `server_name`; quando não há match, cai no default/primeiro server. Logo, hosts TV sem owner explícito podem cair em Rádio. A solução é ownership explícito e único, não novos blocos duplicados.
- MediaMTX expõe HLS diretamente em `/<path>/index.m3u8`; o proxy público preservará exatamente os paths `tvkids`, `tvteens`, `tvviva`, `tvmaisjovem`.
- Chrome permite autoplay mudo; autoplay com som depende de interação/engagement/policy. Portanto o player tenta autoplay muted e usa o primeiro gesto para áudio + Fullscreen API.
- hls.js possui recovery oficial: `startLoad()` para network error e `recoverMediaError()` para media error. Reload de página inteira é último recurso, não heartbeat.
- FFmpeg documenta que concat demuxer é apropriado para evitar re-encode quando timestamps são compatíveis e recomenda concat filter quando é necessário re-encode. O playout canônico evita depender do timestamp AAC de cada MP4: decodifica somente áudio e aplica `aresample` + `asetpts=N/SR/TB`, gerando timeline monotônica por contagem de samples; vídeo continua bit-exact.

## CHG-TV-CANON-001 — WEB/NGINX

Candidate:

```text
candidates/CHG-TV-CANON-001/studiosat-tv.conf
candidates/CHG-TV-CANON-001/index.html
```

Executor autorizado:

```text
scripts/tv/studiosat-tv-canonical-web-migrate-v1.1.sh
```

Comportamento obrigatório:

- lê o `nginx -T` real;
- descobre owners TV ativos por conteúdo carregado, não por nome esperado de arquivo;
- qualquer owner que misture TV com Rádio ou hostname externo aborta **antes da mutação**;
- todo owner exclusivamente TV é arquivado e retirado do include ativo inteiro — sem patch em linha;
- instala somente `/etc/nginx/conf.d/studiosat-tv.conf` como owner TV;
- instala o player único em `/var/www/studiosat-tv/current/index.html`;
- exige `nginx -t` antes do reload;
- prova que cada hostname TV pertence a exatamente um arquivo carregado, o owner canônico;
- valida roots por SNI local (`--resolve ... 127.0.0.1`) para eliminar DNS/cache como falso positivo;
- para station `ready=true`, exige M3U8 real pelo vhost público;
- não reinicia FFmpeg nem MediaMTX;
- PIDs/playlists/configs/webroots Rádio são invariantes PRE/POST.

Resultado obrigatório:

```text
CHG_TV_CANON_001_WEB=PASS
SINGLE_TV_NGINX_OWNER=PASS
TV_FULLSCREEN_PLAYER_V3=PASS
ALL_5_RADIOS_PRESERVED=PASS
MEDIAMTX_PRESERVED=PASS
```

## CHG-TV-CANON-002 — RUNTIME

Candidates:

```text
candidates/CHG-TV-CANON-001/tps-tv-plan-v1.sh
candidates/CHG-TV-CANON-001/tps-tv-playout-v1.sh
```

Executor autorizado **somente depois de CHG-TV-CANON-001 PASS**:

```text
scripts/tv/studiosat-tv-canonical-runtime-migrate-v1.sh
```

Política de runtime:

```text
canonical/*.mp4
  -> ffconcat atômico
  -> vídeo: H.264 stream-copy
  -> áudio: decode -> 48 kHz -> asetpts=N/SR/TB -> AAC 192k stereo
  -> FLV/RTMP local
  -> MediaMTX
```

Antes da mutação, cada station precisa passar:

- canonical não vazio;
- H.264 1280x720 yuv420p 30 fps;
- AAC 48 kHz stereo;
- decode integral de todo asset;
- teste 3x com **a exata política canônica de playout**;
- `rc=0`, `dts=0`, `fatal=0`.

Depois disso, as quatro units têm os drop-ins antigos TV arquivados e substituídos por **um único drop-in canônico por station**. Não se altera unit Rádio nem se reinicia MediaMTX. As TVs convergem uma por vez, com systemd + MediaMTX + RTSP + HLS e journal `dts=0` antes de PASS.

Resultado obrigatório:

```text
CHG_TV_CANON_002_RUNTIME=PASS
ALL_4_TVS_RUNTIME_READY=PASS
ZERO_DTS_CANONICAL_PLAYOUT=PASS
ALL_5_RADIOS_PRESERVED=PASS
MEDIAMTX_PRESERVED=PASS
```

## Trilha crítica atual

| ID | Mudança | Estado |
|---|---|---|
| OBS-NS1-RAYX-20260912 | Raio-X profundo principal | **DONE / ANALISADO** |
| CHG-TV-CANON-001 | Convergência WEB/NGINX TV | **ACTIVE / AUTORIZADA** |
| CHG-TV-CANON-002 | Convergência runtime 4 TVs | **READY / BLOQUEADA ATÉ CANON-001 PASS** |
| CHG-TV-RESTORE-001 | Restore incremental anterior | **SUPERSEDED / NÃO EXECUTAR** |
| CHG-TVKIDS-WEB-003 | Patch isolado TVKIDS | **SUPERSEDED / NÃO EXECUTAR** |
| CHG-TVWEB01/02 | Vhosts TV legados | **SUPERSEDED / NÃO EXECUTAR** |
| CHG-TV-PLAYER-002 | Player incremental anterior | **SUPERSEDED / NÃO EXECUTAR** |
| CHG-R01/R02/R03/RWEB01 | Rádio | **FROZEN / produção atual preservada** |

## Regra de execução

A única production-change autorizada agora é **CHG-TV-CANON-001**. Só após PASS documental e factual do owner NGINX único será liberada `CHG-TV-CANON-002`.
