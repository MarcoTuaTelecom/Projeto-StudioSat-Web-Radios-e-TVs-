# StudioSat Web — Stage Reports

Este diretório registra o resultado real de cada etapa executada no projeto.

## Regra

Nenhuma Change avança para `DONE` sem um relatório correspondente neste diretório.

## Nome

```text
CHG-XXX-AAAA-MM-DD-descricao.md
```

## Template obrigatório

```markdown
# CHG-XXX — Título

Status: PLANNED | EXECUTING | PASS | FAIL | ROLLED_BACK
Owner: Core | TV | Rádio
Baseline commit: <sha>
Start UTC: <timestamp>
End UTC: <timestamp>

## Objetivo

## Escopo autorizado

## Estado antes

## Arquivos/hashes antes

## Comandos planejados

## Comandos realmente executados

## Alterações/correções ocorridas

## Scripts finais usados
- path GitHub
- versão
- blob/commit SHA
- validação

## Validação antes

## Validação depois

## Métricas antes/depois

## Impacto nas demais stations

## Resultado

## Rollback

## Evidências privadas
Descrever somente identificadores/hashes/localização segura; não publicar segredos ou dumps privados.

## Pendências

## Próximo gate

## Commit de fechamento
```

## Princípio

O relatório descreve **o que realmente aconteceu**, não apenas o que estava planejado. Se houve correção de script durante a execução, a correção deve aparecer no relatório e a versão final precisa estar versionada no repositório antes da próxima etapa.
