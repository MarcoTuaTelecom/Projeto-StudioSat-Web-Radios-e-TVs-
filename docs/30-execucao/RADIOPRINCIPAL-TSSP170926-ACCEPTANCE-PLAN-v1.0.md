# Rádio Principal — TSSP170926 Acceptance Plan v1.0 — SUPERSEDED

## Estado

`SUPERSEDED` em 2026-09-17.

Este documento foi criado durante a definição inicial da regra de negócio e utilizava a diferença visual entre uma captura parcial da programação e contagens históricas do mirror como gate de diagnóstico.

Essa premissa foi posteriormente esclarecida como inválida para o novo contrato:

- a estrutura histórica antecede as regras atuais;
- a captura de tela era apenas exemplo da programação em andamento;
- a quantidade visível pode representar somente parte do período/programa;
- contagens antigas podem representar objetos diferentes;
- a aceitação deve ser semântica, e não baseada em igualdade com contagens históricas.

## Documentos sucessores

Usar como autoridade:

- `docs/10-radio/RADIOPRINCIPAL-RADIOBOSS-NS1-AUTHORITY-REPLICATION-v1.0.md`
- `docs/10-radio/RADIOPRINCIPAL-RADIOBOSS-NS1-AUTHORITY-REPLICATION-v1.1-ADDENDUM.md`
- `docs/30-execucao/RADIOPRINCIPAL-CURRENT-PROGRAM-SHADOW-SYNC-PLAN-v1.0.md`

## Regra vigente

O teste passa quando o NS1 consegue identificar e normalizar a programação/grade atualmente autoritativa, montar sua fila efetiva, resolver seus assets, manter o shadow sincronizado e continuar essa mesma programação em caso de perda do estúdio.

A quantidade de itens de uma captura histórica não é critério de aceitação.
