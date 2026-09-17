# WORKSTREAM: RADIOPRINCIPAL-NS1

## Identidade

- `WORKSTREAM_ID`: `RADIOPRINCIPAL-NS1`
- Estado: `ACTIVE`
- Repositório principal: `MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-`
- Escopo: continuidade técnica da Rádio Principal entre RadioBOSS, NS1, mirror/playback, shadow e preparação de failover.
- Fora do escopo: Portal/CMS, app móvel, outras emissoras, mudanças globais de TV.

## Objetivo atual

Concluir a engenharia da Rádio Principal de forma verificável, preservando a produção e separando claramente:

- RadioBOSS autoritativo;
- entrada `radioprincipal-rb`;
- shadow NS1 em `radioprincipal-ns1`;
- caminho público `radioprincipal`;
- caminho de ensaio `radioprincipal-test`;
- selector/failover;
- mirror/runtime/playback.

## Estado importado da conversa anterior

> Estes fatos são handoff histórico e devem ser reconfirmados no estado vivo antes de cutover.

- O trabalho recente concentrou-se na Rádio Principal V8 e no fluxo RadioBOSS → NS1.
- O desenho de teste usa RadioBOSS em `radioprincipal-rb`, shadow NS1 em `radioprincipal-ns1`, selector no caminho público e `radioprincipal-test` para ensaio de falha/retorno.
- O RadioBOSS deveria fornecer estado de playback frequente e snapshots editoriais para o mirror.
- O bridge de playback foi desenhado para usar o `radioboss-sync/current/playback.json` como fonte, sem mudanças amplas de permissões, restart global do MediaMTX ou alteração imediata do caminho público.
- Em diagnóstico anterior, ingest/playback/mirror atualizavam, mas o player NS1 ainda estava acoplado a `radioboss-live.json`/`matched_index` em vez do estado de `playback.json`.
- V8 chegou a ser tratada como produção em uma etapa anterior, mas o caminho LIVE apresentou falha posteriormente; qualquer status de produção deve ser reconfirmado antes de novas ações.
- O selector/shadow e Harbor apareceram misturados em parte do histórico; devem ser tratados como responsabilidades separadas na reconstrução.

## Regra desta continuação

A nova conversa não deve tentar reconstituir toda a história do projeto.

Primeiro deve reconfirmar, somente leitura:

1. serviços e timers ativos;
2. paths/publishers da Rádio Principal;
3. fonte atual do playback;
4. estado do mirror/controller/runtime;
5. geração/revisão/idade dos snapshots;
6. disponibilidade/missing de mídia;
7. papel atual de Harbor e selector;
8. diferença entre caminho público, shadow e teste.

## Baseline somente leitura — ciclo C02

### Fontes examinadas

- `XRAY-RADIOPRINCIPAL-NS1-20260916T183344Z.txt`
- `XRAY-RADIOPRINCIPAL-NS1-20260916T192808Z.txt`
- `XRAY-RADIOPRINCIPAL-NS1-V2-20260916T211627Z.txt`
- `STUDIOSAT-FORENSIC-NS1-20260917T023826Z.tar.gz`

A evidência mais recente fornecida foi coletada a partir de `2026-09-17T02:38:26Z`. Ela é posterior aos XRAYs, mas não deve ser tratada como estado vivo no momento de uma futura mudança sem nova reconfirmação read-only.

Nenhuma mudança de produção, cutover, restart global ou alteração destrutiva foi aplicada nesta etapa.

### Classificação comparada ao ACTIVE STATE anterior

