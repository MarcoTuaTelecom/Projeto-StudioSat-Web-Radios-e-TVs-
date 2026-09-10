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

Provas finais:

```text
archive SHA-256 no host e na cópia recebida:
5d6e0cb9630329cc06444c4592e989cb7adfdf818a71182123724f74f316433a

server sidecar: OK
health tool raw SHA-256:
d209a4d0c0d06ad3cdd1dd70bf2496574f85ebdfb6ffc739e3dad4c86f0d05ee

snapshot Git HEAD:
58b429a359c8f9b8e342319cd2380de74b0bc733

snapshot working tree: clean
```

`registry/critical-artifacts-baseline.yaml` é agora o baseline estático `locked`.

## Trilha crítica

| ID | Mudança | Dono | Estado | Gate |
|---|---|---|---|---|
| CHG-000 | Freeze operacional + protocolo | Core | **IN EFFECT** | permanece entre changes |
| CHG-001 | Core preflight inicial | Core | **DONE / PASS** | histórico |
| CHG-002 | Channels Registry inicial | Core | **DONE / REVALIDATION PENDING** | atualizar após CHG-R01 POST |
| CHG-003 | Core Contract v0.1 | Core + TV + Rádio | **DONE / ACCEPTED** | três domínios |
| CHG-004X | FULL RAY-X v3.1 exaustivo | Rádio + Core | **DONE / PASS / ANALYZED** | fotografia profunda AS-IS |
| CHG-004B | Baseline Oficial Operacional v1 | Core + Rádio | **DONE / PASS / LOCKED** | sidecar + tool hash + units/drop-ins capturados |
| CHG-R01 | Rádio Principal — generator/playlist escaping | Rádio | **ACTIVE — VERIFY IMEDIATO** | restart foi emitido antes da promoção planejada; não executar segunda mutação até diagnosticar estado atual |
| CHG-R02 | Radio Rock — recovery legado | Rádio + Core | **BLOCKED por CHG-R01** | generator PASS, start controlado, MediaMTX/RTSP/output PASS |
| CHG-R03 | Rádio HLS — Country AAC pilot | Rádio + Core | **BLOCKED por R01/R02** | HLS real `#EXTM3U`, freshness, áudio, recursos aceitáveis |
| CHG-R04 | Separação generator Rádio/TV | Rádio + TV + Core | **BLOCKED / DESIGN** | nenhum acoplamento de restart entre domínios |
| CHG-R05+ | profile/canonical/QC/metadata/fallback/A-V/audio-only/live | Rádio | **BLOCKED / SEQUENCIAL** | gates próprios |
| CHG-SEC-* | Samba/permissões/firewall/MediaMTX ACL/TLS | Core | **BLOCKED / INCIDENTES REGISTRADOS** | changes próprias sem misturar escopo |
| CHG-TV-* | TVKIDS/TVTEENS/TVVIVA/TVMAISJOVEM | Engenharia TV | **TV-OWNED / INTERLOCKS ATIVOS** | seguir handoff; Rádio não altera |

## Desvio operacional registrado em CHG-R01

Depois da prova final do baseline, foi executado manualmente:

```text
systemctl restart tps-radioprincipal-playout.service
```

O systemd respondeu:

```text
Warning: The unit file, source configuration file or drop-ins of tps-radioprincipal-playout.service changed on disk. Run 'systemctl daemon-reload' to reload units.
```

O restart ocorreu **antes** de instalar/validar o generator candidate v2. Portanto:

- **NÃO executar `daemon-reload`** neste momento;
- **NÃO reiniciar a Principal novamente**;
- **NÃO promover candidate ainda**;
- primeiro capturar estado pós-restart, PID/start, `NeedDaemonReload`, ExecStart/ExecStartPre carregados, hashes atuais, journal, MediaMTX, RTSP, playlist e PIDs das demais stations/Core.

Esse restart será incorporado ao `RESTART_REGISTER.md` depois que o timestamp/PID/resultados forem obtidos do host.

## Concorrência GitHub já observada

Após o checkpoint Rádio, a Engenharia TV publicou o commit `d4152ca6f652c5eac3c8ccf49039511dea778d6c` com script TVKIDS P0 de lock/certificação. A contribuição foi revisada: é TV-owned e não altera generator/units/MediaMTX/NGINX da Rádio. Deve ser preservada no `main`.

O servidor local estava em `58b429...` no momento do restart, portanto está atrás do `main`. Não fazer reset; sincronizar por `git pull --ff-only` somente depois da fotografia imediata pós-restart.

## Próxima ação autorizada no host

**Somente diagnóstico read-only da Rádio Principal e prova de não impacto.** Nenhum `daemon-reload`, nenhum segundo restart e nenhuma edição até analisar a saída.

Depois do diagnóstico:

```text
SYNC MAIN
→ validar candidates CHG-R01
→ gerar playlist candidate em /tmp
→ provar 18/18
→ backup
→ promoção atômica do generator
→ promoção da playlist
→ restart controlado final
→ health POST
→ rotação 18/18
```
