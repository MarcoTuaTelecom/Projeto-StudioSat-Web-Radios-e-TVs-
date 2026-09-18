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


## Registro C06 — Noite ativa no RadioBOSS, candidate enxerga grade, produção NS1 ainda legada

Evidência de 2026-09-17 aproximadamente 19:15–19:18 America/Sao_Paulo:

- RadioBOSS local estava com a aba/programação **Noite Studio Sat** ativa.
- UI mostrou 68 faixas da programação noturna.
- Snapshot machine-readable recebido no NS1 continha 69 itens porque havia uma inserção virtual de hora certa `saytime=...` entre faixas.
- Snapshot atual:
  - playlist rev. 938, age ~9,7 s;
  - schedule rev. 19577, age ~0,16 s;
  - playback age ~0,52 s;
  - heartbeat age ~7,8 s, `online=true`;
  - librarymanifest age ~8,6 s.
- Playback atual recebido: Eric Clapton — Change The World; próximo item: `(Time Announcement)`; depois Natalie Imbruglia — Torn.
- Playlist XML atual aponta para `H:\MUSICAS\003 - Noite Na Studio Sat\...`.
- Candidate v0.2 importou 69 itens, porém apenas 7 foram resolvidos como disponíveis; 62 ficaram unresolved/missing pelo modelo de resolução atual.
- `current_ready=false`, `queue_aligned=false`, status `NOT_READY`.
- `librarymanifest.data.playlist_definitions` continha somente uma definição originada do scheduler (`Seg_Sex_0730AS1200.m3u8`), não uma grade completa de programas futuros.
- O schedule atual contém 1 evento e a playlist efetiva recebeu a hora certa como item virtual `SCHEDULE_NP`.

Conclusão arquitetural C06:

1. O canal de controle RadioBOSS -> NS1 está vivo e atual.
2. O RadioBOSS já executa lógica editorial real (mudança Tarde -> Noite, scheduler e hora certa).
3. O candidate consegue observar/importar a playlist efetiva, mas ainda não possui resolução completa de assets nem executor de comandos virtuais como `saytime`.
4. O playout de produção `radioprincipal-ns1` continua sendo o `mirror-playout.py` legado; o candidate não controla produção.
5. Portanto qualquer fallback público para o NS1 ainda pode tocar programação antiga/contínua sem obedecer mudança de programa, hora certa e demais eventos.
6. A próxima etapa deixa de ser apenas “sincronizar playlist”: é construir o **Studio Sat Execution Engine candidate**, capaz de:
   - interpretar a playlist efetiva do RadioBOSS;
   - resolver/canonicalizar assets;
   - executar itens virtuais `saytime`;
   - obedecer schedule e transições de programa;
   - persistir grade futura quando disponível;
   - manter posição/checkpoint;
   - publicar somente em path de teste até passar gates.

Nenhum cutover está autorizado neste estágio.


## Registro C08 — túnel persistente RadioBOSS -> NS1 confirmado

Em 2026-09-17 ~20:09 America/Sao_Paulo, o túnel persistente dedicado do Windows da emissora para o Harbor do NS1 foi validado com sucesso.

Evidências do Windows:
- tarefa agendada `StudioSat-RadioBOSS-NS1-Tunnel` instalada;
- chave privada protegida com ACL exclusiva de `NT AUTHORITY\SYSTEM`;
- `127.0.0.1:18005` em estado `Listen`;
- `Test-NetConnection 127.0.0.1 -Port 18005` retornou `TcpTestSucceeded=True`;
- watchdog iniciado e mantendo o processo SSH em background.

Evidências do NS1:
- conta dedicada `studiosat-rb-tunnel` ativa para autenticação por chave;
- `authorized_keys` com permissões corretas;
- Harbor Liquidsoap escutando em `127.0.0.1:18005`.

Regra operacional fixada:
- operador do estúdio não abre SSH nem PowerShell;
- o túnel sobe no boot do Windows e se reconecta automaticamente;
- RadioBOSS continua configurado para `127.0.0.1:18005` e deve reconectar automaticamente ao iniciar/dar play;
- conta SSH dedicada só pode encaminhar para `127.0.0.1:18005` no NS1.

Próximo gate: confirmar no NS1 a conexão TCP ativa do RadioBOSS no Harbor, metadados chegando e selector escolhendo `radioprincipal_rb_harbor`; depois seguir para transferência automática de assets faltantes da playlist em <=10s.


## Registro C09 — shadow síncrono <=5s e anti-flap

Em 2026-09-17 o requisito operacional foi apertado de <=10s para <=5s.

Motivação observada em produção:
- RadioBOSS LIVE apresentou microflaps;
- selector alternou entre `radioprincipal_rb_harbor` e `radioprincipal_ns1_rtmp`;
- fallback NS1 ainda estava baseado em fila/posição legadas, causando alternância entre conteúdo correto do RadioBOSS e conteúdo editorial divergente do NS1.

