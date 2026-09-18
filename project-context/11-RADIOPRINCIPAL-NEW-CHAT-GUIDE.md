# Rádio Principal — Guia para abrir uma nova conversa limpa

## Nome da conversa

**RÁDIO PRINCIPAL — RadioBOSS → NS1 — Continuação C02**

## Workstream

`RADIOPRINCIPAL-NS1`

## Objetivo

Continuar a engenharia da Rádio Principal sem carregar o histórico completo da conversa anterior.

## Links que devem ser entregues ao novo chat

### 1. Repositório mestre / branch de reconstrução

https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/tree/reorg/project-context-v2

### 2. Documentação da reconstrução

https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/docs/00-core/REPOSITORY-RECONSTRUCTION-V2.md

### 3. MASTER do projeto

https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/00-MASTER.md

### 4. Estado específico da Rádio Principal

https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/chats/active/RADIOPRINCIPAL-NS1.md

### Links auxiliares

Decisões:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/02-DECISIONS.md

Chat Bridge:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/06-CHAT-BRIDGE.md

Roadmap:
https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/blob/reorg/project-context-v2/project-context/08-RECONSTRUCTION-ROADMAP.md

## Primeira mensagem do novo chat

Copiar exatamente:

```text
WORKSTREAM_ID: RADIOPRINCIPAL-NS1

Esta é uma nova conversa limpa para continuar o trabalho da RÁDIO PRINCIPAL.
A conversa anterior ficou grande/lenta e não deve ser usada como fonte principal de contexto.

Use o GitHub como fonte persistente de verdade.

Leia nesta ordem:
1. REPOSITORY-RECONSTRUCTION-V2.md
2. project-context/00-MASTER.md
3. project-context/02-DECISIONS.md
4. project-context/06-CHAT-BRIDGE.md
5. project-context/chats/active/RADIOPRINCIPAL-NS1.md

Depois consulte somente os documentos, scripts e evidências necessários para a Rádio Principal.

Não reinicie o projeto.
Não repita etapas marcadas como concluídas sem nova evidência.
Não faça cutover nem alteração destrutiva antes de reconfirmar o estado vivo.

Primeira tarefa desta conversa:
produza um baseline SOMENTE LEITURA do estado atual da Rádio Principal e compare com o ACTIVE STATE, classificando cada ponto como CONFIRMADO, MUDOU, OBSOLETO ou PENDENTE.

Depois continue exatamente do próximo passo comprovado.
```

## Como criar a nova aba

1. Abra o Projeto Studio Sat no ChatGPT.
2. Clique em **Novo chat** dentro do projeto.
3. Não duplique/ramifique a conversa antiga; comece uma conversa vazia.
4. Renomeie para:
   `RÁDIO PRINCIPAL — RadioBOSS → NS1 — Continuação C02`
5. Cole a primeira mensagem acima.
6. Entregue os quatro links principais.
7. Se o GitHub estiver conectado, peça explicitamente para ler os arquivos pelo conector GitHub.
8. Não cole milhares de linhas da conversa antiga.
9. Só envie logs novos quando o novo chat pedir o resultado de um teste específico.

## Quando abrir C03

Quando C02 ficar longa ou encerrar uma etapa técnica:

1. atualizar `project-context/chats/active/RADIOPRINCIPAL-NS1.md`;
2. registrar o último resultado comprovado e próximo passo;
3. abrir:
   `RÁDIO PRINCIPAL — RadioBOSS → NS1 — Continuação C03`;
4. repetir este mesmo procedimento.

O número do ciclo muda. O `WORKSTREAM_ID` e o arquivo ACTIVE permanecem os mesmos.
