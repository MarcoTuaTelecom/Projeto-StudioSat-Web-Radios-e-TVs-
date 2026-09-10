# StudioSat Web — Change Queue

Regra: **uma alteração ativa por vez no host de produção**. Engenharia de TV e Rádio podem preparar artefatos em paralelo, mas mudanças no Core ou no host entram nesta fila.

Protocolo obrigatório: `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`.

Diretriz vigente: `docs/95-conciliacoes/2026-09-10-decisao-in-place-no-containers-country-first.md`.

Handoff TV vigente: `docs/00-core/SHARED_FOUNDATION_HANDOFF_TO_TV_v0.2_IN_PLACE.md`.

Plano Rádio vigente: `docs/10-radio/RADIO_IMPLEMENTATION_PLAN_v1.1_IN_PLACE.md`.

Última evidência Core: `docs/40-stage-reports/CHG-001-2026-09-10-core-preflight.md`.

## Leis atuais

- **IN-PLACE FIRST**: a plataforma atual é a base oficial.
- **NO CONTAINERS / NO VMs**.
- não criar segunda árvore permanente `/srv/studiosat/...`;
- não duplicar MediaMTX, NGINX/TLS, registry ou biblioteca;
- shadow apenas do componente candidato, temporário;
- preservar station IDs, roots e paths públicos quando possível;
- toda mudança com precheck, candidate/backup pequeno, validação e rollback.

## Trilha crítica atual — Rádio-first

| ID | Mudança | Dono | Estado atual | Gate |
|---|---|---|---|---|
| CHG-000 | Freeze operacional + protocolo de coordenação | Core | **IN EFFECT** | manter fora da change ativa |
| CHG-001 | Core preflight somente leitura | Core | **DONE / PASS** | evidência e Stage Report publicados |
| CHG-002 | Channels Registry real | Core | **DONE / PASS** | registry publicado |
| CHG-003 | Core Contract v0.1 | Core + TV + Rádio | **DONE / ACCEPTED** | três domínios aceitos |
| CHG-004 | Health global read-only | Core | **DEFERRED / CANDIDATE PRESERVADO** | não bloqueia Country; poderá ser retomado como health comum |
| CHG-004C | Country Reference Restart — stack atual | Rádio + Core | **READY — PRÓXIMA AÇÃO NO HOST** | precheck Country PASS; restart somente Country; systemd+MediaMTX+HLS+áudio PASS; demais stations sem regressão |
| CHG-005R | Recuperação legado Radio Rock | Rádio + Core | **BLOCKED por CHG-004C** | Rock active + MediaMTX ready + HLS/áudio; causa e correção documentadas |
| CHG-005S | Segurança compartilhada (Samba/firewall) | Core | **DEFERRED / investigação separada** | dependências e GCP/VPC mapeados antes de mutação |
| CHG-006R | Normalização in-place das 5 árvores Rádio | Rádio | BLOCKED | sem mover/duplicar biblioteca; compatibilidade legada preservada |
| CHG-007R | Playlist/atomicidade + canonical/QC Rádio | Rádio | BLOCKED | candidate/current/previous e profile versionado |
| CHG-008A | Country engine candidate — shadow mínimo | Rádio + Core | BLOCKED | usa mídia existente; nenhum segundo Core; candidate aprovado |
| CHG-008B | Country A/V + áudio-only + timeline | Rádio | BLOCKED | dual rendition e current event aprovados |
| CHG-009A | Country fallback/metadata/failure tests | Rádio | BLOCKED | falhas controladas sem impacto externo |
| CHG-009B | Country live locutor/câmera | Rádio + Core | BLOCKED | ingress/auth/ACL/fallback aprovados |
| CHG-009C | Country shadow ≥24h | Rádio | BLOCKED | estabilidade + métricas |
| CHG-010 | Core Compatibility Gate | Core + Rádio + TV | BLOCKED | shared Core compatível com os dois domínios |
| CHG-011 | Country cutover | Rádio + Core | BLOCKED | troca somente do componente necessário + rollback |
| CHG-012 | Pop migration | Rádio + Core | BLOCKED | station própria aprovada |
| CHG-013 | Clássicas migration | Rádio + Core | BLOCKED | station própria aprovada |
| CHG-014 | Rock migration | Rádio + Core | BLOCKED | station própria aprovada |
| CHG-015 | Principal migration | Rádio + Core | BLOCKED | exceção de gerador resolvida |

## Trilha TV — responsabilidade da Engenharia TV

A vertical TV não é implementada pela Engenharia Rádio. A Engenharia TV herda `IN-PLACE FIRST`, `NO CONTAINERS/VMs`, Core único e Change Queue única.

| ID | Mudança | Dono | Estado atual | Gate |
|---|---|---|---|---|
| CHG-TV-* | TVKIDS/TVTEENS/TVVIVA/TVMAISJOVEM | TV + Core quando compartilhado | **TV-OWNED** | seguir handoff v0.2; não substituir Core; uma change no host por vez |

## Interlocks ativos

1. Não reiniciar MediaMTX ou NGINX para testar Country.
2. `CHG-004C` reinicia somente `tps-radiocountry-playout.service` após precheck.
3. Country era active/ready no baseline; restart é teste controlado de resiliência da stack, não correção de incidente.
4. Radio Rock continua incidente separado e será tratada depois do PASS Country.
5. Não reiniciar TVs por modernização a partir da frente Rádio.
6. MediaMTX não deve ser endurecido antes de mapear ingress/live e firewall de nuvem.
7. Nenhum componente Core criado pela Rádio pode exigir retrabalho da TV; seguir handoff v0.2.
8. Sem containers/VMs. Se um engine candidato exigir dependências perigosas para o host, ele é rejeitado ou substituído por outra abordagem.

## Estados permitidos

```text
DRAFT
BLOCKED
READY
EXECUTING
VERIFYING
PASS
FAIL
ROLLED_BACK
DONE
DEFERRED
```

Apenas uma change pode estar em `EXECUTING` no host de produção.

## Regra de documentação

Toda mudança registra objetivo, baseline commit, arquivos/hashes, precheck, candidate/backup, responsável, comandos planejados e executados, validação antes/depois, métricas, correções, scripts finais, rollback, resultado, timestamps e Stage Report sanitizado.

Depois de VERIFYING, uma change só vira DONE quando Stage Report e artefatos finais estiverem publicados e o `main` tiver sido relido novamente.
