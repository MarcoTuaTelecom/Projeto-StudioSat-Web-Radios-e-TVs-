# StudioSat Web — Health Baseline 2026-09-10T16:57:41Z

Status: **ANALISADO / VERIFICAÇÃO DE TRANSFERÊNCIA PENDENTE DO SIDECAR `.sha256`**  
Change: `CHG-004B`  
Host: `ns1`  
Git HEAD no snapshot: `58b429a359c8f9b8e342319cd2380de74b0bc733`  
Working tree no snapshot: **limpa**  
Health tool: `1.0-candidate.1`  
Archive recebido: `studiosat-health-baseline-ns1-20260910T165741Z.tar.gz`  
SHA-256 calculado sobre o archive recebido: `5d6e0cb9630329cc06444c4592e989cb7adfdf818a71182123724f74f316433a`

> O archive recebido foi aberto e lido integralmente e contém 109 entradas sem path traversal/symlink. O sidecar gerado no servidor não foi enviado junto; portanto a igualdade entre o hash calculado aqui e o hash registrado no host ainda precisa ser comprovada antes de converter o baseline para `locked`.

## 1. Core health

| Check | Estado | Detalhe |
|---|---|---|
| `tps-mediamtx.service` | active | PID `217466` |
| `nginx.service` | active | PID `1060` |
| `nginx -t` | PASS | syntax ok / test successful |
| Root filesystem | INFO | 17% usado |
| MemAvailable | INFO | 7,164,780 kB |
| load1 | INFO | 0.31 |
| MediaMTX API | PASS | loopback API respondeu |
| Portal Rádio `www` | 200 | endpoint comum respondeu |

Comparação com FULL RAY-X v3.1: MediaMTX manteve PID `217466` e NGINX manteve PID `1060`; não há evidência de restart desses componentes entre as duas fotografias.

## 2. Nove stations — baseline imediatamente antes da primeira mutação

| Station | Overall | systemd | PID | MediaMTX | Tracks | RTSP | HLS | Freshness | Portal | `Impossible to open` 30m | `NO_READY_MEDIA` 30m | DTS 30m | ready |
|---|---|---:|---:|---|---|---|---|---|---:|---:|---:|---:|---:|
| radioprincipal | **degraded** | active | 1135303 | true | MPEG-1/2 Audio | PASS | HTTP 500 / manifest FAIL | SKIP | 200 | **3** | 0 | 0 | 19 |
| radiopop | **degraded** | active | 1135350 | true | MPEG-1/2 Audio | PASS | HTTP 500 / manifest FAIL | SKIP | 200 | 0 | 0 | 0 | 11 |
| radiorock | **failed** | failed | 0 | false | — | FAIL | HTTP 404 / manifest FAIL | SKIP | 200 | 0 | 0 | 0 | **10** |
| radioclassicas | **degraded** | active | 1135491 | true | MPEG-1/2 Audio | PASS | HTTP 500 / manifest FAIL | SKIP | 200 | 0 | 0 | 0 | 12 |
| radiocountry | **degraded** | active | 1135456 | true | MPEG-1/2 Audio | PASS | HTTP 500 / manifest FAIL | SKIP | 200 | 0 | 0 | 0 | 19 |
| tvkids | **degraded** | active | 1031405 | true | H264 + MPEG-4 Audio | PASS | HTTP 200 / manifest PASS | CHANGING | 200 | 0 | 0 | **7** | 13 |
| tvteens | healthy | active | 841849 | true | H264 + MPEG-4 Audio | PASS | HTTP 200 / manifest PASS | CHANGING | 200 | 0 | 0 | 0 | 1 |
| tvviva | healthy | active | 841863 | true | H264 + MPEG-4 Audio | PASS | HTTP 200 / manifest PASS | CHANGING | 200 | 0 | 0 | 0 | 1 |
| tvmaisjovem | healthy | active | 841879 | true | H264 + MPEG-4 Audio | PASS | HTTP 200 / manifest PASS | CHANGING | 200 | 0 | 0 | 0 | 1 |

### Leitura operacional

