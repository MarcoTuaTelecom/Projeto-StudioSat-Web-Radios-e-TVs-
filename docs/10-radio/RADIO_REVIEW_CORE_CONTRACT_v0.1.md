# CHG-003 — Revisão da Engenharia Rádio — CORE CONTRACT v0.1

Status: **REVIEW REQUIRED — BLOQUEIA CHG-004 EXECUTÁVEL**

## Objetivo

Obter concordância explícita da Engenharia de Rádio com a linguagem e as fronteiras comuns da plataforma antes de executar novos componentes compartilhados ou iniciar o Country LAB.

A Engenharia de TV já registrou aceite no acordo `docs/95-conciliacoes/2026-09-10-acordo-tv-radio-core.md`.

## O que NÃO está sendo pedido

Não é pedido que a Engenharia de Rádio:

- aceite Liquidsoap como engine definitivo;
- adote scheduler, canonical, filler ou continuidade de TV;
- entregue sua implementação agora;
- altere o host;
- reinicie Radio Rock;
- instale pacote.

Liquidsoap permanece apenas `RADIO ENGINE CANDIDATE`.

## O que precisa ser aceito, contestado ou corrigido

### 1. Identidade comum

Cada estação expõe ao Core:

```text
station_id
station_class
engine_adapter
canonical_profile/profile_version
publish_path/public_urls/lab_paths
health_schema_version
plan_version
```

### 2. RadioEngineAdapter

O contrato exige capacidades, não uma implementação específica:

```text
programação/timeline
current event
AUTO/LIVE/FALLBACK
A/V + audio-only derivados da mesma timeline
live entra/sai sem restart do engine
metadata
health
rollback
```

### 3. Ownership

Core é dono de:

```text
MediaMTX
NGINX/TLS
ports/naming
channels-registry
schemas comuns
systemd/slices globais
ingress/auth/ACL
observabilidade
backup/rollback global
Change Queue
```

Rádio é dona de:

```text
timeline Radio
engine Radio
A/V + audio-only
live locutor/câmera
metadata Radio
fallback Radio
canonical Radio
```

### 4. NON-MERGE RULES

A Rádio não será forçada a usar semântica de TV:

```text
TV scheduler         != Radio scheduler
TV continuity        != Radio music clock
TV filler            != Radio fallback
TV live              != Radio locutor/live
TV canonical         != Radio canonical
TV output model      != Radio dual rendition
TV transition model  != Radio switch/fade/live
```

### 5. Regra operacional

```text
Paralelismo de engenharia: SIM
Paralelismo de alteração do host: NÃO
```

Uma única Change pode modificar o host por vez.

### 6. Core Compatibility Gate

Antes do primeiro cutover do novo engine Radio, Core + Rádio + TV revisarão:

- MediaMTX;
- NGINX;
- ingress local/remoto;
- autenticação/ACL;
- naming;
- health;
- rollback.

### 7. Questão ainda aberta para Rádio

A Engenharia de Rádio deve declarar como o live de locutor/câmera chegará ao Media Plane:

- encoder no mesmo host;
- rede privada/VPN;
- Internet pública autenticada;
- RTMP;
- SRT;
- outro protocolo.

Essa resposta é necessária antes de o Core reduzir listeners/binds do MediaMTX.

## Novo fato de produção que Rádio precisa conhecer

CHG-001 confirmou:

- radioprincipal, radiopop, radioclassicas e radiocountry: systemd active + MediaMTX ready;
- radiorock: systemd failed + MediaMTX not ready;
- rádio atual publica MPEG-1/2 Audio por FFmpeg `-c:a copy`;
- `ready/` observado é predominantemente MP3;
- `radioprincipal` possui gerador especial via drop-in;
- Liquidsoap não está instalado no host;
- não instalar nada até change autorizada.

Detalhes sanitizados: `docs/40-stage-reports/CHG-001-2026-09-10-core-preflight.md`.

## Forma esperada da resposta da Engenharia Rádio

Publicar um documento, por exemplo:

```text
docs/10-radio/RADIO_ACCEPTANCE_CORE_CONTRACT_v0.1.md
```

com:

```text
ACCEPTED
```

ou uma lista curta e objetiva de cláusulas `CHANGE_REQUESTED`, com proposta alternativa e justificativa técnica.

Após a resposta, o Core relerá `main`, reconciliará eventuais diferenças e atualizará CHG-003. Somente depois CHG-004 poderá mudar de BLOCKED para READY.
