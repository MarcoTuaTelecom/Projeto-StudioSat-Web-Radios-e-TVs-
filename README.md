# Projeto StudioSat Web — Rádios e TVs

Repositório mestre do projeto **StudioSat Web**, reunindo a arquitetura comum da plataforma, os domínios de **Radio Studio Sat** e **Televisão**, os runbooks de implantação e os scripts de diagnóstico.

## Estado atual

A plataforma existente já opera com 9 canais configurados: 5 rádios e 4 TVs. A regra de evolução é:

> **Não reconstruir por cima da produção. Construir ao lado, provar em laboratório, migrar uma emissora por vez e manter rollback imediato.**

## Hierarquia documental

- `docs/00-core/` — arquitetura e governança compartilhada do StudioSat Web.
- `docs/10-radio/` — documentação e runbook específico da Radio Studio Sat.
- `docs/20-tv/` — documentação e runbook específico das emissoras de TV, começando pela TVKIDS.
- `docs/30-execucao/` — runbook mestre da sequência operacional a partir do servidor já em produção.
- `docs/90-evidencias/` — relatórios técnicos e evidências de baseline.
- `docs/95-conciliacoes/` — propostas e revisões de conciliação entre Core, Rádio e TV.
- `scripts/` — ferramentas de preflight/diagnóstico sem alteração de produção.

## Regra de autoridade

### Core StudioSat Web
Responsável por componentes compartilhados: MediaMTX, NGINX/TLS, nomenclatura, channels-registry, contratos de health/eventos, política systemd, segurança, backup/rollback, observabilidade e integração.

### Domínio Rádio
Responsável por timeline de rádio, A/V + áudio-only, live de locutor/câmera, metadata, fallback, profile canônico de rádio e engine via `RadioEngineAdapter`.

### Domínio TV
Responsável por canonical/QC de TV, continuidade A/V, playlist/scheduler, DTS/timebase, filler, live de TV e engine via `TvEngineAdapter`.

**O Core é comum. Os motores não são.**

## Ordem operacional atual

1. Freeze operacional e snapshot/backup.
2. Core preflight somente leitura.
3. Rebaseline e `channels-registry` dos 9 canais.
4. `CORE CONTRACT v0.1` + health envelope comum.
5. Resolver apenas incidentes P0 existentes.
6. TVKIDS canonical/TVLAB, cutover controlado e observação.
7. Radio Country LAB: A/V + áudio-only + fallback + live + shadow.
8. Core Compatibility Gate para MediaMTX/NGINX/ingress/auth/health.
9. Cutover Country.
10. Migrar rádios e TVs restantes, uma emissora por vez.
11. Control Plane funcional.
12. CDN/HA e retirada gradual do legado.

## Regra de mudança no host

Engenharia de Rádio e Engenharia de TV podem trabalhar em paralelo em código, documentação e laboratório preparado, mas **as alterações no host de produção entram em uma fila única de mudanças**. Nenhum domínio altera isoladamente componentes classificados como Core.

## Segurança

Este repositório é público. Não versionar:

- senhas, tokens, stream keys ou chaves privadas;
- backups privados do servidor;
- dumps com credenciais;
- arquivos `.env` reais;
- configurações não redigidas contendo segredos.

## Próxima ação prática

Executar somente o `scripts/studiosat-core-preflight.sh` no servidor, após snapshot/backup, e analisar o pacote shareable gerado antes de qualquer mudança estrutural.