Regra definitiva:
- RadioBOSS continua autoridade editorial;
- NS1 deve replicar fila efetiva + current + `playlistpos` + `pos_ms` + next + schedule + itens dinâmicos;
- reconciliação completa no máximo a cada 5s, com processamento imediato de eventos;
- fallback assume no mesmo item e aproximadamente no mesmo ponto;
- hora certa/comerciais/temperatura/itens especiais devem seguir a fila efetiva, não uma playlist independente;
- retorno ao LIVE somente após janela contínua de estabilidade; nunca alternar imediatamente a cada microqueda.

Mudanças versionadas:
- `authority-replica-candidate.py` -> v0.3.0 candidate, default 5s, playback freshness 10s, heartbeat freshness 15s;
- blob `c7a6285585ed11f0508bfc10a2a0bdac2adbd1b0`;
- runner v1.2 pinado ao blob novo e `--watch --interval 5`;
- activation script C07 atualizado para instalar watch 5s;
- contrato: `docs/10-radio/RADIOPRINCIPAL-C09-SHADOW-SYNC-5S-FAILOVER-CONTRACT.md`.

Importante: o player público legado `mirror-playout.py` ainda usa `radioboss-live.json/matched_index` e não cumpre sozinho o contrato C09. Próxima implementação deve substituir essa lógica por checkpoint de `playback.json` + `pos_ms`, resolver assets imediatamente e adicionar anti-flap antes de promover.


## Registro C12 — consolidação imediata do fallback e retirada de players antigos

Motivação observada em produção:
- público alternando entre áudio correto do RadioBOSS e conteúdo divergente do fallback NS1;
- selector troca entre `radioprincipal_rb_harbor` e `radioprincipal_ns1_rtmp`;
- fallback legado usa `current/media-map.json` e avança autonomamente quando perde o LIVE;
- mirror-controller legado estava em timer de 30s.

Ação C12 preparada:
- script `scripts/radioprincipal/production/C12-CONSOLIDATE-RADIOPRINCIPAL-FALLBACK-NOW.sh`;
- Git blob `d1233539b9fce59392c88cfd83f7cc4e50c2bf3d`;
- commit `15965bd17d51b000d462df34a97b8c7399ffc010`;
- sintaxe `bash -n` validada;
- faz backup da configuração atual;
- desabilita V8 stage/production/live-ingress antigos para evitar inicialização concorrente;
- altera o mirror-controller para 5s;
- força reconstrução imediata usando snapshot atual do RadioBOSS;
- exige igualdade entre quantidade de itens do candidate e fallback, zero missing e somente paths no store canônico;
- somente se o gate passar reinicia o shadow NS1;
- não apaga MP3, não reinicia MediaMTX e não reinicia selector.

Regra: não deletar pastas de mídia até provar que nenhuma referência ativa depende delas. Primeiro consolidar um único store canônico e retirar players concorrentes; depois remover legado com evidência.


## Registro V2-0 — reconstrução paralela sem downtime

Regra absoluta adicionada em 2026-09-18:

A Rádio Principal pública não pode ser interrompida por desenvolvimento, teste, migração ou validação.

Produção congelada durante a reconstrução:
- não reiniciar/parar `studiosat-radioprincipal-selector.service`;
- não reiniciar/parar `studiosat-radioprincipal-shadow-ns1.service`;
- não reiniciar `tps-mediamtx.service`;
- não reiniciar Nginx;
- não alterar Harbor 18005;
- não alterar o path público `radioprincipal`;
- não usar `radioprincipal-ns1` como superfície de desenvolvimento;
- não apagar mídia existente durante a reconstrução.

Toda engenharia nova será construída em paralelo sob:
- código: `/opt/studiosat/radio-v2-next/radioprincipal/`;
- estado: `/var/lib/studiosat/radio-v2-next/radioprincipal/`;
- paths: `radioprincipal-v2-shadow` e `radioprincipal-v2-test`;
- units: prefixo `studiosat-radioprincipal-v2-`.

Documentação:
- `docs/10-radio/RADIOPRINCIPAL-NO-DOWNTIME-REBUILD-V2.md`.

Guard:
- `scripts/radioprincipal/v2/NO-DOWNTIME-GUARD.sh`.

Scaffold:
- `scripts/radioprincipal/v2/README.md`.

Motivação: alterações C12/C14 demonstraram que validar diretamente sobre o shadow/selector público pode causar silêncio ou alternância editorial. A partir deste registro, candidates não podem mais tocar produção.

Arquitetura alvo V2:
1. authority-reader;
2. asset-reconciler;
3. upload automático de missing a partir do PC da emissora;
4. canonical-state;
5. execution-engine;
6. adapters de hora certa/temperatura/comerciais/scheduler;
7. shadow publisher isolado;
8. test selector isolado;
9. soak test;
10. cutover único com rollback.

