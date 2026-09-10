# CHG-004B — Baseline Oficial Operacional v1

Status: **VERIFYING — SNAPSHOT RECEBIDO E ANALISADO; LOCK PENDENTE DE DUAS PROVAS READ-ONLY**  
Data: 2026-09-10  
Owner: Core + Engenharia Rádio  
Safety: **READ-ONLY**

## Objetivo

Fechar o Item 1 do plano: transformar o FULL RAY-X v3.1 em baseline oficial bloqueado e gerar um snapshot de health imediatamente anterior à primeira mudança mutável.

## Baseline profundo de entrada

- FULL RAY-X v3.1 executado em `2026-09-10T15:35:03Z`;
- Git HEAD da coleta: `d37ec74de015208df18e76a8a1a070d3ecdfa645`;
- working tree da coleta: limpa;
- archive SHA-256 FULL RAY-X: `338c3f808aff8d70c5843daf88bfd7169fbb289704cabe937b60425511f26a6f`;
- manifest interno FULL RAY-X: `1035/1035` sem divergência;
- análise AS-IS: `docs/90-evidencias/BASELINE_OFICIAL_AS_IS_2026-09-10_v1.0.md`;
- disposition: `docs/00-core/COMPONENT_DISPOSITION_v1.0.md`;
- dependency map: `docs/00-core/DEPENDENCY_MAP_AS_IS_v1.0.md`;
- incidents: `docs/30-execucao/INCIDENT_REGISTER.md`;
- hashes: `registry/critical-artifacts-baseline.yaml`;
- restart tracking: `docs/30-execucao/RESTART_REGISTER.md`.

## Candidate executada

```text
candidates/CHG-004B/studiosat-health-baseline-v1.sh
```

Versão registrada dentro do pacote:

```text
1.0-candidate.1
```

Git HEAD registrado dentro do pacote:

```text
58b429a359c8f9b8e342319cd2380de74b0bc733
```

Working tree registrada dentro do pacote: **limpa**.

A candidate `.1` incorpora as correções pré-execução para múltiplos drop-ins, manifest real `#EXTM3U`, freshness de media playlist e ausência possível de `ready/`.

## Pacote recebido

```text
studiosat-health-baseline-ns1-20260910T165741Z.tar.gz
```

Identidade interna:

```text
STUDIOSAT_HEALTH_BASELINE_VERSION=1.0-candidate.1
HOST=ns1
UTC=20260910T165741Z
READ_ONLY=YES
```

SHA-256 calculado sobre a cópia recebida:

```text
5d6e0cb9630329cc06444c4592e989cb7adfdf818a71182123724f74f316433a
```

O archive foi aberto e lido integralmente. Foram observadas 109 entradas, sem path traversal e sem links simbólicos/hardlinks dentro do pacote. **O sidecar `.sha256` gerado no host não foi enviado nesta entrega**, portanto a equivalência entre o hash da cópia recebida e o hash registrado no servidor ainda precisa ser comprovada antes do `LOCKED`.

Relatório sanitizado detalhado: `docs/90-evidencias/HEALTH_BASELINE_2026-09-10T165741Z.md`.

## Core — resultado

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

Comparação com FULL RAY-X: os PIDs de MediaMTX e NGINX são os mesmos. Não há evidência de restart desses componentes entre as fotografias.

## Nove stations — resultado

| Station | Overall | systemd | PID | MediaMTX | RTSP | HLS | Portal | Erro relevante 30m | ready |
|---|---|---:|---:|---|---|---|---:|---|---:|
| radioprincipal | **degraded** | active | 1135303 | ready | PASS | 500 / manifest FAIL | 200 | `Impossible to open` = **3** | 19 |
| radiopop | **degraded** | active | 1135350 | ready | PASS | 500 / manifest FAIL | 200 | 0 | 11 |
| radiorock | **failed** | failed | 0 | not ready | FAIL | 404 / manifest FAIL | 200 | 0 recente | **10** |
| radioclassicas | **degraded** | active | 1135491 | ready | PASS | 500 / manifest FAIL | 200 | 0 | 12 |
| radiocountry | **degraded** | active | 1135456 | ready | PASS | 500 / manifest FAIL | 200 | 0 | 19 |
| tvkids | **degraded** | active | 1031405 | ready | PASS | 200 / PASS / CHANGING | 200 | DTS = **7** | 13 |
| tvteens | healthy | active | 841849 | ready | PASS | 200 / PASS / CHANGING | 200 | 0 | 1 |
| tvviva | healthy | active | 841863 | ready | PASS | 200 / PASS / CHANGING | 200 | 0 | 1 |
| tvmaisjovem | healthy | active | 841879 | ready | PASS | 200 / PASS / CHANGING | 200 | 0 | 1 |

Os PIDs e timestamps de start das nove stations são idênticos aos do FULL RAY-X v3.1. Não ocorreu restart de station entre as duas fotografias.

## Hashes estáticos

