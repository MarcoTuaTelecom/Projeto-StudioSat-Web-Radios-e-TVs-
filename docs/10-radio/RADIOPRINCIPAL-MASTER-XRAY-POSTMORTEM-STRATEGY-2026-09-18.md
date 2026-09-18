# Rádio Principal / Studio Sat — Raio X Mestre, Pós-Mortem e Nova Estratégia

**Data da consolidação:** 2026-09-18  
**Workstream:** `RADIOPRINCIPAL-NS1`  
**Repositório mestre:** `MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-`  
**Branch:** `reorg/project-context-v2`

> Este documento separa rigorosamente: fato comprovado por execução, artefato apenas preparado, hipótese e recomendação. Nada é classificado como instalado/validado sem evidência operacional.

---

## 1. Resumo executivo

O projeto tentou resolver simultaneamente cinco problemas diferentes:

1. manter a Rádio Principal ao vivo pelo RadioBOSS;
2. manter no NS1 uma réplica editorial capaz de assumir sem mudar a programação;
3. sincronizar automaticamente mídia/estado do estúdio;
4. manter outras quatro rádios temáticas no ar;
5. construir console, API e automação definitiva.

A principal falha estratégica foi tentar promover partes do item 2 ao 5 enquanto o item 1 — LIVE RadioBOSS -> NS1 — ainda não estava estável.

O resultado foi uma produção com várias gerações coexistindo: RadioBOSS LIVE, Liquidsoap Harbor, selector, shadow legado, V8, authority candidate, media-transfer, mirror controller, playlists físicas, human repository, candidates C23/C24/C25/C26 e quatro rádios temáticas estáticas em loop.

Isso tornou possível um componente estar `active` sem a experiência pública estar correta.

A estratégia deve mudar para:

**recuperar -> congelar -> medir -> atualizar compatibilidade -> construir paralelo -> soak -> promover.**

---

## 2. Objetivo funcional correto

A Rádio Principal deve obedecer a este contrato:

```
RadioBOSS = única autoridade editorial
        |
        +--> LIVE de áudio
        +--> estado/playlist/playback/schedule
        +--> assets físicos
                 |
                 v
               NS1
                 |
                 +--> réplica executável da MESMA programação
                 +--> current / next / pos_ms
                 +--> comandos virtuais
                 +--> comerciais / scheduler / hora certa / temperatura
                 |
                 v
             saída pública
```

O NS1 não deve criar uma segunda programação editorial.

Em failover, a meta é preservar item atual, posição aproximada, próximo item, ordem da fila, comandos virtuais, metadata e eventos programados.

---

## 3. Arquitetura pública comprovada durante a investigação

A cadeia LIVE observada foi:

```
RadioBOSS Windows
  -> 127.0.0.1:18005
  -> SSH local forward
  -> NS1 127.0.0.1:18005
  -> Liquidsoap input.harbor
  -> selector
  -> RTMP radioprincipal
  -> MediaMTX
  -> HLS
```

O Windows confirmou:
- PID do listener: `ssh.exe`;
- PID da conexão para 127.0.0.1:18005: `radioboss.exe`;
- SSH com chave dedicada;
- usuário remoto `studiosat-rb-tunnel`;
- `ExitOnForwardFailure=yes`;
- keepalive habilitado.

Logo, não é necessário abrir uma nova porta pública para a Rádio Principal.

---

## 4. Segurança do LIVE

A conexão tem duas camadas:

### Transporte
SSH com chave:
`studiosat-rb-tunnel@ns1.tpsolutions.com.br`

### Autenticação da fonte
Liquidsoap Harbor:
- user `source`;
- senha via `RB_HARBOR_PASSWORD`;
- mount `radioprincipal-rb`;
- Harbor bind em loopback.

Essa parte do desenho é boa e deve ser preservada.

---

## 5. O que o RESET-00 revelou

O RESET-00 foi o primeiro ponto em que a produção foi tratada como objeto forense, não como pressuposto.

