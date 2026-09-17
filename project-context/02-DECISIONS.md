# Studio Sat — Decisões de arquitetura

## D-001 — O repositório Core é o MASTER

**Status:** aceito para a reorganização v2.

`Projeto-StudioSat-Web-Radios-e-TVs-` permanece como repositório mestre de arquitetura, operações e coordenação.

Motivo: ele já contém contratos Core, Change Queue, candidatos, evidências, Rádio e TV. Criar um quarto repositório aumentaria a fragmentação.

## D-002 — Portal e Mobile permanecem separados

**Status:** aceito.

Não transformar tudo em monorepo neste momento.

Motivo: Portal e Mobile têm ciclos de build/deploy diferentes e podem ser validados/rollbackados independentemente.

## D-003 — Infraestrutura sai do Mobile

**Status:** migração progressiva.

Scripts que administram NS1/NS2, Nginx, MediaMTX, health, recuperação de portal, mirror ou playout devem existir de forma canônica no Core.

Antes de apagar uma cópia do Mobile:

1. copiar para Core;
2. comparar conteúdo/hash;
3. validar sintaxe;
4. executar em modo read-only ou laboratório quando aplicável;
5. registrar promoção;
6. só então remover a duplicata.

## D-004 — PWA/download são superfície web

**Status:** planejado.

`web/pwa` e `web/download` do repositório Mobile devem ser avaliados para migração ao Portal. Não mover antes de confirmar o deploy público atual e os assets necessários.

## D-005 — Uma única fonte de verdade para conteúdo das emissoras

**Status:** direção arquitetural.

O Portal/CMS é a fonte editorial. O Mobile deve consumir o contrato público e manter fallback local apenas para disponibilidade básica.

## D-006 — Operação nunca depende do histórico do chat

**Status:** aceito.

Decisões, estado, próximos passos e handoffs relevantes devem ser registrados em Git. Chats podem ser descartados/substituídos sem perder a fonte técnica permanente.

## D-007 — Produção não é laboratório

**Status:** preservado da arquitetura anterior.

Toda mudança operacional deve ter baseline, validação, rollback e health pós-mudança. Reorganização de repositório não autoriza reinstalar ou substituir serviços em produção.
