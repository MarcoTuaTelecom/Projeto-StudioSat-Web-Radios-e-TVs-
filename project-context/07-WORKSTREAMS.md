# Workstreams canônicos — Studio Sat

Cada workstream corresponde a uma frente persistente do projeto e pode ter várias conversas sucessivas no ChatGPT.

| ID | Responsabilidade | Repositório principal | Pode consultar | Não deve absorver |
|---|---|---|---|---|
| `MASTER-COORD` | coordenação, dependências, prioridades, decisões globais | Projeto-StudioSat-Web-Radios-e-TVs- | todos | implementação detalhada de cada módulo |
| `RADIOBOSS-NS1` | autoridade RadioBOSS, ingest, mirror, snapshots, playout, scheduler, failover NS1 | Projeto-StudioSat-Web-Radios-e-TVs- | Mobile/Portal quando houver contrato | frontend/mobile |
| `STREAMING-CORE` | MediaMTX, Nginx, HLS, TLS, publishers, health | Projeto-StudioSat-Web-Radios-e-TVs- | Portal | regras editoriais RadioBOSS |
| `FAILOVER-SELECTOR` | selector, prioridades, RadioBOSS/OBS/NS1, cutover/rollback | Projeto-StudioSat-Web-Radios-e-TVs- | RADIOBOSS-NS1, STREAMING-CORE | UI/app |
| `PORTAL-CMS` | backend, admin, API, conteúdo persistente, uploads | portal | Core para deploy | app nativo |
| `PORTAL-WEB` | portal público, UX, player web e integração de conteúdo | portal | PORTAL-CMS, STREAMING-CORE | operação NS1 |
| `MOBILE-APP` | Expo/React Native, player, UI, metadata, favoritos | Radio-Studio-Sat-Mobile-App | Portal API, Streaming | Nginx/MediaMTX/NS1 |
| `MOBILE-RELEASE` | EAS, Android/iOS, versionamento, artefatos, lojas | Radio-Studio-Sat-Mobile-App | Portal para links públicos | recuperação do servidor |
| `TV-CORE` | engenharia TV e integração com Core comum | Projeto-StudioSat-Web-Radios-e-TVs- | STREAMING-CORE | regras específicas do app rádio |
| `OBS-LIVE` | live, locutor/câmera, OBS e entrada prioritária | Projeto-StudioSat-Web-Radios-e-TVs- | FAILOVER-SELECTOR | CMS/mobile |
| `OBSERVABILITY` | health, logs, métricas, alertas, auditoria | Projeto-StudioSat-Web-Radios-e-TVs- | todos | regras de produto |
| `PRODUCAO-AUDIO` | chamadas, vinhetas, jingles, identidade sonora | repositório próprio quando criado | Portal/Mobile para publicação | infraestrutura Core |

## Ciclos

Quando uma conversa ficar lenta, **não crie outro workstream**. Abra um novo ciclo do mesmo ID.

Exemplo:

```text
RADIOBOSS-NS1 / C01
RADIOBOSS-NS1 / C02
RADIOBOSS-NS1 / C03
```

Todos leem e atualizam:

`project-context/chats/active/RADIOBOSS-NS1.md`

## Dependências

Uma frente não deve bloquear as demais apenas por compartilhar o projeto. Dependências reais devem ser descritas explicitamente no MASTER.

Exemplo:

`MOBILE-APP` depende do contrato público de `PORTAL-CMS`, mas não precisa conhecer a implementação interna do CMS.

`PORTAL-WEB` depende dos HLS publicados por `STREAMING-CORE`, mas não deve reconfigurar MediaMTX para corrigir um problema visual.
