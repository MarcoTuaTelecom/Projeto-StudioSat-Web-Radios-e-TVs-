# WORKSTREAM: MASTER-COORD

## Identidade

- `WORKSTREAM_ID`: `MASTER-COORD`
- Estado: `ACTIVE`
- Chat: `00 — MASTER — Coordenação Studio Sat — C01`
- Repositório principal: `MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-`
- Âncora obrigatória: `project-context/anchors/00-MASTER-COORD-ANCHOR.md`

## Missão atual

Coordenar a reconstrução v2 sem absorver implementação técnica dos subsistemas.

## Workstreams autorizados como ACTIVE neste início

1. `MASTER-COORD`
2. `RADIOPRINCIPAL-NS1`
3. `STREAMING-CORE`

Nenhum quarto workstream técnico deve ser ativado apenas porque surgiu uma ideia lateral.

## Estado conhecido

- Repositório Master/Core escolhido e documentado.
- Portal permanece repositório separado.
- Mobile permanece repositório separado.
- Infraestrutura deve migrar progressivamente para Core.
- Chat Bridge e política de workstreams foram criados na branch `reorg/project-context-v2`.
- Rádio Principal recebeu ACTIVE STATE e âncora próprios.
- Streaming Core recebeu âncora própria e deve iniciar por baseline somente leitura.

## Objetivo do C01

Levar as três frentes iniciais a um estado em que:

- cada uma tenha escopo fechado;
- cada uma tenha Definition of Done;
- cada uma tenha próximo passo único;
- dependências entre 01 e 02 sejam explicitadas;
- nenhuma decisão importante dependa da memória das conversas.

## Próximo passo único

Acompanhar os handoffs de `RADIOPRINCIPAL-NS1` e `STREAMING-CORE`, registrar somente resultados e dependências e impedir desvio de escopo.

## Definition of Done do C01

- [ ] Rádio Principal tem baseline vivo atualizado.
- [ ] Streaming Core tem baseline vivo atualizado.
- [ ] divergências relevantes estão classificadas por dono.
- [ ] cada workstream tem um próximo marco único.
- [ ] MASTER e NEXT-STEPS refletem os fatos novos.
- [ ] nenhum quarto workstream foi ativado sem necessidade objetiva.

Ao cumprir:

`MASTER_CYCLE=COMPLETE`

## Não reabrir sem nova evidência

- decisão de manter três repositórios canônicos separados;
- decisão de manter Core como MASTER;
- decisão de retirar progressivamente infraestrutura do Mobile;
- regra de não reconstruir por cima da produção.
