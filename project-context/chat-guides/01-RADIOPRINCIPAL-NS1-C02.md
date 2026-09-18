# Guia de abertura — Chat 01 Rádio Principal

## Nome da conversa

`01 — RÁDIO PRINCIPAL — RadioBOSS → NS1 — C02`

## WORKSTREAM_ID

`RADIOPRINCIPAL-NS1`

## Função

Concluir o pipeline RadioBOSS → snapshots/playback → mirror/runtime → playout shadow NS1 e preparar handoff objetivo para failover/selector.

## Links obrigatórios

1. Repositório/branch:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/tree/reorg/project-context-v2

2. Reconstrução:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/docs/00-core/REPOSITORY-RECONSTRUCTION-V2.md

3. MASTER:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/00-MASTER.md

4. Decisões:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/02-DECISIONS.md

5. Âncora 01:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/anchors/01-RADIOPRINCIPAL-NS1-ANCHOR.md

6. ACTIVE STATE:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/chats/active/RADIOPRINCIPAL-NS1.md

7. Registry histórico:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/main/registry/channels-registry.yaml

8. Chat Bridge:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/06-CHAT-BRIDGE.md

## Primeira mensagem

```text
WORKSTREAM_ID: RADIOPRINCIPAL-NS1

Esta é a conversa 01 — RÁDIO PRINCIPAL — RadioBOSS → NS1 — C02.

Estou continuando uma frente já existente. A conversa anterior ficou longa e não deve ser usada como memória operacional principal.

Use o GitHub como fonte persistente de verdade.

Leia obrigatoriamente, nesta ordem:
1. docs/00-core/REPOSITORY-RECONSTRUCTION-V2.md
2. project-context/00-MASTER.md
3. project-context/02-DECISIONS.md
4. project-context/anchors/01-RADIOPRINCIPAL-NS1-ANCHOR.md
5. project-context/chats/active/RADIOPRINCIPAL-NS1.md
6. registry/channels-registry.yaml somente como baseline histórico

A ÂNCORA 01 é normativa para esta conversa.

MISSÃO DESTA FRENTE:
concluir RadioBOSS → snapshots/playback → mirror/runtime → playout shadow NS1 → scheduler/hora certa e produzir handoff pronto para FAILOVER-SELECTOR.

NÃO absorva:
- Nginx/MediaMTX global;
- Portal;
- Mobile;
- outras rádios;
- TV;
- selector público completo;
- OBS/live.

Quando surgir algo dessas áreas, registre DEPENDÊNCIA e não ramifique.

A primeira fase do C02 é SOMENTE LEITURA.

Quero um baseline vivo único da Rádio Principal e uma matriz:
ITEM | ESTADO DOCUMENTADO | ESTADO VIVO | CLASSIFICAÇÃO | EVIDÊNCIA | AÇÃO

Classifique como:
CONFIRMADO / MUDOU / OBSOLETO / PENDENTE.

Verifique obrigatoriamente:
- serviços/timers;
- playlist.json;
- schedule.json;
- librarymanifest.json;
- playback.json ou contrato equivalente;
- radioboss-live.json apenas para descobrir se ainda participa do runtime;
- mirror/controller/runtime;
- geração/revisão/idade;
- TOTAL/AVAILABLE/MISSING;
- usuário e caminhos de mídia do playout;
- saída shadow radioprincipal-ns1;
- relação com radioprincipal-rb;
- papel atual de Harbor/selector sem alterá-los.

Não corrija durante o baseline inicial.

Depois do baseline escolha apenas UM primeiro desvio necessário ao Definition of Done.

REGRAS ANTI-LOOP:
- duas tentativas sem progresso = parar e diagnosticar;
- três erros básicos de sintaxe/path/linguagem = suspender mutações e voltar a read-only;
- não criar v2/v3/v4 de script às cegas;
- não mudar múltiplas camadas na mesma tentativa;
- cada comando deve dizer HOST, MODO e OBJETIVO;
- scripts devem ser revisados/validados antes de eu executá-los.

A cada marco mostre:
RADIOPRINCIPAL-NS1 STATUS
PHASE:
OBJECTIVE:
LAST_CONFIRMED_FACT:
LAST_CHANGE:
RESULT:
BLOCKER:
NEXT_SINGLE_STEP:
DOD_PROGRESS:

Não abra melhorias opcionais antes de concluir o Definition of Done da âncora.

Quando todos os critérios forem cumpridos, declare:
RADIOPRINCIPAL_NS1=READY_FOR_HANDOFF

e pare de expandir esta frente.
```

## Regra para logs

Não pedir dump gigante por padrão. Pedir somente a menor coleta capaz de testar a hipótese atual. Quando precisar de raio-X amplo, justificar qual decisão ele desbloqueia.

## Encerramento

A conversa não deve implementar failover público. Ela termina ao entregar uma entrada RadioBOSS e um shadow NS1 estáveis, observáveis e documentados ao próximo workstream.