Nenhum cutover está autorizado até aprovação de todos os gates.


## Registro C18 — full forensic XRAY pós-incidente, somente leitura

Objetivo: antes de qualquer nova correção, levantar o estado completo pós-C12/C14/C16/C17 e separar fatos de hipóteses.

Artefatos:
- `scripts/radioprincipal/v2/C18-POSTMORTEM-SUPPLEMENT-READONLY.sh`
  - commit `3be4c840bc521963b39e74f22ae927a4472d6f01`
- `scripts/radioprincipal/v2/C18-RUN-FULL-FORENSIC-XRAY.sh`
  - commit `97961af4f2dc6780f0cdfac0f17bb24f5bce3e28`

O runner executa primeiro o XRAY V2 canônico já aprovado e depois um suplemento pós-incidente.

Safety:
- nenhum `systemctl start/stop/restart/enable/disable`;
- nenhuma alteração de selector/shadow/MediaMTX/Nginx;
- nenhum delete/move de mídia;
- únicas escritas são relatórios e cópias diagnósticas sob `/root`.

O C18 cobre:
- units/timers/ExecStart reais;
- listeners e conexões 18005/1935/8789/8793/9997/8888;
- processos e evidência do túnel;
- probes RTMP/HLS/MediaMTX API;
- config e journal de selector/shadow;
- timeline completa do incidente;
- snapshots RadioBOSS e freshness;
- candidate/status/SQLite/WAL/permissões;
- comparação playback x media-map;
- inventário das bibliotecas/duplicidades;
- protocolo e DB do media-transfer;
- churn de generations/mirror-controller;
- V8/legado ainda referenciado;
- backups C12/C14;
- resumo automatizado final.

Regra: nenhuma nova correção deve ser promovida antes da leitura e análise dos dois relatórios C18.


## Registro C19 — repositórios-base Manhã/Tarde/Noite sem downtime

Decisão de contingência/reconstrução:

Criar três repositórios humanos e estáveis para a Rádio Principal:
- `/srv/tpsmedia/repository/channels/radioprincipal/programacoes/manha`
- `/srv/tpsmedia/repository/channels/radioprincipal/programacoes/tarde`
- `/srv/tpsmedia/repository/channels/radioprincipal/programacoes/noite`

Objetivos:
- fornecer base simples para upload manual de MP3 pelo operador;
- eliminar dependência conceitual de múltiplas bibliotecas desconexas;
- manter um espelho por programa enquanto a V2 é reconstruída;
- nunca usar estes diretórios para derrubar/reiniciar a saída pública durante a construção.

Implementação:
- `scripts/radioprincipal/v2/program-repository-sync.py`
  - commit `4a323e492f8db34441fa63e4302a4689f18b0862`;
- `scripts/radioprincipal/v2/C19-PROVISION-PROGRAM-REPOSITORIES.sh`
  - commit `4cb3ff7011d247286f056cb5803c92f70a55f8d0`;
- documentação:
  - `docs/10-radio/RADIOPRINCIPAL-PROGRAM-REPOSITORIES-BASE.md`
  - commit `197d8bbda88f346c055bdd360fdbe14f1c5a6f11`.

Safety:
- não reinicia selector;
- não reinicia shadow público;
- não reinicia MediaMTX;
- não reinicia Nginx;
- não altera Harbor 18005;
- apenas cria os novos diretórios/config e inicia um novo sidecar V2.

O sidecar roda a cada 5s e:
- lê playback atual do RadioBOSS;
- detecta manhã/tarde/noite pelo source path;
- lê o media-map canônico atual;
- cria hardlinks dos assets já resolvidos no mirror-store para o repositório do programa correspondente, preservando nomes originais;
- gera `manifest.current.json` e `playlist.current.m3u8`;
- atualiza `programacoes/atual` para o programa detectado;
- grava status em `/var/lib/studiosat/radio-v2-next/radioprincipal/program-repositories/status.json`.

Sintaxe do shell validada com `bash -n`; Python validado com `python3 -m py_compile`.

Observação crítica do C18:
- current/next físicos estão resolvidos;
- a divergência de fila permanece porque `playlistpos` inclui itens virtuais e o media-map físico não;
- portanto estes repositórios estabilizam assets/programas, mas não substituem a futura canonical effective queue/execution engine.


## Registro C20 — repositório operacional humano + API do técnico (PREPARADO, NÃO INSTALADO)

Correção de governança:
- nunca tratar script versionado no GitHub como se já estivesse instalado/executado no NS1;
- estado deste C20 neste registro: preparado/versionado, aguardando execução explícita no NS1.

Novo caminho humano oficial proposto:
- `/srv/studiosat/radio-principal/`