Descobertas:
- MediaMTX ativo;
- Nginx ativo;
- RadioBOSS sync ativo;
- media-transfer ativo;
- selector ativo;
- shadow legado ativo;
- Harbor 18005 LISTEN;
- túnel chegou a aparecer ESTABLISHED;
- `radioprincipal` e `radioprincipal-ns1` tiveram evidência de disponibilidade em janelas de coleta;
- vários serviços experimentais coexistiam.

A descoberta mais importante foi que a configuração pública havia divergido da arquitetura assumida.

Em um estado real, o selector era:

```
[rb, local, security]
```

e depois foi observado como:

```
[rb, local]
```

O `local` era:
`/srv/studiosat/radio-principal/playlists/current.m3u`

Essa lista NÃO representava a programação real do RadioBOSS.

---

## 6. Erro editorial grave da playlist local

O `current.m3u` público tinha 291 entradas:
- 109 arquivos de hora certa;
- 28 músicas Manhã;
- 69 músicas Noite;
- 85 músicas Tarde.

A ordem física era:

```
hora certa inteira
-> manhã
-> noite
-> tarde
```

Isso não é uma fila editorial executável.

Quando o Harbor oscilava, o selector alternava em segundos entre `radioprincipal_rb_harbor` e `radioprincipal_local_grade`.

Consequência: o ouvinte escutava duas lógicas editoriais brigando pela mesma rádio.

RESET-01B removeu corretamente `local` do fallback público e normalizou temporariamente para:

```
[rb, security]
```

Essa mudança foi validada por `liquidsoap --check`.

---

## 7. Problema LIVE que permaneceu

Mesmo após retirar a playlist errada, o Harbor continuou apresentando:

`Feeding stopped: Avutil.Error(Invalid data found when processing input)`

Foram observados ciclos:
`RadioBOSS -> blank -> RadioBOSS -> blank -> RadioBOSS`.

Exemplos:
- 19:07:50 RB;
- 19:08:16 blank;
- 19:08:20 RB;
- 19:09:23 blank;
- 19:09:35 RB;
- 19:09:55 blank;
- 19:10:14 RB.

Portanto:
- túnel existe;
- RadioBOSS alcança o listener local;
- autenticação chega a aceitar a fonte;
- metadata chega a ser recebida;
- o problema ocorre durante continuidade/decodificação do stream no Harbor.

---

## 8. C21: prova quantitativa da instabilidade

Janela de 180 s:
- 17 amostras;
- Harbor ESTABLISHED em apenas 3;
- 17,65% de presença ESTABLISHED;
- playback chegou a ficar mais de 9.000 s stale;
- houve `Feeding stopped`;
- houve retorno posterior do RadioBOSS;
- selector conseguiu priorizar o RB quando a fonte voltou.

Conclusão: **a lógica de prioridade funcionou; o LIVE não.**

---

## 9. C21R / Windows

O reset do túnel Windows conseguiu listener `127.0.0.1:18005`, TCP local verdadeiro, novo processo SSH e keepalive.

Mas logs anteriores continham:
`connect_to 127.0.0.1 port 18005: failed: Connection refused`

Isso provou que controle e áudio são planos diferentes; snapshots podem continuar chegando enquanto LIVE falha; “sync fresco” nunca deve ser usado como prova de áudio.

Mais tarde foi comprovado:
- PID 9232 = `ssh.exe`;
- PID 4056 = `radioboss.exe`;
- RadioBOSS realmente abriu conexão ao listener local.

---

## 10. Shadow NS1 / fallback

O shadow público encontrado era legado:

`/opt/studiosat/radio-v2/radioprincipal-mirror/mirror-playout.py`

Ele publica `radioprincipal-ns1`.

Problema: esse legado não representa de forma fiel a Canonical Effective Queue.

Ele usa modelo antigo de índice/playlist física e não resolve corretamente itens virtuais, scheduler, playlistpos efetivo, posição no item e eventos inseridos.

---

## 11. C14: tentativa de shadow sincronizado

A tentativa C14 falhou por acesso ao SQLite:

`sqlite3.OperationalError: unable to open database file`

A investigação posterior mostrou que o banco não estava necessariamente corrompido; o problema estava ligado a sandbox/permissões/path do serviço.

Erro estratégico: o candidate foi promovido cedo demais para um componente público.

Resultado: restart loop, rollback e restauração posterior.

