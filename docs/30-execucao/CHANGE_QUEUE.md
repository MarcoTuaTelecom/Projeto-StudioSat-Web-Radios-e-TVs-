# StudioSat Web — Change Queue

Regra: **uma alteração ativa por vez no host de produção**. Engenharia de TV e Rádio podem preparar artefatos em paralelo, mas mudanças no Core ou no host entram nesta fila.

Protocolo obrigatório: `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`.

Diretriz vigente: **IN-PLACE FIRST / NO CONTAINERS / NO DUPLICATE PLATFORM**.

Handoff TV vigente: `docs/00-core/SHARED_FOUNDATION_HANDOFF_TO_TV_v0.2_IN_PLACE.md`.

Plano Rádio vigente: **PROVISÓRIO até fechamento da CHG-004X**. O raio-X completo pode alterar ordem, engine, normalização e prioridades.

## Leis atuais

- a plataforma atual é a base oficial;
- **NO CONTAINERS / NO VMs**;
- não criar segunda árvore permanente `/srv/studiosat/...`;
- não duplicar MediaMTX, NGINX/TLS, registry ou biblioteca;
- shadow apenas do componente candidato, temporário e somente se necessário;
- preservar station IDs, roots e paths públicos quando possível;
- toda mudança com precheck, candidate/backup pequeno, validação e rollback;
- nenhum restart Country antes do raio-X v2 ser analisado.

## Trilha crítica atual — primeiro medir, depois reavaliar

| ID | Mudança | Dono | Estado atual | Gate |
|---|---|---|---|---|
| CHG-000 | Freeze operacional + protocolo de coordenação | Core | **IN EFFECT** | manter fora da change ativa |
| CHG-001 | Core preflight inicial | Core | **DONE / PASS** | baseline histórico conhecido |
| CHG-002 | Channels Registry inicial real | Core | **DONE / PASS** | será revalidado pelo novo raio-X |
| CHG-003 | Core Contract v0.1 | Core + TV + Rádio | **DONE / ACCEPTED** | três domínios aceitos |
| CHG-004X | **Full Ray-X v2 da plataforma atual** | Rádio + Core | **READY — ÚNICA PRÓXIMA AÇÃO NO HOST** | pacote íntegro + análise completa + reavaliação do projeto |
| CHG-004 | Health global read-only | Core | **DEFERRED** | decidir após CHG-004X se permanece separado ou vira parte do health definitivo |
| CHG-004C | Country Reference Restart | Rádio + Core | **BLOCKED por CHG-004X** | somente após reavaliação; não reiniciar antes |
| CHG-005R | Radio Rock | Rádio + Core | **BLOCKED por CHG-004X** | ordem/correção redefinidas após raio-X |
| CHG-005S | Segurança compartilhada | Core | **BLOCKED por CHG-004X** | mapear dependências antes de mutação |
| CHG-006R+ | Remodelagem in-place das rádios | Rádio + Core | **PROVISIONAL / BLOCKED** | sequência inteira será reavaliada após raio-X |
| CHG-TV-* | TVKIDS/TVTEENS/TVVIVA/TVMAISJOVEM | Engenharia TV + Core quando compartilhado | **TV-OWNED** | Engenharia Rádio não implementa TV; shared Core não pode ser substituído unilateralmente |

## Escopo obrigatório da reavaliação após CHG-004X

A análise deve responder, com evidência atual:

```text
1. O que já funciona perfeitamente e deve ser mantido?
2. O que está quebrado agora?
3. Country pode reiniciar com segurança usando o sistema atual?
4. Qual é a causa real atual da Rock?
5. O gerador global deve ser mantido, dividido ou corrigido?
6. ready/ e canonical/ representam biblioteca, estado ou ambos?
7. Existe duplicação física desnecessária hoje?
8. O FFmpeg atual é suficiente para a Rádio alvo?
9. Se não for, qual capacidade concreta exige outro engine?
10. Como obter A/V + áudio-only na mesma timeline com mínimo de camadas?
11. Como live locutor/câmera entra sem quebrar o Core?
12. Quais partes de MediaMTX/NGINX/TLS/systemd já estão adequadas?
13. Quais mudanças compartilhadas são realmente necessárias?
14. O que a Engenharia TV deverá apenas consumir/estender, sem refazer?
15. Qual passa a ser a nova ordem exata das changes?
```

## Interlocks ativos

1. **Não reiniciar Country ainda.**
2. Não reiniciar MediaMTX ou NGINX para diagnóstico.
3. Não reiniciar TVs a partir da frente Rádio.
4. Não instalar Liquidsoap, ffplayout, Docker, Podman ou qualquer outro engine/runtime antes da reavaliação.
5. Não criar `/srv/studiosat/...`.
6. Não mover ou duplicar biblioteca.
7. Não alterar generator, playlist ou units antes de conhecer o estado real atual.
8. Se a Engenharia TV publicar alteração no `main`, reler antes da execução.

## Estados permitidos

```text
DRAFT
BLOCKED
READY
EXECUTING
VERIFYING
PASS
FAIL
ROLLED_BACK
DONE
DEFERRED
PROVISIONAL
```

Apenas uma change pode estar em `EXECUTING` no host de produção.

## Regra de documentação

Toda mudança registra objetivo, baseline commit, arquivos/hashes, precheck, candidate/backup, responsável, comandos planejados e executados, validação antes/depois, métricas, correções, scripts finais, rollback, resultado, timestamps e Stage Report sanitizado.

Depois de VERIFYING, uma change só vira DONE quando Stage Report e artefatos finais estiverem publicados e o `main` tiver sido relido novamente.
