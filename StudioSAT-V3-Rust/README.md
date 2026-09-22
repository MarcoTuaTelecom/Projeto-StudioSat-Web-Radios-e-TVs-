# StudioSAT V3 — Rust Native + WebGPU

A V3 permanece em Rust. O objetivo é substituir a interface web tradicional por um renderer próprio e manter o áudio completamente separado do pipeline gráfico.

## Stack

- Rust para core, memória, rede, estado e lógica.
- wgpu para GPU moderna.
- WGSL para shaders.
- WebAssembly para o portal.
- AVPlayer no iOS e Media3 no Android para mídia nativa.
- zero React/Vue/Angular.
- zero Three.js.
- zero WebAudio no caminho audível.

## Regra

```text
AUDIO: fonte -> transporte -> decoder nativo -> saída
GRAFICO: Rust -> wgpu -> WGSL -> WebGPU/Metal/Vulkan/D3D12
```

Os dois planos nunca se interceptam.
