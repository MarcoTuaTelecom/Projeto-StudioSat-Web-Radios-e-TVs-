# TVKIDS — P0 Findings — 2026-09-10

## Escopo

Análise do pacote `tvkids-p0-20260910T173345Z.shareable.tar.gz`.

## Fatos comprovados

- `tps-tvkids-playout.service` estava `active`, MainPID `1031405`, iniciado em 2026-09-09 12:59:08 UTC.
- O FFmpeg mantinha aberto `/srv/tpsmedia/repository/channels/tvkids/playlists/playlist.txt (deleted)` via `/proc/1031405/fd/3`.
- A playlist realmente usada pelo processo continha 15 itens, todos em `canonical/`, SHA-256 `2807c6c604f4601f92b990c047c857519fcb3760c58827ad308be297bcf951d0`.
- A playlist presente em disco continha 13 itens, todos em `ready/`, SHA-256 `338b3cbccd7c4b040b86f88b25b94e4028dbae563eed62966fe9a0666c8f9658`.
- A candidate gerada a partir do `canonical/` tinha exatamente o mesmo SHA-256 da playlist realmente em uso: `2807c6c604f4601f92b990c047c857519fcb3760c58827ad308be297bcf951d0`.
- Os 15 arquivos canonical passaram o contrato estrutural: H.264 1280x720, yuv420p, 30/1, video time base 1/90000, AAC 48 kHz stereo, audio time base 1/48000.
- Existem 3 pares de arquivos byte-a-byte duplicados no canonical, comprovados por SHA-256. Não remover antes de decisão editorial.
- O journal dos 60 minutos coletados mostrou 16 ocorrências `Non-monotonic DTS`, todas no output stream 0:1 (áudio), sem fatal/segfault/connection-refused no mesmo índice.
- MediaMTX reportou path `tvkids` ready/available/online com H264 1280x720 High + MPEG-4 Audio 48 kHz 2 canais.
- Os quatro FQDNs responderam HLS `/tvkids/index.m3u8` com HTTP 200.
- Root `/`: `www.tvkidsweb...` 200, `www.tvkids...` 200, `tvkidsweb...` 403, `tvkids...` 403.
- `/tvkids.html` respondeu 200 nos quatro FQDNs.
- `nginx -t` retornou sucesso.

## Correção de evidência

O teste acelerado `concat -> FLV -> /dev/null` do script P0 foi inválido porque o FFmpeg recusou sobrescrever `/dev/null` (`File '/dev/null' already exists`). Portanto os campos `concat_flv_rc=0` e `non_monotonic_dts=0` desse teste NÃO devem ser usados como evidência de integridade de timestamps. O script deverá ser corrigido com `-y` antes de ser reutilizado.

## Risco P0

Um restart/crash do processo poderia executar `ExecStartPre=/usr/local/sbin/tps-generate-playlist tvkids`. O gerador observado usa `MEDIA_ROOT="${BASE}/ready"`, o que regeneraria uma playlist diferente daquela que está sustentando a TVKIDS atualmente.

## Primeira mudança autorizada proposta

Tornar a playlist canonical atual regenerável para `tvkids` sem reiniciar o processo:

1. backup privado do gerador e das duas playlists;
2. confirmar byte-a-byte que o canonical gerado é igual à playlist on-air;
3. adicionar condição específica `tvkids -> canonical/` ao gerador, preservando `ready/` para os demais canais;
4. regenerar somente a playlist em disco da TVKIDS;
5. exigir novo SHA igual a `2807c6c6...951d0`;
6. confirmar que MainPID não mudou;
7. não reiniciar a TVKIDS ainda.

Implementação: `scripts/tv/tvkids-p1-install-restart-guard.sh`.
