# Arquitetura StudioSAT V2

## Mídia separada da interface

```text
FFmpeg/HLS origin -> native media engine -> decoder do dispositivo -> saída
                         ^
                         |
                   UI observa estado
```

### Web

Rust/Axum serve a aplicação. Safari usa HLS nativo. Browsers sem HLS nativo usam MSE/HLS.js mínimo. Não existe WebAudio, AudioContext, AnalyserNode, DSP ou time-stretch.

### Android

Media3/ExoPlayer recebe HLS diretamente por `MediaItem`. Sem WebView e sem leitura de PCM.

### iOS

AVPlayer recebe HLS diretamente; AVAudioSession usa `.playback`.

## Proibido

- `AudioContext` no caminho audível.
- `AnalyserNode` ligado ao áudio.
- sampling PCM para VU.
- ajuste automático de `playbackRate`.
- seeks periódicos para perseguir live edge.
- transcodificação dentro do portal/app.
- service worker interceptando HLS.