Lição: **candidate nunca deve substituir shadow público antes de teste isolado e soak.**

---

## 12. C12: dados bons, promoção ruim

C12 conseguiu provar:
- 67 tracks RadioBOSS;
- 67 assets NS1;
- missing 0;
- canonical store only;
- contagens alinhadas.

Mas reiniciou componentes públicos em uma janela em que o LIVE caiu.

Portanto: **dados corretos não tornam uma mudança de produção segura.**

---

## 13. C17 / C18

C17 encontrou o selector inativo enquanto shadow estava ativo.

C18 mostrou posteriormente:
- selector ativo;
- direct public RTMP saudável em janela de probe;
- direct NS1 RTMP saudável;
- playback fresco;
- mídia 67/67;
- banco acessível;
- media-transfer existente.

Também revelou o problema fundamental da fila: `playlistpos` do RadioBOSS não é equivalente ao índice dos arquivos MP3.

---

## 14. Canonical Effective Queue

A playlist real pode conter MP3, comandos, scheduler, `saytime=...` e elementos virtuais.

Logo:

```
playlistpos != índice físico do media-map
```

`saytime` NÃO é um MP3 faltante.

Nova regra: **fila editorial e inventário de mídia são estruturas diferentes.**

---

## 15. C22 / Human Repository

O reconciler criou/materializou a interface humana:

```
/srv/studiosat/radio-principal/
  grade/manha
  grade/tarde
  grade/noite
  elementos/
  operacao/
  estado/
```

Execução observada:
- Manhã: ~27/28;
- Tarde: 85;
- Noite: 69.

Isso ajuda operação humana, mas não pode virar fonte editorial. O diretório é interface/materialização, não autoridade.

---

## 16. Media Transfer

Existe infraestrutura real de transferência:
- object store;
- SQLite;
- SHA256;
- endpoint exists;
- upload;
- report;
- validação por ffprobe.

Contagens observadas em um ponto:
- assets: 414;
- sources: 197;
- repository_index: 784.

Essa parte deve ser preservada e simplificada, não reescrita do zero.

O que falta é fechar o contrato:
`missing -> upload automático -> verificação -> READY -> fila`

com prioridade current, next, janela imediata e restante.

---

## 17. C23 / C24 / C25 / C26

### C23
Follower V2 isolado existe no GitHub. Limitação: ainda baseado em aproximações de programa/path; não é Canonical Effective Queue completa. Estado: **PREPARADO**.

### C24
Edge Bridge preparado para localhost. Boa ideia: manter segredo/token no NS1 e usar SSH. Estado: **PREPARADO**, não validado como solução final.