| Ponto | Classe | Evidência / interpretação |
|---|---|---|
| RadioBOSS como autoridade editorial/controle | `CONFIRMADO` | `playlist.json`, `schedule.json`, `librarymanifest.json`, `playback.json` e heartbeat continuavam sendo recebidos. No forense mais recente: playlist rev. 489, schedule rev. 8997, librarymanifest rev. 35 e playback em `play`. |
| `radioprincipal-rb` como entrada efetiva de áudio de produção | `MUDOU` | O path MediaMTX `radioprincipal-rb` estava offline. O áudio do RadioBOSS entrava pelo Harbor Liquidsoap local em `127.0.0.1:18005`. |
| Harbor 18005 | `CONFIRMADO` | É a entrada primária do RadioBOSS no selector atual. O selector recebe `input.harbor` e prioriza essa fonte. |
| `radioprincipal-ns1` | `CONFIRMADO` | Online/ready; recebe o playout do `mirror-playout.py` e é lido pelo selector como fallback. |
| `radioprincipal` público | `CONFIRMADO` | Online/ready; é a saída RTMP publicada pelo selector Liquidsoap. |
| `radioprincipal-test` | `CONFIRMADO` | Continua sendo superfície de ensaio. Estava offline no forense; houve publicações temporárias de teste anteriormente. |
| Selector | `CONFIRMADO` | Serviço ativo. Configuração efetiva: `fallback [RadioBOSS/Harbor, NS1 shadow, blank de segurança]` e saída para `radioprincipal`. Houve microtrocas rápidas Harbor→NS1→Harbor, portanto estabilidade deve continuar observada. |
| Bridge `playback.json` | `CONFIRMADO` | `control-bridge-v3.2.py` copia `radioboss-sync/.../playback.json` para `/run/studiosat-radioprincipal-v8-control/playback.json`; XRAY V2 mostrou origem e bridge frescos/coerentes. O serviço seguia ativo no forense. |
| Shadow usando `playback.json` para índice/posição | `PENDENTE` | Ainda não ocorre. `mirror-playout.py` continua lendo `state/radioboss-live.json` e `matched_index`. |
| `radioboss-live.json` / monitor | `CONFIRMADO` | Continua em uso pelo shadow. No forense mais recente estava `connected=true`, porém `matched_index=null`, enquanto o mirror runtime seguia em modo `ns1-continuous`. |
| Mirror controller/timer | `CONFIRMADO` | Timer ativo com ciclo ~30 s e controller one-shot finalizando com sucesso. |
| Idempotência do mirror controller | `PENDENTE` | O controller continuava emitindo `MIRROR_SYNC_CHANGED=SIM` e criando nova geração a cada ~30 s mesmo com 156/156/0 estável. O código inclui hashes dos arquivos-envelope completos de playlist/manifest/schedule na assinatura; esses envelopes mudam por campos de recepção, causando churn de geração mesmo sem mudança editorial equivalente. |
| Mídia disponível/missing | `MUDOU` | XRAY V2 terminou em 158 tracks / 156 disponíveis / 2 missing. No forense a playlist caiu para 156 tracks / 156 disponíveis / 0 missing. `NEW_MEDIA_COPIED=0`; portanto não há evidência de que os missing foram resolvidos por cópia de mídia — a composição da playlist também mudou. |
| `mirror-runtime.json` | `CONFIRMADO` | Estava fresco no forense, geração `rbcanon-20260917T023713Z-dbbfd680ba02`, modo `ns1-continuous`. |
| V8 production runtime | `OBSOLETO` como estado vivo | `v8-production-runtime.json` estava parado desde `2026-09-16T19:11:35Z`, modo `ns1-autonomous`, reason `shutdown`. |
| `studiosat-radioprincipal-v8-production.service` | `OBSOLETO` como caminho de produção atual | Serviço disabled/inactive e configurado para publicar em `radioprincipal-test`, não em `radioprincipal`. Não deve ser reativado como se fosse a produção vigente. |
| `studiosat-radioprincipal-v8-stage.service` | `OBSOLETO` como runtime vivo | Inactive; runtime antigo desde aproximadamente `19:16Z` de 16/09. Pode permanecer como artefato de laboratório/histórico até classificação definitiva. |
| `studiosat-radioprincipal-v8-live-ingress.service` | `OBSOLETO` no fluxo atual | Disabled/inactive. O Harbor em produção pertence hoje ao selector, não a esse ingress V8 separado. |
| `tps-radioprincipal-playout.service` e `tps-radioprincipal-failover.service` | `OBSOLETO` no fluxo atual | Ambos permaneciam masked/inactive. |
| Estado vivo no momento de qualquer próxima mudança | `PENDENTE` | A coleta forense mais recente é evidência histórica de 17/09 02:38 UTC. Antes de editar produção é obrigatório repetir o baseline read-only. |

