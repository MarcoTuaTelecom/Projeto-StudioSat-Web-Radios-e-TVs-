# Rádio Principal — Backlog e Gates da Reconstrução V1

| ID | Prioridade | Entrega | Estado atual | Critério de conclusão |
|---|---|---|---|---|
| RP-000 | P0 | Produção protegida | Em vigor | nenhuma mudança V2 derruba produção |
| RP-010 | P1 | LIVE RadioBOSS estável | Aberto | Harbor sem microflaps por janela de soak |
| RP-020 | P2 | Canonical Effective Queue | Aberto | current/next/virtual events alinhados |
| RP-030 | P3 | Asset Reconciler | Parcial | missing gera upload automático e READY |
| RP-040 | P3 | Transfer Manager | Parcial | progresso/retry/prioridade/audit |
| RP-050 | P4 | Execution Engine V2 | Aberto | mesmo item + drift <=5s em path test |
| RP-060 | P5 | Hora Certa adapter | Aberto | saytime validado no V2 |
| RP-070 | P5 | Temperatura adapter | Aberto | temperatura validada |
| RP-080 | P5 | Comerciais/Scheduler | Aberto | eventos equivalentes ao RadioBOSS |
| RP-090 | P6 | Operator API | Scaffold apenas | API instalada, autenticada e testada |
| RP-100 | P6 | Operator Web UI | Não iniciado | técnico opera sem shell |
| RP-110 | P6 | Auth / Users / RBAC | Não iniciado | login, roles, permissões, MFA admin/técnico |
| RP-120 | P6 | Audit Log | Não iniciado | toda ação crítica auditada |
| RP-130 | P6 | Reports | Não iniciado | relatórios operacionais/export |
| RP-140 | P7 | Selector V2 anti-flap | Não iniciado | failover/handoff estáveis em test path |
| RP-150 | P8 | Soak / comparison | Não iniciado | horas/dias sem divergência editorial |
| RP-160 | P9 | Cutover | Bloqueado | todos gates anteriores aprovados |
| RP-170 | P10 | Legacy cleanup | Bloqueado | produção V2 estável + rollback encerrado |

## Regras

1. Só uma prioridade crítica pode causar mudança na produção por vez.
2. Toda entrega nasce em paralelo.
3. Nenhuma etapa é “concluída” sem evidência.
4. Nenhum legado é apagado antes do cutover estável.
5. Toda mudança recebe Change ID, rollback e prova.
6. A interface do técnico é parte do produto, não um acessório.
