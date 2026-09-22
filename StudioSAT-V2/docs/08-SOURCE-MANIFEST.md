# Manifesto de fontes — StudioSAT V2

Este documento registra a finalidade de cada componente da primeira versão compilável.

## Raiz

- `README.md` — visão geral, streams e primeiro deploy.
- `ARCHITECTURE.md` — separação rígida entre mídia e interface.
- `Cargo.toml` — workspace Rust.
- `.gitignore` — artefatos locais/segredos excluídos.

## Rust

- `crates/studiosat-core/src/lib.rs` — catálogo canônico das cinco emissoras.
- `apps/web-rust/src/main.rs` — servidor Axum, API e publicação do portal.
- `apps/web-rust/static/index.html` — interface web V2.
- `apps/web-rust/static/app.js` — controle mínimo do elemento de mídia; sem DSP/WebAudio.
- `apps/web-rust/static/styles.css` — apresentação visual, inclusive VU puramente visual.

## Android

- `native/android/app/src/main/java/br/com/studiosat/v2/PlaybackService.kt` — ExoPlayer/MediaSession.
- `MainActivity.kt` — interface e comandos; não processa mídia.
- `Station.kt` — catálogo.
- `SimpleItemSelectedListener.kt` — adaptação simples do Spinner.
- `AndroidManifest.xml` — permissões e MediaSessionService.
- `activity_main.xml` — primeira interface funcional.
- `build.gradle.kts` — AGP/Media3.

## iOS

- `PlayerEngine.swift` — AVPlayer + AVAudioSession.
- `Station.swift` — catálogo.
- `ContentView.swift` — interface SwiftUI.
- `StudioSatV2App.swift` — entrada da aplicação.
- `project.yml` — definição XcodeGen.

## Deploy

- `bootstrap-toolchain.sh` — instala/seleciona Rust stable.
- `build-web.sh` — compila web/core em release.
- `studiosat-v2-web.service` — unidade systemd.
- `install-ns1.sh` — instala paralelamente em /listen-v2/, com backup/rollback Nginx.
- `smoke-test.sh` — valida portal e os cinco HLS.

## Documentação

- `docs/00-CONSTRUCTION-LOG.md` — decisões cronológicas.
- `docs/01-AUDIO-INVARIANTS.md` — regras que nenhum desenvolvedor pode violar.
- `docs/02-BUILD-AND-DEPLOY.md` — compilação/publicação.
- `docs/03-FUNCTIONAL-INVENTORY.md` — funcionalidades herdadas como requisito, não como código.
- `docs/04-ANDROID.md` — build e arquitetura Android.
- `docs/05-IOS.md` — build e arquitetura iOS.
- `docs/06-ROLLBACK.md` — reversão segura.
- `docs/07-OPERATIONS.md` — operação e healthcheck.
- `docs/08-SOURCE-MANIFEST.md` — este manifesto.

## Regra de revisão

Qualquer alteração que introduza `AudioContext`, PCM sampling, WebView como player, alteração automática de playbackRate, seek periódico para live edge ou transcodificação no cliente deve ser bloqueada em revisão.