### C25
Agente Windows automático preparado. Risco: conta SYSTEM pode não enxergar drive mapeado `H:\`. Precisa UNC estável, service account explícita ou resolução real do storage.

### C26
Tentou criar fallback ordenado antes da Canonical Effective Queue estar resolvida e antes do LIVE estar estável. Não deve ser promovido na nova estratégia.

---

## 18. RESET-01A / RESET-01B

RESET-01A abortou com segurança porque esperava `[rb, local, security]`, mas produção já estava `[rb, local]`.

Isso foi um sucesso de engenharia: o guard evitou alteração baseada em pressuposto errado.

RESET-01B:
- aceitou estados observados;
- criou candidate;
- adicionou security blank;
- executou `liquidsoap --check`;
- instalou `[rb, security]`;
- removeu local-grade do público.

Funcionou: configuração, Harbor LISTEN, reconnect do RB e HLS. Não resolveu continuidade do LIVE.

---

## 19. RESET-02 / rádios temáticas

Rádios: Pop, Rock, Clássicas e Country.

Todas estavam com playlists estáticas pequenas e `-stream_loop -1`.

Inventário:
- Pop: playlist 10;
- Rock: playlist 10;
- Clássicas: playlist 11;
- Country: playlist 18.

O conteúdo também mostra forte indício de bibliotecas placeholder/incorretas:
- Pop: A-ha;
- Rock: Billy Joel;
- Clássicas: Adele;
- Country: Aerosmith.

Além da repetição existe problema de taxonomia/conteúdo.

RESET-02 procurou restore points em escopo estreito e encontrou 0. Depois a listagem real do `/root` mostrou que o escopo estava errado: existem forensic bundles e backups fora dos paths inicialmente pesquisados.

Lição: **não declarar ausência de backup sem inventariar toda a árvore de recuperação.**

---

## 20. Restore points reais encontrados no root

Chamam atenção:
- `STUDIOSAT-FORENSIC-NS1-20260917T023826Z`;
- `STUDIOSAT-NS1-CLEANUP-BACKUP-20260916-085221`;
- `studiosat-radioprincipal-mirror-v3-backup-20260916T000819Z`;
- `studiosat-radioprincipal-v2-backup-20260916-075244`;
- `studiosat-radioprincipal-consolidate-20260915-231431`;
- `STUDIOSAT-RADIOPRINCIPAL-LIVE-PROOF-20260916T202231Z.txt`;
- `STUDIOSAT-RADIOPRINCIPAL-V8-LIVE-FINAL-V3.1-20260916T204241Z.txt`;
- `studiosat-principal-FIND-RESTORE-v3.sh`;
- `studiosat-principal-GO-NOW.sh`.

---

## 21. RESET-03

RESET-03 fez busca real nos backups e encontrou vários selectors históricos.

Selecionou e validou:
`/root/studiosat-radioprincipal-v2-backup-20260916-075244/radioprincipal-selector-test.liq.before`

Fallback:

```
[rb, ns1, security]
```

O shadow `radioprincipal-ns1` estava READY.

Porém, após instalar o selector:
- Harbor voltou a LISTEN;
- `radioprincipal` público não ficou READY no gate.

Resultado:
`FATAL=PUBLIC_NOT_READY_ROLLBACK`

O rollback foi aplicado.

Isso prova que uma configuração sintaticamente válida e historicamente usada ainda pode não ser compatível com o runtime atual.

---

## 22. RESET-04

RESET-04 foi preparado para emergência:

```
radioprincipal-ns1
 -> FFmpeg bridge
 -> radioprincipal
 -> HLS
