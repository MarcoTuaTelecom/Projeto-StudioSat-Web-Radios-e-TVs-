# Rádio Principal V3 — reescrita do caminho LIVE/failover

## Objetivo

Retirar o Liquidsoap 2.2.4 do caminho de ingest público sem alterar o RadioBOSS, a porta local do Windows ou o túnel SSH.

## Arquitetura

```
RadioBOSS
  -> 127.0.0.1:18005 Windows
  -> SSH existente
  -> 127.0.0.1:18005 NS1
  -> Icecast2 loopback
  -> V3 Core
       primary: RadioBOSS Icecast
       fallback: radioprincipal-ns1
  -> FFmpeg único publisher
  -> MediaMTX radioprincipal
  -> HLS
```

O V3 Core começa sempre no shadow NS1 para colocar áudio público imediatamente. Só muda para o RadioBOSS depois de 15 segundos de source saudável e um ffprobe válido. Se o LIVE cair, retorna para o shadow.

## Princípios

- não abre porta 18005 para Internet;
- reutiliza exatamente o SSH já existente;
- reutiliza a senha do source já existente;
- não usa Liquidsoap para receber o RadioBOSS;
- não usa playlist local como fallback;
- há somente um publisher para `radioprincipal`;
- o selector antigo fica desabilitado após cutover;
- preflight publica primeiro em `radioprincipal-v3-test`, sem tocar produção;
- cutover tem rollback automático se RTMP público não ficar pronto.