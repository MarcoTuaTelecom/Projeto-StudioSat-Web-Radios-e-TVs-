# StudioSat Web — Change Queue

Regra: **uma alteração ativa por vez no host de produção**. Engenharia de TV e Rádio podem preparar artefatos em paralelo, mas mudanças no Core ou no host entram nesta fila.

Protocolo obrigatório: `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`.

Última evidência Core: `docs/40-stage-reports/CHG-001-2026-09-10-core-preflight.md`.

Matriz de risco atual: `docs/90-evidencias/P0_P1_P2_2026-09-10.md`.

| ID | Mudança | Dono | Estado atual | Gate |
|---|---|---|---|---|
| CHG-000 | Freeze operacional + protocolo de coordenação | Core | **IN EFFECT** | manter até autorização explícita de cada change |
| CHG-001 | Core preflight somente leitura | Core | **DONE / PASS** | evidência íntegra; 8 ready, Radio Rock failed; stage report publicado |
| CHG-002 | Channels Registry real | Core | **DONE / PASS** | `registry/channels-registry.yaml` publicado a partir da CHG-001 |
| CHG-003 | Core Contract v0.1 | Core + TV + Rádio | **CORE+TV ACCEPTED; ENGENHARIA RÁDIO PENDENTE** | aceite dos três domínios antes dos labs/health executáveis |
| CHG-004 | Health read-only dos 9 canais | Core | **BLOCKED por CHG-003; pode ser preparado como candidate** | health real disponível sem mutação do host |
| CHG-005 | Incidentes P0 do legado / segurança | Domínio responsável + Core | **BLOCKED por gates; P0 identificados** | mapear dependências antes de remediar; sem regressão |
| CHG-006 | TVKIDS canonical/TVLAB | TV | **BLOCKED** | proteger contra restart com gerador atual; zero DTS no lab + stage report |
| CHG-007 | TVKIDS cutover | TV + Core | BLOCKED | 24 h saudável + rollback preservado |
| CHG-008 | Country Radio LAB | Rádio | BLOCKED | A/V + áudio-only aprovados |
| CHG-009 | Country live/fallback/shadow | Rádio | BLOCKED | shadow ≥24 h |
| CHG-010 | Core Compatibility Gate | Core | BLOCKED | 1 TV + 1 Rádio compatíveis; MediaMTX/NGINX/ingress/naming/health revisados |
| CHG-011 | Country cutover | Rádio + Core | BLOCKED | 24–72 h saudável |
| CHG-012+ | Migração rádios restantes | Rádio + Core | BLOCKED | uma por vez |
| CHG-020+ | Migração TVs restantes | TV + Core | BLOCKED | uma por vez |
| CHG-030 | Control Plane funcional | Core | FUTURE | engines comprovados |
| CHG-040 | CDN / HA | Core | FUTURE | capacidade/criticidade |
| CHG-050 | Retirada do legado | Core + domínios | FUTURE | estabilidade + rollback preservado |

## Interlocks ativos descobertos pela CHG-001

1. **NÃO REINICIAR TVs por modernização neste momento.** O gerador global atual foi modificado depois do start dos quatro processos TV e hoje usa `ready/`; um restart pode reconstruir a playlist com conteúdo diferente do que está no ar.
2. **Radio Rock continua failed.** Não mascarar nem migrar antes de change de recuperação própria.
3. **Samba possui achado P0 sanitizado.** Não publicar detalhes; mapear clientes e firewall GCP/VPC antes da contenção.
4. **MediaMTX não deve ser endurecido ainda.** Listeners/auth precisam ser confrontados com publishers reais e firewall de nuvem.
5. **TVKIDS está DEGRADED por DTS**, embora systemd e MediaMTX estejam ativos/ready.
6. Resultados `HLS FAIL:302` e `RTMP FAIL` de rádio do preflight v1.0 são limitações de probe, não prova de outage. O script v1.1 corrige parte dessa instrumentação.

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
```

Apenas uma change pode estar em `EXECUTING` no host de produção.

## Regras de uma Change

Toda mudança deve registrar:

- objetivo;
- baseline commit do GitHub;
- arquivos afetados;
- hashes antes/depois;
- diff/candidate;
- responsável;
- janela;
- pré-condições;
- comandos planejados;
- comandos realmente executados;
- validação antes;
- validação depois;
- métricas antes/depois;
- correções de scripts ocorridas;
- versão final dos scripts no GitHub;
- rollback;
- resultado;
- timestamps;
- Stage Report sanitizado.

Nenhuma mudança Core pode ser aprovada apenas por um domínio.

## Gate de sincronização

Antes de mudar qualquer estado para `READY` ou `EXECUTING`:

1. reler `main`;
2. comparar mudanças desde o último checkpoint;
3. verificar trabalho publicado por TV e Rádio;
4. confirmar ausência de conflito em Core/host;
5. atualizar plano e rollback se necessário.

Depois de `VERIFYING`, a change só vira `DONE` quando documentação, scripts finais e Stage Report estiverem publicados e o `main` tiver sido relido novamente.
