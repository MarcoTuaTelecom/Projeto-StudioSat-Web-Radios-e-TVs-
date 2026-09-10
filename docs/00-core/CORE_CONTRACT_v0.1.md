# StudioSat Web — CORE CONTRACT v0.1

## Objetivo

Definir a linguagem comum entre o Core, o domínio de TV e o domínio de Rádio antes de qualquer laboratório ou migração. Este contrato não escolhe engines; ele define como cada domínio se apresenta à plataforma.

## Princípios

1. StudioSat Web é uma plataforma única.
2. Core compartilhado não significa engine universal.
3. Uma emissora = um domínio de falha.
4. Componentes compartilhados pertencem ao Core.
5. TV e Rádio podem evoluir em paralelo em engenharia, mas alterações do host de produção entram numa fila única.
6. Nenhuma mídia entra no ar sem certificação.
7. Heavy transcode pertence ao ingest/offline sempre que possível.
8. Health mede o produto final, não apenas PID/systemd.

## Station Registry

Cada estação deve possuir obrigatoriamente:

```yaml
station_id: string
station_class: radio | tv
public_name: string
owner_domain: radio | tv

legacy:
  unit: string
  media_root: string
  playlist: string | null

engine:
  adapter: RadioEngineAdapter | TvEngineAdapter
  implementation: string
  candidate: string | null

media:
  canonical_profile: string
  profile_version: string

output:
  publish_path: string
  public_urls: []
  lab_paths: []

health:
  schema_version: STUDIOSAT-HEALTH-1

control:
  plan_version: STUDIOSAT-PLAN-1
```

## Engine Adapter Contract

### RadioEngineAdapter

O Core não conhece detalhes internos do Liquidsoap ou de outro engine. O adapter deve expor capacidades equivalentes a:

- carregar/atualizar programação;
- consultar evento atual;
- informar estado AUTO/LIVE/FALLBACK;
- produzir A/V e áudio-only da mesma timeline;
- inserir/remover live sem restart do engine;
- reportar health e metadata;
- permitir rollback operacional.

Liquidsoap 2.4.x é o primeiro candidato, não uma obrigação arquitetural.

### TvEngineAdapter

O Core não conhece flags específicas do FFmpeg/ffplayout. O adapter deve expor capacidades equivalentes a:

- carregar/publicar playlist/schedule;
- consultar programa/asset atual;
- manter continuidade A/V;
- operar filler/fallback de TV;
- reportar integridade de timestamps/DTS;
- reportar health;
- permitir rollback operacional.

FFmpeg + ffconcat + canonical é Stage-1 atual. ffplayout ou outro engine é candidato futuro condicionado a benchmark.

## Event Envelope

```yaml
event_id: string
station_id: string
domain: radio | tv
scheduled_start: timestamp
asset_id: string | null
role: string
metadata: {}
policy: {}
version: STUDIOSAT-EVENT-1
```

### Rádio interpreta `role` como
- music
- live
- ad
- jingle
- program
- fallback

### TV interpreta `role` como
- program
- episode
- ad
- promo
- live
- filler

## Profile Registry

Perfis são versionados separadamente.

Exemplos:

```text
STUDIOSAT-RADIO-AV-V1
STUDIOSAT-RADIO-AUDIO-V1
TVKIDS-V1
STUDIOSAT-TV-V2 (futuro)
```

Mesmo codec não significa mesmo contrato.

## Health Envelope

Base comum:

```yaml
station_id: string
state: healthy | degraded | failed
last_event: string | null
output_freshness: number
errors: []
schema_version: STUDIOSAT-HEALTH-1
```

Extensão Rádio:

```yaml
radio:
  av_output: ok | fail
  audio_output: ok | fail
  metadata: ok | stale
  live_state: auto | live | fallback
  silence_state: normal | unexpected
```

Extensão TV:

```yaml
tv:
  video: ok | fail
  audio: ok | fail
  fps: string
  resolution: string
  timestamp_integrity: ok | fail
  filler_ready: true | false
```

## Path Naming

Convenção de laboratório:

```text
lab-tv-tvkids-av
lab-tv-tvteens-av
lab-tv-tvviva-av
lab-tv-tvmaisjovem-av

lab-radio-country-av
lab-radio-country-audio
lab-radio-pop-av
lab-radio-pop-audio
lab-radio-rock-av
lab-radio-rock-audio
lab-radio-classicas-av
lab-radio-classicas-audio
lab-radio-principal-av
lab-radio-principal-audio
```

Paths públicos e internos de produção só serão congelados após o Core preflight.

## Ownership

### Core
- MediaMTX
- NGINX/TLS
- channel registry
- naming
- health/event schemas
- política systemd/slices
- portas
- ingress policy
- observabilidade
- backup/rollback global
- change queue

### Rádio
- timeline
- engine de rádio
- A/V + áudio-only
- live locutor/câmera
- metadata rádio
- fallback rádio
- canonical rádio

### TV
- canonical/QC TV
- playlist/scheduler TV
- continuidade A/V
- DTS/timebase
- filler TV
- live TV
- engine TV

## NON-MERGE RULES

É proibido fundir:

```text
TV scheduler         != Radio scheduler
TV continuity        != Radio music clock
TV filler            != Radio fallback
TV live              != Radio locutor/live
TV canonical         != Radio canonical
TV output model      != Radio dual rendition
TV transition model  != Radio switch/fade/live
```

É proibido construir um Universal Media Engine apenas para reduzir o número de softwares.

## Change Gate

Nenhuma alteração de Core pode ser aplicada sem:

1. diff/candidate;
2. validação técnica específica;
3. impacto em Rádio e TV conhecido;
4. rollback documentado;
5. health antes;
6. mudança única na fila;
7. health depois.

### NGINX

```text
candidate/diff
→ nginx -t
→ health origin
→ reload
→ health público
```

### MediaMTX

```text
candidate/diff
→ validate config
→ publishers/readers inventory
→ path impact
→ gate Rádio + TV
→ reload/restart somente se necessário
→ health de todas as stations
```

## Estado

**v0.1 — contrato inicial para alinhamento entre Core, Engenharia de TV e Engenharia de Rádio.**
