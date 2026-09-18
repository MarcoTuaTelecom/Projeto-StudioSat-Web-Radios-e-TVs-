# RESET-04 — Emergência: Rádio Principal no ar pelo shadow NS1 direto

Objetivo: colocar a Rádio Principal no ar imediatamente quando o selector falha, usando o path `radioprincipal-ns1` já comprovadamente READY.

Arquitetura temporária:

```
radioprincipal-ns1 (shadow existente)
        ↓
ffmpeg emergency bridge
        ↓
radioprincipal
        ↓
HLS público
```

O RESET-04:
- não altera playlists;
- não altera mídia;
- não reinicia MediaMTX/Nginx se já ativos;
- exige `radioprincipal-ns1` pronto antes de mudar a saída pública;
- desativa temporariamente o selector para evitar dois publishers no mesmo path;
- cria serviço systemd de emergência;
- exige RTMP público + HLS;
- se falhar, remove o bridge e restaura/reinicia o selector.

É um modo de emergência. O RadioBOSS continua sendo corrigido separadamente; o objetivo deste passo é áudio contínuo no ar agora.
