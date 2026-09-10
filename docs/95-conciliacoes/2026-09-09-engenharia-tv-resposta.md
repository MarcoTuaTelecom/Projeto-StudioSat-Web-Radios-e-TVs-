# Resposta da Engenharia de TV — Conciliação StudioSat Web

## Denominador comum aceito

O StudioSat Web deve ser tratado como **uma plataforma**, não como dois projetos independentes. O **Core / Control Plane** é comum e os motores são específicos por domínio.

```text
                         STUDIOSAT WEB
                              │
                     CORE / CONTROL PLANE
                              │
        Station • Event • Schedule • Profiles • Health
                              │
                  ┌────────────┴────────────┐
                  │                         │
              DOMÍNIO TV                DOMÍNIO RÁDIO
                  │                         │
           TV Adapter/Engine         Radio Adapter/Engine
                  │                         │
        processo por emissora       processo por emissora
                  │                         │
                  └────────────┬────────────┘
                               │
                            MediaMTX
                               │
                             NGINX
                               │
                          CDN / Internet
```

**O Core é comum. Os motores não são.**

## Sete correções obrigatórias

1. **9 canais configurados ≠ 9 canais HEALTHY.** O estado real precisa ser reconfirmado pelo preflight.
2. O estado de `tps-generate-playlist` deve ser reconfirmado e congelado por hash antes de virar fato oficial.
3. O isolamento atual é **parcial**: processo separado existe; cgroup/slice, usuário por estação, filesystem permissions, HA de router e HA de host são níveis futuros.
4. Liquidsoap é **candidato** do `RadioEngineAdapter`, não tecnologia alvo definitiva.
5. FFmpeg + ffconcat é implementação atual/Stage-1 da TV; o contrato TV deve permanecer independente da implementação e pode futuramente usar ffplayout ou outro engine.
6. O Control Plane completo pode vir depois, mas o **contrato lógico do Core** deve nascer na Fase 1.
7. Paths de laboratório devem seguir uma convenção física única.

## CORE CONTRACT v0 — campos mínimos

```yaml
station_id:
station_class:

legacy:
  unit:
  media_root:
  playlist:

engine:
  adapter:
  implementation:

media:
  canonical_profile:

output:
  publish_path:
  public_urls:

health:
  schema_version:

control:
  plan_version:
```

Campos obrigatórios por estação:

- `station_id`
- `station_class`
- `engine_adapter`
- `profile_id`
- `plan_version`
- `health_schema_version`

O contrato deve existir antes dos laboratórios para impedir que as engenharias de TV e Rádio criem estruturas incompatíveis.

## Convenção proposta para paths LAB

```text
lab-tv-tvkids-av
lab-tv-tvteens-av

lab-radio-country-av
lab-radio-country-audio
lab-radio-pop-av
lab-radio-pop-audio
```

A API/Control Plane poderá posteriormente apresentar nomes lógicos hierárquicos sem exigir a mesma estrutura física no MediaMTX.

## Ordem operacional proposta pela Engenharia de TV

```text
F0  FREEZE + EVIDÊNCIA
F1  CORE CONTRACT v0 + channels-registry
F2  P0 NÃO DESTRUTIVO
F3A TVKIDS LAB
F3B COUNTRY RADIO LAB
    ↓ ambos passam
F4  Primeiro cutover TV
F5  Primeiro cutover Rádio
F6  HARDENING CORE
F7  replicação TVs
F8  replicação Rádios
F9  Control Plane funcional
F10 legado
F11 CDN / HA
```

A engenharia considera possível preparar TVKIDS e Country em trilhas de laboratório paralelas, desde que nenhuma alteração de fachada compartilhada seja feita sem gate conjunto.

## Contratos que TV e Rádio devem compartilhar

Devem usar a mesma linguagem/estrutura para:

- `station_id`
- `event_id`
- registry
- plano/versão
- etapas de ingest
- hash/dedupe
- estrutura de QC
- quarentena
- envelope de health
- MediaMTX
- NGINX/TLS
- logs/métricas
- política systemd
- semântica de rollback

Exemplo de health comum:

```text
health.station_id
health.state
health.last_event
health.output_freshness
health.errors
```

Extensão TV:

```text
video
audio
fps
resolution
timestamp_integrity
```

Extensão Rádio:

```text
av_output
audio_output
metadata
live_state
silence_state
```

## NON-MERGE RULES

```text
NÃO CONSTRUIR UNIVERSAL MEDIA ENGINE

TV scheduler        != Radio scheduler
TV continuity       != Radio music clock
TV filler           != Radio fallback
TV live             != Radio locutor/live
TV canonical        != Radio canonical
TV output model     != Radio dual rendition
TV transition model != Radio switch/fade/live
```

A Rádio mantém uma timeline editorial única da qual saem A/V + áudio-only. A TV não deve herdar essa semântica apenas porque pode compartilhar codecs.

## Procedimentos específicos para componentes do Core

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
→ inventário completo publishers/readers
→ impacto dos paths
→ gate TV + Rádio
→ reload/restart somente se necessário
→ health de TODAS as stations
```

## Formulação proposta ao engenheiro de Rádio

> A arquitetura não escolhe Liquidsoap por decreto. Ela define um contrato `RadioEngineAdapter`. Liquidsoap é o primeiro candidato a implementar esse contrato. Da mesma forma, a TV não obriga o Rádio a adotar seu motor, perfil canônico, filler ou modelo de programação. Em troca, Rádio e TV concordam em falar a mesma linguagem para Station, Event, Registry, Plan, Profile, Health, MediaMTX, NGINX, observabilidade, rollback e segurança.

## Decisão recomendada

```text
                  STUDIOSAT WEB

               CORE CONTRACT v0
                     │
         ┌────────────┴────────────┐
         │                         │
     TV DOMAIN                 RADIO DOMAIN
         │                         │
    TV Adapter                Radio Adapter
         │                         │
 Current: FFmpeg          Current: FFmpeg
 Stage 1: canonical      Candidate: Liquidsoap
         │                         │
         └────────────┬────────────┘
                      │
                 MEDIA CONTRACT
                      │
                   MediaMTX
                      │
                    NGINX
```

Antes de modificar TVKIDS ou instalar Liquidsoap, a Engenharia de TV recomenda fechar o **Contrato principal do StudioSat v0.1 — Registry + Station + Engine Adapter + Canonical Profile Registry + Health Envelope + Path Naming**.
