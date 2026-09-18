# RESET-06 — forense focado no RESET-04 falho

O RESET-05 confirmou que `studiosat-radioprincipal-emergency-direct.service` está em estado FAILED enquanto selector e shadow estão ativos.

RESET-06 é somente leitura e coleta status, unit/journal do emergency-direct, selector/shadow journals, sockets, MediaMTX API, ffprobe RTMP, HLS, estrutura do selector e processos FFmpeg. Nenhum serviço é alterado.