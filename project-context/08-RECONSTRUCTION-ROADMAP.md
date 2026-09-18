# Roadmap de reconstrução/reorganização — Studio Sat

## Princípio

Não haverá uma reescrita big-bang. A reconstrução é incremental, lado a lado, com compatibilidade e rollback.

## Etapa 0 — Contexto e coordenação

**Workstream:** `MASTER-COORD`

Objetivos:

- consolidar os três repositórios;
- manter MASTER, decisões e próximos passos;
- definir responsabilidades;
- instalar Chat Bridge;
- registrar dependências entre frentes.

Critério de saída:

- qualquer nova conversa consegue continuar um módulo lendo GitHub, sem depender do histórico de uma aba antiga.

## Etapa 1 — Inventário e classificação do Core histórico

**Workstreams:** `MASTER-COORD`, `OBSERVABILITY`

Objetivos:

- classificar `candidates/` em: promovido, obsoleto, laboratório, referência histórica;
- classificar `scripts/` em: canônico, diagnóstico, recuperação, legado;
- reconciliar `registry/` com o estado real;
- preservar Stage Reports/evidências como histórico imutável.

Critério de saída:

- cada script/configuração tem dono, status e destino claros.

## Etapa 2 — RadioBOSS → NS1

**Workstream:** `RADIOBOSS-NS1`

Objetivos:

- consolidar autoridade editorial RadioBOSS;
- snapshots playlist/schedule/librarymanifest;
- materialização/indexação de mídia;
- runtime/mirror/controller;
- scheduler/hora certa;
- shadow playout.

Critério de saída:

- NS1 consegue manter continuidade comprovada a partir do mirror sem depender do chat ou de artefatos temporários.

## Etapa 3 — Streaming Core

**Workstream:** `STREAMING-CORE`

Objetivos:

- consolidar MediaMTX, Nginx, HLS, TLS e health;
- definir publishers/paths canônicos;
- separar infraestrutura pública de lógica editorial.

Critério de saída:

- os contratos públicos de streaming são estáveis e observáveis.

## Etapa 4 — Failover e live

**Workstreams:** `FAILOVER-SELECTOR`, `OBS-LIVE`

Objetivos:

- modelar prioridades RadioBOSS / OBS-live / NS1;
- separar selector legado do mirror;
- criar shadow, cutover e rollback verificáveis.

Critério de saída:

- falha e retorno podem ser simulados/testados sem alterar manualmente múltiplas camadas.

## Etapa 5 — Portal/CMS/API

**Workstreams:** `PORTAL-CMS`, `PORTAL-WEB`

Repositório: `MarcoTuaTelecom/portal`

Objetivos:

- manter portal/CMS isolados do Core;
- formalizar schema/versionamento da API;
- robustecer sessão/autenticação e uploads;
- separar frontend público de administração;
- manter conteúdo persistente fora do deploy.

Critério de saída:

- Mobile e Web consomem contrato público estável sem conhecer a implementação interna do CMS.

## Etapa 6 — Mobile App

**Workstream:** `MOBILE-APP`

Repositório: `MarcoTuaTelecom/Radio-Studio-Sat-Mobile-App`

Objetivos:

- remover responsabilidades de NS1/infra do repositório;
- quebrar `App.tsx` em hooks/screens/services/componentes;
- centralizar runtime config;
- usar API/contratos canônicos para estações;
- preservar UX e reprodução que já funcionam.

Critério de saída:

- clone limpo consegue validar/buildar app sem root, Nginx, MediaMTX ou `/var/www`.

## Etapa 7 — Releases e distribuição

**Workstream:** `MOBILE-RELEASE`

Objetivos:

- lockfile/build reproduzível;
- EAS profiles;
- versionamento Android/iOS;
- artefatos/releases;
- publicação e página de download desacopladas do servidor Core.

Critério de saída:

- build mobile e deploy de servidor são pipelines independentes.

## Etapa 8 — TV sobre o Core compartilhado

**Workstream:** `TV-CORE`

Objetivos:

- preservar motores específicos de TV;
- reutilizar somente contratos realmente comuns;
- impedir que mudanças Rádio quebrem TV e vice-versa.

Critério de saída:

- compatibilidade Core validada por contratos e gates.

## Etapa 9 — Observabilidade e operação contínua

**Workstream:** `OBSERVABILITY`

Objetivos:

- health/readiness;
- logs e relatórios sanitizados;
- checks por estação;
- baseline crítico;
- alertas e runbooks.

Critério de saída:

- diagnóstico operacional não depende de lembrar comandos de uma conversa antiga.

## Política de chats

Cada etapa acima pode ter vários ciclos de conversa.

Exemplo:

```text
RADIOBOSS-NS1 / C01 — baseline e mirror
RADIOBOSS-NS1 / C02 — materialização
RADIOBOSS-NS1 / C03 — scheduler/hora certa
RADIOBOSS-NS1 / C04 — shadow e handoff para selector
```

Todos continuam o mesmo arquivo ACTIVE e não duplicam o projeto.
