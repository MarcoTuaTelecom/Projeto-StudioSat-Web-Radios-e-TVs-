# StudioSAT V2 — Rust + Native Media

Nova plataforma de portal e aplicativos da Studio Sat, construída do zero e isolada do player legado.

## Regra principal

```text
WEB V2.2
HLS validado -> FFmpeg -c:a copy -> AAC/ADTS contínuo -> navegador nativo

APPS NATIVOS
HLS ou RAW AAC -> AVPlayer/Media3 -> saída nativa
```

Nenhum VU, animação, metadado ou API pode interceptar, reamostrar, acelerar, desacelerar ou reconstruir o áudio.

## Estrutura

- `crates/studiosat-core`: catálogo/modelos em Rust.
- `apps/web-rust`: portal/API Rust (Axum), inicialmente em `/listen-v2/`.
- `native/android`: Kotlin + AndroidX Media3/ExoPlayer.
- `native/ios`: SwiftUI + AVPlayer.
- `deploy`: build, systemd, Nginx, smoke test.
- `docs`: documentação técnica e operacional.

## Streams

- Principal: `https://radio.studiosatweb.com.br/radioprincipal/index.m3u8`
- Pop: `https://radio.studiosatweb.com.br/radiopop/index.m3u8`
- Rock: `https://radio.studiosatweb.com.br/radiorock/index.m3u8`
- Clássicas: `https://radio.studiosatweb.com.br/radioclassicas/index.m3u8`
- Country: `https://radio.studiosatweb.com.br/radiocountry/index.m3u8`

## Primeiro deploy

```bash
./deploy/bootstrap-toolchain.sh
./deploy/build-web.sh
sudo ./deploy/install-ns1.sh
```

Teste em `https://www.radio.studiosatweb.com.br/listen-v2/`.

O `/listen/` legado permanece intacto até o V2 ser aprovado auditivamente.


## V2.2 — transporte sem MSE no portal

O portal web usa como transporte primário `/listen-v2/live/<radio>.aac`.
O Rust mantém um relay por emissora e o FFmpeg apenas copia os pacotes AAC
(`-c:a copy`) do HLS já validado para ADTS contínuo. Não existe HLS.js/MSE
no caminho normal do portal.

Teste direto:

```text
https://www.radio.studiosatweb.com.br/listen-v2/live/radioprincipal.aac
```