## Arquitetura efetiva observada na última evidência

```text
RadioBOSS
  ├─ snapshots/controle HTTP -> radioboss-sync/current/{playlist,schedule,librarymanifest,playback,heartbeat}.json
  └─ áudio LIVE -> túnel/Harbor 127.0.0.1:18005
                         |
                         v
                 Liquidsoap selector
                 prioridade 1: Harbor RadioBOSS
                 prioridade 2: RTMP radioprincipal-ns1
                 prioridade 3: blank de segurança
                         |
                         v
                 RTMP radioprincipal (público)

RadioBOSS snapshots -> mirror-controller (timer ~30s)
                         |
                         v
                generations/media-map
                         |
                         v
               mirror-playout.py
       [ainda guiado por radioboss-live/matched_index]
                         |
                         v
              RTMP radioprincipal-ns1
```

O bridge V8 de `playback.json` está operacional, mas não está no loop de controle do shadow atualmente ativo.

## Próximo passo exato comprovado

1. Repetir **agora** um baseline somente leitura equivalente ao XRAY/forense, sem comandos de mudança, para confirmar que a arquitetura acima continua viva.
2. Se o baseline confirmar o mesmo estado, corrigir primeiro a **idempotência/assinatura do mirror-controller** em candidate, sem tocar no selector/Harbor/caminho público. O objetivo é parar gerações sintéticas quando não houve mudança editorial/material real.
3. Validar controller em dry-run/laboratório e confirmar `MIRROR_SYNC_CHANGED=NAO` quando playlist/manifest/schedule semanticamente não mudarem.
4. Depois preparar, também como candidate, a evolução do `mirror-playout.py` para usar `playback.json` como autoridade de índice/posição do shadow, retirando a dependência de `matched_index` como mecanismo principal de sincronismo.
5. Somente após shadow estável e validado reabrir scheduler/hora certa, ensaio de failover e qualquer cutover.

## Fatos que não devem ser reabertos sem nova evidência

- O caminho público observado é `radioprincipal`, publicado pelo selector.
- O shadow observado é `radioprincipal-ns1`.
- O RadioBOSS LIVE observado entra por Harbor `18005`, não pelo path MediaMTX `radioprincipal-rb`.
- `radioprincipal-test` é superfície de ensaio, não produção.
- V8 production/stage não estavam executando como produção na última evidência.
- O bridge de playback existe e funciona, mas o shadow atual ainda não o usa como autoridade de sincronismo.
- O controller apresenta churn de gerações e isso deve ser resolvido antes de tratá-lo como canônico estável.

## Próximo passo exato

O próximo passo operacional permanece **read-only**: gerar uma nova coleta atual e compará-la com este baseline C02. Nenhuma mudança em produção deve ocorrer antes dessa reconfirmação.

## Nome recomendado para a próxima conversa

`RÁDIO PRINCIPAL — RadioBOSS → NS1 — Continuação C02`

## Bootstrap para a nova aba

```text
WORKSTREAM_ID: RADIOPRINCIPAL-NS1

Estou continuando a engenharia da Rádio Principal em uma nova conversa limpa.
Use o repositório mestre e o ACTIVE STATE como fonte persistente.
Não reinicie o projeto.
Não presuma que estados históricos ainda são atuais.
Primeiro reconfirme o baseline vivo somente leitura e continue do próximo passo registrado.
```

## Registro C03 — XRAY canônico e executor reproduzível

