# Baseline Técnico — StudioSat Web — 09/09/2026

Este documento resume o raio-X técnico usado como base inicial. É um snapshot, não um estado permanente. Antes de qualquer alteração, reconfirmar com o Core preflight.

## Host

- Ubuntu 24.04.4 LTS
- Google Compute Engine
- 2 vCPU AMD EPYC 7B13
- ~7,8 GiB RAM total
- ~6,8 GiB disponíveis no snapshot
- ~96 GiB filesystem raiz
- ~81 GiB livres no snapshot
- nenhuma GPU física detectada
- FFmpeg 6.1.1

## Plataforma

- 9 canais configurados: 5 rádios + 4 TVs
- MediaMTX ativo
- NGINX ativo em 80/443
- Docker ausente no baseline
- AzuraCast ausente
- Liquidsoap ausente
- ffplayout ausente
- Icecast ausente

## Fluxo legado observado

```text
/srv/tpsmedia/repository/channels/<canal>/ready
→ tps-generate-playlist
→ playlist/ffconcat
→ tps-<canal>-playout.service
→ tps-playout-radio ou tps-playout-tv
→ FFmpeg -re -stream_loop -1 -f concat -safe 0 -c copy
→ RTMP 127.0.0.1:1935/<canal>
→ MediaMTX
→ NGINX
→ Internet
```

## Portas relevantes observadas

- 80/TCP — NGINX
- 443/TCP — NGINX/TLS
- 1935/TCP — MediaMTX RTMP
- 8554/TCP — MediaMTX RTSP
- 8888/TCP — MediaMTX HLS/HTTP
- 9997/TCP localhost — MediaMTX API
- outras portas MediaMTX/WebRTC/SRT/auxiliares apareceram no snapshot e devem ser reinventariadas antes de hardening.

## Rádios — snapshot

- radioprincipal: active; mídia heterogênea 44,1/48 kHz stereo; attached pictures variados.
- radiopop: active; majoritariamente 48 kHz stereo, com teste 44,1 kHz mono.
- radiorock: FAILED no snapshot; inventário insuficiente/playlist stale.
- radioclassicas: active; majoritariamente 48 kHz stereo, com teste 44,1 kHz mono.
- radiocountry: active; amostra mais homogênea 48 kHz stereo.

Por isso Country foi escolhido como primeiro candidato de laboratório Radio, sujeito ao novo preflight.

## TVs

As quatro TVs apareciam configuradas/ativas no snapshot. TVKIDS apresentava histórico de mídia heterogênea e erros temporais, mas já possuía uma pasta `canonical/` com amostra uniforme em:

- MP4
- H.264
- 1280x720
- 30 fps
- yuv420p
- AAC
- 48 kHz stereo

Essa uniformidade tornou TVKIDS adequada para provar canonical/QC/copy sem instalar engine novo, desde que o conjunto seja validado integralmente antes de cutover.

## Riscos

- host de 2 vCPU não deve receber vários transcodes A/V em runtime;
- sem GPU dedicada;
- health histórico baseado demais em processo;
- `ready/` não representava contrato forte em todos os canais;
- exceções de scripts por canal indicavam acúmulo de lógica própria;
- MediaMTX e NGINX são compartilhados e têm blast radius multi-canal;
- publishers remotos precisam ser mapeados antes de qualquer fechamento de bind/firewall;
- Samba 139/445 apareceu no host e precisa ser validado como parte ou não do workflow de ingest.

## Decisão de curto prazo

- manter FFmpeg + MediaMTX + NGINX em produção;
- não atualizar FFmpeg in-place para satisfazer engine novo;
- não fazer migração direta;
- testar novos engines apenas em lab isolado;
- preservar `-c copy` onde mídia for canônica;
- criar conformação/QC antes do on-air;
- manter MediaMTX e NGINX como infraestrutura compartilhada;
- migrar uma emissora por vez.

## Limitações do baseline

- snapshot operacional, não monitoramento contínuo;
- perfis de mídia eram amostrados em parte do raio-X;
- nomes de units, paths e scripts devem ser reconfirmados pelo preflight atual;
- nenhuma informação histórica substitui evidência coletada imediatamente antes de mudança.
