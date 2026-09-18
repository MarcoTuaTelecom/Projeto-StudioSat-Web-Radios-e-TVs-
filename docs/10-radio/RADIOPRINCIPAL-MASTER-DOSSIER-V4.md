# Rádio Principal — Dossiê Mestre V4
## Histórico completo, objetivo, arquitetura, regras de negócio, regras de sistema, falhas, acertos e plano de reconstrução

**WORKSTREAM_ID:** `RADIOPRINCIPAL-NS1`  
**Repositório master:** `MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-`  
**Branch de trabalho:** `reorg/project-context-v2`  
**Atualização:** 2026-09-18  
**Status:** fonte técnica mestre para continuação do projeto.

> Este documento substitui resumos dispersos como referência principal da Rádio Principal. Documentos anteriores continuam preservados como histórico e contratos auxiliares.

---

# 1. Objetivo do projeto

Construir para a **Rádio Principal / Studio Sat** uma cadeia de transmissão contínua em que:

1. **RadioBOSS no estúdio é a autoridade editorial enquanto estiver operacional**.
2. **NS1 mantém uma réplica executável da programação do RadioBOSS**, e não uma playlist de emergência independente.
3. O NS1 conhece, no máximo em aproximadamente **5 segundos**, alterações de:
   - playlist efetiva;
   - música atual;
   - próxima música;
   - posição de reprodução;
   - schedule;
   - comerciais;
   - hora certa;
   - temperatura;
   - vinhetas;
   - eventos;
   - arquivos novos necessários.
4. O NS1 baixa automaticamente apenas assets ausentes/alterados a partir do computador do estúdio.
5. Se o áudio LIVE do RadioBOSS cair, o NS1 assume com:
   - mesma grade;
   - mesmo item;
   - posição equivalente ao último checkpoint;
   - mesma sequência editorial;
   - mesmos eventos programados.
6. Quando o RadioBOSS voltar, o sistema não deve oscilar. O retorno exige uma janela contínua de estabilidade.
7. O técnico/operador deve controlar o sistema por **interface web própria**, com login, usuários, permissões, auditoria, relatórios, downloads, programação e manutenção.
8. O PC local deve exigir apenas:
   - RadioBOSS visível;
   - **um único agente Studio Sat oculto e automático**, iniciado no boot.
9. A produção pública não pode ser usada como laboratório.

---

# 2. Regra de autoridade

## 2.1 Autoridade editorial

Enquanto RadioBOSS estiver conectado e executando programação válida:

```
RadioBOSS = autoridade editorial
NS1       = transmissor contínuo + réplica executável + contingência
```

O NS1 não pode inventar outra grade.

## 2.2 Dois canais independentes

### A. Áudio LIVE

```
RadioBOSS
  -> encoder
  -> Windows localhost:18005
  -> túnel SSH
  -> NS1 localhost:18005
  -> Liquidsoap Harbor
  -> selector
  -> MediaMTX
  -> HLS/Nginx
  -> clientes
```

### B. Controle / autoridade / assets

```
RadioBOSS + agente Studio Sat
  -> playlist
  -> playback
  -> current/next
  -> playlistpos/pos_ms
  -> schedule
  -> heartbeat
  -> librarymanifest
  -> assets necessários
  -> NS1 canonical state
```

**Fato importante:** controle fresco não significa áudio LIVE saudável. Os dois canais já funcionaram em estados diferentes.

---

# 3. Arquitetura pública observada

Produção atualmente documentada:

- selector: `studiosat-radioprincipal-selector.service`;
- selector Liquidsoap: `/etc/studiosat/radioprincipal-selector.liq`;
- path público: `radioprincipal`;
- shadow legado: `radioprincipal-ns1`;
- Harbor RadioBOSS: `127.0.0.1:18005`;
- MediaMTX: `tps-mediamtx.service`;
- distribuição HLS: MediaMTX + Nginx.

