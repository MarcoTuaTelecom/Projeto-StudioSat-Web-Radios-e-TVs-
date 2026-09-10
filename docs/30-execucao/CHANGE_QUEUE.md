# StudioSat Web — Change Queue

Regra: **uma alteração ativa por vez no host de produção**. Engenharia de TV e Rádio podem preparar artefatos em paralelo, mas mudanças no Core ou no host entram nesta fila.

Protocolo obrigatório: `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`.

Diretriz vigente: **IN-PLACE FIRST / NO CONTAINERS / NO DUPLICATE PLATFORM**.

Handoff TV vigente: `docs/00-core/SHARED_FOUNDATION_HANDOFF_TO_TV_v0.2_IN_PLACE.md`.

Plano Rádio vigente: **PROVISÓRIO até fechamento da CHG-004X**. Nenhuma decisão de engine, restart ou remodelagem é final antes da análise do FULL RAY-X v3.1.

## Leis atuais

- a plataforma atual é a base oficial;
- **NO CONTAINERS / NO VMs**;
- não criar segunda árvore permanente `/srv/studiosat/...`;
- não duplicar MediaMTX, NGINX/TLS, registry ou biblioteca;
- shadow apenas do componente candidato, temporário e somente se evidência justificar;
- preservar station IDs, roots e paths públicos quando possível;
- toda mudança com precheck, candidate/backup pequeno, validação e rollback;
- nenhum restart Country/Rock/TV/Core antes do FULL RAY-X v3.1 ser analisado.

## Trilha crítica atual — primeiro medir tudo, depois reavaliar

| ID | Mudança | Dono | Estado atual | Gate |
|---|---|---|---|---|
| CHG-000 | Freeze operacional + protocolo de coordenação | Core | **IN EFFECT** | manter fora da change ativa |
| CHG-001 | Core preflight inicial | Core | **DONE / PASS** | baseline histórico conhecido |
| CHG-002 | Channels Registry inicial | Core | **DONE / PASS** | será revalidado pelo FULL RAY-X |
| CHG-003 | Core Contract v0.1 | Core + TV + Rádio | **DONE / ACCEPTED** | três domínios aceitos |
| CHG-004X | **FULL RAY-X v3.1 EXAUSTIVO** | Rádio + Core | **READY — ÚNICA PRÓXIMA AÇÃO NO HOST** | pacote íntegro + análise integral + reavaliação completa |
| CHG-004 v0.1 | Health global read-only antigo | Core | **DEFERRED / SUPERSEDED COMO DIAGNÓSTICO** | decidir depois se reaproveita no health definitivo |
| CHG-004C | Country Reference Restart | Rádio + Core | **BLOCKED por CHG-004X** | somente se a reavaliação demonstrar que restart é a próxima ação correta |
| CHG-005R | Radio Rock | Rádio + Core | **BLOCKED por CHG-004X** | causa e prioridade redefinidas por evidência atual |
| CHG-005S | Segurança compartilhada | Core | **BLOCKED por CHG-004X** | dependências mapeadas antes de mutação |
| CHG-006R+ | Remodelagem in-place das rádios | Rádio + Core | **PROVISIONAL / BLOCKED** | sequência inteira será reescrita após raio-X |
| CHG-TV-* | TVKIDS/TVTEENS/TVVIVA/TVMAISJOVEM | Engenharia TV + Core quando compartilhado | **TV-OWNED** | frente Rádio observa compatibilidade, não implementa TV |

## O FULL RAY-X v3.1 deve provar

O relatório precisa mapear, com evidência atual do host:

```text
ferramentas/pacotes
→ rotinas/timers/cron
→ todos os serviços
→ todos os processos + CWD/executável
→ scripts/configs
→ filesystem/diretórios
→ cada station
→ playlist real e referências
→ assets reais, tamanhos e formatos
→ processo/engine e origem aberta
→ MediaMTX/path/tracks
→ HLS/RTSP/RTMP
→ NGINX/vhost/TLS
→ domínio/subdomínio/DNS
→ teste HTTP/HTTPS
→ tempos/velocidades
```

Além disso, deve inventariar Samba/ingest, listeners, firewall local, recursos do host, packages e qualquer outro web server/proxy detectado.

## Escopo obrigatório da reavaliação pós-CHG-004X

A análise deve responder, com evidência atual, o que será **KEEP / FIX / REFACTOR / REPLACE / REMOVE**, a causa real de cada incidente, se Country deve ou não ser reiniciada, se outro engine Rádio é realmente necessário, como obter A/V + áudio-only com o mínimo de camadas e quais interfaces Core ficam congeladas para a Engenharia TV.

## Interlocks ativos

1. **Não reiniciar Country ainda.**
2. Não reiniciar Rock para diagnóstico.
3. Não reiniciar MediaMTX, NGINX ou TVs.
4. Não instalar Liquidsoap, ffplayout, Docker, Podman ou qualquer runtime/engine.
5. Não criar `/srv/studiosat/...`.
6. Não mover ou duplicar biblioteca.
7. Não alterar generator, playlists ou units antes da análise.
8. `candidates/CHG-004X/studiosat-full-rayx-v2.sh` está **SUPERSEDED** e não deve ser executado.
9. Candidate vigente: `candidates/CHG-004X/studiosat-full-rayx-v3.sh`.
10. Se a Engenharia TV publicar alteração no `main`, reler antes da execução.

## Regra de carga do diagnóstico

O v3.1 faz `ffprobe` sequencial de todos os assets reconhecidos. Não há transcode nem decode integral, mas a coleta pode demorar. Executar com `nice` e, se disponível, `ionice` de baixa prioridade para minimizar competição com o on-air.

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
SUPERSEDED
```

Apenas uma change pode estar em `EXECUTING` no host de produção.

## Regra de documentação

Toda mudança registra objetivo, baseline commit, arquivos/hashes, precheck, candidate/backup, responsável, comandos planejados e executados, validação antes/depois, métricas, correções, scripts finais, rollback, resultado, timestamps e Stage Report sanitizado.

Depois de `VERIFYING`, uma change só vira `DONE` quando Stage Report, artefatos finais, reavaliação arquitetural e nova Change Queue estiverem publicados e o `main` tiver sido relido novamente.
