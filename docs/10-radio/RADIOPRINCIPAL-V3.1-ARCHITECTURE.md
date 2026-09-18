# Rádio Principal V3.1 — reescrita contínua

V3.1 substitui o preflight que dependia de um path MediaMTX inexistente (`radioprincipal-v3-test`).

## Mudança principal

O público passa a ter um encoder FFmpeg persistente alimentado por PCM. O Core V3.1 troca apenas o decoder de origem (RadioBOSS live ou shadow NS1). Assim o publisher público não é derrubado a cada failover.

## Caminho

RadioBOSS -> SSH existente -> Icecast2 loopback -> decoder live

radioprincipal-ns1 -> decoder fallback

decoder escolhido -> PCM 48k stereo -> encoder público persistente -> radioprincipal -> HLS

## Preflight

- Icecast2 é testado em 127.0.0.1:18015;
- o shadow é decodificado por 3 segundos;
- o encoder AAC/FLV é testado em arquivo local;
- nenhum path MediaMTX de teste é exigido.

## Cutover

- selector antigo é parado;
- Icecast2 assume a mesma porta 18005;
- Core V3.1 começa pelo shadow;
- RadioBOSS só entra após 15 s de presença + ffprobe válido;
- se o live parar de produzir PCM por 1,5 s, o Core retorna ao shadow;
- o publisher público permanece vivo.