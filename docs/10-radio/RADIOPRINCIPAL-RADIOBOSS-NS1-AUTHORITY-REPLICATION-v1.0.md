# Rádio Principal — RadioBOSS → NS1 Authority Replication Contract v1.0

## Identidade

- Workstream: `RADIOPRINCIPAL-NS1`
- Estação: `radioprincipal`
- Versão: `1.0`
- Data de fixação: `2026-09-17`
- Estado: `REGRA DE NEGÓCIO E CONTRATO DE SISTEMA`
- Escopo: emissora local/RadioBOSS, sincronização editorial e de mídia, shadow NS1, failover, transmissão pública e auditoria.
- Fora do escopo: Portal/CMS, aplicativo móvel como produto, outras emissoras e TV.

## 1. Regra fundamental

O `RadioBOSS` da emissora local é a **autoridade editorial** da Rádio Principal.

O `NS1` é o **transmissor contínuo** e uma **réplica operacional executável** da programação autoritativa do RadioBOSS.

O NS1 NÃO deve criar uma programação própria, playlist paralela ou ordem editorial independente enquanto existir uma programação válida recebida do RadioBOSS.

Quando a emissora local estiver conectada, o NS1 deve simultaneamente:

1. receber o áudio LIVE do RadioBOSS;
2. receber e persistir a programação, fila efetiva, schedule, playback e heartbeat;
3. manter uma biblioteca local reconciliada com todos os itens necessários à programação;
4. manter um shadow local alinhado ao item e à posição de reprodução do RadioBOSS;
5. publicar a saída final da estação através do selector/MediaMTX/NGINX.

Quando a emissora local se desconectar por qualquer causa, o NS1 deve assumir o áudio público e continuar a **mesma programação autoritativa**, a partir do último checkpoint de reprodução confirmado, usando a biblioteca local.

## 2. Dois planos de interligação obrigatórios

A solução possui dois planos logicamente independentes.

### Plano A — áudio LIVE

```text
RadioBOSS / estúdio local
  -> túnel seguro
  -> Harbor Liquidsoap NS1 :18005
  -> selector
  -> radioprincipal
  -> MediaMTX
  -> HLS/NGINX
  -> público
```

Este plano transporta o que está efetivamente no ar no estúdio.

### Plano B — autoridade editorial, controle e conteúdo

```text
RadioBOSS / agente Studio Sat
  -> playlist
  -> fila efetiva de execução
  -> schedule/eventos
  -> playback/checkpoint
  -> heartbeat
  -> catálogo/library manifest
  -> metadados e proveniência
  -> arquivos ausentes, somente quando necessários
  -> NS1 replica database + asset store
```

Este plano mantém o NS1 capaz de continuar a emissora sem depender do computador local.

Uma falha do Plano A não pode apagar ou invalidar o último estado válido recebido pelo Plano B.

## 3. Playlist não é biblioteca e biblioteca não é programação

Devem ser tratados como objetos diferentes:

- **biblioteca**: conjunto de mídias disponíveis;
- **playlist definition**: definição editorial de uma programação;
- **playlist revision**: versão imutável de uma definição em determinado instante;
- **execution plan / fila efetiva**: sequência realmente executável após playlist + scheduler + inserções + comandos editoriais;
- **playback checkpoint**: item e posição que o RadioBOSS está efetivamente reproduzindo;
- **transmission event**: ocorrência efetivamente publicada pelo NS1 para o caminho público.

O NS1 monta sua execução consultando o banco e a biblioteca local, mas a ordem vem da autoridade RadioBOSS.

## 4. Identidades: não concentrar tudo em um único código

A mesma música pode tocar muitas vezes, em programas e horários diferentes. Portanto, um único código contendo artista + horário + programa + locutor + IP seria instável e incorreto.

O sistema deve manter identidades em camadas relacionadas.

### 4.1 `work_id`

Identifica a obra/conteúdo lógico.

Exemplo: a música `Thriller` como obra editorial.

Pode possuir artista, título, gênero, tipo editorial e demais metadados lógicos.

### 4.2 `asset_id`

Identifica os bytes exatos de um arquivo.

Formato canônico recomendado:

```text
sha256:<64-hex>
```

Dois arquivos com o mesmo nome, mas bytes diferentes, são assets diferentes.

### 4.3 `asset_version_id`

Identifica uma versão operacional/canônica derivada do asset de origem.

Qualquer transcodificação, edição, normalização, corte ou substituição cria nova versão. O arquivo anterior nunca deve ser sobrescrito sem histórico.

### 4.4 `playlist_id`

Identifica a programação lógica, por exemplo `Tarde Studio Sat Principal`.

