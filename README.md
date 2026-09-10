# Projeto StudioSat Web — Rádios e TVs

Repositório mestre do projeto **StudioSat Web**, reunindo a arquitetura comum da plataforma, os domínios de **Radio Studio Sat** e **Televisão**, os runbooks de implantação, a Change Queue, os relatórios de etapa e os scripts aprovados.

## Estado atual

A plataforma existente possui 9 canais configurados: 5 rádios e 4 TVs. O estado HEALTHY de cada canal deve ser confirmado pelo preflight/health atual; não é presumido.

Regra de evolução:

> **Não reconstruir por cima da produção. Construir ao lado, provar em laboratório, migrar uma emissora por vez e manter rollback imediato.**

## Hierarquia documental

- `docs/00-core/` — arquitetura, CORE CONTRACT e escopo da Engenharia Core.
- `docs/10-radio/` — documentação e runbook específico da Radio Studio Sat.
- `docs/20-tv/` — documentação e escopo específico da Engenharia de TV.
- `docs/30-execucao/` — runbook mestre, Change Queue e protocolo rigoroso de execução/sincronização.
- `docs/40-stage-reports/` — registro do que **realmente aconteceu** em cada etapa.
- `docs/90-evidencias/` — relatórios técnicos e evidências sanitizadas de baseline.
- `docs/95-conciliacoes/` — propostas, revisões e acordos entre Core, Rádio e TV.
- `registry/` — contrato/registro das stations.
- `scripts/` — versão canônica dos scripts aprovados pelo projeto.

## Documentos normativos de coordenação

1. `docs/00-core/CORE_CONTRACT_v0.1.md`
2. `docs/00-core/CORE_ENGINEERING_SCOPE_v0.1.md`
3. `docs/20-tv/TV_ENGINEERING_SCOPE_v0.1.md`
4. `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`
5. `docs/30-execucao/CHANGE_QUEUE.md`

Antes de cada etapa, todos os responsáveis devem reler o `main` atual e verificar mudanças do outro domínio. Depois de cada etapa, scripts finais, correções, validações e Stage Report precisam ser publicados antes de liberar a próxima.

## Regra de autoridade

### Core StudioSat Web
Responsável por MediaMTX, NGINX/TLS, nomenclatura, channels-registry, contratos de health/eventos, política systemd/slices globais, segurança, ingress/ACL, backup/rollback global, observabilidade, Change Queue e compatibilidade entre domínios.

### Domínio Rádio
Responsável por timeline de rádio, A/V + áudio-only, live de locutor/câmera, metadata, fallback, profile canônico de rádio e engine via `RadioEngineAdapter`.

### Domínio TV
Responsável por canonical/QC de TV, continuidade A/V, playlist/scheduler, DTS/timebase, filler, live de TV e engine via `TvEngineAdapter`.

**O Core é comum. Os motores não são.**

## Disciplina de trabalho

```text
PARALELISMO DE ENGENHARIA = SIM
PARALELISMO DE ALTERAÇÃO DO HOST = NÃO
```

TV e Rádio podem preparar candidates, profiles, testes e documentação simultaneamente. Apenas uma Change pode estar em `EXECUTING` no host de produção.

Para mudanças executáveis, o fluxo recomendado é:

```text
chg/CHG-XXX-descricao
→ candidate
→ revisão
→ execução controlada
→ resultado real + correções na branch
→ Stage Report
→ merge em main
→ próxima Change
```

## Ordem operacional atual

1. Freeze operacional e snapshot/backup.
2. `CHG-001` — Core preflight somente leitura.
3. Rebaseline e `channels-registry` real dos 9 canais.
4. Fechamento conjunto do `CORE CONTRACT v0.1` e health envelope.
5. Resolver apenas incidentes P0 existentes.
6. TVKIDS canonical/TVLAB, cutover controlado e observação.
7. Radio Country LAB: A/V + áudio-only + fallback + live + shadow.
8. Core Compatibility Gate para MediaMTX/NGINX/ingress/auth/health/naming.
9. Cutover Country.
10. Migrar rádios e TVs restantes, uma emissora por vez.
11. Control Plane funcional.
12. CDN/HA e retirada gradual do legado.

A `docs/30-execucao/CHANGE_QUEUE.md` é a fonte de verdade do estado de cada change.

## Scripts e correções

Um script que foi corrigido no servidor não pode permanecer apenas no servidor. A versão que efetivamente funcionou deve ser trazida para `scripts/` antes da etapa seguinte, acompanhada de:

- motivo da correção;
- validação;
- versão/hash anterior e novo quando disponível;
- Stage Report correspondente;
- rollback conhecido.

## Segurança

Este repositório é público. Não versionar:

- senhas, tokens, stream keys ou chaves privadas;
- backups privados do servidor;
- dumps com credenciais;
- arquivos `.env` reais;
- configurações não redigidas contendo segredos;
- pacotes brutos de preflight que possam expor topologia/segredos.

Preflights completos são tratados como evidência privada. O GitHub recebe somente achados sanitizados e os scripts/documentos aprovados.

## Próxima ação prática

A próxima mudança autorizada é `CHG-001 — Core preflight somente leitura`.

Executar `scripts/studiosat-core-preflight.sh` no servidor somente após confirmar snapshot/backup. Depois, enviar o `.tar.gz` e `.sha256` em canal privado para análise. **Não publicar o pacote bruto neste repositório público.**
