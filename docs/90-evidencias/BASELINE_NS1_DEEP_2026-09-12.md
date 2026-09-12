# BASELINE Factual NS1 — Raio-X Profundo 2026-09-12

**Evidence ID:** OBS-NS1-RAYX-20260912  
**Coleta:** 2026-09-12T16:27:08Z → 2026-09-12T16:33:29Z  
**Host:** `ns1`  
**Pacote analisado:** `ns1-rayx-deep-ns1-20260912T162708Z.shareable.tar.gz`  
**SHA-256 do pacote recebido:** `de81bec277657eef3073ca3adf727b5fed697a2ccfb2b9c745ebf1a6b11c920a`  
**Classe:** evidência / read-only  
**Uso:** este documento substitui baselines antigos como verdade operacional para decisões posteriores. Dados históricos continuam úteis apenas como comparação.

---

## 1. Garantia da coleta

O coletor registrou `concurrent_mutation_detected=0`. O `HEAD` do clone e `origin/main` estavam sincronizados no commit `6eb0e74085abb084e9f53945244b0bfc242c2088`, com worktree limpo. Os PIDs antes/depois da coleta não mudaram para nenhuma das seis emissoras que estavam em execução. A coleta não reiniciou/recarregou serviços de produção.

PIDs estáveis durante a coleta:

| station | PID PRE | PID POST |
|---|---:|---:|
| radioprincipal | 2230277 | 2230277 |
| radiopop | 2230370 | 2230370 |
| radiorock | 2230386 | 2230386 |
| radioclassicas | 2230398 | 2230398 |
| radiocountry | 2230436 | 2230436 |
| tvkids | 2230409 | 2230409 |
| tvteens | 0 | 0 |
| tvviva | 0 | 0 |
| tvmaisjovem | 0 | 0 |

---

## 2. Host / capacidade

- 2 CPUs lógicas, AMD EPYC 7B13 / KVM.
- RAM 7.8 GiB; ~6.8 GiB disponíveis durante a coleta.
- Sem swap.
- `/` 96 GiB; 17 GiB usados; ~80 GiB disponíveis (17%).
- Load average: `0.19 0.31 0.29`.
- FFmpeg/ffprobe 6.1.1-3ubuntu5.
- NGINX 1.24.0 Ubuntu.
- Certbot 2.9.0.
- MediaMTX executado pelo binário custom em `/opt/tpsmedia/mediamtx/current/mediamtx`; API local em `127.0.0.1:9997`.
- Host possui headroom relevante no snapshot; isso não elimina a necessidade de preservar stream-copy/baixa carga no caminho on-air.

Listeners observados incluem 22, 80, 443, 139/445, MediaMTX RTMP 1935, RTSP 8554 e HLS 8888. UFW estava `inactive`; nft local sem regras de filtragem relevantes. O pacote não contém a política de firewall da rede/GCP, portanto não é possível concluir exposição externa apenas a partir do firewall local.

---

## 3. Estado factual das cinco Rádios Studio Sat

### 3.1 Runtime

As cinco rádios estão **ACTIVE/RUNNING**, com `NRestarts=0` desde o start coordenado de 2026-09-12 ~06:58 UTC.

| station | PID | playlist on-air = disco | itens ativos |
|---|---:|---|---:|
| radioprincipal | 2230277 | SHA `154c3cb081f9a7d7f527ab184739b692c5a930db3fe8ff0659f241e9699b821c` | 18 |
| radiopop | 2230370 | SHA `6e8e3991833c6ff5e15c0695bdde33a0dfd4e4854faf342e0344b2c794d1a23d` | 10 |
| radiorock | 2230386 | SHA `27ebe9adbd1642dbf3ba5cecf1be6f0a7ff1e43b50dad3f61315a833285b8eb5` | 10 |
| radioclassicas | 2230398 | SHA `cf679f2518649137fe33a152ff1b615b36d389ebf1f8bdf3433bd18346c22f7f` | 11 |
| radiocountry | 2230436 | SHA `5a061c3f67080437c51b61c5ebf89916cd6b8eb780e59a59b7ef40dcda53faf4` | 18 |

