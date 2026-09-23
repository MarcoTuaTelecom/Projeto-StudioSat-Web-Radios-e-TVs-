# Incidente da Fase 3 — P2 0/5

Data: 2026-09-23

## Estado observado

A construção limpa chegou ao ponto de iniciar as cinco instâncias `studiosat-p2@`, mas todas encerraram com status 255 e o MediaMTX permaneceu com os cinco paths offline.

## Causa comprovada

- O usuário configurado em `publisher.env` corresponde ao usuário hash do MediaMTX.
- A senha configurada em `publisher.env` NÃO corresponde ao hash de senha armazenado no MediaMTX.
- O MediaMTX registrou falhas de autenticação para as conexões RTMP locais.
- Mídia, playlists, AAC 48 kHz estéreo, mux FLV e FFmpeg passaram 5/5 em teste local.
- As cinco units P2 estão como `static`, portanto o template também precisa receber uma seção `[Install]` antes de ser considerado persistente após reboot.
- O valor da senha local apareceu no journal por estar embutido na URL RTMP; ele não será reutilizado nem registrado neste histórico.

## Correção aprovada para a subetapa P2

1. Separar autenticação local do P2 da autenticação externa do RadioBOSS.
2. Permitir publicação local somente de `127.0.0.1` / `::1` e somente nos cinco paths de rádio.
3. Remover usuário/senha da URL RTMP do supervisor P2.
4. Remover a dependência do `publisher.env` depois que 5/5 estiver comprovado.
5. Tornar `studiosat-p2@.service` habilitável no boot com `WantedBy=multi-user.target`.
6. Subir primeiro a Principal como canário; só então as outras quatro.
7. Não avançar para portal/player/Nginx enquanto não houver 5/5 ready, online, bytes crescendo, HLS local válido e zero novas falhas de autenticação localhost.

O histórico anterior do repositório permanece intacto.
