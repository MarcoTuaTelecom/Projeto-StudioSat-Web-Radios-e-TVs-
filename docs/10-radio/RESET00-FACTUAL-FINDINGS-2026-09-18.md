# RESET-00 — Achados factuais do NS1 — 2026-09-18

Fonte: pacote `studiosat-ns1-raiox-20260918T174058Z` coletado do NS1.

## Estado no instante da coleta

- host: `ns1.tpsolutions.com.br`;
- selector: active;
- MediaMTX: active;
- Nginx: active;
- RadioBOSS sync: active;
- media-transfer: active;
- shadow legado: active;
- Edge Bridge V2: active;
- Operator API V2: active.

## Paths MediaMTX

- `radioprincipal`: READY;
- `radioprincipal-ns1`: READY;
- `radioprincipal-rb`: DOWN.

Observação: `radioprincipal-rb` MediaMTX não é o LIVE usado pelo selector atual. O LIVE entra diretamente pelo Liquidsoap Harbor 18005.

## Harbor

- 127.0.0.1:18005 estava LISTEN;
- havia conexões ESTABLISHED via sshd;
- portanto o túnel alcançava o Harbor no instante da captura.

## Descoberta crítica — selector real

Config ativa:

```liquidsoap
rb = input.harbor(... port=18005 ...)

local = playlist(
  id="radioprincipal_local_grade",
  mode="normal",
  reload=15,
  "/srv/studiosat/radio-principal/playlists/current.m3u"
)

program = fallback(
  id="radioprincipal_selector",
  track_sensitive=false,
  replay_metadata=true,
  [rb, local, security]
)
```

Logo, o fallback público atual NÃO é `radioprincipal-ns1`.

A ordem real é:

```
1. RadioBOSS Harbor
2. /srv/studiosat/radio-principal/playlists/current.m3u
3. blank
```

Isso invalida pressupostos anteriores de que o selector público estava usando o shadow RTMP como segunda fonte.

## Descoberta crítica — current.m3u está editorialmente incorreto

`/srv/studiosat/radio-principal/playlists/current.m3u` possui 291 linhas:

- 109 elementos de hora certa;
- 28 músicas Manhã;
- 69 músicas Noite;
- 85 músicas Tarde.

A ordem é literalmente:
1. todos os 109 arquivos de hora certa;
2. Manhã;
3. Noite;
4. Tarde.

Isso NÃO é uma fila executável válida do RadioBOSS.

## Prova da troca indevida em produção

Na janela observada:

- 17:40:19 — Switch to `radioprincipal_rb_harbor`;
- 17:40:26 — Switch to `radioprincipal_local_grade`;
- 17:40:36 — Switch to `radioprincipal_rb_harbor`;
- 17:40:49 — Switch to `radioprincipal_local_grade`;
- 17:40:59 — Switch to `radioprincipal_rb_harbor`.

Portanto o ouvinte realmente alternava entre RadioBOSS e a lista local errada.

## RadioBOSS / mirror

Mirror controller no mesmo instante:

- RADIOBOSS_PLAYLIST_TRACKS=166;
- NS1_AVAILABLE_TRACKS=163;
- NS1_MISSING_TRACKS=3.

Human repository:

- Manhã=28;
- Tarde=85;
- Noite=69.

Playback observado pelo sync:
- playlistpos=15;
- current: `08 B. J. THOMAS - RAINDROPS KEEP FALLIN.mp3`;
- next: `08 DJAVAN - SINA.mp3`.

Esses dois itens não estavam presentes no `current.m3u` local capturado.

## Shadow legado

`studiosat-radioprincipal-shadow-ns1.service` ainda executa:

`/opt/studiosat/radio-v2/radioprincipal-mirror/mirror-playout.py`

e publica `radioprincipal-ns1`.

Porém o selector atual não consome esse path como fallback.

## Decisão RESET-01A

Baseline imediata:

```
RadioBOSS Harbor -> blank
```

Remover temporariamente `radioprincipal_local_grade` do fallback público.

Motivo:
- impedir arquivos antigos/não autorizados de voltarem ao ar;
- manter RadioBOSS como única fonte editorial pública;
- em microqueda do LIVE, silêncio é preferível a programação errada;
- reconstruir o fallback correto apenas no RESET-02.
