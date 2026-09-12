# StudioSat Web — Change Queue

Regra: **uma alteração ativa por vez no host de produção**. Engenharia de TV e Rádio podem preparar documentação/candidates em paralelo, mas apenas uma change pode modificar o host por vez.

Protocolo obrigatório: `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`.

Diretriz vigente: **IN-PLACE FIRST / NO CONTAINERS / NO VMs / NO DUPLICATE PLATFORM**.

## Baseline factual vigente — 2026-09-12

O pacote `OBS-NS1-RAYX-20260912` foi coletado e analisado. O baseline factual completo está em:

```text
docs/90-evidencias/BASELINE_NS1_DEEP_2026-09-12.md
```

O baseline antigo de 09/09–10/09 não deve ser usado isoladamente como verdade do host atual.

## Estado factual congelado antes da mudança

- cinco Rádios Studio Sat: **ON-AIR / baseline imutável**;
- sites/player/portal Rádio: **EM PRODUÇÃO / baseline imutável**;
- TVKIDS local: **ON-AIR**, 15/15 canonical, porém com `Non-monotonic DTS` de áudio em boundaries recorrentes;
- TVKIDS público: **BROKEN**, pois não há vhost TV dedicado e os hosts caem no player Rádio;
- TVTEENS/TVVIVA/TVMAISJOVEM: **FAILED**, com canonical válido disponível e falha de `ExecStartPre` porque o generator legado exclui `test/teste` em `ready/`;
- MediaMTX: compartilhado e saudável para as cinco rádios + TVKIDS;
- antigo `CHG-TVKIDS-001`: **STALE / NÃO USAR** contra o NGINX atual.

## Falsos positivos eliminados

O novo health read-only é:

```text
scripts/ns1-health-certify-v3.sh
```

Ele substitui os testes ambíguos do coletor v2 para decisão operacional:

1. segue redirects HLS locais antes de validar M3U8;
2. prova freshness usando `#EXT-X-MEDIA-SEQUENCE` do media playlist, e não apenas HTTP 200/master estático;
3. valida o portal `www.radio.studiosatweb.com.br` pela rota real `/hls/<station>/index.m3u8`;
4. para TVs, HTTP 200 sozinho não vale: exige o header `X-StudioSat-TV: tv-player-v1` e M3U8 real;
5. não usa o `r_frame_rate` isolado do RTSP como verdade do FPS de produto TV.

## CHG-TV-RESTORE-001 — AUTORIZADA

Objetivo: colocar as quatro TVs no ar e corrigir o produto público TV **sem alterar o baseline Rádio**.

Executor único:

```text
scripts/tv/restore-four-tvs-production-v2.sh
```

Candidates:

```text
candidates/CHG-TV-RESTORE-001/tps-tv-canonical-plan-v1.sh
candidates/CHG-TV-RESTORE-001/studiosat-tv-v1.conf
candidates/CHG-TV-RESTORE-001/tv-player-index-v1.html
```

### Gates obrigatórios antes de qualquer mutação

O executor aborta antes da primeira alteração se qualquer condição falhar:

- `HEAD != origin/main` ou worktree rastreada suja;
- outra change/processo mutável ou job systemd em andamento;
- MediaMTX sem PID válido;
- qualquer uma das cinco rádios não estiver active, AAC 48 kHz stereo, `ready=true` e HLS real;
- qualquer HLS do portal Rádio real em `/hls/` falhar;
- webroots/configurações Rádio ausentes;
- canonical de TVTEENS/TVVIVA/TVMAISJOVEM não passar perfil, decode integral e loop temporal 3x;
- canonical TVKIDS não passar perfil/decode;
- falta de RAM/disco mínimos.

### Correção TVKIDS

A timeline atual é testada offline em dois ciclos completos. Se houver DTS:

1. tenta reconstrução apenas do áudio AAC, preservando vídeo bit-a-bit;
2. exige profile/decode e **zero DTS em dois ciclos completos**;
3. se a correção de áudio for insuficiente, usa normalização integral deterministicamente;
4. nenhum candidate toca produção antes de passar o gate temporal.

O canonical atual só é trocado depois do candidate passar. O original é movido para archive e fica disponível para rollback.

### TVTEENS / TVVIVA / TVMAISJOVEM

As três passam a usar um builder TV dedicado que lê `canonical/` e não aplica a exclusão nominal `test/teste` do generator legado. Cada station é iniciada individualmente e validada por systemd + MediaMTX + RTSP + HLS antes da próxima.

### NGINX / produto público TV

A mudança cria somente:

```text
/etc/nginx/conf.d/studiosat-tv.conf
/var/www/studiosat-tv-player/index.html
```

Os arquivos Rádio abaixo são invariantes e não são editados:

```text
/etc/nginx/conf.d/studiosat-radio.conf
/etc/nginx/conf.d/zz-studiosat-radio-portal.conf
/var/www/studiosat-radio-player
/var/www/studiosat-radio-portal
/var/www/studiosat-radio/current
```

O NGINX candidate só é recarregado depois de `nginx -t` passar.

### Gate de preservação Rádio

No final da change o executor exige:

- mesmo PID das cinco rádios PRE/POST;
- mesmo SHA das cinco playlists PRE/POST;
- mesmos hashes dos dois arquivos NGINX Rádio;
- mesmos hashes dos três webroots Rádio;
- mesmo PID MediaMTX;
- cinco rádios continuam active/ready/AAC/HLS;
- portal Rádio continua servindo M3U8 pela rota `/hls/`.

Qualquer violação pós-mutação dispara rollback TV.

### Resultado obrigatório

```text
CHG_TV_RESTORE_001=PASS
ALL_5_RADIOS_PRESERVED=PASS
ALL_4_TVS_ON_AIR=PASS
PUBLIC_TV_VHOSTS=PASS
FALSE_POSITIVE_HEALTH_V3=PASS
```

## Trilha crítica

| ID | Mudança | Estado |
|---|---|---|
| OBS-NS1-RAYX-20260912 | Raio-X profundo principal | **DONE / ANALISADO** |
| OBS-NS1-HEALTH-V3 | Health sem falsos positivos | **READY / READ-ONLY** |
| CHG-TV-RESTORE-001 | Restaurar 4 TVs preservando Rádio | **ACTIVE / AUTORIZADA** |
| CHG-TVKIDS-001 antigo | Executor anterior | **STALE / NÃO USAR** |
| CHG-R01/R02/R03/RWEB01 | Rádio | **FROZEN / produção atual preservada** |

## Regra de execução

A única production-change autorizada neste momento é `CHG-TV-RESTORE-001`. Nenhum outro apply, restart, reload ou mudança Rádio deve ser executado em paralelo. O executor contém lock global, gates PRE/POST e rollback próprio.