### 4.5 `playlist_instance_id`

Identifica uma instância concreta originada no RadioBOSS, preservando o identificador externo quando existir, por exemplo `TSSP170926`.

### 4.6 `playlist_revision_id`

Identifica uma revisão imutável da sequência normalizada.

Deve mudar somente quando houver mudança semântica relevante em playlist/fila/schedule; timestamp de recepção sozinho não pode criar nova revisão.

### 4.7 `playlist_item_id`

Identifica uma ocorrência específica de um asset dentro de uma revisão/execução.

A mesma música em dois horários possui o mesmo `asset_id`, mas dois `playlist_item_id` diferentes.

### 4.8 `execution_event_id`

Identifica uma execução efetiva, seja no RadioBOSS LIVE ou no shadow NS1.

### 4.9 `transmission_event_id`

Identifica a publicação efetiva no caminho público do NS1.

É a chave que conecta programa, item, asset, origem, operador, horário, failover e evidência de entrega.

## 5. Metadados obrigatórios

### 5.1 Mídia/obra

Sempre que disponíveis:

- `work_id`;
- `asset_id` SHA-256;
- `asset_version_id`;
- tipo: `music | ad | jingle | liner | call | news | utility | institutional | live | other`;
- título;
- artista/intérprete;
- gênero/estilo;
- álbum;
- duração;
- codec/profile operacional;
- nome original do arquivo;
- caminho/origem no RadioBOSS;
- base/fonte de dados de origem;
- data de criação conhecida;
- data de modificação conhecida;
- hash da origem;
- hash da cópia no NS1.

### 5.2 Contexto editorial

- `station_id`;
- `program_id`;
- nome do programa;
- `playlist_instance_id`;
- `playlist_revision_id`;
- posição/ordem;
- data/hora planejada;
- regra de schedule relacionada;
- `announcer_id`/locutor quando aplicável;
- `programmer_id`/programador quando conhecido;
- `auditor_id` quando aplicável;
- campanha/cliente para comerciais quando aplicável.

### 5.3 Contexto da fonte

Registrar por evento, e não dentro da identidade da música:

- software de origem;
- versão do software;
- host/PC de origem;
- identificador estável da máquina quando disponível;
- IP observado no momento do evento;
- agente Studio Sat e versão;
- timestamp UTC;
- identificador da sessão/conexão quando disponível.

IP é evidência contextual e pode mudar; não deve ser usado como identidade primária do computador.

## 6. Proveniência e histórico de alteração

Toda mídia e toda revisão editorial deve possuir cadeia de proveniência.

O sistema deve conseguir responder:

- de qual base/fonte o conteúdo saiu;
- quando foi criado/descoberto;
- qual era o hash original;
- se foi alterado;
- quando foi alterado;
- por qual software/processo;
- por qual operador, quando conhecido;
- qual versão anterior originou a nova;
- qual versão foi usada no momento da transmissão.

Modelo mínimo:

```text
origin -> asset version A -> transformation event -> asset version B -> playlist item -> execution event -> transmission event
```

Eventos de auditoria devem ser append-only. Para detectar adulteração, cada evento pode carregar `previous_event_hash` e `event_hash`, formando uma cadeia verificável.

Credenciais, segredos e IPs sensíveis não devem ser publicados no GitHub. O repositório guarda esquema e documentação; os registros operacionais permanecem em armazenamento protegido do NS1.

## 7. Banco do NS1

O banco armazena metadados, estado, relações e auditoria. Os arquivos de áudio permanecem em storage de mídia; não devem ser gravados como blobs no banco.

Para a primeira implementação no NS1 é aceitável SQLite em WAL mode, com migrações versionadas e backup. Se a concorrência/analytics futuros excederem este perfil, o esquema deve permanecer migrável para PostgreSQL.

Tabelas/entidades mínimas:

```text
stations
source_hosts
operators
programs
works
assets
asset_versions
asset_origins
asset_presence
playlist_instances
playlist_revisions
playlist_items
schedule_events
execution_plans
playback_checkpoints
sync_runs
transfer_jobs
failover_events
execution_events
transmission_events
public_delivery_evidence
audit_events
```

## 8. Organização física da biblioteca

A fonte canônica dos arquivos deve ser orientada por conteúdo/hash, evitando colisões de nome.

Exemplo:

```text
mirror-store/<sha256>.mp3
```

Pastas por cantor, gênero, programa ou campanha podem existir como **views derivadas**, índices ou links, mas não devem ser a autoridade física da mídia.

Exemplos derivados:

```text
by-artist/Elton John/...
by-genre/Anos 90/...
by-program/Tarde Studio Sat Principal/...
```

