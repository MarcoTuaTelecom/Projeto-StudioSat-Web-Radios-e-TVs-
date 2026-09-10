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
| CHG-004B | **Baseline Oficial Operacional v1** | Core + Rádio | **VERIFYING — SNAPSHOT RECEBIDO/ANALISADO** | sidecar `.sha256` do host + SHA raw da health tool ainda precisam ser comprovados antes do `LOCKED` |
| CHG-R01 | Rádio Principal — generator/playlist escaping | Rádio | **BLOCKED por CHG-004B** | 18/18 itens válidos, zero `Impossible to open`, rotação completa |
| CHG-R02 | Radio Rock — recovery legado | Rádio + Core | **BLOCKED por CHG-R01** | generator PASS, start controlado, MediaMTX/RTSP/output PASS |
| CHG-R03 | Rádio HLS — Country AAC pilot | Rádio + Core | **BLOCKED por R01/R02** | HLS real `#EXTM3U`, freshness, áudio, recursos aceitáveis |
| CHG-R04 | Separação generator Rádio/TV | Rádio + TV + Core | **BLOCKED / DESIGN APÓS BASELINE** | nenhum acoplamento de restart entre domínios |
| CHG-R05+ | profile/canonical/QC/metadata/fallback/A-V/audio-only/live | Rádio | **BLOCKED / SEQUENCIAL** | gates próprios |
| CHG-SEC-* | Samba/permissões/firewall/MediaMTX ACL/TLS | Core | **BLOCKED / INCIDENTES REGISTRADOS** | changes próprias sem misturar escopo |
| CHG-TV-* | TVKIDS/TVTEENS/TVVIVA/TVMAISJOVEM | Engenharia TV | **TV-OWNED / INTERLOCKS ATIVOS** | seguir handoff; Rádio não altera |

## Snapshot CHG-004B recebido — 2026-09-10T16:57:41Z

```text
radioprincipal  degraded / active / MediaMTX ready / RTSP PASS / HLS 500 / 3x Impossible to open em 30m
radiopop        degraded / active / MediaMTX ready / RTSP PASS / HLS 500
radiorock       failed   / failed / MediaMTX not ready / RTSP FAIL / HLS 404 / ready=10
radioclassicas  degraded / active / MediaMTX ready / RTSP PASS / HLS 500
radiocountry    degraded / active / MediaMTX ready / RTSP PASS / HLS 500

tvkids          degraded / active / MediaMTX ready / RTSP PASS / HLS PASS+CHANGING / 7 DTS em 30m
tvteens         healthy  / active / MediaMTX ready / RTSP PASS / HLS PASS+CHANGING
tvviva          healthy  / active / MediaMTX ready / RTSP PASS / HLS PASS+CHANGING
tvmaisjovem     healthy  / active / MediaMTX ready / RTSP PASS / HLS PASS+CHANGING
```

Core no mesmo snapshot:

```text
tps-mediamtx.service active PID 217466
nginx.service        active PID 1060
nginx -t             PASS
root disk            17%
MemAvailable         7,164,780 kB
load1                0.31
MediaMTX API          PASS
www.radio portal      HTTP 200
```

PIDs/start timestamps das nove stations e PIDs de MediaMTX/NGINX são os mesmos do FULL RAY-X; os 9 hashes estáticos críticos também são iguais. Raw hashes das units/drop-ins já foram capturados em `registry/critical-artifacts-baseline.yaml`.

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

## Próxima ação autorizada no host

**Somente prova read-only de integridade/identidade. Nenhuma mutação.**

Executar, no host:

```bash
cd /root/Projeto-StudioSat-Web-Radios-e-TVs-

SHA_FILE=/tmp/studiosat-health-baseline-ns1-20260910T165741Z.tar.gz.sha256
ARCHIVE=/tmp/studiosat-health-baseline-ns1-20260910T165741Z.tar.gz

echo '===== SERVER SIDECAR ====='
cat "$SHA_FILE"

echo '===== VERIFY SERVER SIDECAR ====='
sha256sum -c "$SHA_FILE"

echo '===== HEALTH TOOL RAW SHA256 ====='
sha256sum candidates/CHG-004B/studiosat-health-baseline-v1.sh

echo '===== GIT ====='
git status --short
git rev-parse HEAD
```

Esperado para o archive, se a transferência recebida corresponde ao arquivo gerado no host:

```text
5d6e0cb9630329cc06444c4592e989cb7adfdf818a71182123724f74f316433a  /tmp/studiosat-health-baseline-ns1-20260910T165741Z.tar.gz
...: OK
```

O SHA da health tool deve ser devolvido como evidência; não presumir o valor.

Nenhuma mutação deve ser executada até a CHG-004B ser convertida para `DONE / PASS / LOCKED` no GitHub.
