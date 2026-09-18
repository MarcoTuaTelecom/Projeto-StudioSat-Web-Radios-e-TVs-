# C21 / P1 — RadioBOSS LIVE Stability Probe

Objetivo: medir sem mutação a disponibilidade real do canal de áudio LIVE RadioBOSS -> túnel -> Harbor 18005 -> selector.

O probe registra:
- listener 18005;
- conexão TCP estabelecida;
- disponibilidade de selector/shadow;
- freshness do playback de controle;
- probes periódicos de RTMP público e shadow;
- switches do selector;
- metadata Harbor;
- feeding stopped/read errors;
- resumo de estabilidade.

Status possíveis:
- `CRITICAL_BLANK`: selector chegou ao blank;
- `UNSTABLE`: houve queda para NS1, feed stop/read error ou Harbor <99% estabelecido;
- `SAMPLE_PASS`: janela curta sem falha observada; não substitui soak test.

Safety: read-only na produção; escreve somente relatório em /root.
