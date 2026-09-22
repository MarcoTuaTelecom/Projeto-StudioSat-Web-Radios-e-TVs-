# Data plane de baixo nível — Rust + io_uring

A V3 não abandona Rust.

## Transporte

O plano de mídia definitivo será escrito em Rust com controle explícito de buffers e I/O assíncrono no kernel Linux.

Caminho alvo:

```text
RadioBOSS / encoder
  -> AAC/ADTS
  -> socket de ingest
  -> Rust
  -> ring buffers fixos
  -> io_uring
  -> sockets dos ouvintes
```

Sem Axum no data plane, sem framework HTTP e sem filas ilimitadas por cliente.

O HTTP de controle/API pode continuar separado; o áudio terá um servidor de dados próprio.

## Memória

- arenas/slabs prealocadas;
- buffers fixos por estação;
- sem heap por frame no hot path;
- limites rígidos por cliente;
- cliente atrasado é desconectado, nunca recebe backlog acumulado.

## CPU

- io_uring para accept/read/write;
- batching de syscalls;
- zero cópia adicional quando o kernel permitir;
- afinidade/telemetria de CPU separadas do renderer.

## Interface

Rust + wgpu + WGSL permanece completamente separado do áudio.