```

Objetivo: bypassar temporariamente o selector e colocar áudio contínuo no ar.

Status no momento deste relatório: **PREPARADO NO GITHUB; execução/validação ainda não comprovadas neste contexto.**

---

## 23. O que funcionou

### Funcionou bem
- GitHub como fonte de verdade;
- backups antes de alteração;
- guards de configuração;
- rollback automático;
- MediaMTX/HLS em várias janelas;
- shadow `radioprincipal-ns1` READY em RESET-03;
- SSH seguro;
- RadioBOSS conectando ao listener local;
- snapshots de controle;
- media-transfer;
- SHA256;
- object store;
- materialização Manhã/Tarde/Noite;
- forensic bundles;
- diferenciação entre PREPARADO e VALIDADO.

### Funcionou parcialmente
- Harbor: aceita conexão e metadata, mas perde decode;
- selector: prioridade funciona quando fontes ficam disponíveis;
- shadow legado: transmite, mas não preserva editoria corretamente;
- authority candidate: entende parte da playlist, mas ainda diverge em fila efetiva;
- repository reconciler: organiza arquivos, mas não fecha a grade completa.

---

## 24. O que deu errado

1. Produção usada como laboratório.
2. Muitas gerações de arquitetura coexistindo.
3. Confusão entre estado/heartbeat e áudio.
4. Confusão entre mídia física e programação.
5. Comando virtual tratado como arquivo.
6. Fallback editorial independente brigando com RadioBOSS.
7. Compatibilidade de versão não tratada como gate.
8. Restore search incompleto.
9. Rádios temáticas sem gestão de catálogo.
10. `systemctl active` usado como evidência excessiva de saúde.

---

## 25. Auditoria de versões e compatibilidade

### Liquidsoap

**Instalado no NS1 (evidência 16/09):**
`Liquidsoap 2.2.4-1+dev`

Essa é a maior bandeira técnica.

Em 2026-09-18, upstream mantém 2.4.x como linha suportada e a release estável é 2.4.5.

A própria documentação upstream alerta que versões minor diferentes podem ser incompatíveis e recomenda staging.

### Decisão
**não continuar expandindo a arquitetura em cima do 2.2.4-1+dev.**

Nova abordagem:
1. manter 2.2.4 apenas para recuperação/rollback;
2. instalar Liquidsoap 2.4.5 em staging isolado;
3. portar script usando documentação 2.4.5;
4. validar `input.harbor`, auth, metadata e `%ffmpeg`;
5. executar soak;
6. somente depois decidir promoção.

Não fazer upgrade in-place direto na produção.

---

## 26. RadioBOSS

Versão observada no projeto:
`7.2.2.0`

Em 2026-09-17 o fabricante publicou RadioBOSS 7.2.5.

Também houve 7.2.3 com correções de bugs de streaming e outras correções operacionais.

### Decisão
Planejar atualização para **7.2.5**, mas não no meio da recuperação.

Antes:
1. exportar/backup da configuração;
2. backup de scheduler, encoders, playlists e perfis;
3. confirmar licença/update entitlement;
4. instalar em janela;
5. validar API/comandos usados pelo agente;
6. validar encoder MP3/Icecast;
7. validar scheduler/saytime.

Não desenvolver integrações novas dependendo de 7.2.5 enquanto PC ainda estiver 7.2.2.

---

## 27. FFmpeg

NS1:
`FFmpeg / ffprobe 6.1.1-3ubuntu5`

Não há evidência de que FFmpeg 6.1.1 seja hoje o principal bloqueio.

O erro aparece dentro da integração FFmpeg do Liquidsoap/Harbor.

### Decisão
Não atualizar FFmpeg isoladamente agora.

Ao testar Liquidsoap 2.4.5:
- usar pacote/binário compatível;
- conferir bibliotecas libav usadas pelo Liquidsoap;
- reproduzir RadioBOSS -> Harbor por horas.

---

## 28. MediaMTX

MediaMTX está funcional em vários probes de RTMP, API local e HLS.

A versão exata do binário de produção precisa ser coletada novamente antes de qualquer mudança.

Upstream atual em 2026 oferece linha 1.21.x.

### Decisão
MediaMTX não é o primeiro candidato a upgrade.

Primeiro executar:
`/opt/tpsmedia/mediamtx/current/mediamtx --version`

Depois comparar config/migration notes.

Se HLS/RTMP estão funcionando, não trocar o roteador durante correção do ingest.

---

## 29. OpenSSH Windows

O desenho atual deve permanecer:
- uma task automática;
- uma chave;
- uma conexão supervisionada;
- apenas forwards necessários;
- portas remotas em loopback.

Não abrir 18005 na Internet.

---

## 30. Nova estratégia técnica

### FASE A — RECUPERAÇÃO
Objetivo único: áudio contínuo. Não construir feature.

Gate:
- public RTMP READY;
- HLS READY;
- 30 min sem interrupção.

### FASE B — FREEZE
Congelar C12-C26, V8, selectors antigos e scripts ad hoc.

Classificar: canonical, recovery, lab, obsolete.

### FASE C — STAGING DE VERSÃO
Criar runtime isolado:
- Liquidsoap 2.4.5;
- mesma fonte RadioBOSS;
- path de teste;
- sem tocar público.

### FASE D — LIVE
Provar 6 h e 24 h, zero `Feeding stopped`, metadata, reconnect e nenhuma oscilação.

### FASE E — CANONICAL EFFECTIVE QUEUE
Só então: parser, playlistpos, current, next, pos_ms, virtual commands e schedule.

### FASE F — ASSETS
Fechar SHA, missing, upload automático, prioridade, retry e audit.

### FASE G — SHADOW V2
Tocar mesma fila, mesmo item, posição aproximada e continuar offline. Sempre em path isolado.

### FASE H — FAILOVER
Selector:
`LIVE -> SHADOW V2 -> security`

Com estabilidade mínima antes de voltar, hysteresis, anti-flap e métricas.

### FASE I — CONSOLE
Somente depois da cadeia funcionar.

---

## 31. Estratégia das quatro rádios temáticas

Não usar mais `playlist pequena + stream_loop -1` como solução permanente.

Precisamos separar por emissora:
- catálogo;
- classificação;
- programação;
- repeat protection;
- rotação;
- comerciais;
- horário.

Primeiro recuperar conteúdo histórico real dos backups. Depois criar catálogo canônico. A playlist gerada deve ser produto de regras, não a fonte de verdade.

---

## 32. Gate de compatibilidade obrigatório a partir de agora

Antes de escrever qualquer configuração para software de terceiros:

1. capturar `--version`;
2. fixar a versão no Change ID;
3. abrir documentação DA MESMA versão;
4. validar sintaxe;
5. executar em staging;
6. verificar comportamento;
7. registrar hash da configuração;
8. só promover após soak.

Proibido:
- usar documentação 2.4 para produção 2.2;
- assumir parâmetro existente em versão antiga;
- copiar script histórico sem checar runtime atual;
- restaurar config antiga apenas porque `liquidsoap --check` passa.

---

## 33. Matriz de prioridade

| Prioridade | Trabalho | Estado |
|---|---|---|
| P0 | Rádio Principal com áudio contínuo | EM RECUPERAÇÃO |
| P0 | parar alterações concorrentes | OBRIGATÓRIO |
| P1 | inventário de versões runtime | NECESSÁRIO |
| P1 | staging Liquidsoap 2.4.5 | NOVA ESTRATÉGIA |
| P1 | atualizar RadioBOSS 7.2.2 -> 7.2.5 controladamente | PLANEJAR |
| P2 | Canonical Effective Queue | BLOQUEADO ATÉ LIVE |
| P2 | asset sync automático | PARCIAL |
| P3 | Shadow V2 | BLOQUEADO ATÉ QUEUE |
| P3 | anti-flap | BLOQUEADO ATÉ SHADOW |
| P4 | temáticas / catálogo real | URGENTE EM PARALELO ISOLADO |
| P5 | console/auth/RBAC | DEPOIS DA CADEIA |
| P10 | cleanup legado | SOMENTE NO FIM |

---

## 34. O que não deve mais acontecer

- nenhum script novo reinicia produção “para testar”;
- nenhum candidate é promovido sem path isolado;
- nenhuma lista física vira programação;
- nenhum `active` vira sinônimo de “no ar”;
- nenhum backup é declarado inexistente antes de busca global;
- nenhuma versão antiga recebe parâmetros consultados em docs novas;
- nenhum upgrade é feito diretamente no servidor de produção sem staging;
- nenhum componente de console bloqueia recuperação de áudio.

---

## 35. Próximo desenho recomendado

```
                    RADIOBOSS
                 /      |       \
              LIVE    CONTROL    ASSETS
               |         |         |
             SSH       Agent     Transfer
               |         |         |
               v         v         v
          INGEST STAGE   QUEUE    STORE
          Liquidsoap     Engine    SHA256
            2.4.5          |         |
               \           |        /
                \          |       /
                 +---- SHADOW V2 ---+
                        |
                selector anti-flap
                        |
                    MediaMTX
                        |
                       HLS
