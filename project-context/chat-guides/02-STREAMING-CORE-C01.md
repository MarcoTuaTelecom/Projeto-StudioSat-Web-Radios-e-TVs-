# Guia de abertura — Chat 02 Streaming Core

## Nome da conversa

`02 — STREAMING CORE — MediaMTX / Nginx / HLS — C01`

## WORKSTREAM_ID

`STREAMING-CORE`

## Função

Consolidar a camada comum de transporte/streaming: MediaMTX, Nginx, HLS, TLS, paths, publishers e health, sem absorver lógica editorial, mirror, Portal, Mobile ou selector.

## Links obrigatórios

1. Repositório/branch:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/tree/reorg/project-context-v2

2. Reconstrução:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/docs/00-core/REPOSITORY-RECONSTRUCTION-V2.md

3. MASTER:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/00-MASTER.md

4. Decisões:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/02-DECISIONS.md

5. Âncora 02:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/anchors/02-STREAMING-CORE-ANCHOR.md

6. ACTIVE STATE:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/chats/active/STREAMING-CORE.md

7. Registry histórico:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/main/registry/channels-registry.yaml

8. Chat Bridge:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/06-CHAT-BRIDGE.md

## Primeira mensagem

```text
WORKSTREAM_ID: STREAMING-CORE

Esta é a conversa 02 — STREAMING CORE — MediaMTX / Nginx / HLS — C01.

Use o GitHub como fonte persistente de verdade.

Leia obrigatoriamente, nesta ordem:
1. docs/00-core/REPOSITORY-RECONSTRUCTION-V2.md
2. project-context/00-MASTER.md
3. project-context/02-DECISIONS.md
4. project-context/anchors/02-STREAMING-CORE-ANCHOR.md
5. project-context/chats/active/STREAMING-CORE.md
6. registry/channels-registry.yaml apenas como baseline histórico

A ÂNCORA 02 é normativa para esta conversa.

MISSÃO:
concluir e documentar a camada comum de streaming com MediaMTX, Nginx, HLS, TLS, paths, publishers e health objetivos.

NÃO absorva:
- playlist/schedule/librarymanifest;
- playback editorial;
- mirror/materialização de mídia;
- scheduler/hora certa;
- lógica do selector/failover;
- Portal/CMS;
- Mobile;
- motores Rádio/TV.

Quando surgir algo dessas áreas, registre DEPENDÊNCIA.

A primeira fase é SOMENTE LEITURA.

Quero descobrir a topologia viva real, não assumir que o registry histórico ainda está atual.

Colete/analise somente o necessário para confirmar:
- processo/versão/configuração carregada do MediaMTX;
- portas/protocolos;
- paths configurados;
- publishers/readiness atuais;
- serviços systemd relacionados;
- configuração Nginx efetivamente carregada;
- server blocks/hosts;
- TLS/certificados/redirects;
- roteamento HLS;
- HLS público final após redirects;
- classificação dos paths como PUBLIC / AUTHORITATIVE_INPUT / SHADOW / TEST / LAB / LEGACY / UNKNOWN.

Entregue primeiro uma matriz:
ITEM | HISTÓRICO/REGISTRY | ESTADO VIVO | CLASSIFICAÇÃO | EVIDÊNCIA | AÇÃO

Não faça reload/restart/cutover durante o baseline inicial.

Depois escolha somente a PRIMEIRA divergência necessária ao Definition of Done.

REGRAS ANTI-LOOP:
- antes de editar Nginx, descubra a configuração realmente carregada;
- antes de editar MediaMTX, descubra processo, config e path reais;
- duas tentativas sem progresso = voltar a diagnóstico;
- três erros básicos de sintaxe/configuração = suspender mutações;
- não reiniciar múltiplos serviços como tentativa;
- não editar arquivos que não foram provados como ativos;
- não mudar path público quando shadow/test pode validar a hipótese;
- toda mudança precisa de validação e rollback.

Todo comando mutável deve declarar:
HOST:
COMPONENT:
MODE:
PUBLIC_IMPACT:
BACKUP:
ROLLBACK:
VALIDATION:

A cada marco mostre:
STREAMING-CORE STATUS
PHASE:
SCOPE_TARGET:
LAST_CONFIRMED_TOPOLOGY:
LAST_CHANGE:
RESULT:
PUBLIC_IMPACT:
BLOCKER:
NEXT_SINGLE_STEP:
DOD_PROGRESS:

Quando o baseline inicial estiver fechado, declare:
STREAMING_BASELINE=COMPLETE

Quando todo o Definition of Done da âncora estiver cumprido, declare:
STREAMING_CORE=READY_FOR_HANDOFF

e pare de expandir a frente.
```

## Encerramento

O C01 deve primeiro concluir o baseline. Ele não deve virar uma sequência infinita de reparos antes de saber exatamente qual configuração está ativa.
