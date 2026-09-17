# Studio Sat — Reconstrução dos Repositórios v2

## Objetivo

Reconstruir a organização técnica do Studio Sat sem reescrever a produção de uma só vez, preservando histórico, rollback e contratos já validados.

A reconstrução separa claramente três responsabilidades:

1. **Master/Core/OPS** — infraestrutura, arquitetura, execução, RadioBOSS/NS1, streaming, failover, TV, observabilidade e coordenação.
2. **Portal** — portal público, CMS, API, painel administrativo e conteúdo editorial.
3. **Mobile** — aplicativo Expo/React Native, Android/iOS, player móvel e releases.

## Repositórios canônicos

### 1. Master / Core / OPS

`MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-`

Responsável por:

- arquitetura global;
- NS1/NS2;
- RadioBOSS mirror/snapshots/playout;
- MediaMTX;
- Nginx/TLS;
- HLS;
- failover/selector;
- OBS/live;
- health/observabilidade;
- TV;
- Change Queue;
- registry;
- Stage Reports;
- evidências sanitizadas;
- documentação mestre;
- contexto persistente dos chats.

### 2. Portal

`MarcoTuaTelecom/portal`

Responsável por:

- portal público;
- CMS/API;
- painel `/admin`;
- conteúdo das cinco emissoras;
- uploads;
- frontend web;
- configuração de deploy específica do Portal.

O Portal não deve conter lógica de mirror RadioBOSS, selector, recuperação geral do NS1 ou build mobile.

### 3. Mobile

`MarcoTuaTelecom/Radio-Studio-Sat-Mobile-App`

Responsável por:

- Expo/React Native;
- Android/iOS;
- player móvel;
- metadata;
- UI/UX;
- favoritos;
- EAS;
- assets;
- build/release do aplicativo.

O Mobile não deve ser o repositório de scripts de NS1, Nginx, MediaMTX, recuperação do Portal ou TV.

## Regra fundamental

**Não reconstruir por cima da produção.**

Toda migração deve seguir:

`inventariar -> classificar -> copiar -> validar -> promover -> retirar duplicata`

Nunca:

`apagar -> descobrir depois`

## Estrutura alvo do repositório Master

```text
Projeto-StudioSat-Web-Radios-e-TVs-/
├── project-context/
│   ├── 00-MASTER.md
│   ├── 01-ARCHITECTURE.md
│   ├── 02-DECISIONS.md
│   ├── 03-NEXT-STEPS.md
│   ├── 04-REPOSITORIES.md
│   ├── 06-CHAT-BRIDGE.md
│   ├── 07-WORKSTREAMS.md
│   ├── 08-RECONSTRUCTION-ROADMAP.md
│   ├── chats/
│   │   ├── ACTIVE-TEMPLATE.md
│   │   └── active/
│   ├── checkpoints/
│   └── generated/
│
├── docs/
│   ├── 00-core/
│   ├── 10-radio/
│   ├── 20-tv/
│   ├── 30-execucao/
│   ├── 40-stage-reports/
│   ├── 90-evidencias/
│   └── 95-conciliacoes/
│
├── registry/
│
├── scripts/
│   ├── context/
│   ├── health/
│   ├── ns1/
│   ├── radioboss/
│   ├── streaming/
│   ├── failover/
│   ├── recovery/
│   └── tv/
│
├── candidates/
└── README.md
```

A estrutura física dos scripts será migrada progressivamente. A existência desta documentação não autoriza mover ou apagar scripts de produção sem validação.

## Classificação obrigatória dos artefatos

Todo script/configuração deverá receber um estado:

- `CANONICAL` — versão oficial em uso.
- `PROMOTED` — candidate aprovado e promovido.
- `DIAGNOSTIC` — somente leitura/diagnóstico.
- `RECOVERY` — recuperação/rollback.
- `LAB` — experimento controlado.
- `LEGACY` — ainda pode existir por compatibilidade.
- `HISTORICAL` — mantido como evidência/histórico.
- `OBSOLETE` — substituído, não usar.

Artefatos `OBSOLETE` não devem ser apagados no mesmo commit em que recebem essa classificação.

## Ordem da reconstrução

### Fase 0 — Contexto

Criar MASTER, decisões, workstreams, Chat Bridge, checkpoints e handoffs.

### Fase 1 — Inventário Core

Classificar `candidates/`, `scripts/`, `registry/` e Stage Reports.

### Fase 2 — Rádio Principal / RadioBOSS / NS1

Consolidar:

- autoridade editorial RadioBOSS;
- snapshots `playlist`, `schedule`, `librarymanifest`;
- bridge de playback;
- mirror/controller/runtime;
- materialização de mídia;
- scheduler/hora certa;
- shadow playout.

### Fase 3 — Streaming

Consolidar MediaMTX, Nginx, HLS, TLS, publishers e health.

### Fase 4 — Failover/live

Separar mirror de selector/failover e integrar RadioBOSS, NS1 e OBS/live com prioridades claras.

### Fase 5 — Portal

Formalizar contrato da API, CMS, admin, persistência e frontend público.

### Fase 6 — Mobile

Retirar responsabilidades de servidor do Mobile e modularizar o app.

### Fase 7 — Releases

Separar pipeline EAS/mobile do deploy dos servidores.

### Fase 8 — TV

Usar somente contratos realmente compartilhados do Core.

### Fase 9 — Observabilidade

Health, logs, baseline, alertas e runbooks independentes das conversas do ChatGPT.

## Política de alteração

Cada alteração deve registrar:

- workstream;
- objetivo;
- estado anterior;
- mudança aplicada;
- validação;
- rollback;
- branch/commit;
- resultado;
- próximo passo.

## ChatGPT como área de trabalho, não banco de dados

Cada conversa trabalha em um único `WORKSTREAM_ID`.

Quando uma conversa ficar lenta, ela é encerrada com handoff e um novo ciclo é criado.

Exemplo:

```text
RÁDIO PRINCIPAL — RadioBOSS → NS1 — C01
RÁDIO PRINCIPAL — RadioBOSS → NS1 — C02
RÁDIO PRINCIPAL — RadioBOSS → NS1 — C03
```

O estado persistente permanece no GitHub.

## Critério final de sucesso

A reconstrução estará concluída quando:

- cada responsabilidade tiver um único repositório canônico;
- scripts ativos tiverem status e dono claros;
- Portal/Mobile não carregarem responsabilidades de Core indevidas;
- deploy mobile e deploy servidor forem independentes;
- RadioBOSS/NS1/Streaming/Failover tiverem contratos claros;
- qualquer novo chat conseguir continuar uma etapa apenas lendo o GitHub e o ACTIVE STATE correspondente.
