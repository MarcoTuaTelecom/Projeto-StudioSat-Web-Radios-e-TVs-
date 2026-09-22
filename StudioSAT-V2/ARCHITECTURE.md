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


## Web V2.2 — nível abaixo do MSE

```text
HLS origem
  ↓
FFmpeg demux/remux (-c:a copy)
  ↓
AAC/ADTS contínuo
  ↓
Tokio broadcast
  ↓
HTTP chunked
  ↓
Nginx com proxy_buffering off
  ↓
HTMLMediaElement
```

O broadcast descarta backlog quando um cliente fica atrasado. Isso impede a
aplicação de acumular áudio antigo para entregá-lo posteriormente em rajada.

HLS nativo permanece somente como fallback para navegadores que não anunciem
suporte a `audio/aac`. HLS.js/MSE não fazem parte do caminho V2.2.
