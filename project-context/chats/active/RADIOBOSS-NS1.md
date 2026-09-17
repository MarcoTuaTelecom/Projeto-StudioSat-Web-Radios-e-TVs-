# WORKSTREAM: RADIOBOSS-NS1

## Identidade

- `WORKSTREAM_ID`: `RADIOBOSS-NS1`
- Estado: `ACTIVE`
- Escopo: autoridade editorial RadioBOSS, sincronização, snapshots, mirror, materialização de mídia, playout NS1, scheduler/hora certa e preparação de failover.
- Fora do escopo: UI mobile, portal editorial, redesign, mudanças gerais de Nginx sem dependência direta.

## Contrato funcional

1. RadioBOSS é a autoridade editorial e prioridade normal de áudio.
2. NS1 mantém um espelho atualizado de playlist/programação/biblioteca suficiente para continuidade.
3. Em indisponibilidade do RadioBOSS, NS1 deve continuar a programação a partir do estado conhecido.
4. Quando RadioBOSS retornar e estiver validado, a prioridade volta para ele de forma controlada.
5. OBS/live é tratado como entrada prioritária própria e deve ser integrado pelo workstream de selector/failover.
6. A solução deve suportar uma janela editorial de até 10 dias.

## Estado importado da conversa anterior

> Este bloco é um handoff inicial vindo do trabalho anterior. Antes de executar cutover ou mudança destrutiva, reconfirmar o estado vivo no NS1.

- Arquitetura operando em modo `RADIOBOSS_AUTHORITATIVE_MIRROR`.
- Snapshots de `playlist`, `schedule` e `librarymanifest` foram sincronizados/versionados.
- `mirror-playout.py`, controller/monitor e runtime persistente já foram trabalhados.
- Em uma etapa anterior o controller mostrou 160 itens totais, 117 disponíveis e 43 ausentes; a causa identificada foi mídia presente em uploads/object store mas ainda não materializada/indexada para o usuário/runtime de playout.
- Uma etapa posterior registrou 156/158 mídias disponíveis, indicando progresso mas ainda sem baseline final consolidado.
- Foi identificado acoplamento incorreto do mirror-playout a `radioboss-live.json`/`matched_index` em vez de `playback.json`.
- Também foi identificado que o hash/wrapper podia criar gerações falsas.
- `Harbor 18005` e selector legado apareceram misturados na mesma frente e devem ser separados antes do cutover final.
- Forense NS1 concluída em 2026-09-17 com bundle `/root/STUDIOSAT-FORENSIC-NS1-20260917T023826Z.tar.gz` e resultado `FORENSIC_NS1_OK`.
- Coleta Windows permaneceu pendente porque o bundle PowerShell correspondente ainda não estava presente no caminho esperado.

## Evidências/artefatos conhecidos

- `STUDIOSAT-NS1-MASTER-XRAY-20260916-081439.txt`
- `STUDIOSAT-NS1-MASTER-XRAY-V2.sh`
- `STUDIOSAT-RADIOPRINCIPAL-NS1-DEEP-XRAY-20260915-230134.txt`
- `STUDIOSAT-RADIOPRINCIPAL-AUDIT2-20260915T235635Z.txt`
- `/root/STUDIOSAT-FORENSIC-NS1-20260917T023826Z.tar.gz`

## Pendências canônicas antes de cutover

1. Reconfirmar contagem atual total/disponível/missing com o runtime vivo.
2. Confirmar fonte correta do índice de reprodução (`playback.json` ou contrato atual equivalente).
3. Eliminar geração falsa causada apenas por wrapper/hash instável.
4. Confirmar materialização/indexação de todas as mídias necessárias ao usuário de playout.
5. Implementar/validar Scheduler e Hora Certa sobre snapshots reais.
6. Separar Harbor/selector legado da lógica de mirror-playout.
7. Só então integrar ao `FAILOVER-SELECTOR` e executar shadow/cutover controlado.

## Próximo passo recomendado para um novo ciclo de chat

Executar **somente leitura** e produzir um baseline único do estado atual:

- serviços/timers ativos;
- idade/revisão/hash dos três snapshots;
- geração do mirror/controller/runtime;
- total/available/missing e lista exata dos missing;
- fonte do item atualmente tocando;
- relação entre `playback.json`, `radioboss-live.json`, media-map e runtime;
- publishers/ports relevantes sem alterar tráfego.

Depois do baseline, atualizar este arquivo substituindo fatos históricos por fatos atuais comprovados.

## Regra para a próxima aba

A nova conversa deve começar dizendo:

```text
WORKSTREAM_ID: RADIOBOSS-NS1
Leia project-context/00-MASTER.md,
project-context/02-DECISIONS.md,
project-context/06-CHAT-BRIDGE.md e
project-context/chats/active/RADIOBOSS-NS1.md.
Continue do próximo passo registrado. Não reinicie o projeto e não execute cutover antes de reconfirmar o baseline vivo.
```
