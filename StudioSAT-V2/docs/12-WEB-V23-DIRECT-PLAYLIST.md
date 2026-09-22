# V2.3 — fonte local direta para as cinco rádios

## Motivo

O V2.2 RAW comprovou geração local nas quatro primeiras emissoras, mas Country
não entregou o primeiro chunk dentro do timeout. Como o relay ainda consumia
HLS como fonte, o experimento ainda herdava uma camada que queremos eliminar.

## Caminho V2.3

```text
atual.ffconcat
  ↓
FFmpeg executado como tpsmedia
  ↓
aresample=48000:async=0
asetpts=N/SR/TB
  ↓
AAC-LC 128 kb/s / 48 kHz / 2 canais
  ↓
ADTS contínuo
  ↓
Rust broadcast limitado
  ↓
HTTP
  ↓
decoder nativo
```

Nenhuma das cinco rádios depende de HLS, RTMP ou MediaMTX como fonte do V2.3.

## Controle de backlog

O broadcast foi reduzido para 32 frames AAC (~0,68 s a 48 kHz). Se um cliente
ficar atrás dessa janela, a sessão é encerrada em vez de drenar áudio antigo.

## Usuário do serviço

O serviço roda como `tpsmedia`, porque esse usuário já é o proprietário
operacional do playout e possui acesso ao acervo em `/srv/studiosat`.

## Pre-flight

Antes da instalação, cada playlist é codificada por 2 segundos como
`tpsmedia` e o instalador exige sync ADTS válido. Isso detecta permissão,
playlist e encoder antes de tocar no serviço.
