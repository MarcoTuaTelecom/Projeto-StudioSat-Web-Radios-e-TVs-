# StudioSat Web — Baseline Oficial AS-IS v1.0

Status: **OFICIAL / AS-IS — PENDENTE apenas do snapshot health imediato CHG-004B antes da primeira mutação**  
Data da evidência: 2026-09-10 15:35:03 UTC  
Host: `ns1.tpsolutions.com.br`  
Fonte: FULL RAY-X v3.1  
Git HEAD observado durante a coleta: `d37ec74de015208df18e76a8a1a070d3ecdfa645`  
Working tree durante a coleta: limpa  
Archive SHA-256: `338c3f808aff8d70c5843daf88bfd7169fbb289704cabe937b60425511f26a6f`  
Manifest interno: **1035/1035 arquivos verificados sem divergência**

> Este documento é a fotografia oficial anterior às mudanças corretivas. O pacote bruto permanece privado; somente fatos sanitizados são publicados neste repositório público.

## 1. Freeze operacional

Até o fechamento da CHG-004B e abertura explícita da primeira change mutável:

- nenhuma alteração improvisada no host;
- nenhum restart de station, MediaMTX, NGINX ou host;
- nenhuma instalação/upgrade de engine/runtime;
- nenhuma edição direta de generator, playlist, unit, MediaMTX, NGINX, Samba ou firewall;
- nenhuma criação de segunda plataforma/árvore permanente;
- nenhuma mudança TV pela frente Rádio;
- qualquer alteração externa publicada no GitHub deve ser relida antes da próxima ação.

Política estrutural vigente: **IN-PLACE FIRST / NO CONTAINERS / NO VMs / NO DUPLICATE PLATFORM**.

## 2. Host e capacidade observados

| Item | Estado observado |
|---|---|
| Plataforma | Google Compute Engine / KVM |
| OS | Ubuntu 24.04.4 LTS (Noble) |
| Kernel | Linux 6.17.0-1022-gcp |
| CPU | 2 CPUs lógicas, AMD EPYC 7B13 |
| RAM | 7.8 GiB total |
| RAM usada | ~947 MiB |
| RAM disponível | ~6.8 GiB / 7,156,312 kB |
| Swap | 0 |
| Root filesystem | ext4, 96 GiB |
| Root usado | 16 GiB / 17% |
| Root disponível | ~80 GiB |
| Load average | 0.13 / 0.16 / 0.20 |
| CPU idle nas amostras | ~85–91% |
| I/O wait nas amostras | ~0% |
| Pacotes dpkg | 1,137 |
| Listeners observados | 51 |
| Hostnames descobertos localmente | 27 |
| Services loaded | 199 linhas reportadas pelo systemctl; 174 unidades com LOAD=loaded |
| Services active/running | 38 por recontagem do `all-services.txt` |
| Services failed | 1 |

Nota: o arquivo-resumo automático do FULL RAY-X informou 37 running, mas a recontagem do inventário completo encontrou 38. Esse defeito do coletor foi registrado para correção; a fonte detalhada prevalece.

## 3. Nove emissoras — estado AS-IS

| Station | Domínio | systemd | PID | Media files | Bytes de mídia | ready | canonical | Playlist | MediaMTX | Tracks | Classificação operacional |
|---|---|---:|---:|---:|---:|---:|---:|---|---|---|---|
| radioprincipal | Rádio | active | 1135303 | 20 | 169,200,624 | 19 | 1 | existe | ready | MPEG-1/2 Audio | **DEGRADED / P0** — generator especial quebra nome com apóstrofo e trunca a programação |
| radiopop | Rádio | active | 1135350 | 12 | 91,423,721 | 11 | 1 | existe | ready | MPEG-1/2 Audio | **LEGACY HEALTHY**, porém HLS Rádio não fecha |
| radiorock | Rádio | failed | 0 | 11 | 98,401,275 | 10 | 1 | existe | not ready | — | **FAILED / P0**, mas `ready/` agora contém conteúdo elegível |
| radioclassicas | Rádio | active | 1135491 | 13 | 135,585,184 | 12 | 1 | existe | ready | MPEG-1/2 Audio | **LEGACY HEALTHY**, porém HLS Rádio não fecha |
| radiocountry | Rádio | active | 1135456 | 20 | 192,652,614 | 19 | 1 | existe | ready | MPEG-1/2 Audio | **LEGACY HEALTHY / station de referência**, porém HLS Rádio não fecha |
| tvkids | TV | active | 1031405 | 28 | 1,371,645,188 | 13 | 15 | existe | ready | H264 + MPEG-4 Audio | **DEGRADED / TV-OWNED** — DTS e restart interlock |
| tvteens | TV | active | 841849 | 2 | 4,005,812 | 1 | 1 | existe | ready | H264 + MPEG-4 Audio | **ON-AIR / TV-OWNED / restart interlock** |
| tvviva | TV | active | 841863 | 2 | 4,005,812 | 1 | 1 | existe | ready | H264 + MPEG-4 Audio | **ON-AIR / TV-OWNED / restart interlock** |
| tvmaisjovem | TV | active | 841879 | 2 | 4,005,812 | 1 | 1 | existe | ready | H264 + MPEG-4 Audio | **ON-AIR / TV-OWNED / restart interlock** |