Prioridade configurada:

```
1. radioprincipal_rb_harbor
2. radioprincipal_ns1_rtmp
3. radioprincipal_emergency_blank
```

Logo, a prioridade lógica do RadioBOSS já existe. O problema observado foi indisponibilidade/intermitência da fonte LIVE, fazendo o selector cair para o shadow legado.

---

# 4. Problema estrutural central

O fallback público atual ainda usa:

```
/opt/studiosat/radio-v2/radioprincipal-mirror/mirror-playout.py
```

Esse player foi construído em torno de mapa físico/matched index e não representa corretamente a **fila efetiva editorial** do RadioBOSS.

A fila efetiva pode conter:

- MP3;
- `saytime=...`;
- comerciais;
- scheduler;
- vinhetas;
- comandos virtuais;
- eventos inseridos dinamicamente.

Portanto:

```
playlistpos do RadioBOSS != necessariamente índice do MP3 no media-map
```

Esse descompasso explica ocorrências de:

```
current_item_ready = true
current_matches_playlistpos = false
next_matches_playlistpos_plus_1 = false
queue_aligned = false
```

O projeto precisa abandonar a equivalência falsa entre “lista física de MP3” e “fila executável”.

---

# 5. Store de mídia e protocolo real

O NS1 já possui:

```
studiosat-media-transfer.service
/opt/studiosat/radio-v2/media-transfer/server.py
```

Banco:

```
/var/lib/studiosat/radio-v2/media-transfer/index.sqlite3
```

Tabelas confirmadas:

- `assets`;
- `sources`;
- `repository_index`.

Protocolo confirmado:

```
PUT /v1/upload/radioprincipal
```

Headers relevantes:

- `Authorization: Bearer ...`;
- `X-SHA256`;
- `X-Filename-B64`;
- `X-SourcePath-B64`;
- `X-Media-Class`;
- `Content-Length`.

O servidor:

1. valida SHA256;
2. valida tamanho;
3. valida extensão;
4. usa ffprobe para áudio;
5. grava object store;
6. registra asset;
7. registra source path;
8. deduplica quando o objeto já existe.

A regra definitiva é usar este mecanismo como base, não criar stores paralelos desconectados.

---

# 6. Estrutura operacional humana

O técnico não deve operar em `/var/lib/...` ou paths de implementação.

Caminho humano oficial alvo:

```
/srv/studiosat/radio-principal/
```

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

Regra:

- esta árvore é uma **interface humana/materialização operacional**;
- o object store interno continua sendo canônico para deduplicação/integridade;
- não criar uma segunda autoridade editorial;
- uploads manuais precisam ser indexados e reconciliados com o store canônico.

---

# 7. Histórico cronológico consolidado

## Fase documental inicial

### Authority Replication v1.0
Arquivo:
`docs/10-radio/RADIOPRINCIPAL-RADIOBOSS-NS1-AUTHORITY-REPLICATION-v1.0.md`

Commit conhecido:
`9c43454...`

Definiu RadioBOSS como autoridade e NS1 como réplica executável.

### Acceptance Plan v1.0
Commits:
- `e3d63...`
- `b11653...`

### Addendum v1.1
Commit:
`86009a...`

### Current Program Shadow Sync Plan
Commit:
`6765fd...`

### Grade Temporal v1.2
Arquivo:
`docs/10-radio/RADIOPRINCIPAL-RADIOBOSS-NS1-AUTHORITY-REPLICATION-v1.2-GRADE-TEMPORAL.md`

Commit:
`de75449ab61e80b95cdbf925cabe8891691f4899`

Resultado: contratos de autoridade, temporalidade e failover foram formalizados, mas implementação ainda permaneceu incompleta.

---

# 8. Candidate authority replica

Foi construído candidate v0.2 para comparar:

- playlist;
- playback;
- disponibilidade;
- current/next;
- freshness;
- queue alignment.