Em `2026-09-17` o arquivo `STUDIOSAT-RADIOPRINCIPAL-FULL-XRAY-V2.sh` fornecido pelo operador foi validado localmente com `bash -n`; os 11 blocos Python embutidos também foram compilados sem erro. O corpo funcional foi preservado e recebeu somente o cabeçalho de governança exigido por `scripts/README.md`.

Arquivos registrados na branch `reorg/project-context-v2`:

- `scripts/radioprincipal/STUDIOSAT-RADIOPRINCIPAL-FULL-XRAY-V2.sh`
- `scripts/radioprincipal/RUN-RADIOPRINCIPAL-BASELINE.sh`
- `scripts/radioprincipal/README.md`

Integridade aprovada do XRAY no GitHub:

- Git blob SHA: `5128ecfb411bb4244cac7b383a2fef62bfc68aac`
- commit de inclusão do XRAY: `b01f6b4ff1e93d619aff70f7882eafbfc7310bc8`
- commit do executor: `9ff3fd8d197eb0dbf81352ec97280f5191e7573d`
- commit das instruções de recuperação: `8fbd9f57a91276823be5353dbe8a93c6772104c9`

O executor baixa o XRAY canônico pela API pública do GitHub, compara o blob recebido e o blob calculado localmente com o SHA aprovado, executa `bash -n`, instala a cópia em `/root/STUDIOSAT-RADIOPRINCIPAL-FULL-XRAY-V2.sh` com modo `0700` e só então executa a coleta. Se o XRAY versionado mudar sem atualização explícita do executor, a execução aborta.

Nenhuma mudança de produção foi executada no ciclo C03. O próximo passo continua sendo executar este baseline read-only no NS1 e devolver o relatório atual para comparação com C02.


## Registro C05 — autoridade temporal, snapshots stale e grade futura

Em 2026-09-17, o primeiro candidate de réplica autoritativa importou a playlist recebida com:

- 85 itens;
- 85 assets disponíveis;
- 0 missing;
- 0 unresolved;
- playback apontando para Donna Lewis / próximo Enigma;
- banco SQLite candidate criado com sucesso.

O probe de freshness executado aproximadamente às 19:07 America/Sao_Paulo mostrou que a origem de controle estava stale/offline:

- playlist recebida ~18:20 local;
- schedule recebido ~18:20 local;
- librarymanifest recebido ~18:34 local;
- playback recebido ~17:54 local;
- heartbeat recebido ~18:43 local, `online=false`.

Conclusão: a réplica de mídia estava completa, mas a autoridade temporal não estava fresca. O candidate v0.1 classificava incorretamente esse caso como `HOT_READY`.

Correção C05:

- candidate atualizado para `0.2.0-candidate`;
- Git blob canônico: `16604dd88421950747ad7c66a264b29f8552710c`;
- estados agora separam source freshness, playback freshness, replica completeness e queue alignment;
- estado stale com réplica completa passa a `REPLICA_READY_SOURCE_STALE`, não `HOT_READY`;
- runner atualizado e pinado ao novo blob;
- runner Git blob: `26410b9f108a495f0b2cd2a9e9321b0e14b485fb`;
- probe de grade futura: `scripts/radioprincipal/candidate/PROBE-PROGRAM-GRID.py`;
- probe Git blob: `885ae526f4f65149258d4e5760968605eb876e62`;
- documentação: `docs/10-radio/RADIOPRINCIPAL-RADIOBOSS-NS1-AUTHORITY-REPLICATION-v1.2-GRADE-TEMPORAL.md`.

Regra incorporada: o NS1 não pode manter indefinidamente o último programa recebido. Se a grade previamente sincronizada indicar mudança às 19:00, o NS1 deve executar a nova programação pelo relógio local mesmo com o RadioBOSS desconectado, desde que grade e assets tenham sido previamente validados.

Próximo passo exato: executar somente o probe read-only de grade futura para inspecionar `playlist_definitions` e a estrutura real de `schedule.json`; localizar como programas futuros e transições de horário são representados antes de implementar o executor autônomo.
