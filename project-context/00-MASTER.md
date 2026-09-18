# Studio Sat — MASTER do projeto

> Fonte rápida de contexto para engenharia e novos chats. Este arquivo descreve arquitetura, autoridade e prioridades. O estado operacional de produção deve ser reconfirmado por health checks antes de qualquer mudança.

**Auditoria de referência:** 2026-09-17

## 1. Produto

A plataforma Studio Sat é composta por cinco rádios independentes:

- `radioprincipal`
- `radiopop`
- `radiorock`
- `radioclassicas`
- `radiocountry`

A fundação compartilhada também deve permanecer compatível com os canais de TV já documentados neste repositório.

## 2. Repositórios canônicos

### Core / Operações / Coordenação

`MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-`

Responsável por:

- arquitetura comum;
- NS1 / NS2;
- MediaMTX;
- Nginx/TLS compartilhado;
- RadioBOSS / mirror / sincronização;
- observabilidade e health;
- runbooks e Change Queue;
- candidatos, rollback e evidências sanitizadas;
- contexto mestre do projeto.

### Portal / CMS / API Web

`MarcoTuaTelecom/portal`

Responsável por:

- portal público;
- CMS/API;
- conteúdo editorial das cinco emissoras;
- painel administrativo;
- configuração de deploy específica do portal;
- integração web com HLS.

### Aplicativo móvel

`MarcoTuaTelecom/Radio-Studio-Sat-Mobile-App`

Responsável por:

- aplicativo Expo/React Native;
- Android/iOS;
- código cliente e componentes do app;
- assets do app;
- configuração EAS;
- build/release específico do aplicativo.

Scripts de recuperação de NS1, Nginx, CMS ou infraestrutura devem migrar progressivamente para o repositório Core e deixar de nascer no repositório móvel.

## 3. Baseline de código auditado

- Core: `462d995428303c74c325fddae66f81de012520bf`
- Mobile: `68294ff93e5fdfa3a59f899db77965c73936e2da`
- Portal: `0a1a979d9bba6f59d0b09ca22ba13be83c8c236c`

Esses hashes são apenas a referência desta auditoria; não substituem `git pull` e a verificação do HEAD atual.

## 4. Endpoints e contrato público

- Portal: `https://www.radio.studiosatweb.com.br`
- Player: `https://radio.studiosatweb.com.br`
- Conteúdo: `https://www.radio.studiosatweb.com.br/api/content`
- Health CMS: `https://www.radio.studiosatweb.com.br/api/health`
- HLS: `https://radio.studiosatweb.com.br/<station-id>/index.m3u8`
- Metadata atual: `https://radio.studiosatweb.com.br/assets/now/<station-id>.json`

## 5. Mobile atual

- Nome: Radio Studio Sat
- Expo SDK: 57
- React Native: 0.86.3
- Package/bundle: `br.com.studiosatweb.radio`
- Versão declarada na auditoria: `1.1.0`
- EAS project configurado no `app.json`.

## 6. Portal atual

Arquitetura observada:

- `index.html` — portal público;
- `admin/index.html` — CMS web;
- `backend/server.py` — API/CMS local;
- `data/content.json` — modelo editorial inicial;
- `deploy/nginx-radio-portal.conf` — rotas web/HLS/API;
- `deploy/studiosat-portal-cms.service` — unidade systemd.

Persistência de produção documentada:

- `/var/lib/studiosat-portal/content.json`
- `/var/lib/studiosat-portal/uploads/`
- `/etc/studiosat-portal/admin.secret`

## 7. Dívida técnica prioritária

1. Separar scripts de infraestrutura que hoje vivem no repositório Mobile.
2. Remover do build Mobile a responsabilidade de publicar diretamente arquivos do Portal.
3. Reduzir duplicação de URLs/configuração entre `app.json`, `stations.ts` e `api.ts`.
4. Adicionar lockfile e builds reprodutíveis ao Mobile antes de trocar CI para `npm ci`.
5. Dividir gradualmente o `App.tsx` em hooks/componentes/telas sem mudar o comportamento primeiro.
6. Adicionar CI e testes mínimos ao Portal.
7. Tornar sessões/autenticação do CMS mais robustas sem quebrar o painel existente.
8. Formalizar schema/versionamento do contrato `/api/content`.
9. Classificar o repositório Core em `canonical`, `candidates`, `legacy` e `project-context`.

## 8. Regra de mudança

**Não reconstruir por cima da produção.**

Para alterações de infraestrutura:

1. observar;
2. registrar baseline;
3. preparar candidate;
4. validar sintaxe/configuração;
5. criar backup/rollback;
6. aplicar uma mudança por vez;
7. executar health pós-mudança;
8. promover para canônico somente após evidência.

## 9. Regra para chats do ChatGPT

Use chats separados por domínio. Um novo chat deve começar lendo, nesta ordem:

1. `project-context/00-MASTER.md`;
2. `project-context/02-DECISIONS.md`;
3. `project-context/03-NEXT-STEPS.md`;
4. módulo técnico relevante;
5. último checkpoint/handoff.

Chats são área de trabalho; Git é a fonte permanente.

## 10. Estado operacional

Não inferir o estado atual de NS1/NS2/streams apenas deste arquivo. Antes de executar mudança em produção, atualizar um checkpoint usando health/read-only e registrar o resultado em `project-context/checkpoints/`.


## 11. Rádio Principal — referência mestre atualizada em 2026-09-18

A frente `RADIOPRINCIPAL-NS1` possui dossiê mestre próprio:

`docs/10-radio/RADIOPRINCIPAL-MASTER-DOSSIER-V4.md`

Esse dossiê consolida:
- objetivo detalhado;
- arquitetura atual e alvo;
- histórico C01-C25;
- o que funcionou;
- o que falhou;
- incidentes;
- regras de negócio;
- regras de sistema;
- prioridades;
- gates;
- console do operador;
- automação Windows;
- próximos passos.

Estado resumido da frente:
- RadioBOSS continua autoridade editorial;
- selector público já prioriza RadioBOSS;
- LIVE RadioBOSS/Harbor permanece instável e P1 segue aberto;
- shadow público ainda é legado;
- C22 provou repositório humano incompleto (Manhã 27, Tarde 85, Noite 69);
- C24/C25 estão preparados, mas ainda não devem ser considerados instalados sem evidência;
- Operator Web UI final ainda não está concluído.

Para este workstream, novos chats devem ler o dossiê V4 antes de propor mudanças.