Nenhuma das cinco tinha playlist aberta via FD `(deleted)` no snapshot.

### 3.2 O runtime real NÃO é o wrapper base

O arquivo `/usr/local/sbin/tps-playout-radio` ainda contém `-c:a copy` (SHA `5920f385cc47aed6466b58ad48b26c7f9d4b2da2ba9aa17690ab1289691607e3`). Porém **o runtime efetivo das cinco rádios é sobrescrito pelos drop-ins systemd `30-force-aac.conf`**.

Comando efetivo em cada rádio:

```text
-re -stream_loop -1 -f concat -safe 0 -i <playlist>
-map 0:a:0 -c:a aac -b:a 128k -ar 48000 -ac 2
-f flv rtmp://127.0.0.1:1935/<station>
```

Isto é uma dependência crítica: qualquer reconstrução que olhe apenas o wrapper `/usr/local/sbin/tps-playout-radio` inferirá incorretamente o estado de produção.

A Principal usa ainda um generator dedicado via drop-in `20-fixed-playlist.conf`:

`/usr/local/sbin/tps-generate-playlist-radioprincipal-fixed` — SHA `d2ba61daeeaaa89389fe1cc2ed277af68ac12c09b769c2eb9dda1feea9316fcd`.

Pop/Rock/Clássicas/Country usam o generator compartilhado:

`/usr/local/sbin/tps-generate-playlist` — SHA `690528ce3cb3b8db6ba7afcde2e180899fec689552137ff85892f44700714078`.

### 3.3 Sinal real / MediaMTX

MediaMTX no snapshot:

- `radioprincipal`: `ready=true`, source `rtmpConn`, track `MPEG-4 Audio`, inboundFramesInError=0.
- `radiopop`: igual.
- `radiorock`: igual.
- `radioclassicas`: igual.
- `radiocountry`: igual.

RTSP das cinco: **PASS**, AAC, 48 kHz, 2 canais/stereo.

O Core Preflight v1.1 — que segue corretamente o redirect do HLS — registrou para as cinco rádios:

```text
RTMP/stream: PASS
HLS HTTP: PASS
HLS freshness: CHANGING
```

O campo `local_hls=302 / hls_changed=NO` do coletor custom v2 não representa falha de produção: o teste custom não seguiu o redirect local do MediaMTX. O resultado de freshness do Core Preflight é a evidência correta.

### 3.4 Mídia de origem das rádios

Inventário `ready/`:

- Principal: 19 arquivos; playlist ativa 18.
- Pop: 11; playlist 10.
- Rock: 10; playlist 10.
- Clássicas: 12; playlist 11.
- Country: 19; playlist 18.

As fontes são heterogêneas (MP3, sample-rates diferentes em parte da biblioteca, capas MJPEG em vários arquivos). O on-air normaliza para AAC-LC 128k / 48 kHz / stereo. O decode integral das playlists ativas terminou `rc=0`, `dts=0`, `media_errors=0` nas cinco rádios.

O aviso `Estimating duration from bitrate` aparece em MP3s e, na Principal, há avisos de pixel format relacionados a cover-art MJPEG; o on-air mapeia apenas `0:a:0`, portanto esses avisos não constituem evidência de falha do áudio publicado.

**Conclusão Rádio:** as cinco emissoras estão funcionando e devem ser tratadas como baseline imutável para qualquer intervenção TV. O objetivo de qualquer change TV é preservar PIDs/configuração/rotas Rádio, não “melhorar” Rádio incidentalmente.

---

## 4. Web/portal Rádio — produção atual

A configuração NGINX Rádio está separada em:

- `/etc/nginx/conf.d/studiosat-radio.conf` — SHA `d9787fa02a5c098d95ebfd5d361ca1fd5e60937b5a5d14ea67e5950089bc0292`.
- `/etc/nginx/conf.d/zz-studiosat-radio-portal.conf` — SHA `d9fb8ea47f823028ca7fe67b1c6499363573e75cf1ac623bf50aa44f73df2360`.