Os 9 artefatos estáticos críticos confrontados são **9/9 idênticos** ao FULL RAY-X:

```text
4b2277f91d8c5b469e41d70fab4a93f11c5d32ce4e4d99a634378fb80d5a6d5f  /usr/local/sbin/tps-generate-playlist
d7140c872191f6b9efabeb8ef6bd813eba898f9978822e7f5ab15c7e819a5f18  /usr/local/sbin/tps-generate-playlist-radioprincipal-fixed
5920f385cc47aed6466b58ad48b26c7f9d4b2da2ba9aa17690ab1289691607e3  /usr/local/sbin/tps-playout-radio
8a3739d78fefa8c98fec051f3ec8214c4853277b8b15a2c4f497a13ddeed86d9  /usr/local/sbin/tps-playout-tv
31540e918832c7b9d2ffd8e36c34f44cfe04dfe297f57dd188b8647b5079c264  /etc/tpsmedia/mediamtx/mediamtx.yml
25d849a8188327bfde73b2aecc4143a8acaf81361b8baf73d0ec3a983ffe0975  /etc/nginx/nginx.conf
d5918e3e912eb5f43f6d00be239f7907b145173fd56492dc8a15149cd55d2f24  /etc/nginx/conf.d/tps-9-emissoras.conf
3e875a7e8dd3176a13bccc6a239f16c15951e6060ec10cd12697fda9f63c1d69  /etc/nginx/conf.d/tps-studiosatweb.conf
4e22fdc0659234c93db9f0354a6c5d11ba76373cf918e2304ab25b6e9f7a0317  /etc/nginx/conf.d/tps-tpsolutions-https.conf
```

Resultado: **0 drift estático conhecido**.

## Units e drop-ins — hashes crus agora capturados

O snapshot capturou SHA-256 diretamente dos arquivos reais de unit/drop-in. Foram registrados em `registry/critical-artifacts-baseline.yaml`.

Resumo:

- 9 unit fragments capturados;
- `10-tps-production-safety.conf` presente nas nove stations e byte-idêntico, SHA-256 `102238932b4292834f864d3f0470e5ca3e603d18a29346e8d9ebf7316dcb5d48`;
- Rádio Principal possui ainda `20-fixed-playlist.conf`, SHA-256 `2e15e711c624aed3e393abe294446574dc50fbab2eae5559304f90ebf70e83e3`.

## Playlists

Os hashes das nove playlists no snapshot coincidem com o registry provisório produzido após o FULL RAY-X. Não foi detectado drift de playlist no intervalo observado.

## Diferenças FULL RAY-X → CHG-004B

1. Git HEAD mudou apenas porque documentação e a candidate do baseline foram publicadas no repositório.
2. Working tree permaneceu limpa.
3. Nenhum PID/start timestamp das 9 stations mudou.
4. MediaMTX e NGINX mantiveram os mesmos PIDs.
5. Os 9 hashes estáticos críticos permaneceram iguais.
6. As contagens `ready/` permanecem coerentes com o FULL RAY-X.
7. HLS Rádio continua falhando; não é regressão desta change.
8. Principal continua com erro funcional recorrente.
9. TVKIDS continua com DTS recorrente.

## Gate de conclusão

Concluído:

- [x] health das 9 stations recebido e analisado;
- [x] Core health recebido;
- [x] raw unit/drop-in hashes capturados;
- [x] hashes estáticos confrontados com FULL RAY-X — 9/9 iguais;
- [x] diferenças entre snapshots explicadas;
- [x] relatório sanitizado publicado;
- [x] `critical-artifacts-baseline.yaml` atualizado com hashes crus.

Pendente antes de `PASS / DONE / LOCKED`:

- [ ] sidecar `.sha256` do archive gerado no host e `sha256sum -c` comprovados;
- [ ] SHA-256 raw do `studiosat-health-baseline-v1.sh` realmente executado informado pelo host;
- [ ] `critical-artifacts-baseline.yaml` convertido de `verification-pending-server-sidecar` para `locked`;
- [ ] `channels-registry.yaml` revalidado para o snapshot atual;
- [ ] `CHANGE_QUEUE.md` convertido para CHG-004B DONE e CHG-R01 READY;
- [ ] `main` relido após o fechamento.

## Única próxima ação autorizada

Read-only:

```bash
cd /root/Projeto-StudioSat-Web-Radios-e-TVs-

SHA_FILE=/tmp/studiosat-health-baseline-ns1-20260910T165741Z.tar.gz.sha256

echo '===== SERVER SIDECAR ====='
cat "$SHA_FILE"

echo '===== VERIFY SERVER SIDECAR ====='
sha256sum -c "$SHA_FILE"

echo '===== HEALTH TOOL RAW SHA256 ====='
sha256sum candidates/CHG-004B/studiosat-health-baseline-v1.sh

echo '===== GIT ====='
git status --short
git rev-parse HEAD
```

Nenhuma mutação é autorizada até este Stage Report ser fechado como `DONE / PASS / LOCKED`.
