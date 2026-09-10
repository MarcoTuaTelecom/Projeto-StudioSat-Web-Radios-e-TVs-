# StudioSat Web — Change Queue

Regra: **uma alteração ativa por vez no host de produção**. Engenharia de TV e Rádio podem preparar documentação/candidates em paralelo, mas apenas uma change pode modificar o host por vez.

Protocolo obrigatório: `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`.

Diretriz vigente: **IN-PLACE FIRST / NO CONTAINERS / NO VMs / NO DUPLICATE PLATFORM**.

## Baseline oficial

CHG-004B está **DONE / PASS / LOCKED** com snapshot `2026-09-10T16:57:41Z`.

## Prioridade operacional vigente

Por determinação do owner em `2026-09-10`, a estabilização/reconstrução da **TVKIDS** é a única mudança mutável prioritária até o fechamento de `CHG-TVKIDS-001` ou rollback formal. `CHG-R01B` permanece preservada e volta à fila após a TVKIDS.

## Trilha crítica atual

| ID | Mudança | Dono | Estado | Gate |
|---|---|---|---|---|
| CHG-R01 | Principal — escaping/playlist atômica | Rádio | **APPLY PASS / ROTATION FINAL PENDING** | generator e playlist corrigidos; PID 1383293; MediaMTX/RTSP PASS; 0 Impossible/NO_READY pós-fix |
| CHG-R01B | Principal — AAC 48 kHz estéreo + HLS real + limpeza de timestamps/FLV shutdown | Rádio | **PAUSED / PRESERVADA — aguarda CHG-TVKIDS-001** | candidate já preparado; retomar somente após checkpoint TVKIDS |
| CHG-TVKIDS-001 | Reconstrução integral da cadeia de produção TVKIDS | TV | **ACTIVE / PACKAGE READY** | certificar 15/15 → corrigir timestamps se necessário → manifest/plan dedicado → cutover só TVKIDS → MediaMTX/RTSP/HLS → quatro FQDNs → 0 DTS → health PASS |
| CHG-R02 | Rock — recovery legado | Rádio + Core | **BLOCKED por R01/R01B** | 10 assets → playlist → start somente Rock → MediaMTX/RTSP PASS |
| CHG-R03 | HLS das demais rádios | Rádio + Core | **BLOCKED por R01B/R02** | replicar profile comprovado sem quebra por station |
| CHG-R04 | Separação generator Rádio/TV | Rádio + TV + Core | **PARCIALMENTE ENDEREÇADA POR CHG-TVKIDS-001** | TVKIDS ganha builder dedicado; restante da separação continua como change própria |
| CHG-TV-002+ | TVTEENS/TVVIVA/TVMAISJOVEM | Engenharia TV | **BLOCKED por TVKIDS** | replicar somente após TVKIDS comprovada |

## CHG-R01 — resultado já comprovado

Apply em `2026-09-10T18:15:42Z`:

```text
candidate/production playlist: 18/18
MISSING_OR_TRUNCATED_LINES=0
FFPROBE_FAILURES=0
FULL_CONCAT_TRAVERSAL=PASS
Principal PRE PID=1363987
Principal POST PID=1383293
ActiveState=active
SubState=running
MediaMTX ready=true
RTSP mp3 48000 stereo
impossible_to_open_post=0
no_ready_media_post=0
other_process_pids_unchanged=PASS
other_playlists_unchanged=PASS
```

Generator atual Principal:

```text
d2ba61daeeaaa89389fe1cc2ed277af68ac12c09b769c2eb9dda1feea9316fcd
```

Playlist atual Principal:

```text
154c3cb081f9a7d7f527ab184739b692c5a930db3fe8ff0659f241e9699b821c
```

O observer de rotação iniciado em foreground foi interrompido junto com a sessão SSH e deixou apenas `1/18`; isso é falha do método de observação, não evidência de falha do playout. Nova observação deverá ser destacada da sessão (`nohup`/transient unit) após o último restart da Principal.

## CHG-R01B — estado preservado

A Principal ainda precisa do profile AAC/HLS preparado em `CHG-R01B`. Os candidates permanecem no repositório e não são descartados. A mudança está temporariamente pausada para cumprir a prioridade explícita de reconstrução da TVKIDS e a regra de uma alteração mutável por vez.

Candidates preservados:

```text
candidates/CHG-R01B/tps-playout-radio-v2-principal-aac.sh
candidates/CHG-R01B/apply-radioprincipal-aac-hls-v1.sh
```

## CHG-TVKIDS-001 — pacote de reconstrução

Fonte única no GitHub:

```text
scripts/tv/tvkids-rebuild-production-v1.sh
scripts/tv/tvkids-rebuild-lib-v1.sh
scripts/tv/tvkids-rebuild-media-v1.sh
scripts/tv/tvkids-rebuild-cutover-v1.sh
scripts/tv/tvkids-rebuild-public-v1.sh
scripts/tv/tvkids-build-plan-v1.sh
scripts/tv/tvkids-normalize-asset-v1.sh
scripts/tv/tvkids-health-v1.sh
scripts/tv/tvkids-nginx-patch-v1.py
config/tv/tvkids/TV-C720P30-v1.yaml
```

O executor preserva a station `tvkids`, o root `/srv/tpsmedia/repository/channels/tvkids`, MediaMTX e NGINX como infraestrutura compartilhada. Reconstrói a cadeia TV específica com profile formal, certificação integral, normalização offline apenas quando necessária, plan/manifest dedicado, cutover apenas da unit TVKIDS, verificação de RTSP/HLS e correção dos aliases públicos sem criar segunda plataforma permanente.

## Próxima ação autorizada

Executar exclusivamente:

```text
scripts/tv/tvkids-rebuild-production-v1.sh
```

O executor possui backup privado, gates antes da mutação, espera por mutações concorrentes detectadas, validação 15/15, rollback transacional e health final do produto. Somente após `CHG_TVKIDS_001_RESULT=PASS` e `TVKIDS_PRODUCT=HEALTHY` esta change pode ser documentada como concluída e `CHG-R01B` pode voltar a `READY`.
