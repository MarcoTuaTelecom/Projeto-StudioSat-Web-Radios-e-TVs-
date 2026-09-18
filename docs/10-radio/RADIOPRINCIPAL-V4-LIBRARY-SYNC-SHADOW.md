# Rádio Principal V4 — Library Sync + Effective Queue + Shadow

Implementação executável do plano editorial.

- indexa MP3 existentes no NS1;
- lê playlist/playback/schedule/librarymanifest snapshots do RadioBOSS;
- resolve arquivos locais por basename normalizado e artista+título;
- não trata virtual items como missing;
- gera effective-queue.json;
- segue current + playlistpos + pos_ms;
- publica shadow sincronizado em radioprincipal-ns1;
- em snapshots stale continua autonomamente pela fila local;
- substitui apenas o shadow legado; V3.2 público permanece ativo durante a troca.

O instalador aborta antes da troca se current/next não resolverem ou cobertura for <80%.