# StudioSat Web — Component Disposition Matrix v1.0

Status: **NORMATIVO após FULL RAY-X v3.1**  
Data: 2026-09-10  
Princípio: **IN-PLACE FIRST / NO CONTAINERS / NO VMs / NO DUPLICATE PLATFORM**

## Semântica

- **KEEP** — componente existente é parte da solução e deve ser preservado.
- **FIX** — há defeito concreto; corrigir sem redesenhar desnecessariamente.
- **REFACTOR** — responsabilidade/estrutura precisa melhorar mantendo a plataforma.
- **REPLACE** — substituir somente quando houver evidência e candidate aprovado.
- **REMOVE** — retirar somente legado/duplicação comprovadamente desnecessária após estabilidade e rollback expirado.

Nenhum `REPLACE` ou `REMOVE` abaixo autoriza execução por si só; toda ação precisa de Change própria.

## Matriz oficial

| Componente | Classificação | Owner | Decisão atual | Gate |
|---|---|---|---|---|
| Google Compute Engine host atual | KEEP | Core | host tem folga para carga corrente | capacity baseline/monitoring |
| Ubuntu 24.04.4 LTS | KEEP | Core | nenhuma reinstalação/rebuild | upgrades por Change |
| `/srv/tpsmedia/repository/channels/<station>` | KEEP + REFACTOR | Core + domínio | base oficial existente; evoluir internamente | não mover biblioteca |
| station IDs atuais | KEEP | Core | identidade pública/operacional estável | mudança só por necessidade real |
| systemd | KEEP + REFACTOR | Core + domínio | 1 station = 1 unit/processo principal | hashes + policy/drop-ins |
| FFmpeg 6.1.1 | KEEP | Core/domínios | engine atual eficiente em `-c copy`; não atualizar por hipótese | benchmark antes de qualquer major upgrade |
| `/usr/local/sbin/tps-playout-radio` | KEEP + REFACTOR | Rádio | manter legado funcionando; evoluir outputs/capacidades se necessário | Rádio pilot |
| `/usr/local/sbin/tps-playout-tv` | KEEP / TV-OWNED | TV | Rádio não altera | Engenharia TV |
| `tps-generate-playlist` global | REFACTOR | Core + Rádio + TV | compartilhamento Rádio/TV cria acoplamento indevido | separar semântica por domínio |
| generator especial da Rádio Principal | FIX → depois REFACTOR/retirar | Rádio | escaping atual quebra conteúdo com apóstrofo | CHG-R01 |
| playlists ffconcat | KEEP + REFACTOR | domínio | manter formato enquanto útil; adicionar candidate/current/previous e atomicidade | change por domínio |
| `ready/` | KEEP compatibilidade + REFACTOR | domínio | não duplicar biblioteca; semântica deve ser explícita | canonical/QC design |
| `canonical/` | KEEP + REFACTOR | domínio | tornar fonte certificada de conteúdo quando perfil estiver congelado | profile/QC |
| MediaMTX v1.20.1 | KEEP + REFACTOR | Core | router atual atende produção; não duplicar | auth/ACL/listeners/health |
| `/etc/tpsmedia/mediamtx/mediamtx.yml` | KEEP + FIX/REFACTOR | Core | preservar paths; endurecer somente após mapear ingress/live | Core Change Gate |
| NGINX atual | KEEP + FIX | Core | configuração funciona; corrigir rotas/403/permissões sem rebuild | `nginx -t` + health cruzado |
| TLS/Certbot | KEEP + FIX | Core | certificados válidos; automação de renovação precisa ser comprovada | dry-run em change própria |
| Domínios `www.*` de portais | KEEP | Core/domínio | principais portais responderam 200 | health externo |
| Domínios sem `www` que retornam 403 | FIX/DECIDE | Core/domínio | definir se 403 é intencional ou corrigir redirect/portal | matriz de hostname |
| HLS TV atual | KEEP / TV-OWNED | TV + Core | manifests reais observados | Engenharia TV |
| HLS Rádio atual | FIX | Rádio + Core | MediaMTX não cria HLS para MPEG-1/2 Audio legado | Country AAC probe antes de novo engine |
| RTSP atual | KEEP | Core | útil como probe e saída técnica | health |
| RTMP localhost publish | KEEP | Core/domínio | publishers atuais locais e isolados | auth/live design |
| WebRTC/SRT listeners MediaMTX | REFACTOR/DECIDE | Core | manter somente o que tiver uso/requisito documentado | ingress inventory |
| API MediaMTX loopback | KEEP | Core | restrição local está correta | health/control |
| Samba ingest | FIX + REFACTOR | Core | exposição/permissões precisam ser reduzidas ao mínimo necessário | mapear clientes antes |
| UFW/firewall local atual | REFACTOR | Core | estado local permissivo; confrontar GCP/VPC antes de mudança | network change |
| permissões world-writable críticas | FIX | Core | eliminar 777 injustificado por lotes testados | health + rollback |
| Prometheus/Grafana/exporters instalados | KEEP + REFACTOR | Core | reaproveitar se configs seguras; não instalar observabilidade paralela | audit antes de enable |
| PostgreSQL/Redis instalados e não essenciais ao playout atual | KEEP DORMANT / DECIDE | Core | não remover nem tornar dependência sem necessidade | Control Plane futuro |
| unattended-upgrades/timers de update | REFACTOR/DECIDE | Core | revisar política para broadcast 24x7 | maintenance policy |
| Docker | KEEP ABSENT | Core | proibido nesta arquitetura | — |
| Podman | KEEP ABSENT | Core | proibido nesta arquitetura | — |
| VMs adicionais para esta stack | KEEP ABSENT | Core | proibido como solução de acomodação | — |
| Liquidsoap | KEEP ABSENT / CANDIDATE NÃO SELECIONADO | Rádio | só reconsiderar se requisito concreto não for resolvido pela stack atual | benchmark/gate |
| ffplayout | KEEP ABSENT / NÃO SELECIONADO | TV | decisão exclusivamente TV | TV gate |
| Icecast | KEEP ABSENT | Rádio | só introduzir se houver gap real de protocolo | evidence gate |
| segunda árvore `/srv/studiosat/...` | REMOVE DO PLANO | Core | não criar | norma vigente |
| segundo MediaMTX/NGINX/registry/health permanente | REMOVE DO PLANO | Core | não duplicar shared Core | norma vigente |

## Regras de evolução

1. **KEEP não significa intocável**; significa que a identidade/componente permanece enquanto melhorias são aplicadas por Change.
2. **FIX precede REPLACE**. Um defeito de generator não justifica substituir o engine inteiro.
3. **REFACTOR não significa duplicar**. A responsabilidade pode ser separada mantendo a mesma infraestrutura física.
4. **REPLACE exige prova**: problema concreto, candidate, benchmark, rollback e vantagem mensurável.
5. **REMOVE só ocorre por último**, após estabilidade, observação e inexistência de dependência.

## Ordem imposta pela matriz

```text
BASELINE LOCK
→ Rádio Principal FIX
→ Radio Rock FIX
→ generator Rádio/TV REFACTOR
→ restart/recovery proof por station
→ Rádio HLS FIX em Country
→ profile/canonical/QC
→ health/observability
→ metadata/fallback/A-V/audio-only/live
→ security Core
→ compatibility gate TV
→ limpeza de legado somente depois
```

Esta matriz deve ser relida antes de qualquer mudança que adicione nova ferramenta, daemon, árvore de filesystem, listener ou serviço compartilhado.