Sem `www`, os hosts Rádio servem `/var/www/studiosat-radio-player`. Os hosts individuais com `www` servem `/var/www/studiosat-radio-portal`. `www.radio.studiosatweb.com.br` é um portal separado em `/var/www/studiosat-radio/current`, com `/api/` em `127.0.0.1:8789` e `/hls/` reescrito para MediaMTX.

As raízes públicas Rádio observadas responderam 200 após HTTPS. Os HLS diretos dos hosts individuais retornaram M3U8 real com `CODECS="mp4a.40.2"`.

**Limitação detectada no coletor:** para `www.radio.studiosatweb.com.br`, o teste genérico usou `/<station>/index.m3u8`, mas o portal real usa `/hls/<station>/index.m3u8`. O HTTP 200 registrado no teste genérico é HTML do SPA fallback e não prova o endpoint HLS do portal. O NGINX mostra a rota `/hls/`, mas a prova funcional exata desta URL precisa entrar na suplementação read-only.

NGINX `-t`: successful. Há warnings não fatais de `protocol options redefined` no arquivo `tps-tpsolutions-https.conf`.

---

## 5. TVKIDS — sinal interno está no ar, produto público NÃO está correto

### 5.1 Runtime

- `tps-tvkids-playout.service`: active/running.
- PID `2230409` desde 06:58:06Z, `NRestarts=0`.
- playlist efetivamente aberta = playlist no disco.
- SHA comum `2807c6c604f4601f92b990c047c857519fcb3760c58827ad308be297bcf951d0`.
- 15 referências, todas em `canonical/`.
- nenhum FD `(deleted)`.
- runtime: FFmpeg concat + `-c copy` → RTMP local `tvkids`.

MediaMTX: `tvkids ready=true`, tracks H264 + MPEG-4 Audio, inboundFramesInError=0. Core Preflight confirma HLS local PASS/CHANGING. HLS master observado: 1280x720, 30 fps, H.264 + AAC.

O RTSP do coletor custom inferiu `r_frame_rate=60/1`; isso conflita com todos os canonical 30/1, com o probe RTMP e com o HLS master `FRAME-RATE=30.000`. Não usar o 60/1 isolado como verdade de frame-rate do produto.

### 5.2 Canonical e ready

`canonical/`: 15 arquivos, ~800.6 MB. Todos os 15 apresentam perfil estrutural consistente: H.264 1280x720, yuv420p, 30/1, video time_base 1/90000, AAC 48 kHz stereo, audio time_base 1/48000. Decode integral da playlist: `rc=0`, sem erro de decode.

`ready/`: 13 arquivos heterogêneos e inadequados para concat stream-copy direto como fonte automática: resoluções e fps variados, sample-rate 44.1 kHz em vários itens e pelo menos um material sem áudio. O restart guard que coloca TVKIDS em `canonical/` continua sendo necessário no estado atual.

Há três pares de arquivos canonical byte-a-byte duplicados (prefixados 01/02/03 e os três nomes WhatsApp sem prefixo). Portanto 15 entradas representam 12 payloads únicos. Isto é um ponto editorial a confirmar, não corrupção técnica comprovada.

### 5.3 Causa dos `Non-monotonic DTS` agora isolada

O journal de 24h contém 356 warnings `Non-monotonic DTS`, todos em `output stream 0:1` — áudio. Para o PID atual, há 142 warnings no intervalo observado.

Os warnings do processo atual repetem-se em 10 boundaries específicos da playlist, com retrocessos de aproximadamente 3–21 ms:

- 02 → 03
- 03 → 04
- 04 → 05
- 05 → 06
- 08 → 09
- 09 → 10
- 10 → 11
- 11 → 12
- 12 → 13
- 14 → 15

Primeiros exemplos após o start atual:

- boundary 02→03: `previous=28.616s`, `current=28.600s`.
- 03→04: `76.961s` → `76.940s`.
- 04→05: `291.852s` → `291.841s`.
- 05→06: `607.020s` → `607.005s`.