Artefatos conhecidos:

- candidate blob histórico: `16604dd88421950747ad7c66a264b29f8552710c`;
- runner: `26410b9f108a495f0b2cd2a9e9321b0e14b485fb`;
- probe grid: `885ae526f4f65149258d4e5760968605eb876e62`.

C07 activation script:
`scripts/radioprincipal/candidate/ACTIVATE-RADIOBOSS-NS1-SYNC-NOW.sh`

Commit:
`a11b118344531a26ec9d4883945719bfdc1fdb12`

Resultado técnico:
- conseguiu separar freshness de source e readiness;
- conseguiu detectar divergência;
- inicialmente não fazia transferência real de missing;
- não executava `saytime`;
- portanto era diagnóstico/candidate, não solução final.

---

# 9. Evidência de programação Noite — C05/C06

Em 2026-09-17, evidência do RadioBOSS mostrou programação da Noite.

Candidate observou:

- `items=69`;
- `available=7`;
- `missing=62`;
- current = Eric Clapton - Change The World;
- next = Time Announcement;
- playlist/schedule/playback frescos;
- RadioBOSS editorialmente correto;
- muitos assets ainda não transferidos.

Conclusão correta daquela fase:

```
controle PC -> NS1 estava funcionando
áudio LIVE tinha falhas
assets novos não chegavam rápido
fallback legado não seguia a grade correta
```

---

# 10. Construção do túnel Windows -> NS1

RadioBOSS foi configurado para encoder:

```
127.0.0.1:18005/radioprincipal-rb
```

A arquitetura exige um local forward no Windows.

Foi criado par de chaves dedicado e tarefa agendada:

```
StudioSat-RadioBOSS-NS1-Tunnel
```

## Erro 1 — authorized_keys incorreta

No primeiro provisionamento do NS1, o placeholder de chave pública foi deixado no script.

Efeito:
`Permission denied (publickey)`.

Correção:
- instalar chave real;
- validar sshd;
- restringir usuário de túnel.

## Erro 2 — ACL da chave privada Windows

OpenSSH recusou:

```
WARNING: UNPROTECTED PRIVATE KEY FILE
bad permissions
```

Correção aplicada:
- private key passou a pertencer a SYSTEM;
- herança removida;
- FullControl apenas SYSTEM.

Resultado naquela etapa:

```
Test-NetConnection 127.0.0.1 -Port 18005
TcpTestSucceeded=True
```

Isso provou listener local, não estabilidade permanente do áudio.

---

# 11. C12 — consolidação do fallback

C12 tentou:

- desabilitar V8 stage/production/live-ingress;
- colocar mirror controller em 5s;
- reconstruir mapa;
- consolidar store;
- recarregar shadow.

Resultados positivos:

```
RADIOBOSS_PLAYLIST_TRACKS=67
NS1_AVAILABLE_TRACKS=67
NS1_MISSING_TRACKS=0
NON_CANONICAL_PATHS=0
CANONICAL_STORE_ONLY=True
```

Resultados negativos:

- shadow foi recarregado no mesmo instante em que Harbor RadioBOSS caiu;
- as duas fontes ficaram indisponíveis;
- rádio pública saiu do ar.

Lição:
**não reiniciar componentes de áudio público para validar reconstrução.**

---

# 12. C14 — tentativa de playback-synced shadow

Objetivo:
substituir o `matched_index` legado por `current + pos_ms`.

Falha observada:
`sqlite3.OperationalError: unable to open database file`.

O serviço entrou em restart loop.

O rollback restaurou o unit anterior, mas a cadeia pública não se recuperou automaticamente naquele momento.

Importante:
- o XRAY posterior mostrou o SQLite em si legível em modo root;
- portanto não é correto afirmar que “o banco estava corrompido”;
- a falha foi de implantação/acesso/sandbox/contexto de serviço e deve ser reproduzida somente em laboratório.

