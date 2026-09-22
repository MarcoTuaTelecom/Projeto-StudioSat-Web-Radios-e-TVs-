# Operação

Health: `http://127.0.0.1:8792/health`

Logs:

```bash
journalctl -u studiosat-v2-web.service -f
```

Comparação obrigatória: HLS cru -> `/diag-bypass/` -> `/listen-v2/` -> app nativo.