## 4. Dependência comum real

```text
/srv/tpsmedia/repository/channels/<station>
        │
        ├── playlist generator
        │      ├── global: /usr/local/sbin/tps-generate-playlist
        │      └── Principal: /usr/local/sbin/tps-generate-playlist-radioprincipal-fixed
        │
        ├── playlist.txt
        │
        ├── tps-playout-radio OU tps-playout-tv
        │
        ├── FFmpeg 6.1.1 / -c copy
        │
        ├── RTMP localhost:1935/<station>
        │
        ├── MediaMTX v1.20.1
        │
        ├── RTSP/HLS/WebRTC/SRT conforme compatibilidade
        │
        └── NGINX/TLS → portais/domínios
```

### Shared Core que nenhuma vertical pode substituir unilateralmente

- MediaMTX e seu arquivo global;
- NGINX, listeners 80/443 e política TLS;
- station IDs e production paths;
- `/srv/tpsmedia/repository/channels/<station>` como base atual;
- Change Queue;
- registry;
- health envelope;
- política de ports/ingress/auth/ACL;
- regras compartilhadas de systemd/observabilidade/backup.

### Dependência problemática identificada

O `tps-generate-playlist` global está sendo compartilhado por Rádio e TV apesar de os dois domínios terem semânticas diferentes de `ready/canonical`, formatos e requisitos. Ele deverá ser **REFACTOR**, não simplesmente editado para satisfazer uma vertical.

## 5. Ferramentas principais presentes

| Ferramenta | Versão/estado |
|---|---|
| FFmpeg / ffprobe | 6.1.1-3ubuntu5 |
| NGINX | 1.24.0 pelo pacote observado |
| MediaMTX | v1.20.1 na árvore `/opt/tpsmedia/mediamtx/current` |
| Certbot | 2.9.0 |
| curl | 8.5.0 |
| jq | 1.7 |
| Git | 2.43.0 |
| rsync | 3.2.7 |
| Samba | 4.19.5-Ubuntu |
| Python | 3.12.3 |
| PHP | 8.3.6 |
| Redis | 7.0.15 instalado, não selecionado como dependência do playout |
| PostgreSQL client | 16.15 |
| Docker | ausente — manter ausente |
| Podman | ausente — manter ausente |
| Liquidsoap | ausente — nenhuma instalação autorizada |
| ffplayout | ausente — nenhuma instalação autorizada |
| Icecast | ausente — nenhuma instalação autorizada |

## 6. Hashes estáticos críticos já provados pelo FULL RAY-X

| Artefato | SHA-256 AS-IS | Dono |
|---|---|---|
| `/usr/local/sbin/tps-generate-playlist` | `4b2277f91d8c5b469e41d70fab4a93f11c5d32ce4e4d99a634378fb80d5a6d5f` | compartilhado/Core até separação |
| `/usr/local/sbin/tps-generate-playlist-radioprincipal-fixed` | `d7140c872191f6b9efabeb8ef6bd813eba898f9978822e7f5ab15c7e819a5f18` | Rádio |
| `/usr/local/sbin/tps-playout-radio` | `5920f385cc47aed6466b58ad48b26c7f9d4b2da2ba9aa17690ab1289691607e3` | Rádio |
| `/usr/local/sbin/tps-playout-tv` | `8a3739d78fefa8c98fec051f3ec8214c4853277b8b15a2c4f497a13ddeed86d9` | TV |
| `/etc/tpsmedia/mediamtx/mediamtx.yml` | `31540e918832c7b9d2ffd8e36c34f44cfe04dfe297f57dd188b8647b5079c264` | Core |
| `/etc/nginx/nginx.conf` | `25d849a8188327bfde73b2aecc4143a8acaf81361b8baf73d0ec3a983ffe0975` | Core |
| `/etc/nginx/conf.d/tps-9-emissoras.conf` | `d5918e3e912eb5f43f6d00be239f7907b145173fd56492dc8a15149cd55d2f24` | Core |
| `/etc/nginx/conf.d/tps-studiosatweb.conf` | `3e875a7e8dd3176a13bccc6a239f16c15951e6060ec10cd12697fda9f63c1d69` | Core |
| `/etc/nginx/conf.d/tps-tpsolutions-https.conf` | `4e22fdc0659234c93db9f0354a6c5d11ba76373cf918e2304ab25b6e9f7a0317` | Core |

