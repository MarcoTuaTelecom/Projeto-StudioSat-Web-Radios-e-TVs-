# StudioSAT V2 — Rust + Native Media

Nova plataforma de portal e aplicativos da Studio Sat, construída do zero e isolada do player legado.

## Regra principal

```text
HLS da emissora -> mecanismo nativo do cliente -> saída de áudio
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
