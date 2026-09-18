# Rádio Principal — Âncora Mestre V3

Status: **documento de governança e reconstrução**  
Workstream: `RADIOPRINCIPAL-NS1`  
Regra principal: **RadioBOSS é a autoridade editorial; NS1 é transmissor contínuo, réplica executável e plano de contingência.**

---

## 1. Problema real confirmado

A produção atual possui uma cadeia funcional, porém ainda mistura componentes legados com componentes candidatos.

O selector público está configurado com prioridade:

`RadioBOSS Harbor -> shadow NS1 -> blank`.

Isso significa que a prioridade lógica do RadioBOSS já existe. O problema é que o áudio Harbor apresentou microquedas; cada vez que o source fica indisponível, o Liquidsoap entrega o shadow NS1. O shadow atual ainda é o `mirror-playout.py` legado, que não executa a fila efetiva do RadioBOSS com `current + playlistpos + pos_ms + itens virtuais`. Resultado: o ouvinte percebe mudança editorial quando ocorre failover.

A presença de playback/heartbeat atualizados não prova estabilidade do áudio Harbor. São canais diferentes.

---

## 2. Estado factual do projeto

### Produção pública
- selector: `studiosat-radioprincipal-selector.service`;
- path público: `radioprincipal`;
- prioridade configurada: Harbor RadioBOSS, depois `radioprincipal-ns1`, depois blank;
- Harbor: localhost NS1 porta 18005;
- shadow público atual: `mirror-playout.py` legado;
- MediaMTX e Nginx fazem distribuição.

### Autoridade/control plane
- snapshots de playlist, playback, schedule, librarymanifest e heartbeat chegam ao NS1;
- playback possui `current`, `next`, `playlistpos`, `pos_ms`, duração e metadata;
- candidate reconcilia a cada 5 s;
- ainda existe `queue_aligned=false` porque a fila editorial inclui itens virtuais/scheduler e o media-map legado contém somente itens físicos.

### Media plane
- existe `studiosat-media-transfer.service`;
- protocolo real de upload: `PUT /v1/upload/radioprincipal`;
- integridade por SHA256;
- banco de assets/sources/repository_index;
- ainda falta ligar automaticamente: missing detectado -> upload imediato do PC -> validação -> READY.

### Operação humana
- não existe ainda um painel web de operação final, validado e acessível ao técnico;
- uma API/operator-console foi apenas preparada em código, não deve ser tratada como instalada até haver evidência de execução no NS1;
- operação atual ainda depende excessivamente de terminal e paths internos.

---

## 3. Regra de negócio principal

Enquanto RadioBOSS estiver disponível e seu áudio LIVE estiver saudável:
- RadioBOSS é a fonte pública;
- NS1 acompanha silenciosamente a mesma execução;
- NS1 não escolhe programação editorial própria.

Quando o áudio LIVE falhar:
- NS1 assume;
- mesma grade;
- mesmo item;
- posição aproximada do último checkpoint + tempo transcorrido;
- mesma sequência editorial;
- hora certa, temperatura, comerciais, vinhetas e eventos continuam.

Quando LIVE voltar:
- não retornar instantaneamente;
- exigir janela contínua de estabilidade;
- handoff controlado;
- nunca alternar música por música.

---

## 4. Regra de segurança de desenvolvimento

É proibido desenvolver diretamente nos paths públicos.

Protegidos:
- `radioprincipal`;
- `radioprincipal-ns1`;
- selector público;
- Harbor público;
- MediaMTX;
- Nginx.

Toda evolução nasce em paralelo:
- `radioprincipal-v2-shadow`;
- `radioprincipal-v2-test`;
- services `studiosat-radioprincipal-v2-*`;
- estado V2 separado.

Cutover só existe depois de gates objetivos.

---

## 5. Estrutura operacional humana alvo

Caminho oficial do técnico:

`/srv/studiosat/radio-principal/`

Estrutura:

```
/srv/studiosat/radio-principal/
├── grade/
│   ├── manha/
│   ├── tarde/
│   ├── noite/
│   └── ATUAL
├── elementos/
│   ├── comerciais/
│   ├── vinhetas/
│   ├── hora-certa/
│   └── temperatura/
├── operacao/
│   ├── importar/
│   └── quarentena/
└── estado/
```

Essa árvore é para uso humano. Stores internos podem continuar existindo por implementação, porém não são a interface operacional.

---

## 6. Componentes definitivos a construir

### Authority Reader
Lê snapshots do RadioBOSS e produz estado autoritativo normalizado.

### Canonical Effective Queue
Representa exatamente a fila executável:
- mídia física;
- hora certa;
- temperatura;
- comerciais;
- vinhetas;
- chamadas;
- eventos de scheduler;
- comandos virtuais.

### Asset Reconciler
Para cada item físico:
- identifica path original;
- resolve hash;
- verifica NS1;
- dispara upload se ausente;
- acompanha progresso;
- valida;
- torna READY.

### Execution Engine V2
Mantém shadow colado ao RadioBOSS usando:
- current;
- playlistpos;
- pos_ms;
- next;
- checkpoint;
- drift/reseek.

Se perder autoridade fresca, continua localmente pela canonical effective queue.

### Adapters
- saytime/hora certa;
- temperatura;
- comerciais;
- vinhetas;
- scheduler/eventos;
- metadata.

### Selector V2
- prioridade LIVE;
- takeover para shadow;
- anti-flap;
- janela de estabilidade antes do retorno;
- telemetria de cada handoff.

### Operator Console
Interface web para técnico/operador.

### Audit/Reporting
Toda ação humana ou automática gera registro consultável.

---

## 7. Prioridades obrigatórias

**P0 — continuidade pública**  
Manter a rádio no ar e congelar mudanças destrutivas.

**P1 — diagnosticar e estabilizar LIVE RadioBOSS**  
Eliminar microflaps Harbor/túnel/encoder. A prioridade já está configurada; o problema é disponibilidade real do source.

**P2 — canonical effective queue**  
Parar de tratar playlist física como equivalente à fila executada.

**P3 — transferência automática de assets**  
Missing -> upload imediato -> SHA256 -> READY.

**P4 — execution engine V2 isolado**  
Mesmo item/posição, sem tocar produção.

**P5 — elementos editoriais**  
Hora certa, temperatura, comerciais, scheduler e metadata.

**P6 — operator API + UI + autenticação/RBAC**  
Dar controle humano, seguro e auditável.

**P7 — selector V2 + anti-flap**  
Testar apenas em path isolado.

**P8 — soak test**  
Rodar horas/dias em paralelo comparando RadioBOSS x V2.

**P9 — cutover controlado**  
Somente com todos os gates aprovados.

**P10 — limpeza de legado**  
Aposentar serviços/stores antigos somente depois do cutover estável.

---

## 8. Gates de conclusão

Não declarar concluído enquanto não existir prova de:
- LIVE RadioBOSS estável;
- shadow V2 sincronizado;
- drift <= 5 s;
- current/next corretos;
- 100% de assets imediatos READY;
- hora certa funcionando;
- temperatura funcionando;
- comerciais funcionando;
- scheduler funcionando;
- failover em teste;
- retorno anti-flap;
- painel do operador com autenticação;
- RBAC;
- audit log;
- relatórios;
- soak test aprovado;
- rollback testado.

---

## 9. Regra de comunicação do projeto

Sempre distinguir:
- **PREPARADO NO GITHUB**
- **INSTALADO NO NS1**
- **ATIVO**
- **VALIDADO**
- **PROMOVIDO PARA PRODUÇÃO**

Nunca usar “pronto” sem dizer qual desses estados foi comprovado.

---

## 10. Próximo passo único

O próximo passo técnico é P1: medir o estado atual do Harbor RadioBOSS, identificar por que o source LIVE fica indisponível mesmo com RadioBOSS tocando, e estabilizá-lo sem alterar a programação pública.

Em paralelo, P2/P3/P6 podem ser construídos fora da produção.