A mesma mídia pode pertencer a vários programas/gêneros sem duplicar o arquivo canônico.

## 9. Algoritmo de sincronização

### 9.1 Recepção

O agente do RadioBOSS envia continuamente snapshots e eventos.

O NS1 deve validar schema, estação, timestamps e integridade antes de promover uma revisão.

### 9.2 Normalização

O NS1 converte a representação do RadioBOSS para um modelo canônico, preservando os identificadores de origem.

### 9.3 Revisão semântica

Nova `playlist_revision_id` somente quando conteúdo/ordem/regras relevantes mudarem.

Campos como `received_at_utc` não podem causar churn de revisão/generation por si sós.

### 9.4 Reconciliação de assets

Para cada item requerido:

```text
resolver referência de origem
-> calcular/obter identidade do asset
-> consultar asset_presence no NS1
-> existe e hash confere? READY
-> não existe? criar transfer_job
-> transferir
-> validar hash/duração/QC
-> promover READY
```

O NS1 transfere somente o que ainda não possui ou cuja versão mudou.

### 9.5 Prioridades de prefetch

A sincronização deve priorizar:

1. item atual e itens imediatamente seguintes;
2. inserções urgentes de scheduler/comercial;
3. restante do programa atual;
4. próximas horas/dia;
5. restante do horizonte futuro disponível no RadioBOSS.

Se o RadioBOSS disponibilizar 10 ou 30 dias de programação futura, o NS1 deve registrar todas as revisões e preparar os assets únicos necessários dentro do horizonte configurado e suportado pelo storage.

## 10. Inserções dinâmicas

A playlist estática não é suficiente.

Scheduler, comerciais, hora certa, chamadas, notícias, utilidade pública ou comandos manuais podem alterar a fila efetiva.

Por isso o NS1 deve manter um `execution_plan` resultante de:

```text
playlist revision
+ schedule
+ inserções
+ remoções
+ overrides
+ estado de playback
= fila efetiva
```

Mudança de fila deve gerar atualização imediata, além da reconciliação periódica de segurança.

## 11. Frequência de sincronização

O sistema deve usar simultaneamente:

- atualização orientada a eventos quando houver mudança;
- checkpoints de playback de alta frequência;
- reconciliação periódica completa para recuperar eventos perdidos.

O timer periódico é uma salvaguarda; não substitui os eventos em tempo real.

## 12. Shadow hot-synchronized

O shadow NS1 deve usar `playback.json`/checkpoint equivalente como autoridade principal de sincronismo.

Campos mínimos:

- `playlist_revision_id`;
- `playlist_item_id` ou resolução inequívoca do item;
- `playlistpos`;
- `asset_id`;
- `pos_ms`;
- `len_ms`;
- `state`;
- `next`;
- timestamp da fonte e timestamp de recepção.

`matched_index` pode existir como telemetria auxiliar, mas não deve ser a autoridade principal do failover.

## 13. Regra de failover

Se o áudio LIVE/Harbor ficar indisponível além do limiar configurado:

1. congelar último checkpoint RadioBOSS válido;
2. localizar exatamente o mesmo item/asset no NS1;
3. calcular posição de retomada considerando idade do checkpoint;
4. iniciar/alinhar shadow nesse ponto;
5. selector troca para `radioprincipal-ns1`;
6. continuar a fila efetiva replicada;
7. registrar `failover_event` e todos os `transmission_events` subsequentes.

O NS1 nunca deve trocar silenciosamente para uma playlist genérica diferente.

Se um asset requerido estiver ausente, isso é `DIVERGENCE/NOT_READY` e deve ser registrado. Qualquer fallback editorial de emergência precisa ser explícito e auditado; não pode ser apresentado como reprodução idêntica.

## 14. Operação desconectada por horas ou dias

O NS1 deve persistir programações futuras e assets para continuar mesmo com o estúdio desconectado por período prolongado.

Durante a desconexão:

- o último plano autoritativo aceito permanece imutável como base;
- schedules futuros previamente recebidos continuam válidos;
- o NS1 executa a mesma ordem programada;
- qualquer divergência é registrada;
- nenhuma informação nova é inventada como se tivesse vindo do RadioBOSS.

Quando o RadioBOSS reconectar, a nova autoridade deve ser reconciliada antes do retorno do áudio LIVE.

## 15. Failback e hysteresis

A simples reabertura do TCP não é suficiente para retornar ao RadioBOSS.

Antes do failback, exigir por janela configurável:

- Harbor estável;
- playback fresco e coerente;
- heartbeat válido;
- identidade do item resolvida;
- diferença de posição dentro do limite;
- ausência de flapping recente.

