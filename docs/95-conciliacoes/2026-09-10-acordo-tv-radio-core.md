# Acordo Técnico TV + Rádio + Core — 2026-09-10

Status: **APROVADO COMO ESTRATÉGIA CONJUNTA, COM GATES OPERACIONAIS**

## Conclusão

A Engenharia de TV concorda com a estratégia consolidada pela Engenharia de Rádio para a StudioSat Web, com duas condições operacionais que passam a ser normativas:

1. **Paralelismo de projeto: SIM. Paralelismo de alteração do host: NÃO.**
2. Antes do primeiro cutover de Rádio para o engine candidato, executar um **Core Compatibility Gate** sobre MediaMTX, NGINX, ingress, auth/ACL, health, naming e rollback.

## Decisões conjuntas aprovadas

- StudioSat Web é uma plataforma única.
- O Core/Control Plane é compartilhado.
- TV e Rádio possuem engines separados.
- Uma instância/processo por emissora.
- MediaMTX e NGINX permanecem infraestrutura compartilhada.
- `station_id`, `event_id`, profile, health e plan version pertencem ao contrato comum.
- Perfis canônicos de TV e Rádio são separados.
- Liquidsoap é o primeiro **candidato** a `RadioEngineAdapter`, não uma obrigação arquitetural.
- FFmpeg `-c copy` é o Stage-1 da TV enquanto os assets forem canônicos.
- ffplayout/outro engine TV permanece candidato futuro, condicionado a benchmark.
- Paths LAB seguem nomenclatura comum.
- Nenhuma mudança estrutural ocorre antes de freeze/preflight.
- Cutover sempre de uma station por vez.

## Engines — formulação oficial

```text
RADIO ENGINE CURRENT:
FFmpeg legado

RADIO ENGINE CANDIDATE:
Liquidsoap

RADIO ENGINE SELECTED:
somente depois do gate

TV ENGINE CURRENT:
FFmpeg + ffconcat

TV ENGINE STAGE-1:
FFmpeg + canonical + copy

TV ENGINE FUTURE CANDIDATE:
ffplayout / outro
```

A arquitetura depende dos adapters (`RadioEngineAdapter` e `TvEngineAdapter`), não de detalhes internos das implementações.

## Core Contract antes dos laboratórios

O `CORE CONTRACT v0.1` é obrigatório antes de novas estruturas de lab porque define a linguagem comum:

```text
Station
Channel Registry
Domain
Engine Adapter
Event
Profile Registry
Health Envelope
Output/Path Naming
Change Ownership
Non-Merge Rules
Versioning
```

## NON-MERGE RULES

```text
TV scheduler        != Radio scheduler
TV continuity       != Radio music clock
TV filler           != Radio fallback
TV live             != Radio locutor/live
TV canonical        != Radio canonical
TV output model     != Radio dual rendition
TV transition       != Radio switch/fade/live
```

É proibido criar um Universal Media Engine apenas para uniformizar software.

## Ordem operacional conjunta

```text
F0  FREEZE + EVIDÊNCIA
F1  CORE CONTRACT v0.1 + channels-registry
F2  P0 NÃO DESTRUTIVO
F3  TVKIDS LAB
F4  TVKIDS CUTOVER + 24h
F5  RADIO COUNTRY LAB + A/V + audio-only + live + fallback + shadow 24h
F6  CORE COMPATIBILITY GATE
F7  RADIO COUNTRY CUTOVER
F8  demais rádios, uma por vez
F9  demais TVs, uma por vez
F10 Control Plane funcional
F11 legado
F12 CDN / HA
```

A ordem das emissoras restantes pode ser alterada com base no novo preflight; o princípio de **uma mudança ativa no host por vez** não muda.

## Health comum com extensões de domínio

Envelope comum:

```text
health.station_id
health.state
health.last_event
health.output_freshness
health.errors
```

TV acrescenta vídeo, áudio, FPS, resolução e integridade de timestamps.

Rádio acrescenta A/V, áudio-only, metadata, live state e silence state.

## Procedimentos Core separados

NGINX:

```text
candidate/diff
→ nginx -t
→ origin health
→ reload
→ public health
```

MediaMTX:

```text
candidate/diff
→ validate config
→ publishers/readers inventory
→ path impact
→ gate TV + Rádio
→ reload/restart somente se necessário
→ health de todas as stations
```

## Divisão de autoridade

### Core

MediaMTX, NGINX/TLS, registry, naming, schemas comuns, systemd/slices globais, portas, ingress/ACL, observabilidade, backup/rollback global e Change Queue.

### Engenharia TV

TVKIDS/TVTEENS/TVVIVA/TVMAISJOVEM, canonical/QC TV, continuity/scheduler/filler/live TV, `TvEngineAdapter`, health TV e rollback por TV.

### Engenharia Rádio

Radio Principal/Pop/Rock/Clássicas/Country, timeline, A/V + áudio-only, live/fallback/metadata, canonical Rádio, `RadioEngineAdapter`, health Rádio e rollback por Rádio.

## Posição final da Engenharia de TV

**Concordamos com a estratégia da Engenharia de Rádio.** Ela preserva corretamente o Core comum sem fundir semânticas que precisam continuar próprias de cada domínio. A única disciplina adicional é operacional: engenharia pode avançar em paralelo, mas o host de produção recebe uma mudança por vez, dentro da Change Queue, e o primeiro cutover Rádio exige Core Compatibility Gate antes da promoção.