Estrutura:
- `grade/manha`
- `grade/tarde`
- `grade/noite`
- `grade/ATUAL`
- `elementos/comerciais`
- `elementos/vinhetas`
- `elementos/hora-certa`
- `elementos/temperatura`
- `operacao/importar`
- `operacao/quarentena`
- `estado`

Componentes preparados:
- `scripts/radioprincipal/v2/program-repository-human-sync.py`
  - commit `5a3cb21a0e35bad5b29eb3cf9f1b8552bffc7d05`
- `scripts/radioprincipal/v2/operator-api.py`
  - commit `8cabbb2b4f793796076f3b935221201670e8f4aa`
- `scripts/radioprincipal/v2/C20-PROVISION-HUMAN-REPOSITORY-AND-API.sh`
  - commit `05b50241441c966a991badd5d6e617e8782db678`
- documentação:
  - `docs/10-radio/RADIOPRINCIPAL-OPERACAO-HUMANA-E-API.md`
  - commit `1601a4bf4e28499a10c0cbd7b82fa3d08367e701`

Safety do C20:
- cria apenas árvore operacional nova e units V2;
- não reinicia selector;
- não reinicia shadow público;
- não reinicia MediaMTX;
- não reinicia Nginx;
- não altera Harbor;
- API local em 127.0.0.1:8810;
- endpoints de produção ficam bloqueados (HTTP 423) durante reconstrução.

O sync inicial pode semear Manhã/Tarde/Noite usando generations históricos + media-map atual, por hardlink quando possível, sem sobrescrever silenciosamente arquivo manual conflitante.


## Registro V3 — Âncora mestre, regras do operador e backlog/gates

Em 2026-09-18 foram formalizados os documentos que passam a orientar todo o workstream:

- `docs/10-radio/RADIOPRINCIPAL-MASTER-ANCHOR-V3.md`
  - commit `dade1e51f1481fac0103748f8c29129a0b19d87f`
- `docs/10-radio/RADIOPRINCIPAL-OPERATOR-CONSOLE-BUSINESS-RULES-V1.md`
  - commit `f616fe7a21e473916d5378e23efb181b9bb0b747`
- `docs/10-radio/RADIOPRINCIPAL-REBUILD-BACKLOG-AND-GATES-V1.md`
  - commit `d2895c8d29378c04e9e53ad1cc70d5fddd49417c`

Fatos fixados:
- a prioridade lógica do selector já é RadioBOSS Harbor -> NS1 shadow -> blank;
- o problema observado não é ausência dessa prioridade, mas indisponibilidade/microflaps reais do source Harbor, que fazem o selector cair no shadow;
- playback/control fresh não equivale a áudio LIVE estável;
- o shadow público continua legado e diverge da fila efetiva;
- não existe ainda Operator Web UI final instalada/validada;
- API/UI preparadas em código não devem ser tratadas como instaladas sem evidência;
- autenticação, usuários, RBAC, MFA, auditoria, transfer manager e relatórios são entregas obrigatórias do produto;
- não declarar “pronto” sem classificar o estado como PREPARADO / INSTALADO / ATIVO / VALIDADO / PRODUÇÃO.

Prioridade atual:
P0 continuidade pública;
P1 estabilizar LIVE RadioBOSS/Harbor;
P2 canonical effective queue;
P3 assets/transfer manager;
P4 execution engine V2;
P5 adapters editoriais;
P6 operator API/UI/auth/RBAC/audit/reports;
P7 selector V2 anti-flap;
P8 soak;
P9 cutover;
P10 legacy cleanup.


## Registro C21 — P1 RadioBOSS LIVE Stability Probe (PREPARADO)

Prioridade em execução: P1 — estabilizar o áudio LIVE RadioBOSS -> túnel -> Harbor 18005 -> selector, sem tocar na produção.

Artefatos preparados:
- `scripts/radioprincipal/v2/C21-P1-RADIOBOSS-LIVE-STABILITY-PROBE.sh`
  - commit `40fed07b39ee619df8ff525b014ba159ec057869`
- documentação:
  - `docs/10-radio/RADIOPRINCIPAL-C21-P1-LIVE-STABILITY-PROBE.md`
  - commit `66e36d40654c8ba8f145af0c2e9eed0414e2124d`

O probe é read-only contra produção e mede:
- listener/established da porta 18005;
- selector/shadow ativos;
- freshness do playback de controle;
- RTMP público/shadow;
- switches RB/NS1/blank;
- metadata Harbor;
- Feeding stopped / Error while reading;
- percentual de amostras com Harbor estabelecido.

Estados:
- CRITICAL_BLANK;
- UNSTABLE;
- SAMPLE_PASS (janela curta; não substitui soak).

Nenhum P2/P3/P4 será promovido para produção antes de fechar P1.


## Registro C21R/C22 — recuperação de túnel único + reconciliação real do repositório humano