- **Rádio Principal** continua confirmadamente degradada; os 3 erros `Impossible to open` em apenas 30 minutos tornam o incidente `INC-RADIO-001` atual e não histórico.
- **Rádio Rock** continua failed/not-ready, mas `ready/` contém 10 arquivos; isso sustenta o plano de recovery controlado em `CHG-R02` depois da Principal.
- **Pop, Clássicas e Country** continuam com playout/RTSP ativos, mas o HLS Rádio continua ausente/falhando com HTTP 500.
- **TVKIDS** continua on-air, HLS real/fresh, porém ainda registra `Non-monotonic DTS` (7 ocorrências em 30 min); permanece TV-owned e com interlock de restart.
- **TVTEENS, TVVIVA e TVMAISJOVEM** continuam on-air, RTSP/HLS/portal PASS no instante do snapshot. Os interlocks de restart derivados do FULL RAY-X continuam válidos porque esta change não os modifica.

## 3. Prova de ausência de restart das 9 stations

Os PIDs e timestamps de start do snapshot CHG-004B são idênticos aos observados no FULL RAY-X v3.1:

| Station | PID | Start timestamp UTC | Mudou desde FULL RAY-X? |
|---|---:|---|---|
| radioprincipal | 1135303 | 2026-09-09 16:25:08 | não |
| radiopop | 1135350 | 2026-09-09 16:25:10 | não |
| radiorock | 0 | — | não |
| radioclassicas | 1135491 | 2026-09-09 16:25:20 | não |
| radiocountry | 1135456 | 2026-09-09 16:25:19 | não |
| tvkids | 1031405 | 2026-09-09 12:59:08 | não |
| tvteens | 841849 | 2026-09-09 00:48:57 | não |
| tvviva | 841863 | 2026-09-09 00:48:57 | não |
| tvmaisjovem | 841879 | 2026-09-09 00:48:57 | não |

## 4. Hashes estáticos críticos — comparação contra FULL RAY-X

Todos os 9 artefatos estáticos capturados pela CHG-004B são **idênticos** ao FULL RAY-X v3.1:

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

Resultado: **0 drift estático conhecido** entre FULL RAY-X e CHG-004B.

## 5. Hashes crus das units e drop-ins — baseline capturado

```text
d57cd94cba7c8fc4975cba927c922ffaae2d32e460ccf3aa88558cb1acccec58  /etc/systemd/system/tps-radioprincipal-playout.service
102238932b4292834f864d3f0470e5ca3e603d18a29346e8d9ebf7316dcb5d48  /etc/systemd/system/tps-radioprincipal-playout.service.d/10-tps-production-safety.conf
2e15e711c624aed3e393abe294446574dc50fbab2eae5559304f90ebf70e83e3  /etc/systemd/system/tps-radioprincipal-playout.service.d/20-fixed-playlist.conf
0296237e790583c9b3d0a3eecfeda529f13d06eb44f428bba810c5d785704461  /etc/systemd/system/tps-radiopop-playout.service
102238932b4292834f864d3f0470e5ca3e603d18a29346e8d9ebf7316dcb5d48  /etc/systemd/system/tps-radiopop-playout.service.d/10-tps-production-safety.conf
8b860c8923e46f0ee098f8ed9c8fb9a84becb702ad3efaf44384b1594f123c67  /etc/systemd/system/tps-radiorock-playout.service
102238932b4292834f864d3f0470e5ca3e603d18a29346e8d9ebf7316dcb5d48  /etc/systemd/system/tps-radiorock-playout.service.d/10-tps-production-safety.conf
1e658df9b4244ce1fe34d53100e13596ca2d9075426db3bd8ddfc06f54cb8637  /etc/systemd/system/tps-radioclassicas-playout.service
102238932b4292834f864d3f0470e5ca3e603d18a29346e8d9ebf7316dcb5d48  /etc/systemd/system/tps-radioclassicas-playout.service.d/10-tps-production-safety.conf
db31a501da9b25a3ac4b5f46bafa2142353ef83db955900cd4759a145288bc26  /etc/systemd/system/tps-radiocountry-playout.service
102238932b4292834f864d3f0470e5ca3e603d18a29346e8d9ebf7316dcb5d48  /etc/systemd/system/tps-radiocountry-playout.service.d/10-tps-production-safety.conf
a2bc8776cc5399f711ee5c9fe7a04f213455ccc8851c1a0e55f7fce68622afee  /etc/systemd/system/tps-tvkids-playout.service
102238932b4292834f864d3f0470e5ca3e603d18a29346e8d9ebf7316dcb5d48  /etc/systemd/system/tps-tvkids-playout.service.d/10-tps-production-safety.conf
1f8b82b3cdf1fc5fbd711645c4c516136d8d87e8e9f903b017f5a07cf016dea5  /etc/systemd/system/tps-tvteens-playout.service
102238932b4292834f864d3f0470e5ca3e603d18a29346e8d9ebf7316dcb5d48  /etc/systemd/system/tps-tvteens-playout.service.d/10-tps-production-safety.conf
2d7a24823288dabbdd72f9a3ea3f9a4a8af745cc9ae483d69e538726a4b4080b  /etc/systemd/system/tps-tvviva-playout.service
102238932b4292834f864d3f0470e5ca3e603d18a29346e8d9ebf7316dcb5d48  /etc/systemd/system/tps-tvviva-playout.service.d/10-tps-production-safety.conf
5797e75cfd97bd6c4fbfafbafcc33d802fc315cfd38f66330f75c761a5b49cf0  /etc/systemd/system/tps-tvmaisjovem-playout.service
102238932b4292834f864d3f0470e5ca3e603d18a29346e8d9ebf7316dcb5d48  /etc/systemd/system/tps-tvmaisjovem-playout.service.d/10-tps-production-safety.conf
```

