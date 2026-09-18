# ÂNCORA 01 — RÁDIO PRINCIPAL / RadioBOSS → NS1

## Identidade fixa

- `WORKSTREAM_ID`: `RADIOPRINCIPAL-NS1`
- Nome recomendado do chat atual: `01 — RÁDIO PRINCIPAL — RadioBOSS → NS1 — C02`
- Repositório mestre: `MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-`
- Emissora: `radioprincipal`
- Missão desta frente: concluir o pipeline RadioBOSS → snapshots/playback → mirror/runtime → playout shadow NS1 e entregar uma interface estável ao futuro workstream de failover.

---

# 1. RESULTADO FINAL DESTA FRENTE

Este chat **não existe para melhorar indefinidamente a Rádio Principal**.

Ele existe para chegar a um ponto objetivo:

> **Rádio Principal com RadioBOSS como autoridade editorial, estado de playback e programação sincronizados de forma confiável, mídia necessária disponível no NS1, playout shadow do NS1 coerente com a programação, scheduler/hora certa validados e handoff formal pronto para o workstream de failover/selector.**

Quando isso estiver comprovado, esta frente deve ser marcada `READY_FOR_HANDOFF` ou `DONE` e parar de expandir escopo.

---

# 2. ESCOPO EXATO

## 2.1 RadioBOSS como autoridade

Confirmar e preservar:

- RadioBOSS é a origem editorial principal;
- playlist/programação/biblioteca são exportadas/sincronizadas;
- estado de reprodução atual possui uma fonte única e identificada;
- timestamps/revisões/hashes permitem detectar atualização real.

## 2.2 Snapshots

Trabalhar somente com os contratos necessários:

- `playlist.json`;
- `schedule.json`;
- `librarymanifest.json`;
- `playback.json` ou o contrato que vier a substituí-lo formalmente.

Cada snapshot precisa ter:

- origem conhecida;
- revisão/versão;
- timestamp;
- validação mínima de estrutura;
- comportamento conhecido quando estiver ausente ou desatualizado.

## 2.3 Mirror de mídia

Responsável por:

- determinar quais mídias são necessárias;
- mapear origem → destino;
- materializar/indexar para o usuário/runtime real de playout;
- medir `TOTAL`, `AVAILABLE`, `MISSING`;
- produzir lista exata dos ausentes;
- impedir que “arquivo existente em storage” seja confundido com “arquivo utilizável pelo playout”.

## 2.4 Runtime / controller

Responsável por:

- geração real do mirror;
- persistência de runtime;
- posição/índice atual;
- transição entre itens;
- evitar geração falsa causada por wrapper/hash instável;
- manter contrato simples e auditável entre controller e playout.

## 2.5 Playout shadow NS1

Responsável por fazer o NS1 reproduzir coerentemente o estado conhecido da Rádio Principal sem assumir ainda o caminho público.

O shadow deve ser independente o suficiente para ser testado sem afetar `radioprincipal` público.

## 2.6 Scheduler / Hora Certa

Apenas o necessário para reproduzir corretamente eventos de programação obrigatórios.

Não transformar esta frente em um sistema editorial novo.

---

# 3. TOPOLOGIA QUE ESTE CHAT DEVE PRESERVAR

Conceitualmente:

```text
RadioBOSS
   │
   ├── áudio/entrada autoritativa ──> radioprincipal-rb
   │
   ├── playlist/schedule/librarymanifest
   │
   └── playback state
             │
             ▼
      sync / mirror / controller
             │
             ▼
        runtime NS1
             │
             ▼
      playout shadow NS1
             │
             ▼
      radioprincipal-ns1
```

O caminho público `radioprincipal`, o selector e OBS/live pertencem prioritariamente ao workstream de failover/streaming. Este chat só fornece os contratos e a saída necessária.

---

# 4. NÃO É RESPONSABILIDADE DESTE CHAT

Não deve:

- redesenhar Nginx global;
- redesenhar MediaMTX global;
- alterar TLS/domínios;
- desenvolver Portal/CMS;
- desenvolver Mobile;
- corrigir Pop/Rock/Clássicas/Country;
- reestruturar TV;
- implementar o selector público completo;
- mudar OBS/live;
- criar uma nova arquitetura porque um script local falhou.

Se um problema for claramente dessas áreas, gerar uma **DEPENDÊNCIA**, não absorvê-lo.

---

# 5. FASES OBRIGATÓRIAS

## Fase A — Baseline vivo

Somente leitura.

Confirmar:

- serviços/timers;
- processos relevantes;
- snapshots e idades;
- revisões/hashes;
- mirror generation;
- runtime generation;
- total/available/missing;
- fonte de playback;
- usuário e caminhos reais do playout;
- paths/publishers necessários apenas para observar shadow/entrada.

**Saída:** tabela `CONFIRMADO / MUDOU / OBSOLETO / PENDENTE`.

Não corrigir nada durante a coleta inicial, salvo risco operacional evidente.

## Fase B — Contrato de playback

Escolher **uma única fonte canônica** para “o que está tocando/agendado agora”.

Eliminar dependência ambígua entre:

- `playback.json`;
- `radioboss-live.json`;
- `matched_index`;
- índices derivados.

**Saída:** contrato documentado e teste que prova que o playout segue a fonte escolhida.

## Fase C — Mirror de mídia

Fechar lacunas de mídia.

**Saída:** `MISSING=0` para a janela definida ou exceções explicitamente justificadas e aprovadas.