O padrão se repete aproximadamente a cada 2427.46 s (~40m27s), isto é, em cada volta da playlist. O decode integral passar não contradiz esta falha: decode testa decodificabilidade; o defeito ocorre na timeline de pacotes AAC durante concat + stream-copy → FLV.

**Conclusão DTS:** o problema não é aleatório do MediaMTX. A evidência aponta para pequenas sobreposições/recuos de timestamp de áudio em boundaries específicos da concatenação dos MP4 canonical. A correção deve ser provada offline antes de qualquer cutover.

### 5.4 TVKIDS público

Os quatro FQDNs resolvem e apresentam certificado TLS válido, mas o conteúdo/roteamento NGINX está errado:

- `tvkids.studiosatweb.com.br` root HTTPS 200, HLS público 404.
- `www.tvkids.studiosatweb.com.br` root 200, HLS 404.
- `tvkidsweb.studiosatweb.com.br` root 200, HLS 404.
- `www.tvkidsweb.studiosatweb.com.br` root 200, HLS 404.

Mais importante: os quatro roots TVKIDS têm o mesmo SHA (`fe197b9d...`) e o mesmo `<title>Radio Studio Sat — Player</title>` do player Rádio sem-www.

O `nginx -T` atual NÃO contém `server_name` TV. Existem apenas as configurações principais `studiosat-radio.conf`, `tps-studiosatweb.conf`, `tps-tpsolutions-https.conf`, `zz-studiosat-radio-portal.conf`. Assim, os nomes TV estão caindo no primeiro/default vhost Rádio.

**Conclusão pública:** TVKIDS possui sinal local real e ativo, mas o produto público TV está atualmente roteado para conteúdo Rádio e seu HLS via host TV retorna 404.

---

## 6. TVTEENS / TVVIVA / TVMAISJOVEM

As três estão `failed`, MainPID 0, NRestarts=5. O incidente é reproduzível documentalmente:

- cada unit executa `ExecStartPre=/usr/local/sbin/tps-generate-playlist <station>`;
- cada `ready/` possui apenas um arquivo `teste-*`;
- o generator atual exclui nomes `test`/`teste`;
- resultado: `FATAL=NO_READY_MEDIA:<station>`;
- systemd tentou novamente até o start-limit.

Os três diretórios possuem também um canonical, mas o generator compartilhado usa `ready/` para estas stations. Portanto restart/start atual delas não é seguro sem corrigir primeiro o contrato de source/generator.

---

## 7. Incidente coordenado de 06:58 UTC

Há evidência de que por volta de 06:58:04–06:58:06Z ocorreram em conjunto:

- stop/start do NGINX;
- stop/start das 5 rádios;
- stop/start da TVKIDS;
- stop/start das outras 3 TVs.

As cinco rádios e TVKIDS retornaram. TVTEENS/TVVIVA/TVMAISJOVEM falharam devido a `NO_READY_MEDIA` e atingiram restart limit.

O host não reiniciou (uptime >5 dias). Não há root/tpsmedia crontab que explique a ação.

Existe uma correlação temporal relevante: `apt-daily-upgrade.timer` registra execução às 06:56:35Z, cerca de 90 segundos antes do restart coordenado. **O pacote atual não contém `/var/log/apt/history.log`, logs `unattended-upgrades`, `dpkg.log` nem journal detalhado do `apt-daily-upgrade.service`; portanto não é possível atribuir causalidade.** A origem do restart coletivo permanece `UNPROVEN` até uma suplementação read-only coletar estes artefatos.

---

## 8. MediaMTX / Core compartilhado

Config observada:

- API localhost `127.0.0.1:9997`.
- RTMP `:1935`.
- HLS `:8888`, always-remux, MPEG-TS, 7 segmentos, 2 s.
- `pathDefaults.source=publisher`.
- paths declarados para as 5 rádios e 4 TVs.

No snapshot, paths prontos: cinco rádios + `tvkids`. Paths não prontos: `tvteens`, `tvviva`, `tvmaisjovem`.

Não existe evidência que exija alteração ou restart do MediaMTX para restaurar o web público da TVKIDS: o path local `tvkids` já está publicado e saudável.

---

## 9. Certificado/DNS

