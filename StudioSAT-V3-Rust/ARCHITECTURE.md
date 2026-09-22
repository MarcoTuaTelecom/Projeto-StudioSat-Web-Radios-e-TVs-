# Arquitetura V3 Rust/WGPU

## Plano gráfico

```text
Rust scene/state
   ↓
buffers explícitos
   ↓
wgpu
   ↓
WGSL shaders
   ↓
WebGPU no navegador
Metal no Apple
Vulkan/D3D12 no desktop
```

O portal pode ter estúdio 3D real, iluminação, partículas, espectro visual sintético e câmera sem tocar nas amostras de áudio.

## Plano de mídia

O áudio não entra em wgpu e não entra no WebAssembly para DSP. O cliente usa o decoder nativo da plataforma.

## Controle

- buffers de GPU explícitos;
- lifetime e ownership em Rust;
- sem garbage collector;
- sem DOM como motor principal da cena;
- UI HTML fica restrita a acessibilidade/controles essenciais;
- telemetria do player é somente leitura.

## Shader

WGSL é usado diretamente para vertex/fragment/compute shaders. Não usamos uma camada JavaScript 3D intermediária.