## Fase D — Runtime estável

Eliminar geração falsa, drift e transições incorretas.

**Saída:** runtime persiste e muda somente por evento real previsto.

## Fase E — Scheduler / Hora Certa

Validar eventos temporais necessários.

**Saída:** teste reproduzível com resultado PASS/FAIL.

## Fase F — Shadow

Executar o NS1 em shadow sem assumir o caminho público.

**Saída:** shadow reproduz sequência e estado esperados durante a janela de teste definida no plano da change.

## Fase G — Handoff

Entregar ao `FAILOVER-SELECTOR`:

- entrada RadioBOSS;
- saída shadow NS1;
- health de cada uma;
- regra de readiness;
- comportamento de retorno;
- limitações conhecidas.

Depois disso, **este chat não deve implementar o failover público**.

---

# 6. DEFINITION OF DONE

Este workstream só pode ser declarado concluído quando TODOS os critérios abaixo estiverem comprovados ou formalmente excetuados:

- [ ] baseline vivo registrado;
- [ ] fonte canônica de playback definida e testada;
- [ ] snapshots com contrato/timestamp/revisão conhecidos;
- [ ] mídia necessária materializada/indexada;
- [ ] lista de missing encerrada ou exceções aprovadas;
- [ ] controller/runtime sem geração falsa conhecida;
- [ ] playout NS1 segue o estado esperado;
- [ ] scheduler/hora certa testados;
- [ ] shadow `radioprincipal-ns1` validado;
- [ ] nenhuma mudança pública depende de hipótese não testada;
- [ ] rollback conhecido;
- [ ] ACTIVE STATE atualizado;
- [ ] handoff para failover produzido.

Quando isso acontecer, responder explicitamente:

`RADIOPRINCIPAL_NS1=READY_FOR_HANDOFF`

E parar de criar melhorias adicionais dentro desta frente.

---

# 7. PROTOCOLO ANTI-LOOP

## Regra das duas tentativas

Se duas correções da mesma hipótese não gerarem progresso mensurável:

1. parar;
2. não criar “v2/v3/v4” às cegas;
3. comparar estado antes/depois;
4. identificar a evidência que falta;
5. executar diagnóstico mínimo;
6. reformular a hipótese.

## Regra dos três erros

Se três scripts/comandos sucessivos falharem por erro básico de sintaxe, quoting, path ou linguagem:

- suspender alterações;
- voltar a `READ_ONLY_DIAGNOSTIC`;
- simplificar o script;
- validar sintaxe antes de entregar;
- só retomar mudança depois de um comando diagnóstico correto.

## Proibido

- mudar várias camadas ao mesmo tempo;
- editar Nginx + MediaMTX + mirror + systemd numa única tentativa;
- esconder erro com `|| true` em teste que deveria bloquear promoção;
- considerar sucesso apenas porque o processo está rodando;
- considerar mídia disponível apenas porque existe em algum storage;
- criar novo daemon quando o defeito ainda não foi localizado.

---

# 8. DISCIPLINA DE COMANDOS E SCRIPTS

Todo comando entregue deve declarar:

```text
HOST: NS1 | WINDOWS/RADIOBOSS | OUTRO
MODO: READ-ONLY | MUTÁVEL
OBJETIVO:
ROLLBACK: se aplicável
```

Antes de fornecer Bash:

- revisar quoting;
- preferir `set -Eeuo pipefail` em scripts mutáveis/diagnósticos estruturados;
- validar com `bash -n` quando o script for criado no Git;
- não misturar sintaxe PowerShell.

Antes de PowerShell:

- evitar escapes de Bash;
- usar caminhos Windows reais;
- não supor ferramentas Unix não instaladas.

---

# 9. UMA MUDANÇA POR VEZ

Para qualquer correção:

```text
HIPÓTESE
↓
EVIDÊNCIA
↓
MUDANÇA MÍNIMA
↓
TESTE
↓
PASS → registrar
FAIL → rollback/diagnóstico
```

Não avançar para a próxima correção sem classificar o resultado da anterior.

---

# 10. FORMATO OBRIGATÓRIO DE PROGRESSO

A cada marco, atualizar:

```text
RADIOPRINCIPAL-NS1 STATUS
PHASE:
OBJECTIVE:
LAST_CONFIRMED_FACT:
LAST_CHANGE:
RESULT: PASS | FAIL | PARTIAL
BLOCKER:
NEXT_SINGLE_STEP:
DOD_PROGRESS: X/12
```

Isso deve impedir que a conversa perca o ponto atual.

---

# 11. REGRA DE FOCO

Se o usuário trouxer um problema lateral, primeiro responder:

```text
IMPACTO NO DOD: REQUIRED | DEPENDENCY | BACKLOG
```

Somente `REQUIRED` entra imediatamente neste chat.

---

# 12. PRIMEIRA TAREFA DO C02

Não começar corrigindo.

Começar reconstruindo um baseline vivo único da Rádio Principal e compará-lo com:

- `project-context/chats/active/RADIOPRINCIPAL-NS1.md`;
- `project-context/00-MASTER.md`;
- evidências atuais do NS1;
- estado atual do RadioBOSS quando necessário.

A saída obrigatória é uma matriz:

```text
ITEM | ESTADO DOCUMENTADO | ESTADO VIVO | CLASSIFICAÇÃO | EVIDÊNCIA | AÇÃO
```

Depois escolher **apenas o primeiro item necessário ao Definition of Done**.