O certificado Let’s Encrypt observado possui CN `studiosatweb.com.br`, validade 2026-09-09 → 2026-12-08 e SAN cobrindo os nomes Rádio e TV observados, incluindo os quatro nomes TVKIDS.

A falha pública das TVs não é, portanto, explicada pelo TLS; a evidência aponta para ausência de vhosts TV no NGINX atual.

---

## 10. Incompatibilidade crítica do antigo executor CHG-TVKIDS-001

O pacote Git atual `scripts/tv/tvkids-rebuild-production-v1.sh` / lib associada foi construído supondo a existência de:

```text
/etc/nginx/conf.d/tps-9-emissoras.conf
```

No estado atual do NS1, esse arquivo não aparece entre as configurações NGINX carregadas. O patcher antigo também pressupõe encontrar blocos TVKIDS existentes com `location = /`.

Logo, o executor antigo **não representa mais o servidor atual e fica classificado como STALE / REDESIGN REQUIRED**. Ele não será usado como próxima mutação.

---

## 11. Riscos cruzados agora conhecidos

1. Rádio está saudável por meio de drop-ins systemd AAC; o wrapper base sozinho não representa a produção.
2. O NGINX Rádio está separado e funcional; uma correção TV deve usar vhosts TV dedicados e preservar byte-a-byte os arquivos Rádio.
3. O generator compartilhado ainda acopla domínios e torna três TVs restart-unsafe.
4. TVKIDS local está no ar; seu problema público é NGINX/vhost e seu problema temporal é AAC/DTS em boundaries.
5. Global restart/reload de estações não é aceitável: o evento 06:58 demonstrou impacto cruzado real.
6. MediaMTX é compartilhado e saudável para Rádio + TVKIDS; não há justificativa atual para reiniciá-lo.
7. Host-local UFW está inativo e SMB/MediaMTX possuem listeners amplos; exposição externa depende de firewall de nuvem não incluído neste pacote.

---

## 12. Lacunas que ainda precisam ser fechadas em modo read-only

Antes de autorizar qualquer produção-change, uma suplementação forense deve coletar apenas o que o primeiro pacote não conseguiu provar:

- origem do restart coordenado de 06:58: apt/unattended-upgrades/dpkg/journal;
- journal completo do systemd/NGINX no intervalo 06:55–07:01;
- validação funcional do HLS real do portal `www.radio...` via `/hls/<station>/index.m3u8`;
- opcionalmente política de firewall GCP, se houver fonte autorizada disponível, para classificar listeners externos;
- snapshot de hashes/conteúdo dos webroots Rádio que serão invariantes da future change TV.

Até essa suplementação e sua análise, o freeze operacional continua vigente.

---

## 13. Estado geral factual

| Produto | Estado factual 2026-09-12 |
|---|---|
| Studio Sat Principal | **ON-AIR / AAC / HLS fresh / público** |
| Studio Sat Pop | **ON-AIR / AAC / HLS fresh / público** |
| Studio Sat Rock | **ON-AIR / AAC / HLS fresh / público** |
| Studio Sat Clássicas | **ON-AIR / AAC / HLS fresh / público** |
| Studio Sat Country | **ON-AIR / AAC / HLS fresh / público** |
| Portal/player Rádio | **em produção; rotas principais funcionais; HLS `/hls/` do portal requer prova suplementar exata** |
| TVKIDS sinal local | **ON-AIR / MediaMTX ready / HLS local fresh** |
| TVKIDS DTS | **DEGRADED — recorrente em 10 boundaries de áudio** |
| TVKIDS público | **BROKEN — root cai no player Rádio; HLS público 404** |
| TVTEENS | **FAILED — NO_READY_MEDIA** |
| TVVIVA | **FAILED — NO_READY_MEDIA** |
| TVMAISJOVEM | **FAILED — NO_READY_MEDIA** |

**Decisão documental:** preservar as cinco rádios e seu NGINX como baseline de produção. Redesenhar a recuperação TV contra este baseline factual; nenhuma ativação será baseada nos baselines de 09/09 ou 10/09.