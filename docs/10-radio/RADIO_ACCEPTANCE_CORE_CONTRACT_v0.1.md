# CHG-003 — Aceite da Engenharia Rádio — CORE CONTRACT v0.1

Status: **ACCEPTED**
Data: 2026-09-10
Owner: Engenharia Rádio / StudioSat Web
Baseline revisado antes do aceite: `c72132d1ee9909f042cd72985d1b2874cf2a1b73`

## Decisão

A Engenharia Rádio aceita o `docs/00-core/CORE_CONTRACT_v0.1.md` como contrato comum da plataforma StudioSat Web.

O aceite é de **fronteiras, contratos e responsabilidades**, não de uma implementação específica de engine.

## Cláusulas aceitas

1. `station_id`, `station_class`, `EngineAdapter`, Profile Registry, Event Envelope, Health Envelope, naming, versionamento e Change Queue pertencem ao contrato comum.
2. MediaMTX, NGINX/TLS, portas, ingress/auth/ACL, registry, schemas comuns, observabilidade, backup/rollback global e política systemd compartilhada pertencem ao Core.
3. A Engenharia Rádio possui autoridade sobre timeline, engine, A/V + áudio-only, live locutor/câmera, metadata, fallback e canonical da Rádio.
4. A Engenharia TV possui autoridade sobre canonical/QC, scheduler/continuity/filler/live e engine das TVs.
5. Uma emissora continua sendo um domínio de falha independente.
6. Não será criado Universal Media Engine apenas para uniformizar software.
7. Uma única alteração pode estar ativa no host por vez.
8. Toda mudança compartilhada exige candidate/diff, impacto cruzado conhecido, rollback e health antes/depois.
9. Antes do primeiro cutover do novo engine Rádio será executado o Core Compatibility Gate.

## Engine Rádio

A Engenharia Rádio aceita:

```text
RADIO ENGINE CURRENT   = FFmpeg legado
RADIO ENGINE CANDIDATE = Liquidsoap 2.4.x
RADIO ENGINE SELECTED  = somente após laboratório, benchmark e gates
```

O compromisso arquitetural é com `RadioEngineAdapter`, não com Liquidsoap por decreto.

## Live Rádio — decisão ainda não congelada

O contrato está aceito mesmo com o transporte de live ainda em aberto.

Não será feito hardening definitivo de listeners/binds do MediaMTX antes de medir e definir:

- origem dos encoders/câmeras;
- rede local, VPN ou Internet autenticada;
- RTMP, SRT ou outro protocolo;
- autenticação por station;
- política de ACL;
- fallback quando o live cai.

Essa decisão será fechada antes do Core Compatibility Gate e não bloqueia o Health read-only.

## Regra de implementação Rádio-first

A partir desta data, a entrega principal desta frente é deixar as cinco emissoras Radio Studio Sat prontas, estáveis e operacionais.

A Engenharia Rádio pode construir primeiro a fundação compartilhada necessária, mas tudo que for Core deve permanecer neutro e documentado para que a Engenharia TV se integre **sem substituir ou desfazer** componentes previamente validados.

## Resultado

**CHG-003: ACCEPTED pela Engenharia Rádio.**

Com o aceite já existente da Engenharia TV e do Core, o Core Contract v0.1 está apto a fechar o gate de governança e liberar CHG-004 após novo SYNC do `main`.