Diagnóstico do C21 em 2026-09-18:
- Harbor 18005 LISTEN em 100% da janela;
- conexão ESTABLISHED em apenas 17,65% das amostras;
- playback/control ficou ~9000s stale no início e voltou a ficar fresco no fim;
- dois eventos `Feeding stopped: Avutil.Error(Invalid data found when processing input)`;
- metadata Tim Maia chegou e o selector finalmente mudou para `radioprincipal_rb_harbor`;
- conclusão: prioridade do RadioBOSS funciona, mas o canal LIVE/túnel/source não ficou continuamente estabelecido.

C21R preparado:
- `scripts/radioprincipal/v2/C21R-WINDOWS-RESET-SINGLE-TUNNEL.ps1`
- commit `b5ee975b4ef518d4ff4984f03620f301b43a66dd`
- objetivo: eliminar instâncias antigas do túnel Windows e subir exatamente o watchdog agendado uma vez.

Falha de arquitetura identificada:
- a árvore humana `/srv/studiosat/radio-principal/grade/*` não alimentava o shadow público legado;
- o sync anterior só semeava a árvore a partir de maps/generations e não reconciliava diretamente o banco real de `media-transfer`;
- por isso upload manual na pasta humana não significava automaticamente asset conhecido pelo legado.

C22 preparado:
- `scripts/radioprincipal/v2/human-repository-reconciler.py`
- commit `8e37fbb6341451e1f5ec47528f869195c9b69db6`
- `scripts/radioprincipal/v2/C22-INSTALL-HUMAN-REPOSITORY-RECONCILER.sh`
- commit `2a794fa0c0c6a820c5a02262b50ac9394d464a46`
- reconcilia a cada 5s `media-transfer.sources + repository_index + assets + media-map` para `grade/manha|tarde|noite`;
- preserva arquivos manuais e registra conflitos;
- não reinicia áudio público.

Importante: C22 corrige a sincronização da biblioteca humana, mas ainda não troca o shadow público legado. A troca do fallback só será feita depois de um V2 shadow isolado ser validado.


## Registro C24/C25 — automação local reduzida a um único agente oculto

Conclusão após C21R/C22:
- C21R restaurou listener local 18005 no Windows e TCP local=True, porém o log ainda registrou repetidos `connect failed: Connection refused` para o destino NS1 em alguns momentos; portanto a estabilidade Harbor continua P1.
- C22 apenas reconciliou o que o NS1 já conhecia: Manhã 27, Tarde 85, Noite 69. Isso não equivale à playlist da manhã mostrada no RadioBOSS (~166 faixas). Logo, o mecanismo correto precisa buscar a lista autoritativa e puxar os arquivos ausentes diretamente do PC.

Nova arquitetura:
- PC local deve executar somente RadioBOSS + um único agente oculto Studio Sat em background;
- o agente sobe automaticamente no boot como SYSTEM;
- ele usa um túnel SSH restrito para um bridge localhost no NS1;
- consulta a playlist efetiva recebida pelo NS1;
- prioriza current/next;
- calcula SHA256 local com cache;
- verifica deduplicação no NS1;
- registra source path quando asset já existe;
- faz upload quando ausente;
- repete a cada 5s;
- não exige janela/terminal/aplicativo visível.

C24 NS1 edge bridge PREPARADO:
- `scripts/radioprincipal/v2/edge-bridge.py`
  - commit inicial `eb184e7b660c4d740125a5341d701ff0c5bf9c9b`
  - exists/register enhancement `ae35e647add36928f7806a0dfa1c81f5b51f3dc7`
- `scripts/radioprincipal/v2/C24-INSTALL-NS1-EDGE-BRIDGE.sh`
  - commit `3a8037c5c07779a642353b5d36441b2e5a2ae055`
- bridge bind: 127.0.0.1:8796;
- SSH PermitOpen passa a permitir 18005 e 8796;
- não reinicia selector/shadow/MediaMTX/Nginx/Harbor.

C25 Windows automatic agent PREPARADO:
- `scripts/radioprincipal/v2/StudioSat-RadioPrincipal-Agent.ps1`
  - commit `71c37252ab46913f82a4c05104c4fe48148a1415`
- `scripts/radioprincipal/v2/C25-INSTALL-WINDOWS-AUTOMATIC-AGENT.ps1`
  - commit `e07b3eba1d5dbcbed3cb0251553f3e502737e6ad`
- task: `StudioSat-RadioPrincipal-Agent`;
- startup: ONSTART, SYSTEM, hidden;
- bridge local: 127.0.0.1:18796 -> NS1 127.0.0.1:8796;
- temporariamente NÃO substitui o túnel de áudio 18005 até validar uploads; depois haverá consolidação final em um único agente/túnel.

Regra: não declarar C24/C25 instalados antes de evidência de execução.


## Registro 2026-09-18 — consolidação documental imediata do projeto