Lição:
**candidate nunca deve substituir shadow público antes de provar publicação em path isolado.**

---

# 13. C16/C17 e regra no-downtime

Após os incidentes foi formalizada a regra:

```
produção pública = congelada durante reconstrução
```

Documento:
`docs/10-radio/RADIOPRINCIPAL-NO-DOWNTIME-REBUILD-V2.md`

Protegidos:

- selector público;
- shadow público;
- MediaMTX;
- Nginx;
- Harbor;
- path `radioprincipal`;
- path `radioprincipal-ns1`.

Toda nova engenharia deve nascer em:

- `radioprincipal-v2-shadow`;
- `radioprincipal-v2-test`;
- units `studiosat-radioprincipal-v2-*`.

---

# 14. C18 — Full Forensic XRAY

C18 passou a ser o inventário pós-incidente.

Confirmou:

- MediaMTX ativo;
- Nginx ativo;
- RadioBOSS sync ativo;
- media-transfer ativo;
- selector ativo na coleta;
- shadow legado ativo;
- authority candidate ativo;
- Harbor listener presente;
- control plane recebendo POSTs;
- shadow público executando `mirror-playout.py`;
- V8 stage/production/live-ingress desativados;
- V8 control bridge ainda existente;
- stores e bases históricas ainda coexistindo;
- `queue_aligned=false`.

Também confirmou protocolo real do media-transfer.

C18 é a referência forense para explicar o estado herdado.

---

# 15. Repositórios Manhã/Tarde/Noite

Foi adotado endereço humano:

```
/srv/studiosat/radio-principal/grade/manha
/srv/studiosat/radio-principal/grade/tarde
/srv/studiosat/radio-principal/grade/noite
```

A captura posterior mostrou a pasta `manha` existente e contendo arquivos, portanto pelo menos a estrutura humana passou a existir no NS1.

Entretanto, isso não significa que a programação completa estava sincronizada.

---

# 16. C21 — teste real de estabilidade LIVE

C21 foi executado em 2026-09-18.

Resultado:

```
HARBOR_LISTEN_SAMPLES=17
HARBOR_ESTABLISHED_SAMPLES=3
HARBOR_ESTABLISHED_PERCENT=17.65
RB_FEED_STOP_EVENTS=2
P1_SAMPLE_STATUS=UNSTABLE
```

Eventos:

```
Feeding stopped: Avutil.Error(Invalid data found when processing input)
```

Depois:
- metadata Tim Maia chegou;
- selector mudou para `radioprincipal_rb_harbor`.

Conclusão:

- prioridade do RadioBOSS funciona;
- Harbor ouve;
- source/túnel/encoder não permaneceu conectado;
- P1 continua aberto.

Também foi observado playback com aproximadamente 9000s de idade no início da janela, ficando fresco novamente ao final.

---

# 17. C21R — reset para túnel único

Executado no Windows.

Resultado:

```
LOCAL_18005_LISTEN=YES
TCP_18005=True
```

Uma instância antiga foi encerrada e uma nova tarefa iniciou o SSH.

Porém o log continha repetidamente:

```
channel ... open failed: connect failed: Connection refused
```

Logo:

- listener Windows ficou disponível;
- ainda houve recusa ao encaminhar para o destino NS1 em momentos anteriores/da operação;
- o resultado não fecha P1;
- precisamos de um agente/túnel único supervisionado, com health dos dois lados.

---

# 18. C22 — reconciliador do repositório humano

C22 foi executado no NS1.

Resultado:

```
db_rows=1185
candidates=149
MANHA=27
TARDE=85
NOITE=69
conflicts=[]
```

Missing observados:

1. `saytime=HoraCertaSegSextManha`;
2. `98 14 BIS - NOVA MANHÃ.mp3`.

Erro conceitual revelado:
`saytime` apareceu como missing source, mas é comando virtual e **não deve ser tratado como MP3**.

