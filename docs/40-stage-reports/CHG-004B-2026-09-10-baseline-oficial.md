# CHG-004B — Baseline Oficial Operacional v1

Status: **DONE / PASS / LOCKED**  
Data: 2026-09-10  
Owner: Core + Engenharia Rádio  
Safety: **READ-ONLY**

## Objetivo

Transformar o FULL RAY-X v3.1 em baseline oficial bloqueado e gerar um snapshot de health imediatamente anterior à primeira mudança mutável.

## Evidência profunda de entrada

- FULL RAY-X v3.1 executado em `2026-09-10T15:35:03Z`;
- Git HEAD da coleta: `d37ec74de015208df18e76a8a1a070d3ecdfa645`;
- working tree limpa;
- FULL RAY-X archive SHA-256: `338c3f808aff8d70c5843daf88bfd7169fbb289704cabe937b60425511f26a6f`;
- manifest interno: `1035/1035` sem divergência.

## Health baseline executado

```text
candidate: candidates/CHG-004B/studiosat-health-baseline-v1.sh
version: 1.0-candidate.1
snapshot UTC: 2026-09-10T16:57:41Z
snapshot Git HEAD: 58b429a359c8f9b8e342319cd2380de74b0bc733
snapshot worktree: clean
archive: studiosat-health-baseline-ns1-20260910T165741Z.tar.gz
archive SHA-256: 5d6e0cb9630329cc06444c4592e989cb7adfdf818a71182123724f74f316433a
server sidecar verification: OK
health tool raw SHA-256: d209a4d0c0d06ad3cdd1dd70bf2496574f85ebdfb6ffc739e3dad4c86f0d05ee
```

A cópia recebida e o sidecar gerado no host possuem o mesmo SHA-256. O archive foi aberto e analisado, com 109 entradas e sem path traversal ou links internos inesperados.

## Core no baseline

```text
tps-mediamtx.service  active  PID 217466
nginx.service         active  PID 1060
nginx -t              PASS
root disk use         17%
MemAvailable          7,164,780 kB
load1                 0.31
MediaMTX API           PASS
www.radio portal       HTTP 200
```

## Nove stations no baseline

| Station | Overall | systemd | PID | MediaMTX | RTSP | HLS | Portal | Evidência relevante |
|---|---|---:|---:|---|---|---|---:|---|
| radioprincipal | degraded | active | 1135303 | ready | PASS | 500 / FAIL | 200 | `Impossible to open` recorrente |
| radiopop | degraded | active | 1135350 | ready | PASS | 500 / FAIL | 200 | sem erro equivalente |
| radiorock | failed | failed | 0 | not ready | FAIL | 404 / FAIL | 200 | 10 assets ready já existentes |
| radioclassicas | degraded | active | 1135491 | ready | PASS | 500 / FAIL | 200 | sem erro equivalente |
| radiocountry | degraded | active | 1135456 | ready | PASS | 500 / FAIL | 200 | referência Rádio funcional |
| tvkids | degraded | active | 1031405 | ready | PASS | 200 / CHANGING | 200 | DTS recorrente |
| tvteens | healthy | active | 841849 | ready | PASS | 200 / CHANGING | 200 | interlock de restart permanece |
| tvviva | healthy | active | 841863 | ready | PASS | 200 / CHANGING | 200 | interlock de restart permanece |
| tvmaisjovem | healthy | active | 841879 | ready | PASS | 200 / CHANGING | 200 | interlock de restart permanece |

Os PIDs e timestamps de start eram idênticos aos observados no FULL RAY-X, provando ausência de restart no intervalo entre as duas fotografias.

## Hash lock

Os artefatos estáticos críticos, units e drop-ins foram capturados e estão registrados em:

```text
registry/critical-artifacts-baseline.yaml
```

O registry está com:

```text
status: locked
health_archive_server_sidecar_verified: true
```

Os nove hashes estáticos críticos confrontados com o FULL RAY-X eram 9/9 idênticos. Os hashes das playlists também coincidiam no snapshot.

## Critérios do Item 1

```text
FULL RAY-X AS-IS                 PASS
KEEP/FIX/REFACTOR/REPLACE/REMOVE PASS
CPU/RAM/disco/processos/serviços PASS
9 emissoras registradas          PASS
dependências compartilhadas      PASS
hashes estáticos                  PASS
units/drop-ins raw hashes         PASS
incident owner                    PASS
restart register                  PASS
health imediatamente pré-change   PASS
archive sidecar                   PASS
baseline lock                     PASS
```

## Fechamento

CHG-004B está encerrada como `DONE / PASS / LOCKED`. O snapshot é a referência PRE para CHG-R01. Qualquer hash estático fora do escopo de uma Change precisa ser explicado antes de prosseguir.

Depois do fechamento, ocorreu um restart manual antecipado somente da Rádio Principal. Esse evento pertence à CHG-R01 e está documentado no Stage Report específico; não invalida a fotografia CHG-004B, que continua sendo o PRE oficial anterior à primeira mutação de serviço.