Os hashes exatos dos nove unit fragments e drop-ins serão capturados diretamente dos arquivos crus do host pela CHG-004B antes da primeira mutação. Não são inferidos de `systemctl cat`.

## 7. Playlists — hashes dinâmicos AS-IS

Esses hashes registram a fotografia; playlists são artefatos dinâmicos e podem mudar somente em change autorizada.

| Station | SHA-256 playlist AS-IS |
|---|---|
| radioprincipal | `9bded92a31b437063adacb968c1b0985a4c8a82dd4e2783a1ef3335896e49cfe` |
| radiopop | `6e8e3991833c6ff5e15c0695bdde33a0dfd4e4854faf342e0344b2c794d1a23d` |
| radiorock | `fa2deaa33806adf912eb3fc33346253c766d021f37c4322cf6ddfe7e4bf45f85` |
| radioclassicas | `cf679f2518649137fe33a152ff1b615b36d389ebf1f8bdf3433bd18346c22f7f` |
| radiocountry | `5a061c3f67080437c51b61c5ebf89916cd6b8eb780e59a59b7ef40dcda53faf4` |
| tvkids | `338b3cbccd7c4b040b86f88b25b94e4028dbae563eed62966fe9a0666c8f9658` |
| tvteens | `f12c57941606002504c233dd1fc2358f8251235bec81da2b6d8c93db5de6dccc` |
| tvviva | `525b9a3da1c35dba727613ad4880e2e70f2daa2fcfda379d485e9de64b360f90` |
| tvmaisjovem | `7bfc6117cc3b74652aea17c5c2dbadf716542de489326deb4dbd43658da7f266` |

## 8. Estado de saúde que deve ser repetido antes/depois de cada change

O health mínimo não pode se limitar a `systemctl active`.

Por station deve registrar:

```text
systemd state/PID/start timestamp
MediaMTX ready + tracks
RTSP bounded media probe
HLS HTTP + validação real #EXTM3U + freshness
portal HTTP
journal recente
Impossible to open
NO_READY_MEDIA
Non-monotonic DTS
ready file count
playlist SHA-256
```

Core deve registrar:

```text
tps-mediamtx.service
nginx.service
nginx -t
MediaMTX API
disk use
MemAvailable
load1
critical static hashes
unit/drop-in hashes
```

O candidate oficial para esse snapshot é `candidates/CHG-004B/studiosat-health-baseline-v1.sh`.

## 9. Regra de comparação de change

Toda change mutável terá dois snapshots:

```text
PRE-CHANGE HEALTH
        │
        ▼
UMA ÚNICA MUDANÇA
        │
        ▼
POST-CHANGE HEALTH
        │
        ▼
DIFF
```

PASS somente se:

- o objetivo específico da change passou;
- nenhum componente fora do escopo regrediu;
- hashes de arquivos estáticos fora do escopo permaneceram iguais;
- mudanças de hash no escopo são explicadas/documentadas;
- qualquer restart ocorrido tem PID/timestamp antes/depois e resultado explícito;
- Stage Report e script final foram publicados antes da próxima change.

## 10. Critério para fechar este baseline

O baseline oficial v1.0 estará **LOCKED** quando CHG-004B gerar um pacote atual imediatamente anterior à primeira mutação e forem registrados:

- health das 9 stations;
- health Core;
- hashes crus dos 9 unit fragments/drop-ins;
- hashes estáticos críticos atuais;
- hashes das playlists atuais;
- HEAD do GitHub e working tree limpo.

Até esse momento, este documento é a fotografia AS-IS oficial derivada do FULL RAY-X e nenhuma mutação está autorizada.