Por solicitação explícita, todo o histórico conhecido da Rádio Principal foi consolidado no GitHub para impedir perda de contexto e repetição de erros.

### Fonte mestre nova

`docs/10-radio/RADIOPRINCIPAL-MASTER-DOSSIER-V4.md`

Commit:
`8b4e0b9c8ac26a03c842afe4aa4478655555b9bf`

Conteúdo:
- objetivo detalhado;
- arquitetura atual e alvo;
- RadioBOSS como autoridade;
- separação LIVE/control/assets;
- histórico C01-C25;
- acertos;
- falhas;
- incidentes C12/C14;
- C18 forensic;
- resultados C21/C21R/C22;
- C23/C24/C25 preparados;
- regras de negócio;
- regras de sistema;
- console do operador;
- prioridades P0-P10;
- gates;
- plano passo a passo;
- definição de sucesso.

### Decisões atualizadas

`project-context/02-DECISIONS.md`

Commit:
`a64235f860bf3483a1aa040173598be15a47510a`

Novas decisões D-008..D-016:
- RadioBOSS autoridade editorial;
- planos LIVE/control/assets separados;
- failover preserva conteúdo;
- produção congelada para candidates;
- Canonical Effective Queue;
- SHA256 + transferência automática;
- operação humana obrigatória;
- PC local com um agente oculto;
- status explícito de artefatos.

### MASTER atualizado

`project-context/00-MASTER.md`

Commit:
`3a81cd2f8b48723b558f19fa5a24a26b29bf4513`

Passa a apontar o dossiê V4 como referência obrigatória da frente.

### Next Steps atualizados

`project-context/03-NEXT-STEPS.md`

Commit:
`ceaa79dca1d6793c1ad2d0d4ad2310aaddd4a0a3`

P0-P10 passam a ter precedência operacional.

### Backlog/gates atualizado

`docs/10-radio/RADIOPRINCIPAL-REBUILD-BACKLOG-AND-GATES-V1.md`

Commit:
`38e724a68c457fb6fa799542bd9f0a158e1d36dd`

Registra estado factual de C21/C21R/C22/C23/C24/C25 e gates obrigatórios.

### Chat Bridge atualizado

`project-context/06-CHAT-BRIDGE.md`

Commit:
`481ddb3c215948d6f930a607656d44e339e08bbb`

Novo chat RADIOPRINCIPAL-NS1 deve obrigatoriamente ler o Dossiê V4.

### Regras do console atualizadas

`docs/10-radio/RADIOPRINCIPAL-OPERATOR-CONSOLE-BUSINESS-RULES-V1.md`

Commit:
`70cadd4e18e24923e549dd7f4cae607782d7fedd`

Foi explicitado o que é requisito e o que ainda não está implementado.

### Estado técnico no momento desta consolidação

CONFIRMADO:
- C21 classificou LIVE como UNSTABLE;
- Harbor established em 17,65% das amostras daquela janela;
- C21R restaurou listener local 18005/TCP local=True, mas logs ainda mostraram connection refused;
- C22 executou com Manhã 27, Tarde 85, Noite 69;
- C22 ainda classificou indevidamente `saytime` como missing source, defeito registrado;
- shadow público continua legado;
- sincronização automática completa da grade ainda não está validada.

PREPARADO NO GITHUB, NÃO CONFIRMADO COMO INSTALADO:
- C23 isolated V2 shadow;
- C24 Edge Bridge;
- C25 Windows Automatic Agent;
- Operator API scaffold.

NÃO CONCLUÍDO:
- Operator Web UI final;
- auth/users/password/MFA/RBAC;
- transfer manager completo;
- audit log;
- reports;
- Canonical Effective Queue;
- adapters de hora certa/temperatura/comerciais;
- selector V2 anti-flap;
- soak;
- cutover;
- legacy cleanup.

### Próxima ordem obrigatória

1. P1 — estabilizar LIVE/túnel/Harbor end-to-end;
2. validar C24;
3. validar C25;
4. provar sync completo da playlist atual;
5. construir Canonical Effective Queue;
6. validar execution engine V2 isolado;
7. construir adapters;
8. construir console operacional;
9. selector V2;
10. soak;
11. cutover;
12. cleanup.

Regra: não criar uma nova linha arquitetural enquanto C24/C25 não forem decididos por evidência.


## Registro C26 — RadioBOSS prioritário + fallback ordenado autoritativo (PREPARADO)

Solicitação operacional: conectar RadioBOSS imediatamente, impedir o NS1 de tocar arquivos antigos em ordem aleatória e preservar a ordem Manhã/Tarde/Noite conforme a fila real do RadioBOSS.

Artefatos criados:
- `scripts/radioprincipal/v2/ordered-authoritative-shadow.py`
  - commit `92aae06d9ff02896ef60bda435f96a455e6ac6e4`
