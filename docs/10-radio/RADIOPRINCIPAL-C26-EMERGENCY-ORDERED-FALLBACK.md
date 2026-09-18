# C26 — Conectar RadioBOSS e substituir fallback aleatório por ordem autoritativa

## Objetivo imediato

1. manter RadioBOSS como prioridade 1;
2. tornar o túnel Windows automático e único;
3. impedir o NS1 de iniciar por arquivo antigo/aleatório;
4. fazer o fallback seguir a ordem real de `playlist.json` do RadioBOSS;
5. usar `playback.json` para current + playlistpos + pos_ms;
6. continuar pela mesma fila quando o controle ficar stale;
7. não reiniciar selector, MediaMTX ou Nginx.

## Artefatos

- `scripts/radioprincipal/v2/C26-WINDOWS-UNIFIED-TUNNEL.ps1`
- `scripts/radioprincipal/v2/ordered-authoritative-shadow.py`
- `scripts/radioprincipal/v2/C26-INSTALL-AND-PROMOTE-ORDERED-FALLBACK.sh`

## Regra do novo fallback

O engine não usa o media-map legado como fonte de ordem.

Ordem:

`playlist.json do RadioBOSS -> playlistpos/current -> asset resolvido -> próximo item da mesma fila`.

Se playback ainda não estiver fresco após o start, ele **não começa por um MP3 arbitrário**. Aguarda checkpoint válido.

Itens virtuais como `saytime=` são classificados como virtual e não são tratados como MP3. Nesta etapa emergencial são registrados/skipped; adapters editoriais completos continuam em P5.

## Promoção protegida

O instalador:
1. sobe primeiro em `radioprincipal-v2-shadow-hotfix`;
2. exige áudio RTMP válido;
3. exige conexão Harbor 18005 ESTABLISHED;
4. só então troca o publisher do fallback `radioprincipal-ns1`;
5. não reinicia selector;
6. não reinicia MediaMTX;
7. não reinicia Nginx;
8. faz rollback do unit anterior se o novo fallback não publicar.

## Windows

A tarefa nova:
`StudioSat-RadioPrincipal-Unified`

Substitui a tarefa antiga de túnel e sobe automaticamente no boot como SYSTEM.

Forward:
- 127.0.0.1:18005 -> NS1 127.0.0.1:18005
- 127.0.0.1:18796 -> NS1 127.0.0.1:8796

O segundo forward prepara o agente único C25/C24; o primeiro é o áudio RadioBOSS.

## Estado

C26 está PREPARADO NO GITHUB. Só passa a INSTALADO/ATIVO/VALIDADO após execução e evidência no Windows/NS1.
