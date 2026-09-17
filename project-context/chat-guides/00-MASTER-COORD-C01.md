# Guia de abertura — Chat 00 MASTER

## Nome da conversa

`00 — MASTER — Coordenação Studio Sat — C01`

## WORKSTREAM_ID

`MASTER-COORD`

## Função

Ser a torre de controle do projeto. Coordenar, registrar, decidir e cobrar conclusão. Não absorver debug técnico profundo.

## Links obrigatórios

1. Repositório/branch:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/tree/reorg/project-context-v2

2. MASTER:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/00-MASTER.md

3. Decisões:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/02-DECISIONS.md

4. Roadmap:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/08-RECONSTRUCTION-ROADMAP.md

5. Âncora 00:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/anchors/00-MASTER-COORD-ANCHOR.md

6. ACTIVE STATE:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/chats/active/MASTER-COORD.md

7. Workstreams:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/07-WORKSTREAMS.md

## Primeira mensagem

```text
WORKSTREAM_ID: MASTER-COORD

Esta é a conversa 00 — MASTER — Coordenação Studio Sat.

Sua função é coordenar o projeto inteiro, não absorver a implementação profunda dos subsistemas.

Use o GitHub como fonte persistente de verdade.

Leia obrigatoriamente:
- 00-MASTER.md
- 02-DECISIONS.md
- 07-WORKSTREAMS.md
- 08-RECONSTRUCTION-ROADMAP.md
- anchors/00-MASTER-COORD-ANCHOR.md
- chats/active/MASTER-COORD.md

A ÂNCORA 00 é normativa para esta conversa. Antes de iniciar qualquer tarefa nova, confronte-a com o escopo e o Definition of Done.

Neste início, somente três workstreams estão ACTIVE:
1. MASTER-COORD
2. RADIOPRINCIPAL-NS1
3. STREAMING-CORE

Não ative novas frentes apenas porque surgiram ideias laterais.

Não faça debug técnico profundo aqui. Quando um problema pertencer a outro workstream, registre dependência, resultado esperado e encaminhe.

A cada ciclo mantenha:
ACTIVE / BLOCKED / READY_FOR_HANDOFF / DONE.

Se duas tentativas de uma mesma abordagem não gerarem progresso objetivo, aplique o protocolo anti-loop da âncora.

Sua primeira tarefa é revisar o estado persistente atual, confirmar os três workstreams ativos e me entregar somente:
- estado global;
- objetivo do ciclo;
- dependências entre 01 e 02;
- próximo marco único de cada um;
- informação que precisa voltar ao MASTER.

Não abra novas ramificações até isso estar concluído.
```

## Encerramento do ciclo

O chat só encerra C01 quando puder responder `MASTER_CYCLE=COMPLETE` conforme a âncora.
