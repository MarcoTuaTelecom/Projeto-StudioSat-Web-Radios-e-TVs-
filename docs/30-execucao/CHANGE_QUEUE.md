# StudioSat Web — Change Queue

Regra: **uma alteração ativa por vez no host de produção**. Engenharia de TV e Rádio podem preparar documentação/candidates em paralelo, mas apenas uma change pode modificar o host por vez.

Protocolo obrigatório: `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`.

Diretriz vigente: **IN-PLACE FIRST / NO CONTAINERS / NO VMs / NO DUPLICATE PLATFORM**.

Documentos normativos atuais:

- `docs/90-evidencias/BASELINE_OFICIAL_AS_IS_2026-09-10_v1.0.md`
- `docs/00-core/COMPONENT_DISPOSITION_v1.0.md`
- `docs/00-core/DEPENDENCY_MAP_AS_IS_v1.0.md`
- `docs/30-execucao/INCIDENT_REGISTER.md`
- `docs/30-execucao/RESTART_REGISTER.md`
- `registry/critical-artifacts-baseline.yaml`
- `docs/00-core/SHARED_FOUNDATION_HANDOFF_TO_TV_v0.2_IN_PLACE.md`

## Freeze vigente

Até CHG-004B PASS/DONE:

- nenhum restart de station/Core;
- nenhuma instalação/upgrade;
- nenhuma edição de generator/playlist/unit/MediaMTX/NGINX/Samba/firewall;
- nenhuma movimentação/duplicação da biblioteca;
- nenhuma criação de `/srv/studiosat/...`;
- nenhum componente compartilhado alterado unilateralmente por Rádio ou TV.

## Trilha crítica

| ID | Mudança | Dono | Estado | Gate |
|---|---|---|---|---|
| CHG-000 | Freeze operacional + protocolo | Core | **IN EFFECT** | permanece entre changes |
| CHG-001 | Core preflight inicial | Core | **DONE / PASS** | histórico |
| CHG-002 | Channels Registry inicial | Core | **DONE / REVALIDATION PENDING** | atualizar após baseline locked |
| CHG-003 | Core Contract v0.1 | Core + TV + Rádio | **DONE / ACCEPTED** | três domínios |
| CHG-004X | FULL RAY-X v3.1 exaustivo | Rádio + Core | **DONE / PASS / ANALYZED** | archive íntegro; 1035/1035 manifest; relatório AS-IS publicado |
| CHG-004B | **Baseline Oficial Operacional v1** | Core + Rádio | **READY — ÚNICA PRÓXIMA AÇÃO NO HOST** | health atual + raw unit/drop-in hashes + lock do baseline |
| CHG-R01 | Rádio Principal — generator/playlist escaping | Rádio | **BLOCKED por CHG-004B** | 18/18 itens válidos, zero `Impossible to open`, rotação completa |
| CHG-R02 | Radio Rock — recovery legado | Rádio + Core | **BLOCKED por CHG-R01** | generator PASS, start controlado, MediaMTX/RTSP/output PASS |
| CHG-R03 | Rádio HLS — Country AAC pilot | Rádio + Core | **BLOCKED por R01/R02** | HLS real `#EXTM3U`, freshness, áudio, recursos aceitáveis |
| CHG-R04 | Separação generator Rádio/TV | Rádio + TV + Core | **BLOCKED / DESIGN APÓS BASELINE** | nenhum acoplamento de restart entre domínios |
| CHG-R05+ | profile/canonical/QC/metadata/fallback/A-V/audio-only/live | Rádio | **BLOCKED / SEQUENCIAL** | gates próprios |
| CHG-SEC-* | Samba/permissões/firewall/MediaMTX ACL/TLS | Core | **BLOCKED / INCIDENTES REGISTRADOS** | changes próprias sem misturar escopo |
| CHG-TV-* | TVKIDS/TVTEENS/TVVIVA/TVMAISJOVEM | Engenharia TV | **TV-OWNED / INTERLOCKS ATIVOS** | seguir handoff; Rádio não altera |

## Estado AS-IS de referência

```text
radioprincipal  active / MediaMTX ready / DEGRADED P0
radiopop        active / MediaMTX ready / legacy healthy; Rádio HLS gap
radiorock       failed / MediaMTX not ready / P0
radioclassicas  active / MediaMTX ready / legacy healthy; Rádio HLS gap
radiocountry    active / MediaMTX ready / reference; Rádio HLS gap

tvkids          active / MediaMTX ready / DEGRADED / TV-OWNED
tvteens         active / MediaMTX ready / TV-OWNED restart interlock
tvviva          active / MediaMTX ready / TV-OWNED restart interlock
tvmaisjovem     active / MediaMTX ready / TV-OWNED restart interlock
```

## Regra PRE/POST obrigatória

Toda change mutável será cercada por:

```text
SYNC MAIN
→ HEALTH PRE
→ HASH PRE
→ UMA MUDANÇA
→ VERIFY ESPECÍFICO
→ HEALTH POST
→ HASH POST
→ DIFF
→ STAGE REPORT
→ SCRIPT/CONFIG FINAL NO GITHUB
→ RELER MAIN
→ SOMENTE ENTÃO PRÓXIMA CHANGE
```

Hashes estáticos fora do escopo não podem mudar. Qualquer hash alterado precisa de explicação, owner e Change ID.

## Restart policy operacional

Nenhum restart é “só um restart”. Registrar em `RESTART_REGISTER.md` PID/timestamp/health antes e depois, comando, journal, impacto e resultado.

## Próxima execução autorizada

Somente:

```bash
sudo nice -n 10 bash candidates/CHG-004B/studiosat-health-baseline-v1.sh
```

após `git pull`, working tree limpa e `bash -n` PASS.

Nenhuma mutação deve ser executada depois do snapshot até que CHG-004B seja analisada e fechada no GitHub.