Problema maior:
a tela do RadioBOSS mostrava a grade Manhã com cerca de 166 faixas, enquanto o repositório humano tinha apenas 27 arquivos.

Conclusão:
**C22 apenas reorganiza o que o NS1 já conhece; não resolve transferência automática da playlist completa do PC.**

---

# 19. C23 — shadow V2 isolado

Artefatos preparados:

- `scripts/radioprincipal/v2/v2-shadow-playback-follower.py`;
- `scripts/radioprincipal/v2/C23-INSTALL-ISOLATED-V2-SHADOW.sh`.

Objetivo:
publicar somente em:

```
radioprincipal-v2-shadow
```

Sem tocar no selector público.

Status:
**PREPARADO NO GITHUB; não há evidência suficiente para classificar como INSTALADO/VALIDADO.**

---

# 20. C24 — Edge Bridge NS1

Nova direção arquitetural para reduzir carga operacional no PC.

Artefatos:

- `scripts/radioprincipal/v2/edge-bridge.py`;
- commit inicial `eb184e7b660c4d740125a5341d701ff0c5bf9c9b`;
- enhancement exists/register `ae35e647add36928f7806a0dfa1c81f5b51f3dc7`;
- instalador `scripts/radioprincipal/v2/C24-INSTALL-NS1-EDGE-BRIDGE.sh`;
- instalador corrigido commit `d044d61daaabb0ab67b7dc72d3a11a8dd8828059`.

Funções alvo:

- bind local `127.0.0.1:8796`;
- gerar plan de assets da playlist;
- informar missing/present;
- registrar source paths;
- encaminhar uploads para media-transfer real;
- não expor token ao PC;
- não tocar produção pública.

Status:
**PREPARADO NO GITHUB; não confirmado como instalado.**

---

# 21. C25 — agente único oculto Windows

Artefatos:

- `scripts/radioprincipal/v2/StudioSat-RadioPrincipal-Agent.ps1`;
- commit `71c37252ab46913f82a4c05104c4fe48148a1415`;
- `scripts/radioprincipal/v2/C25-INSTALL-WINDOWS-AUTOMATIC-AGENT.ps1`;
- commit `e07b3eba1d5dbcbed3cb0251553f3e502737e6ad`.

Objetivo final no PC:

```
RadioBOSS visível
+
1 agente Studio Sat oculto
```

Agente deve:

1. iniciar no boot como SYSTEM;
2. manter bridge/túneis necessários;
3. consultar plan;
4. detectar arquivos ausentes;
5. priorizar current/next;
6. calcular SHA256 com cache;
7. registrar source já existente;
8. fazer upload apenas do missing;
9. repetir <=5s;
10. registrar status/log;
11. funcionar sem operador abrir terminal.

Status:
**PREPARADO NO GITHUB; não confirmado como instalado.**

---

# 22. O que deu certo

## Confirmado

- RadioBOSS envia snapshots de controle ao NS1.
- Playback expõe current, next, playlistpos e pos_ms.
- Selector possui prioridade RadioBOSS -> NS1 -> blank.
- Harbor 18005 pode receber RadioBOSS.
- RadioBOSS já conectou e transmitiu metadata real.
- Tunnel Windows pode criar listener 18005.
- Media-transfer possui upload real com validação e SHA256.
- NS1 possui object store e banco de assets/sources/index.
- Mirror/controller consegue materializar listas físicas.
- Manhã/Tarde/Noite passaram a ter estrutura humana.
- C18 produziu diagnóstico abrangente.
- C21 mediu instabilidade LIVE de forma objetiva.
- C22 mediu cobertura real do repositório humano.
- Regra no-downtime foi formalizada.
- V8 stage/production/live-ingress deixaram de ser caminhos ativos da produção.

---

# 23. O que deu errado

## Produção usada como superfície de teste

C12/C14 alteraram/reiniciaram componentes que participavam do áudio público.