```

Em produção atual, 2.4.5 deve existir primeiro apenas como staging.

---

## 36. Estado final deste relatório

### Comprovado
- RadioBOSS chega ao túnel Windows;
- SSH dedicado existe;
- Harbor aceita fonte em alguns momentos;
- Harbor 2.2.4 perde stream/decode;
- local-grade errado foi retirado do público;
- shadow NS1 existe e ficou READY no RESET-03;
- restore real de 16/17 existe no root;
- selector histórico `[rb, ns1, security]` foi encontrado e validado sintaticamente;
- promoção RESET-03 falhou no public RTMP e fez rollback;
- quatro temáticas têm catálogos/playlist mínimos e repetitivos;
- MediaMTX/HLS funcionaram em múltiplas janelas.

### Não comprovado ainda
- RESET-04 ativo em produção;
- LIVE estável;
- Shadow editorialmente fiel;
- C24/C25 instalados e validados;
- C26 correto;
- console final;
- RBAC/MFA;
- anti-flap;
- soak;
- cutover V2.

---

## 37. Regra mestre daqui em diante

**Recuperação não é reconstrução.**

Primeiro recuperamos áudio estável.

Depois construímos a nova cadeia em paralelo usando versões suportadas e documentação correspondente.

Somente após soak a nova cadeia toca produção.
