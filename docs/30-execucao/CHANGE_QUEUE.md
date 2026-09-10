# StudioSat Web — Change Queue

Regra: **uma alteração ativa por vez no host de produção**. Engenharia de TV e Rádio podem preparar documentação/candidates em paralelo, mas apenas uma change pode modificar o host por vez.

Protocolo obrigatório: `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`.

Diretriz vigente: **IN-PLACE FIRST / NO CONTAINERS / NO VMs / NO DUPLICATE PLATFORM**.

Documentos normativos atuais:

- `docs/90-evidencias/BASELINE_OFICIAL_AS_IS_2026-09-10_v1.0.md`
- `docs/90-evidencias/HEALTH_BASELINE_2026-09-10T165741Z.md`
- `docs/00-core/COMPONENT_DISPOSITION_v1.0.md`
- `docs/00-core/DEPENDENCY_MAP_AS_IS_v1.0.md`
- `docs/30-execucao/INCIDENT_REGISTER.md`
- `docs/30-execucao/RESTART_REGISTER.md`
- `registry/critical-artifacts-baseline.yaml`
- `docs/00-core/SHARED_FOUNDATION_HANDOFF_TO_TV_v0.2_IN_PLACE.md`

## Baseline oficial

CHG-004B está **DONE / PASS / LOCKED** com snapshot `2026-09-10T16:57:41Z`.

```text
archive SHA-256 host/cópia:
5d6e0cb9630329cc06444c4592e989cb7adfdf818a71182123724f74f316433a
server sidecar: OK
health tool raw SHA-256:
d209a4d0c0d06ad3cdd1dd70bf2496574f85ebdfb6ffc739e3dad4c86f0d05ee
snapshot Git HEAD: 58b429a359c8f9b8e342319cd2380de74b0bc733
snapshot working tree: clean
```

`registry/critical-artifacts-baseline.yaml` é o baseline estático `locked`.

## Trilha crítica

| ID | Mudança | Dono | Estado | Gate |
|---|---|---|---|---|
| CHG-000 | Freeze operacional + protocolo | Core | **IN EFFECT** | permanece entre changes |
| CHG-001 | Core preflight inicial | Core | **DONE / PASS** | histórico |
| CHG-002 | Channels Registry inicial | Core | **DONE / REVALIDATION PENDING** | atualizar após CHG-R01 POST |
| CHG-003 | Core Contract v0.1 | Core + TV + Rádio | **DONE / ACCEPTED** | três domínios |
| CHG-004X | FULL RAY-X v3.1 exaustivo | Rádio + Core | **DONE / PASS / ANALYZED** | fotografia profunda AS-IS |
| CHG-004B | Baseline Oficial Operacional v1 | Core + Rádio | **DONE / PASS / LOCKED** | sidecar + tool hash + units/drop-ins capturados |
| CHG-R01 | Rádio Principal — generator/playlist escaping | Rádio | **ACTIVE — APPLY v1.1 READY** | 18/18 candidate + backup + promoção atômica + restart só Principal + health + rotação 18/18 |
| CHG-R02 | Radio Rock — recovery legado | Rádio + Core | **BLOCKED por CHG-R01** | generator PASS, start controlado, MediaMTX/RTSP/output PASS |
| CHG-R03 | Rádio HLS — Country AAC pilot | Rádio + Core | **BLOCKED por R01/R02** | HLS real `#EXTM3U`, freshness, áudio, recursos aceitáveis |
| CHG-R04 | Separação generator Rádio/TV | Rádio + TV + Core | **BLOCKED / DESIGN** | nenhum acoplamento de restart entre domínios |
| CHG-R05+ | profile/canonical/QC/metadata/fallback/A-V/audio-only/live | Rádio | **BLOCKED / SEQUENCIAL** | gates próprios |
| CHG-SEC-* | Samba/permissões/firewall/MediaMTX ACL/TLS | Core | **BLOCKED / INCIDENTES REGISTRADOS** | changes próprias sem misturar escopo |
| CHG-TV-* | TVKIDS/TVTEENS/TVVIVA/TVMAISJOVEM | Engenharia TV | **TV-OWNED / INTERLOCKS ATIVOS** | seguir handoff; Rádio não altera |

## CHG-R01 — estado comprovado após restart antecipado

Restart manual em `2026-09-10 17:31:47 UTC`:

```text
pre PID Principal: 1135303
post PID Principal: 1363987
post state: active/running
MediaMTX: ready=true
RTSP: PASS
NeedDaemonReload: yes
```

O generator e a playlist permaneceram com os hashes locked antigos. A playlist continua contendo a linha inválida de `Ain't No Mountain High Enough...`; portanto o restart não resolveu a causa.

As outras oito stations, MediaMTX e NGINX mantiveram os PIDs do baseline. O isolamento da station foi comprovado.

**Não executar `systemctl daemon-reload`.** CHG-R01 não modifica unit/drop-ins; a configuração já carregada aponta para o generator e playout paths esperados.

## Concorrência GitHub

A contribuição TV mais recente observada é `d4152ca6f652c5eac3c8ccf49039511dea778d6c`, TVKIDS-owned. Foi revisada e deve ser preservada. Ela não altera o escopo Rádio da CHG-R01.

## Única próxima ação mutável autorizada

Após sincronizar `main`, executar exclusivamente:

```text
candidates/CHG-R01/apply-radioprincipal-fix-v1.1.sh
```

O executor:

```text
confere hashes locked
→ gera candidate em /tmp
→ valida 18/18 + full traversal
→ cria backup privado
→ promove generator v2 atomicamente
→ gera playlist production atomicamente
→ revalida 18/18
→ restart SOMENTE Principal
→ MediaMTX ready + RTSP
→ 0 Impossible to open / 0 NO_READY_MEDIA
→ prova nenhuma outra PID/playlist mudou
→ gera evidence shareable
```

Se qualquer gate falhar antes da mutação, aborta sem tocar produção. Se falhar depois da mutação, executa rollback dos arquivos; se a falha ocorrer após restart, restaura e reinicia somente a Principal.

`apply-radioprincipal-fix-v1.sh` está superseded; **usar somente v1.1**.

Depois do `CHG_R01_IMMEDIATE_RESULT=PASS`, ainda falta o observer read-only:

```text
observe-radioprincipal-rotation-v1.sh
```

Gate final:

```text
ROTATION_RESULT=PASS
SEEN=18/18
```

Somente então CHG-R01 fecha e CHG-R02 pode ser liberada.