Só então realizar handoff e registrar o evento.

## 16. Prova de transmissão e prova de audiência

Existem níveis distintos de evidência e eles não podem ser confundidos.

### `PUBLISHED`

O NS1 comprova que publicou determinado `transmission_event_id` no path público `radioprincipal`.

### `DELIVERED`

MediaMTX/NGINX comprova que bytes/segmentos daquele intervalo foram entregues a uma sessão cliente.

### `CLIENT_PLAYBACK_REPORTED`

Web/app instrumentado pode confirmar que o player informou reprodução daquela janela/evento.

### Audição humana

O servidor não pode afirmar tecnicamente que uma pessoa humana efetivamente ouviu o áudio apenas porque bytes foram entregues. Portanto a auditoria deve usar o termo exato correspondente à evidência disponível e nunca registrar `HEARD_BY_HUMAN` sem uma fonte apropriada que realmente suporte essa afirmação.

## 17. Estado READY do NS1

O NS1 somente pode ser considerado `HOT_READY` quando, no mínimo:

- execution plan atual está válido;
- item atual está resolvido;
- checkpoint está fresco;
- todos os assets da janela crítica estão disponíveis e validados;
- shadow está publicando `radioprincipal-ns1`;
- selector consegue ler o shadow;
- MediaMTX está saudável;
- não existem divergências não reconhecidas na janela crítica.

Estados sugeridos:

```text
SYNCING
HOT_READY
LIVE_PRIMARY
NS1_PRIMARY
DEGRADED
NOT_READY
DIVERGED
```

## 18. Evidência visual TSSP170926 em 2026-09-17

A captura fornecida pelo operador mostra no RadioBOSS Ultimate 7.2.2.0:

- playlist/programação ativa `Tarde Studio Sat Principal (TSSP170926)`;
- relógio da captura aproximadamente `16:47:45`;
- item em execução visível: Elton John — `Something About The Way You Look Tonight`;
- próximo item visível: Corona — `The Rhythm Of The Night`;
- sequência posterior visível inclui Spice Girls, Banda Eva, Claudinho & Buchecha e Cher;
- a interface indica `85` faixas e duração total aproximada de `5:33:55`;
- tempo restante indicado de aproximadamente `4:13:14`, término previsto `21:00:59`;
- scheduler aparece habilitado e há evento futuro às `16:50:00` na lateral;
- o log visual mostra atividade de `Starting event`, `Schedule` e inserção de faixa.

A captura é evidência operacional visual, não substitui o snapshot machine-readable. A aceitação deve provar que o NS1 consegue identificar a `TSSP170926` e sua fila efetiva item a item através dos dados sincronizados.

## 19. Gate obrigatório TSSP170926

Existe hoje uma diferença a ser explicada antes de qualquer mudança de produção:

- a tela do RadioBOSS mostra `85` faixas para `TSSP170926`;
- o mirror/controller observado no XRAY recente trabalhava com aproximadamente `154` itens de mídia.

Não assumir que são a mesma coleção.

O primeiro teste deve determinar exatamente o que cada snapshot representa: playlist ativa, aggregate playlist, biblioteca, schedule ou outro escopo.

Somente depois de obter uma correspondência inequívoca `RadioBOSS UI -> snapshot -> normalized DB -> asset -> execution plan` o failover por réplica poderá ser promovido.

## 20. Critérios de aceitação de negócio

A implementação só atende este contrato quando for possível provar, em sequência:

1. identificar a programação ativa pelo nome/ID do RadioBOSS;
2. registrar uma revisão imutável e semanticamente estável;
3. reproduzir no banco a ordem real dos itens;
4. resolver cada item para um asset e versão;
5. transferir apenas assets ausentes/alterados;
6. manter janela crítica 100% READY;
7. seguir item e `pos_ms` do RadioBOSS;
8. receber uma inserção dinâmica e incorporá-la ao execution plan;
9. retirar o link LIVE e assumir no mesmo item/ponto dentro da tolerância aprovada;
10. continuar os próximos itens da mesma programação sem conexão com o estúdio;
11. registrar o que foi publicado pelo NS1;
12. reconectar o RadioBOSS e realizar failback apenas após estabilidade;
13. preservar trilha de proveniência desde a origem até a transmissão.

## 21. Regra de segurança da implantação

Toda implantação deve seguir:

```text
inventariar
-> modelar
-> executar candidate/shadow
-> comparar
-> provar READY
-> ensaiar falha controlada
-> somente então promover
```

Não alterar selector, Harbor ou caminho público enquanto o candidate de réplica ainda não tiver passado os gates acima.