Consequência:
outages e recuperação difícil.

## Shadow legado não segue fila efetiva

O NS1 toca sequência física diferente quando assume.

## LIVE RadioBOSS instável

C21 provou apenas 17,65% das amostras com Harbor established.

## Túnel ainda não é uma solução única e observável

Listener local não é prova de conexão end-to-end.

## Sincronização de assets incompleta

27 músicas na Manhã não representam a grade ativa completa.

## Comando virtual confundido com mídia

`saytime` não é arquivo MP3.

## Interface do operador incompleta

Ainda não existe console web final autenticado, homologado e publicado.

## Estado “GitHub” confundido com “instalado”

Regra corrigida:
sempre classificar como PREPARADO / INSTALADO / ATIVO / VALIDADO / PRODUÇÃO.

## Muitos scripts/candidates

Foram criados vários scripts de recuperação/experimento.
Eles devem ser classificados e consolidados, não continuar acumulando indefinidamente.

---

# 24. Regras de negócio

## RN-01 — RadioBOSS é autoridade editorial
NS1 não cria grade própria enquanto RadioBOSS estiver em operação.

## RN-02 — failover transparente
O ouvinte não deve perceber mudança de programação ao trocar para NS1.

## RN-03 — sincronismo <=5s
Mudanças editoriais relevantes precisam chegar ao NS1 em aproximadamente no máximo 5 segundos.

## RN-04 — current/next primeiro
Prioridade de asset:
1. current;
2. next;
3. próximos itens;
4. evento/comercial iminente;
5. restante do programa;
6. programas futuros.

## RN-05 — comandos virtuais são executáveis, não arquivos
`saytime`, temperatura e comandos equivalentes devem ser adapters.

## RN-06 — mídia por conteúdo
Identidade canônica de asset baseada em SHA256, não somente nome/path.

## RN-07 — nenhuma remoção se asset estiver referenciado
Delete é operação controlada e auditada.

## RN-08 — operação humana é parte do produto
Não é aceitável depender de shell/MobaXterm para rotina normal.

## RN-09 — automação local mínima
PC local deve iniciar sozinho e não exigir dezenas de aplicações manuais.

## RN-10 — auditoria completa
Toda ação humana/automática crítica deve ser registrável.

---

# 25. Regras de sistema

## RS-01 — separação de planos
LIVE, controle e assets são canais separados.

## RS-02 — no downtime
Candidates não podem reiniciar produção pública.

## RS-03 — paths de laboratório
Usar:
- `radioprincipal-v2-shadow`;
- `radioprincipal-v2-test`.

## RS-04 — anti-flap
Selector V2 deve exigir estabilidade antes de retornar ao LIVE.

## RS-05 — estado canônico executável
Construir canonical effective queue, não somente media-map.

## RS-06 — source freshness independente
Heartbeat/playback/source áudio possuem freshness separados.

## RS-07 — transferência idempotente
Upload deve deduplicar por SHA256.

## RS-08 — retry com backoff
Falhas de rede/upload não podem gerar loops agressivos.

## RS-09 — observabilidade
Expor:
- live source;
- shadow source;
- drift;
- current;
- next;
- queue alignment;
- transfer queue;
- missing;
- failover events.

## RS-10 — rollback
Toda promoção deve ter rollback antes do cutover.

---

# 26. Sistema do operador — escopo obrigatório

## Autenticação

- login;
- senha com hash forte;
- sessão segura;
- MFA para Superadmin/Técnico;
- recuperação auditada;
- rate limit;
- reautenticação para ações críticas.

## Perfis

- Superadmin;
- Administrador da Rádio;
- Programador;
- Operador;
- Técnico;
- Auditor/Consulta.

## RBAC

Permissões:

- users.read/write;
- roles.read/write;
- programming.read/write/publish;
- assets.read/upload/delete;
- transfers.read/retry/cancel;
- commercials.read/write/publish;
- live.read/control;
- failover.read/control;
- system.read/maintain;
- reports.read/export;
- audit.read.

## Dashboard

Exibir:

- ON AIR;
- fonte pública;
- RadioBOSS LIVE;
- NS1 shadow;
- NOW;
- NEXT;
- posição;
- drift;
- programa;
- assets missing;
- transfers;
- hora certa;
- temperatura;
- comerciais;
- scheduler;
- failover;
- alertas.

## Transfer Manager

Estados:

- PENDING;
- CHECKING;
- DOWNLOADING;
- VERIFYING;
- READY;
- RETRYING;
- FAILED;
- QUARANTINED.

Campos:

- origem;
- destino;
- SHA;
- bytes;
- percentual;
- velocidade;
- ETA;
- tentativas;
- prioridade;
- erro;
- referência editorial.

## Relatórios

- histórico ON AIR;
- faixas;
- comerciais;
- hora certa;
- temperatura;
- scheduler;
- failovers;
- indisponibilidade LIVE;
- divergências RB x NS1;
- assets missing;
- transfers;
- erros/retries;
- mudanças de programação;
- ações de usuário;
- disponibilidade;
- CSV/PDF.

---

# 27. Prioridades oficiais

## P0 — Continuidade pública
Nunca derrubar a rádio durante reconstrução.

## P1 — LIVE RadioBOSS estável
Fechar túnel/Harbor/encoder end-to-end e provar estabilidade.

## P2 — Canonical Effective Queue
Representar música + eventos + itens virtuais na mesma ordem editorial.

## P3 — Asset plane automático
Missing -> PC -> SHA -> upload -> READY.

## P4 — Execution Engine V2
Seguir current + pos_ms em path isolado.

## P5 — Adapters editoriais
Hora certa, temperatura, comerciais, vinhetas e scheduler.

## P6 — Console do operador
API + UI + auth + users + RBAC + audit + reports.

## P7 — Selector V2 anti-flap
Failover testado fora do público.

## P8 — Soak
Horas/dias de comparação paralela.

## P9 — Cutover
Troca controlada somente após gates.

## P10 — Limpeza
Aposentar legado depois de produção V2 comprovada.

---

# 28. Plano passo a passo

## Etapa 1 — fechar P1
1. medir túnel end-to-end;
2. medir Harbor established;
3. verificar encoder RadioBOSS;
4. unificar watchdog;
5. soak de conexão;
6. zero switch indevido para NS1 durante janela.

## Etapa 2 — instalar/validar C24
1. instalar edge bridge localhost;
2. validar health;
3. validar plan da playlist;
4. separar virtual x físico;
5. validar missing real.

## Etapa 3 — instalar/validar C25
1. instalar task SYSTEM;
2. boot automático;
3. bridge oculto;
4. plan a cada <=5s;
5. upload automático;
6. current/next priorizados;
7. medir pending -> 0 para janela imediata.

## Etapa 4 — canonical queue
1. parser da playlist;
2. reconciliar playlistpos;
3. inserir virtual items;
4. schedule;
5. commercials;
6. now/next;
7. persistir revisions.

## Etapa 5 — execution engine V2
1. tocar current em pos_ms;
2. acompanhar drift;
3. reseek;
4. continuar offline;
5. publicar em `radioprincipal-v2-shadow`;
6. não tocar produção.

## Etapa 6 — adapters
1. saytime;
2. temperatura;
3. comerciais;
4. scheduler;
5. metadata.

## Etapa 7 — console
1. backend/API;
2. banco auth;
3. users/roles;
4. login/MFA;
5. dashboard;
6. programação;
7. biblioteca;
8. transfer manager;
9. relatórios;
10. auditoria.

## Etapa 8 — selector V2
1. LIVE preferred;
2. shadow synchronized;
3. hysteresis;
4. failover;
5. recovery window;
6. event logs.

