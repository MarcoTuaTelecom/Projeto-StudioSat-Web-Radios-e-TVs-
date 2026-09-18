# Rádio Principal V6 — Reconstrução Final Consolidada

Uma única produção canônica no NS1, usando o canal HTTPS já existente do RadioBOSS e a mídia local do NS1.

- playlist/library: radioboss-sync;
- playback fresco: V8 control bridge;
- playback antigo: extrapolação determinística da última posição sobre a própria fila;
- mídia: árvore humana + media-transfer DB + manifest SHA;
- lab obrigatório em radioprincipal-test antes do cutover;
- produção canônica: studiosat-radioprincipal.service;
- sem instalação no PC;
- sem dependência do túnel de áudio.
