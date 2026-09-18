# Studio Sat — Próximos passos

## PRIORIDADE ATUAL — Rádio Principal / RadioBOSS / NS1

A sequência abaixo tem precedência operacional sobre as fases genéricas deste arquivo enquanto o workstream `RADIOPRINCIPAL-NS1` estiver em recuperação/reconstrução.

- [x] P0 — formalizar no-downtime e proteger produção.
- [ ] P1 — estabilizar LIVE RadioBOSS -> túnel -> Harbor 18005 e provar soak sem microflap.
- [ ] P2 — construir Canonical Effective Queue com MP3 + itens virtuais + scheduler.
- [ ] P3 — instalar/validar edge bridge C24 e agente automático Windows C25.
- [ ] P3 — provar missing -> upload -> SHA256 -> READY em <=5s para current/next.
- [ ] P4 — instalar/validar shadow V2 somente em `radioprincipal-v2-shadow`.
- [ ] P5 — implementar e validar hora certa, temperatura, comerciais, vinhetas e scheduler.
- [ ] P6 — construir Operator API final.
- [ ] P6 — construir Operator Web UI.
- [ ] P6 — implementar login, usuários, senha, MFA, RBAC.
- [ ] P6 — implementar Transfer Manager, audit log e relatórios.
- [ ] P7 — construir selector V2 com anti-flap em path de teste.
- [ ] P8 — executar soak/comparação por horas/dias.
- [ ] P9 — cutover controlado, somente com todos os gates aprovados.
- [ ] P10 — classificar/remover legado somente após estabilidade comprovada.

Referência obrigatória:
`docs/10-radio/RADIOPRINCIPAL-MASTER-DOSSIER-V4.md`


## Fase 1 — Contexto e limites de responsabilidade

- [x] Criar MASTER do projeto.
- [x] Definir arquitetura canônica dos repositórios.
- [x] Registrar decisões iniciais.
- [ ] Adicionar documentos de escopo ao Mobile e Portal.
- [ ] Abrir PRs separados, sem alteração de produção.

## Fase 2 — Inventário e classificação

### Mobile

Classificar `scripts/` em:

- manter no Mobile: build/release/assets;
- migrar para Core: NS1, recovery, Nginx/HLS, portal operational deploy;
- revisar: scripts universais que misturam as duas responsabilidades.

### Portal

Classificar:

- frontend público;
- player/PWA futuro;
- CMS/admin;
- deploy específico do portal;
- contratos de API.

### Core

Classificar scripts em:

- canonical;
- candidate;
- recovery;
- legacy.

## Fase 3 — Migração de scripts Mobile -> Core

Executar por lote pequeno.

Primeiros candidatos identificados para migração/revisão:

- `ns1-all-in-one.sh`
- `ns1-emergency-recover.sh`
- `ns1-menos1-pre-xray.sh`
- `rebuild-final-ns1.sh`
- `restore-ns1-cleanroom-foundation-20260905.sh`
- `recover-tvteens-round2.sh`
- `fix-hls-cors.sh`
- `fix-universal-routing.sh`
- scripts de publicação que escrevem diretamente no portal.

Não apagar do Mobile na primeira cópia.

## Fase 4 — Build Mobile reprodutível

- gerar/validar `package-lock.json`;
- trocar CI para `npm ci`;
- separar build de publicação no portal;
- manter EAS como pipeline do app;
- consolidar versão em processo único;
- adicionar validação de configuração.

## Fase 5 — Configuração e contrato Mobile

- centralizar base URLs;
- criar camada `src/config/runtime.ts`;
- usar `/api/content` como fonte preferencial de dados das emissoras;
- manter cinco defaults locais como fallback;
- versionar o contrato da API.

## Fase 6 — Refatoração do App

Sem redesenhar primeiro:

- extrair `useRadioPlayer`;
- extrair `useNowPlaying`;
- extrair `useStationContent`;
- separar telas/sheets;
- manter componentes de apresentação menores;
- adicionar persistência de preferências/favoritos se desejado;
- adicionar testes de funções puras e normalização de API.

## Fase 7 — Portal

- adicionar CI para Python/JSON/configurações;
- adicionar testes do contrato `/api/content` e autenticação;
- versionar schema do conteúdo;
- revisar sessões do CMS para sobreviver a restart se necessário;
- validar uploads por conteúdo além de `Content-Type`;
- revisar headers de segurança;
- preservar persistência em `/var/lib/studiosat-portal`.

## Fase 8 — Web/PWA

- identificar exatamente o que está publicado em `radio.studiosatweb.com.br`;
- comparar com `web/pwa` do Mobile;
- migrar ao Portal apenas com deploy paralelo e rollback;
- mover página de download para o domínio web correspondente.

## Fase 9 — Chat/Context workflow

Para cada frente:

- um chat por domínio;
- checkpoint ao final de uma mudança real;
- handoff ao trocar de chat;
- atualizar MASTER somente com estado confirmado.
