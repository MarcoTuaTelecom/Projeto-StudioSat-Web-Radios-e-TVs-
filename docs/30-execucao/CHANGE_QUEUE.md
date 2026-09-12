# StudioSat Web — Change Queue

Regra: **uma alteração ativa por vez no host de produção**. Engenharia de TV e Rádio podem preparar documentação/candidates em paralelo, mas apenas uma change pode modificar o host por vez.

Protocolo obrigatório: `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`.

Diretriz vigente: **IN-PLACE FIRST / NO CONTAINERS / NO VMs / NO DUPLICATE PLATFORM**.

## Baseline oficial

CHG-004B está **DONE / PASS / LOCKED** com snapshot `2026-09-10T16:57:41Z`.

## FREEZE OPERACIONAL — 2026-09-12

Por determinação mais recente do owner, **nenhuma mutação de produção está autorizada até a conclusão e análise do novo raio-X completo e profundo do NS1**.

A razão é operacional: as cinco emissoras de Rádio Studio Sat, seus sites/player/portal e demais componentes do host já sofreram mudanças posteriores aos baselines antigos. Antes de qualquer execução TVKIDS, Rádio, NGINX, MediaMTX, systemd, playlist, generator, canonical ou webroot, o estado real atual precisa ser conhecido e reconciliado.

Estado obrigatório durante o freeze:

- CHG-TVKIDS-001: **FROZEN / PRESERVADA**;
- CHG-R01/R02/R03/RWEB01: **FROZEN / PRESERVADAS**;
- CHG-R04 e CHG-TV-002+: **PENDENTES**;
- única ação operacional autorizada: **OBS-NS1-RAYX-20260912**, classe `read-only`.

## OBS-NS1-RAYX-20260912 — ação autorizada

Executor:

```text
scripts/ns1-full-deep-rayx-v2.sh --deep
```

Esse raio-X usa o `studiosat-core-preflight.sh` já existente e acrescenta coleta profunda do estado atual, sem alterar a produção. O pacote final deve cobrir:

1. host/CPU/RAM/disco/load/processos;
2. nove units e seus PIDs/comandos/journals/restarts/recursos;
3. playlists efetivamente abertas por `/proc/<pid>/fd`, playlists no disco, SHA e FDs `(deleted)`;
4. MediaMTX API/paths, RTSP e HLS local das nove stations;
5. duas amostras HLS para provar freshness, não apenas HTTP 200;
6. NGINX completo, vhosts, webroots, identidades/hashes e `nginx -t`;
7. DNS/TLS/root/HLS dos hostnames públicos Rádio e TV;
8. inventário de `ready/canonical/incoming/quarantine/playlists/state/graphics/logs/lab/archive`;
9. SHA256 + `ffprobe` de todos os assets em `ready/` e `canonical/` no modo deep;
10. decode integral das playlists ativas, sequencial, `nice 19`, `ionice idle`, uma station por vez;
11. timers/cron/firewall/sockets e indícios de automação oculta;
12. fault signatures das últimas 24h;
13. Git local vs `origin/main`;
14. comparação dos PIDs antes/depois para registrar qualquer alteração espontânea durante a coleta;
15. pacote shareable redigido e snapshots privados locais separados.

O modo deep é automaticamente suprimido se o coletor detectar uma mutação concorrente ou job systemd em andamento; a parte estática ainda é coletada e o fato fica registrado.

Resultado esperado da coleta:

```text
NS1_RAYX_RESULT=COLLECTED
production_mutations_by_script=0
```

A coleta **não autoriza** automaticamente nenhuma change posterior. O pacote deve ser analisado primeiro, confrontando o estado atual das cinco rádios, sites/portal, quatro TVs, MediaMTX, NGINX e filesystem.

## Trilha crítica preservada

| ID | Mudança | Dono | Estado durante o freeze |
|---|---|---|---|
| OBS-NS1-RAYX-20260912 | Raio-X completo e profundo NS1 | Core | **ACTIVE / READ-ONLY** |
| CHG-TVKIDS-001 | Reconstrução integral TVKIDS | TV | **FROZEN / PRESERVADA** |
| CHG-R01 | Principal — escaping/playlist atômica | Rádio | **FROZEN / preservar estado atual** |
| CHG-R02 | Rock — recovery legado | Rádio + Core | **FROZEN / preservar estado atual** |
| CHG-R03 | Cinco rádios — AAC/HLS | Rádio + Core | **FROZEN / estado real será revalidado** |
| CHG-RWEB01 | Player/portal/NGINX Rádio | Rádio + Core | **FROZEN / estado real será revalidado** |
| CHG-R04 | Separação generator Rádio/TV | Rádio + TV + Core | **PENDENTE** |
| CHG-TV-002+ | TVTEENS/TVVIVA/TVMAISJOVEM | TV | **PENDENTE** |

## Regra para sair do freeze

Somente após análise do pacote OBS-NS1-RAYX-20260912 será produzido um novo baseline factual. A próxima change deverá partir desse baseline, declarar exatamente o que já funciona, o que está degradado, dependências compartilhadas, risco cruzado, candidate, precheck, rollback e health público. Nenhum baseline de 09/09 ou 10/09 será usado como verdade atual sem reconfirmação.