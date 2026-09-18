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


## D-008 — RadioBOSS é a autoridade editorial da Rádio Principal

**Status:** aceito e obrigatório.

Enquanto o RadioBOSS estiver operacional, ele define a programação efetiva. O NS1 é transmissor contínuo, réplica executável e contingência. O NS1 não deve manter uma programação editorial independente para failover.

## D-009 — LIVE, controle e assets são planos separados

**Status:** aceito.

O sistema deve tratar separadamente:
- áudio LIVE;
- snapshots/controle;
- transferência e disponibilidade de mídia.

Heartbeat/playback frescos não provam que o áudio Harbor está saudável.

## D-010 — Failover deve preservar conteúdo editorial

**Status:** aceito.

Quando o LIVE cair, o NS1 deve assumir a mesma grade, item e posição aproximada, preservando eventos e comandos. Um fallback com playlist diferente é considerado falha funcional.

## D-011 — Produção da Rádio Principal fica congelada durante reconstrução

**Status:** aceito.

Candidates e testes novos não podem reiniciar selector, shadow público, MediaMTX, Nginx ou Harbor. Desenvolvimento usa paths V2 isolados até gates de promoção.

## D-012 — Canonical Effective Queue substitui índice físico como modelo editorial

**Status:** aceito.

`playlistpos` pode incluir itens virtuais e scheduler. Media-map físico não é suficiente para representar a programação. A V2 deve persistir uma fila efetiva que contenha mídia e comandos virtuais na ordem executável.

## D-013 — Assets são identificados por conteúdo e sincronizados automaticamente

**Status:** aceito.

SHA256 é identidade canônica de mídia. Missing deve disparar transferência automática do PC do estúdio, com prioridade current/next, deduplicação, validação e auditabilidade.

## D-014 — Operação humana é parte obrigatória do produto

**Status:** aceito.

A Rádio Principal deve possuir console web próprio com autenticação, usuários, RBAC, programação, biblioteca, transfer manager, manutenção, auditoria e relatórios. Rotina normal não pode depender de shell/MobaXterm.

## D-015 — PC local deve ter automação mínima

**Status:** aceito.

Meta operacional: RadioBOSS visível + um único agente Studio Sat oculto iniciado automaticamente no boot. O operador não deve abrir manualmente túneis, sincronizadores ou múltiplas aplicações auxiliares.

## D-016 — Status de artefato deve ser explícito

**Status:** aceito.

Todo artefato relevante deve ser classificado como:
- PREPARADO NO GITHUB;
- INSTALADO;
- ATIVO;
- VALIDADO;
- PROMOVIDO PARA PRODUÇÃO;
- FALHOU;
- ROLLBACK APLICADO;
- OBSOLETO/NÃO USAR.

A palavra “pronto” isoladamente não é aceita como evidência.
