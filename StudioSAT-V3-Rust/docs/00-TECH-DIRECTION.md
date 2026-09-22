# Direção tecnológica

O requisito é manter Rust como linguagem central e usar tecnologia gráfica de baixo nível.

Escolha:
- Rust + wgpu + WGSL para 3D;
- WASM/WebGPU no portal;
- mesmos modelos Rust compartilháveis com desktop;
- player de mídia nativo desacoplado.

Linguagens raras não serão escolhidas só por raridade. WGSL entra porque é a linguagem de shader do WebGPU e fica próxima do hardware gráfico. Zig pode ser usado futuramente apenas como ferramenta auxiliar/FFI, nunca para substituir o core Rust.
