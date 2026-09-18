# Rádio Principal — Backlog e Gates da Reconstrução V1

**Atualização:** 2026-09-18  
**Referência mestre:** `docs/10-radio/RADIOPRINCIPAL-MASTER-DOSSIER-V4.md`

| ID | Prioridade | Entrega | Estado comprovado | Próxima evidência exigida |
|---|---|---|---|---|
| RP-000 | P0 | Produção protegida/no-downtime | **EM VIGOR** | nenhum candidate reinicia produção |
| RP-010 | P1 | LIVE RadioBOSS estável | **FALHOU C21 / ABERTO** | Harbor established contínuo + soak sem feed stop |
| RP-011 | P1 | Túnel Windows único/supervisionado | **PARCIAL** | C21R deu listener/TCP local, mas logs tiveram connection refused |
| RP-020 | P2 | Canonical Effective Queue | **ABERTO** | current/next/virtual events alinhados |
| RP-021 | P2 | Virtual item classifier | **ABERTO** | `saytime` não aparecer como mídia missing |
| RP-030 | P3 | Asset Reconciler | **PARCIAL** | missing da playlist gera upload automático |
| RP-031 | P3 | Human repository Manhã/Tarde/Noite | **INSTALADO/PARCIAL** | cobertura compatível com playlist real |
| RP-032 | P3 | C22 repository reconciler | **EXECUTADO/PARCIAL** | Manhã 27 -> cobertura real da grade; missing físicos zerados |
| RP-033 | P3 | C24 Edge Bridge | **PREPARADO NO GITHUB** | instalar NS1 + validar plan/health |
| RP-034 | P3 | C25 Windows Automatic Agent | **PREPARADO NO GITHUB** | instalar no boot + upload automático sem operador |
| RP-040 | P3 | Transfer Manager | **ABERTO** | progresso/retry/prioridade/ETA/audit |
| RP-050 | P4 | Execution Engine V2 | **ABERTO** | mesmo item + drift <=5s em test path |
| RP-051 | P4 | C23 isolated shadow | **PREPARADO NO GITHUB** | instalar em `radioprincipal-v2-shadow` e validar |
| RP-052 | P4 | C26 ordered authoritative fallback | **PREPARADO NO GITHUB** | conectar Harbor, validar test path e substituir shadow legado sem reiniciar selector |
| RP-060 | P5 | Hora Certa adapter | **ABERTO** | saytime executado corretamente |
| RP-070 | P5 | Temperatura adapter | **ABERTO** | evento/áudio de temperatura validado |
| RP-080 | P5 | Comerciais/Scheduler | **ABERTO** | equivalência RadioBOSS x V2 |
| RP-090 | P6 | Operator API | **SCAFFOLD/PARCIAL** | API autenticada instalada e testada |
| RP-100 | P6 | Operator Web UI | **NÃO CONCLUÍDO** | técnico opera sem shell |
| RP-110 | P6 | Auth / Users / RBAC / MFA | **NÃO INICIADO COMPLETO** | login, roles, permissões e MFA |
| RP-120 | P6 | Audit Log | **NÃO INICIADO COMPLETO** | toda ação crítica auditada |
| RP-130 | P6 | Reports | **NÃO INICIADO COMPLETO** | relatórios operacionais + export |
| RP-140 | P7 | Selector V2 anti-flap | **NÃO INICIADO** | failover/handoff estáveis em test path |
| RP-150 | P8 | Soak / comparison | **NÃO INICIADO** | horas/dias sem divergência editorial |
| RP-160 | P9 | Cutover | **BLOQUEADO** | todos gates anteriores aprovados |
| RP-170 | P10 | Legacy cleanup | **BLOQUEADO** | V2 estável + rollback encerrado |

## Gates obrigatórios

Nenhuma promoção para produção V2 sem provar simultaneamente:

- Harbor LIVE estável;
- current correto;
- next correto;
- drift <= 5 s;
- current/next assets READY;
- transferência automática funcionando;
- fila efetiva incluindo itens virtuais;
- hora certa;
- temperatura;
- comerciais;
- scheduler;
- metadata;
- shadow V2 contínuo;
- failover testado;
- anti-flap testado;
- console autenticado;
- RBAC;
- audit log;
- relatórios;
- soak;
- rollback.

## Regras

1. Só uma prioridade crítica pode causar mudança na produção por vez.
2. Toda entrega nasce em paralelo.
3. Nenhuma etapa é “concluída” sem evidência.
4. Nenhum legado é apagado antes do cutover estável.
5. Toda mudança recebe Change ID, rollback e prova.
6. A interface do técnico é parte do produto.
7. Não confundir `PREPARADO NO GITHUB` com `INSTALADO`.
8. Não tratar comando virtual como MP3.
9. Não usar playlist física como substituto da fila efetiva.
10. Nenhum teste pode derrubar a Rádio Principal pública.