O drop-in `10-tps-production-safety.conf` é byte-idêntico nas nove stations. A Principal possui adicionalmente `20-fixed-playlist.conf`.

## 6. Hashes das playlists no snapshot

```text
radioprincipal  9bded92a31b437063adacb968c1b0985a4c8a82dd4e2783a1ef3335896e49cfe
radiopop        6e8e3991833c6ff5e15c0695bdde33a0dfd4e4854faf342e0344b2c794d1a23d
radiorock       fa2deaa33806adf912eb3fc33346253c766d021f37c4322cf6ddfe7e4bf45f85
radioclassicas  cf679f2518649137fe33a152ff1b615b36d389ebf1f8bdf3433bd18346c22f7f
radiocountry    5a061c3f67080437c51b61c5ebf89916cd6b8eb780e59a59b7ef40dcda53faf4
tvkids          338b3cbccd7c4b040b86f88b25b94e4028dbae563eed62966fe9a0666c8f9658
tvteens         f12c57941606002504c233dd1fc2358f8251235bec81da2b6d8c93db5de6dccc
tvviva          525b9a3da1c35dba727613ad4880e2e70f2daa2fcfda379d485e9de64b360f90
tvmaisjovem     7bfc6117cc3b74652aea17c5c2dbadf716542de489326deb4dbd43658da7f266
```

Esses hashes coincidem com o registry provisório já derivado da análise do FULL RAY-X; não há drift de playlist detectado no intervalo observado.

## 7. Diferenças relevantes FULL RAY-X → health baseline

- Git HEAD passou de `d37ec74...` para `58b429a...` apenas por documentação/candidate no repositório; o snapshot confirma working tree limpa.
- PIDs e start timestamps das nove stations não mudaram.
- PIDs de MediaMTX e NGINX não mudaram.
- Os nove hashes estáticos críticos não mudaram.
- Contagens `ready/` permanecem coerentes com a fotografia profunda: Principal 19, Pop 11, Rock 10, Clássicas 12, Country 19, TVKIDS 13 e uma em cada uma das outras três TVs.
- Rádio HLS continua falhando de forma consistente; não é regressão introduzida entre snapshots.
- Rádio Principal continua apresentando erro funcional recorrente.
- TVKIDS continua apresentando DTS recorrente.

## 8. Gate CHG-004B

Concluído:

- health das 9 stations recebido e analisado;
- Core health recebido;
- raw hashes de unit/drop-in capturados;
- hashes estáticos confrontados com FULL RAY-X: **9/9 iguais**;
- diferenças entre snapshots explicadas;
- ausência de restart entre snapshots comprovada por PID/start timestamp.

Pendente antes de `LOCKED / DONE`:

1. confirmar o sidecar SHA-256 gerado no host para o archive recebido;
2. registrar o SHA-256 raw do `studiosat-health-baseline-v1.sh` executado no host (o archive registra versão + Git HEAD + clean working tree, mas não captura a saída do `sha256sum` feito no PRECHECK);
3. converter `registry/critical-artifacts-baseline.yaml` para `locked`;
4. atualizar `channels-registry.yaml` para este snapshot;
5. fechar Stage Report e Change Queue;
6. reler `main`.

**Nenhuma mudança mutável está autorizada enquanto os dois valores de prova do item 1–2 acima não forem recebidos.**
