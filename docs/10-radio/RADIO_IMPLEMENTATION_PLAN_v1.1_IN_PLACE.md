# Radio Studio Sat — Plano Mestre de Implementação v1.1 — IN-PLACE FIRST

Status: **ATIVO — SUBSTITUI v1.0 PARA EXECUÇÃO**  
Data: 2026-09-10  
Owner: Engenharia Rádio

## Objetivo final

Entregar as cinco emissoras Radio Studio Sat — Principal, Pop, Rock, Clássicas e Country — prontas, estáveis e operacionais, aproveitando e remodelando a estrutura que já está no ar.

## Leis de implementação

1. **NO CONTAINERS / NO VMs.**
2. **IN-PLACE FIRST.** A base física oficial continua `/srv/tpsmedia/repository/channels/<station>`.
3. Não criar nova árvore permanente `/srv/studiosat/...`.
4. Não duplicar MediaMTX, NGINX, TLS, registry, biblioteca ou famílias permanentes de services.
5. Preservar `station_id`, path MediaMTX, URLs públicas e roots existentes sempre que possível.
6. Refatorar playlist, canonical/QC, health, metadata, fallback, ingest, segurança e observabilidade dentro da estrutura atual.
7. Shadow somente do componente candidato à substituição, temporário, usando mídia existente e path LAB separado.
8. Depois do cutover aprovado, remover o shadow.
9. Nenhuma edição improvisada do arquivo ativo: usar precheck, candidate/backup pequeno, validação, promoção controlada e rollback.
10. Engenharia TV é dona da vertical TV. Engenharia Rádio apenas preserva interfaces Core neutras para integração futura.

## Estado confirmado pela CHG-001

```text
radioprincipal   active / MediaMTX ready
radiopop         active / MediaMTX ready
radiorock        failed / MediaMTX not ready
radioclassicas   active / MediaMTX ready
radiocountry     active / MediaMTX ready
```

Country possui conteúdo em `ready/` e é a station mais adequada para validar primeiro o comportamento da stack atual.

## Sequência revisada

### R0 — Country Reference Restart

Objetivo: validar imediatamente que a stack atual reinicia corretamente usando o conteúdo e estrutura existentes.

Fluxo:

```text
ready/
→ tps-generate-playlist
→ playlist.txt
→ tps-radiocountry-playout.service
→ FFmpeg legado
→ RTMP localhost
→ MediaMTX /radiocountry
→ HLS
```

Antes do restart:

- sincronizar GitHub;
- confirmar unit/ExecStartPre/ExecStart;
- confirmar conteúdo elegível em `ready/`;
- registrar hash da playlist atual;
- registrar hash do gerador;
- confirmar MediaMTX ready;
- confirmar HLS atual;
- registrar states das demais stations.

Execução:

- restart somente `tps-radiocountry-playout.service`;
- não reiniciar MediaMTX, NGINX, outras rádios ou TVs.

PASS:

- service active após restart;
- novo MainPID/ExecMainStartTimestamp;
- ExecStartPre sem erro;
- MediaMTX ready;
- HLS respondendo e avançando;
- áudio presente;
- sem restart loop;
- demais stations sem regressão.

### R1 — Recuperação Radio Rock no legado atual

Depois de Country comprovar a stack saudável, recuperar Rock in-place.

- confirmar asset elegível real;
- corrigir somente mídia/playlist/gerador necessários;
- não instalar engine novo para mascarar o incidente;
- validar service, MediaMTX, HLS e áudio;
- documentar causa, correção e rollback.

### R2 — Normalização das cinco árvores atuais

Sem mover bibliotecas. Avaliar/criar apenas subdiretórios necessários dentro de cada root atual:

```text
incoming/
quarantine/
canonical/
ready/
playlists/
state/
graphics/
logs/
lab/   # somente estado temporário quando necessário
```

`ready/` permanece fisicamente compatível com o legado nesta fase. Evolução para estado lógico/manifesto será change futura e não pode quebrar o playout atual.

### R3 — Playlist e atomicidade

Padronizar no local:

```text
candidate
→ validar
→ publicar atomicamente
→ current
→ previous/rollback
```

Principal possui exceção própria e continua por último até seu gerador especial ser reconciliado.

### R4 — Canonical/QC Rádio

Definir profile Rádio versionado e procedimento offline de ingest/QC. Evitar transcode pesado on-air.

Perfis Rádio permanecem independentes dos perfis TV.

### R5 — Health/metadata/state Rádio

Construir extensão Rádio do health comum:

- process;
- MediaMTX ready;
- output freshness;
- áudio/silêncio;
- metadata/current event;
- AUTO/LIVE/FALLBACK;
- A/V e áudio-only quando o novo engine entrar.

### R6 — Country engine candidate

Somente depois da base atual estar estável.

Liquidsoap 2.4.x continua candidato inicial, não decisão final.

Sem containers/VMs. Se a instalação exigir upgrade perigoso de bibliotecas/FFmpeg do host, o candidato é rejeitado e outra abordagem/engine deve ser considerada.

Não criar segunda biblioteca. O candidato lê a mídia já existente.

### R7 — Shadow mínimo Country

Somente o engine candidato roda em paralelo:

```text
mídia existente
├── produção FFmpeg → radiocountry
└── candidate       → lab-radio-country-*
```

Não duplicar MediaMTX, NGINX, TLS ou filesystem de produção.

### R8 — A/V + áudio-only + fallback + metadata + live

Provar uma única timeline editorial e duas rendições coerentes.

Live deve entrar/sair sem restart do engine. Transporte/auth/ACL são decididos com Core antes de abrir listener público.

### R9 — Shadow ≥24 h

Comparar continuidade, CPU/RAM, logs, metadata, rendições, fallback, live e impacto nas demais stations.

### R10 — Core Compatibility Gate

Antes do cutover Country, revisar com Engenharia TV os componentes realmente compartilhados: MediaMTX, NGINX/TLS, naming, ingress/auth/ACL, health, systemd policy e rollback.

### R11 — Country cutover

Trocar somente o componente necessário. Preservar station ID, path de produção, URL pública e biblioteca.

Após estabilidade, remover shadow temporário.

### R12 — Demais rádios

```text
Pop → Clássicas → Rock → Principal
```

Cada station repete precheck, QC, shadow mínimo se houver troca de engine, cutover, observação e rollback.

## Proibido

- containers/VMs;
- segunda plataforma permanente;
- nova árvore `/srv/studiosat/` como requisito de migração;
- segundo MediaMTX/NGINX;
- duplicação de bibliotecas apenas para LAB;
- restart em massa;
- trocar FFmpeg global por necessidade de uma station;
- editar configuração ativa sem candidate/rollback;
- mudar TV para resolver Rádio.

## Critério final

A vertical Rádio só encerra quando as cinco stations estiverem estáveis, isoladas, com output validado, timeline correta, metadata, fallback, live conforme necessidade, recovery, health e rollback documentados, e sem exigir retrabalho da vertical TV no Core compartilhado.