- `scripts/radioprincipal/v2/C26-INSTALL-AND-PROMOTE-ORDERED-FALLBACK.sh`
  - commit `d74f1618b01a744a6d20b1d34421eb1214264d51`
- `scripts/radioprincipal/v2/C26-WINDOWS-UNIFIED-TUNNEL.ps1`
  - commit `098384c657d90f8819aba9f1be95148702978858`
- runbook:
  - `docs/10-radio/RADIOPRINCIPAL-C26-EMERGENCY-ORDERED-FALLBACK.md`
  - commit `ebbe5748ee7d61709c95dcd3edb1a2d0b7cdc8e7`

Mudança de lógica:
- o novo fallback NÃO usa o media-map legado como autoridade de ordem;
- lê `playlist.json` do RadioBOSS;
- alinha por `current + playlistpos + pos_ms`;
- resolve o asset via media-transfer DB / repositório humano;
- se o playback estiver stale no boot, espera checkpoint válido e não inicia por arquivo arbitrário;
- quando perde controle depois de sincronizado, continua para o próximo item físico da MESMA fila;
- `saytime=` é classificado como virtual, não como MP3.

Promoção protegida:
- sobe primeiro em `radioprincipal-v2-shadow-hotfix`;
- exige stream válido;
- exige Harbor 18005 ESTABLISHED;
- só então substitui o publisher do fallback `radioprincipal-ns1`;
- não reinicia selector, MediaMTX ou Nginx;
- rollback do unit anterior se o novo fallback não publicar.

Windows:
- nova tarefa `StudioSat-RadioPrincipal-Unified`;
- desabilita a tarefa antiga `StudioSat-RadioBOSS-NS1-Tunnel`;
- sobe automaticamente no boot como SYSTEM;
- forwards 18005 (áudio) e 18796->8796 (edge bridge futuro/automação).

Estado neste registro:
PREPARADO NO GITHUB. Ainda não classificar como INSTALADO/ATIVO/VALIDADO sem saída da execução.


## RESET BASELINE — 2026-09-18

Decisão operacional: começar do zero a partir do estado real do NS1.

Scripts C12–C26 ficam congelados como histórico e não devem ser executados durante o reset sem decisão explícita baseada em nova evidência.

Nova sequência:
1. RESET-00 — full XRAY NS1 read-only;
2. RESET-01 — recuperação mínima RadioBOSS -> Harbor -> selector -> radioprincipal -> HLS;
3. RESET-02+ — reconstrução somente a partir da baseline comprovada.

Artefatos:
- `scripts/radioprincipal/reset/RESET00-NS1-FULL-XRAY-READONLY.sh`
  - commit `c7c51f22eadbc9a979fa7227d83bc45f5a7a44c4`
- `scripts/radioprincipal/reset/RESET01-NS1-RECOVER-RADIOBOSS.sh`
  - commit `9e2e5da1ae5f0962861ff9ab4199218c921089c3`
- `scripts/radioprincipal/reset/RESET01-WINDOWS-LIVE-TUNNEL.ps1`
  - commit `c7ba020c53e94dd371ab2588aabba17a38a0c96e`
- `docs/10-radio/RADIOPRINCIPAL-RESET-BASELINE-2026-09-18.md`
  - commit `ccb3b3463b59fcc68c40bf08f421b727a2428c00`

Meta imediata:
não corrigir fallback/playlist ainda; primeiro colocar a Rádio Principal no ar pelo RadioBOSS e capturar o raio X completo do NS1.


## RESET-00 factual baseline recebida — 2026-09-18

Foi analisado o pacote real `studiosat-ns1-raiox-20260918T174058Z`.

Descobertas decisivas:
- `radioprincipal` READY;
- `radioprincipal-ns1` READY;
- `radioprincipal-rb` MediaMTX DOWN, porém este path não é o LIVE atual;
- Harbor Liquidsoap 127.0.0.1:18005 LISTEN e com conexões ESTABLISHED no snapshot;
- selector público real usa `[rb, local, security]`;
- `local` = `/srv/studiosat/radio-principal/playlists/current.m3u`;
- portanto o selector público NÃO estava usando `radioprincipal-ns1` como fallback;
- `current.m3u` contém 291 entradas: 109 hora-certa, 28 Manhã, 69 Noite, 85 Tarde;
- ordem da lista: todos os elementos hora-certa -> Manhã -> Noite -> Tarde;
- isso é editorialmente inválido;
- switches comprovados: RB 17:40:19 -> local 17:40:26 -> RB 17:40:36 -> local 17:40:49 -> RB 17:40:59;
- mirror controller: 166 tracks RadioBOSS / 163 disponíveis / 3 missing;
- playback: playlistpos 15; current B. J. Thomas; next Djavan;
- current/next não estavam no current.m3u capturado;
- shadow legado `mirror-playout.py` continua ativo e publica radioprincipal-ns1, mas não é usado pelo selector atual.

