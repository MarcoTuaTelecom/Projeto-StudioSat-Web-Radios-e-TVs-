# StudioSat Web — Incident Register

Status: **ATIVO**  
Fonte inicial: FULL RAY-X v3.1 de 2026-09-10 15:35 UTC  
Regra: nenhum incidente é considerado resolvido apenas porque `systemd` está `active`; precisa de evidência funcional e Stage Report.

| ID | Severidade | Domínio | Componente | Sintoma/causa observada | Owner | Estado | Próxima Change/Gate |
|---|---|---|---|---|---|---|---|
| INC-RADIO-001 | P0 | Rádio | radioprincipal generator/playlist | generator especial não escapa apóstrofo; FFmpeg registra `Impossible to open` e a grade reinicia antes de percorrer todos os itens | Engenharia Rádio | OPEN | CHG-R01 — candidate playlist + prova de rotação completa |
| INC-RADIO-002 | P0 | Rádio | radiorock | unit failed; falha histórica `NO_READY_MEDIA`; agora há 10 arquivos ready, portanto causa deve ser revalidada e recovery executado sem restart loop | Engenharia Rádio + Core | OPEN | CHG-R02 — precheck + generator candidate + start controlado |
| INC-RADIO-003 | P0 funcional | Rádio/Core | entrega HLS Rádio | paths Rádio estão ready via MediaMTX/RTSP, porém HLS local retorna erro e não há HLS muxer Rádio; input atual é MPEG-1/2 Audio copiado | Engenharia Rádio + Core | OPEN | CHG-R03 — Country AAC bounded candidate, sem trocar engine por hipótese |
| INC-CORE-001 | P0 segurança | Core | Samba ingest | compartilhamento/permissões observados são excessivamente permissivos; pacote bruto contém detalhes não publicados | Core | OPEN / CONTAINMENT PENDING | mapear clientes/origens + GCP/VPC antes de alterar |
| INC-CORE-002 | P0/P1 segurança | Core | filesystem/config permissions | objetos críticos world-writable/777 foram observados | Core | OPEN | corrigir em lotes com hash, backup, serviço-specific health |
| INC-CORE-003 | P1 | Core | MediaMTX auth/listeners | listeners amplos e auth permissiva; não endurecer sem mapear live/publishers TV+Rádio | Core | OPEN | ingress/ACL matrix + Core gate |
| INC-CORE-004 | P1 | Core | firewall | UFW inativo e policy local permissiva; exposição externa real depende do firewall GCP/VPC ainda não capturado | Core | OPEN | inventário GCP/VPC antes de candidate |
| INC-CORE-005 | P1 | Core | Certbot renewal | certificados existem, mas rotina efetiva de renovação automática não foi comprovada; timers observados não fornecem garantia operacional | Core | OPEN | TLS renewal change + dry-run |
| INC-WEB-001 | P1 | Core/Web | hostnames sem `www` | vários hostnames retornam 403 enquanto portais `www.*` retornam 200; comportamento precisa ser declarado intencional ou corrigido | Core + owner do domínio | OPEN | hostname matrix + NGINX candidate |
| INC-WEB-002 | P1 | Core/Web | falso health `/hls/...` | alguns paths em portais podem retornar HTML 200 em vez de manifest; health não pode usar apenas HTTP status | Core | OPEN | health v1 valida `#EXTM3U` |
| INC-TV-001 | P0 interlock | TV | TVKIDS | processo on-air segura estado antigo/playlist removida; ready heterogêneo e há risco no próximo ExecStartPre; DTS recorrente observado | Engenharia TV | TV-OWNED / OPEN | não reiniciar pela frente Rádio; Engenharia TV deve executar sua change |
| INC-TV-002 | P0 interlock | TV | TVTEENS/TVVIVA/TVMAISJOVEM | processo atual consome estado/canonical antigo; único ready observado por station é marcado teste e pode ser excluído pelo generator atual em restart | Engenharia TV | TV-OWNED / OPEN | não reiniciar pela frente Rádio; handoff à TV |
| INC-TOOL-001 | P1 qualidade | Core | FULL RAY-X v3.1 | parser ffconcat produz falsos `MISSING` com escaping `\'`; versão genérica falha para algumas tools; active service count automático ficou 37 vs 38 reais | Core | OPEN | corrigir no v3.2 antes do próximo full audit |
| INC-OPS-001 | P1 | Core | unattended upgrades | servidor broadcast 24x7 possui rotinas de atualização automática; política precisa ser revisada para evitar mudança não coordenada de componente crítico | Core | OPEN / REVIEW | maintenance policy |

## Regras de owner

- **Engenharia Rádio** resolve timeline, generator Rádio, playout Rádio, A/V, audio-only, metadata, fallback e live Rádio.
- **Engenharia TV** resolve canonical/QC/timeline/engine/continuity das TVs; Rádio apenas registra interlocks e impactos compartilhados.
- **Core** resolve MediaMTX global, NGINX/TLS, ports, ingress/auth/ACL, firewall, Samba compartilhado, registry, health envelope, observabilidade e governança systemd comum.

## Critério de resolução

Um incidente só vira `RESOLVED` quando:

```text
causa identificada
+ candidate/backup/rollback
+ mudança executada na Change correta
+ verificação funcional
+ health pós-change
+ nenhuma regressão externa
+ script/config final versionado
+ Stage Report publicado
+ Change Queue atualizada
```

Se o problema reaparecer, o mesmo ID é reaberto; não se cria um novo ID apenas para esconder recorrência.