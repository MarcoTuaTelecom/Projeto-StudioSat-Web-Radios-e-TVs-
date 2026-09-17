# ChatGPT ↔ GitHub Bridge — Studio Sat

## Objetivo

Permitir que cada frente do projeto Studio Sat seja trabalhada em uma conversa separada do ChatGPT sem depender do histórico infinito de uma única aba.

## Regra principal

**A conversa não é a memória oficial. O GitHub é a memória oficial.**

Cada frente possui um `WORKSTREAM_ID` persistente. Uma conversa do ChatGPT é apenas um ciclo de trabalho temporário daquele workstream.

Exemplo:

- Workstream persistente: `RADIOBOSS-NS1`
- Conversa atual: `RADIOBOSS-NS1 / ciclo 01`
- Quando a aba ficar lenta: fechar ciclo 01 com HANDOFF e abrir `RADIOBOSS-NS1 / ciclo 02`
- O ciclo 02 lê o mesmo arquivo de estado e continua do ponto exato.

## Fontes de verdade

1. `project-context/00-MASTER.md` — estado global.
2. `project-context/02-DECISIONS.md` — decisões vigentes.
3. `project-context/03-NEXT-STEPS.md` — fila global.
4. `project-context/chats/active/<WORKSTREAM_ID>.md` — estado específico da frente.
5. `project-context/checkpoints/` — snapshots históricos.
6. Código/configuração real nos repositórios correspondentes.

## Protocolo de início de uma conversa

A primeira mensagem de uma nova aba deve informar:

```text
STUDIOSAT CHAT BRIDGE
WORKSTREAM_ID: <id>
REPOSITÓRIO MASTER: MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-
ARQUIVO DE ESTADO: project-context/chats/active/<id>.md

Antes de propor mudanças:
1. leia 00-MASTER.md;
2. leia 02-DECISIONS.md;
3. leia o arquivo de estado deste workstream;
4. consulte somente os repositórios/arquivos necessários para esta frente;
5. preserve as decisões vigentes e não repita etapas já concluídas.

Ao final de uma etapa importante, atualize o estado do workstream e registre o próximo passo verificável.
```

## Protocolo de encerramento / troca de aba

Antes de abandonar uma conversa longa, registrar no arquivo do workstream:

- último fato comprovado;
- último comando/alteração executada;
- resultado;
- arquivos/serviços afetados;
- commit/branch quando houver;
- pendências;
- próximo teste exato;
- riscos/rollback;
- fatos que **não** devem ser reabertos sem nova evidência.

Depois disso, a aba antiga pode ser arquivada. A nova aba recebe apenas o bootstrap acima e continua pelo GitHub.

## Regra de granularidade

Uma aba = um workstream técnico. Não misturar assuntos apenas porque usam o mesmo servidor.

Exemplos:

- `RADIOBOSS-NS1` — espelho editorial/playout/failover.
- `STREAMING-CORE` — MediaMTX/Nginx/HLS/TLS.
- `PORTAL-CMS` — CMS/API/admin/content.
- `PORTAL-WEB` — frontend público.
- `MOBILE-APP` — React Native/Expo/player.
- `MOBILE-RELEASE` — EAS/lojas/releases.
- `TV-CORE` — integração e engenharia de TV.

## Regra de coordenação

O workstream pode alterar apenas os arquivos sob sua responsabilidade. Alterações cruzadas exigem registrar dependência no `00-MASTER.md` ou `03-NEXT-STEPS.md`.

## Segurança

Nunca gravar no bridge:

- senha;
- token;
- chave privada;
- stream key;
- cookie de sessão;
- dump não sanitizado.

Registrar apenas caminhos, nomes de segredo/variável e evidências sanitizadas.