## Etapa 9 — soak
Comparar:
- current;
- next;
- pos_ms;
- eventos;
- metadata;
- assets;
- failover.

## Etapa 10 — cutover
Somente com:
- rollback;
- backup;
- gate aprovado;
- janela controlada;
- observabilidade.

## Etapa 11 — cleanup
Classificar:
- CANONICAL;
- PROMOTED;
- DIAGNOSTIC;
- RECOVERY;
- LAB;
- LEGACY;
- HISTORICAL;
- OBSOLETE.

Só depois remover duplicatas.

---

# 29. Gates obrigatórios antes de produção V2

Todos devem passar:

- Harbor estável;
- current correto;
- next correto;
- drift <=5s;
- immediate assets READY;
- transfer manager funcional;
- saytime correto;
- temperatura correta;
- comerciais corretos;
- scheduler correto;
- metadata correta;
- shadow V2 contínuo;
- failover testado;
- retorno anti-flap;
- console autenticado;
- RBAC;
- audit;
- reports;
- soak;
- rollback.

---

# 30. Vocabulário obrigatório de status

Nunca escrever apenas “pronto”.

Usar:

- **PREPARADO NO GITHUB**
- **INSTALADO NO NS1/PC**
- **ATIVO**
- **VALIDADO**
- **PROMOVIDO PARA PRODUÇÃO**
- **FALHOU**
- **ROLLBACK APLICADO**
- **OBSOLETO / NÃO USAR**

---

# 31. Estado atual consolidado em 2026-09-18

## Confirmado por execução

- C21: LIVE instável; Harbor established 17,65%.
- C21R: listener Windows 18005 restaurado, TCP local True; logs ainda tinham connection refused.
- C22: Manhã 27, Tarde 85, Noite 69; repositório incompleto.
- `saytime` precisa ser removido do conceito de mídia física.

## Confirmado por estrutura/forense

- selector público prioriza RadioBOSS;
- shadow público é legado;
- media-transfer real existe;
- object store real existe;
- control snapshots existem;
- V8 stage/production/live-ingress não são mais os paths ativos.

## Preparado mas ainda não validado como instalado

- C23 shadow isolado;
- C24 edge bridge;
- C25 Windows automatic agent;
- Operator API scaffold;
- Operator Web UI final;
- auth/users/RBAC/MFA;
- transfer dashboard;
- reports.

---

# 32. Próxima ação oficial

Não criar nova arquitetura paralela até concluir os artefatos já preparados.

Ordem imediata:

1. validar P1 end-to-end;
2. instalar/validar C24;
3. instalar/validar C25;
4. comprovar sincronização real da playlist atual;
5. construir canonical effective queue;
6. validar C23 ou substituir por execution engine V2 definitivo;
7. construir console operacional.

---

# 33. Regra para novos chats

Novo chat deve ler nesta ordem:

1. `project-context/00-MASTER.md`;
2. `project-context/02-DECISIONS.md`;
3. **este dossiê V4**;
4. `docs/10-radio/RADIOPRINCIPAL-REBUILD-BACKLOG-AND-GATES-V1.md`;
5. `project-context/chats/active/RADIOPRINCIPAL-NS1.md`;
6. evidência operacional mais recente.

Não reiniciar discussão arquitetural sem nova evidência.

---

# 34. Definição de sucesso final

O projeto estará concluído quando:

- RadioBOSS puder cair sem mudar a experiência editorial;
- NS1 assumir no mesmo programa/item/posição aproximada;
- todos os elementos editoriais continuarem;
- assets forem sincronizados automaticamente;
- PC local exigir apenas RadioBOSS + agente invisível;
- técnico operar tudo por console autenticado;
- cada ação crítica for auditada;
- relatórios estiverem disponíveis;
- failover não oscilar;
- legado não participar mais da cadeia;
- produção permanecer observável e recuperável.