Documento factual:
`docs/10-radio/RESET00-FACTUAL-FINDINGS-2026-09-18.md`
commit `0ce1e279a849cb567451ea846e16c7a7ad55026c`.

RESET-01A preparado:
`scripts/radioprincipal/reset/RESET01A-RADIOBOSS-ONLY-PUBLIC.sh`
commit `98b4feae2d57f14e8237edaa725672736169c4e9`.

Objetivo RESET-01A:
- remover `local_grade` do fallback público;
- deixar temporariamente `RadioBOSS Harbor -> blank`;
- impedir qualquer arquivo antigo/não autorizado de entrar no ar;
- reiniciar somente o selector uma vez, com backup e rollback se o Harbor não voltar a LISTEN;
- confirmar Harbor ESTABLISHED + public RTMP/HLS + latest switch para RadioBOSS.

RESET-02 só será iniciado depois desta baseline pública ficar estável.


### Hardening RESET-01A

RESET-01A foi endurecido antes da execução:
- agora exige Harbor 18005 ESTABLISHED antes de alterar o selector;
- se RadioBOSS não estiver conectado, aborta sem tocar produção;
- se `liquidsoap --check` falhar, restaura imediatamente a configuração anterior antes de qualquer restart.

Novo commit:
`f198858fffb6168acc2f70318ab9bc6f7c13c87e`.


## RESET-01A execution result / RESET-01B prepared

User executed RESET-01A at 2026-09-18T19:03Z.

Observed:
- selector service active;
- Harbor 127.0.0.1:18005 LISTEN;
- `RADIOBOSS_ESTABLISHED_BEFORE_CHANGE=YES`;
- RESET-01A aborted BEFORE changing config because current selector fallback was no longer `[rb, local, security]`;
- actual current fallback grep showed:
  - line 22: `radioprincipal_local_grade`;
  - line 28: `program = fallback(`;
  - line 32: `[rb, local]`.

Therefore RESET-01A safety gate worked and production config remained unchanged.

RESET-01B prepared to normalize both observed variants:
- `[rb, local]`;
- `[rb, local, security]`;
to:
- `[rb, security]`.

RESET-01B safety:
- requires RadioBOSS ESTABLISHED before any config change;
- creates candidate config;
- guarantees security blank source;
- runs `liquidsoap --check`;
- installs only after check passes;
- restarts selector once;
- rolls back if selector/Harbor fails to return LISTEN;
- does not restart MediaMTX/Nginx;
- does not change playlists/media.

Artifacts:
- `scripts/radioprincipal/reset/RESET01B-RADIOBOSS-ONLY-PUBLIC.sh`
  - commit initial `d6cab6b1b0a5bc645a298acf6ff9b7eca8e9309c`
  - hardened verify `807e459b5ee8c0ac7c641ace3e474f111f4e0656`
- `docs/10-radio/RESET01B-RADIOBOSS-ONLY-PUBLIC.md`
  - commit `baf1b1c2bf11cd762b1c611b1652d7c6cd51c4c9`.

Next action: execute RESET-01B, then classify baseline only from its output.


## RESET-01B execution result — 2026-09-18

User executed RESET-01B successfully through config validation and public fallback normalization.

Confirmed:
- selector active before change;
- Harbor 18005 LISTEN;
- RadioBOSS ESTABLISHED before change;
- current public fallback before change: `[rb, local]`;
- candidate build OK;
- Liquidsoap check OK;
- installed public fallback: `[rb, security]`;
- selector restarted once;
- Harbor LISTEN returned after 14s;
- RadioBOSS ESTABLISHED returned after 21s;
- local grade removed from public fallback;
- HLS READY;
- latest observed switch at 19:10:14Z was to `radioprincipal_rb_harbor`.

Remaining failure:
- repeated Harbor decoder failures:
  `Feeding stopped: Avutil.Error(Invalid data found when processing input)`;
- public source flapped between `radioprincipal_rb_harbor` and `radioprincipal_emergency_blank`;
- examples:
  - RB at 19:07:50;
  - blank at 19:08:16;
  - RB at 19:08:20;
  - blank at 19:09:23;
  - RB at 19:09:35;
  - blank at 19:09:55;
  - RB at 19:10:14;
- script result:
  `RESULTADO=RESET01B_BASELINE_APPLIED_LIVE_NEEDS_RECOVERY`.

Interpretation:
- wrong local playlist is no longer a public source;
- remaining outage/flap is now isolated to the RadioBOSS LIVE ingest path, specifically Harbor/decode/source continuity;
- MediaMTX/HLS path remained available;
- do not reintroduce local playlist while diagnosing LIVE ingest.

Next workstream:
RESET-01C = stabilize RadioBOSS LIVE ingest without changing editorial/fallback logic.
