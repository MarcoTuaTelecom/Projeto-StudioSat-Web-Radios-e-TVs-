# StudioSat Web — Change Queue

Regra: **uma alteração ativa por vez no host de produção**. Engenharia de TV e Rádio podem preparar documentação/candidates em paralelo, mas apenas uma change pode modificar o host por vez.

Protocolo obrigatório: `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`.

Diretriz vigente: **IN-PLACE FIRST / NO CONTAINERS / NO VMs / NO DUPLICATE PLATFORM**.

## Baseline factual vigente — 2026-09-12

O pacote `OBS-NS1-RAYX-20260912` foi coletado e analisado. O baseline factual completo está em:

```text
docs/90-evidencias/BASELINE_NS1_DEEP_2026-09-12.md
```

O baseline antigo de 09/09–10/09 não deve ser usado isoladamente como verdade do host atual.

## FREEZE OPERACIONAL CONTINUA

**Nenhuma mutação de produção está autorizada.** As cinco rádios, seus sites/player/portal e a TVKIDS local têm estado atual que precisa ser preservado enquanto fechamos as últimas lacunas forenses.

Estado durante o freeze:

- cinco Rádios Studio Sat: **ON-AIR / PRESERVAR COMO BASELINE IMUTÁVEL**;
- sites/player/portal Rádio: **EM PRODUÇÃO / PRESERVAR**;
- TVKIDS local: **ON-AIR, porém DTS de áudio recorrente**;
- TVKIDS público: **BROKEN — vhosts TV ausentes; roots caem no player Rádio; HLS público 404**;
- TVTEENS/TVVIVA/TVMAISJOVEM: **FAILED — `NO_READY_MEDIA` após restart coordenado de 06:58**;
- MediaMTX: **COMPARTILHADO / cinco Rádios + TVKIDS ready**;
- antigo `CHG-TVKIDS-001` executor: **STALE / REDESIGN REQUIRED** contra o NGINX atual.

## Fatos críticos confirmados pelo raio-X

### Rádio

As cinco rádios estão active/running, AAC 48 kHz stereo, MediaMTX ready, RTSP PASS e HLS local PASS/CHANGING segundo o Core Preflight v1.1. Playlists on-air e em disco têm SHA idêntico e não há FD `(deleted)`.

O runtime real das cinco rádios é definido por drop-ins systemd `30-force-aac.conf`, que sobrescrevem o wrapper `/usr/local/sbin/tps-playout-radio`. Isto é invariável para futuras changes TV.

### TVKIDS

TVKIDS local está active, MediaMTX ready, H.264/AAC e HLS local fresh. Sua playlist é 15/15 canonical e on-air = disco.

O `Non-monotonic DTS` foi localizado no áudio (`stream 0:1`) e se repete em 10 boundaries específicos da playlist, com pequenos recuos de ~3–21 ms por volta. A próxima correção temporal deverá ser provada offline antes de qualquer cutover.

### TV pública

O NGINX atual não possui `server_name` de TV. Todos os roots TV observados estão caindo no vhost Radio Studio Sat e os HLS públicos TV retornam 404. A futura restauração TV deverá criar vhosts TV dedicados e disjuntos, preservando byte-a-byte as configurações Rádio atuais.

### Outras TVs

TVTEENS, TVVIVA e TVMAISJOVEM falham porque o generator usa `ready/`, cada station possui somente mídia `teste-*` em ready, e o generator exclui `test/teste` antes do ExecStart. Foram 5 tentativas de restart até start-limit.

### Evento 06:58

Há evidência de stop/start coordenado de NGINX + todas as nove stations em ~06:58 UTC. O host não rebootou. O pacote mostra `apt-daily-upgrade.timer` às 06:56:35, mas não contém apt/unattended/dpkg logs suficientes para provar ou excluir causalidade. O iniciador do restart global permanece **UNPROVEN**.

## Única ação operacional autorizada agora

**OBS-NS1-FORENSIC-20260912 — read-only**

Executor:

```text
scripts/ns1-forensic-supplement-20260912.sh
```

Objetivos:

1. fechar a origem do restart coordenado de 06:58 com journal + apt/unattended-upgrades/dpkg/auth/sudo;
2. registrar mtimes de systemd/NGINX/scripts próximos ao incidente;
3. provar o HLS real do portal `www.radio...` na rota correta `/hls/<station>/index.m3u8`;
4. repetir HLS local seguindo redirect para corrigir o falso negativo 302 do coletor custom;
5. congelar hashes dos três webroots Rádio como invariantes para a futura change TV.

Resultado esperado:

```text
NS1_FORENSIC_RESULT=COLLECTED
production_mutations_by_script=0
```

A suplementação continua sendo coleta, não autorização para produção-change.

## Trilha crítica

| ID | Mudança | Estado |
|---|---|---|
| OBS-NS1-RAYX-20260912 | Raio-X profundo principal | **DONE / ANALISADO** |
| OBS-NS1-FORENSIC-20260912 | Suplemento incidente + portal HLS | **ACTIVE / READ-ONLY** |
| CHG-TVKIDS-001 antigo | Executor de reconstrução anterior | **FROZEN / STALE / REDESIGN REQUIRED** |
| CHG-TVKIDS-002 | Nova recuperação baseada no baseline 12/09 | **DESIGN ONLY / ainda não autorizada** |
| CHG-R01/R02/R03/RWEB01 | Rádio | **FROZEN / produção atual preservada** |
| CHG-TV-003+ | TVTEENS/TVVIVA/TVMAISJOVEM | **PENDENTE** |

## Gate para uma futura mutação TVKIDS

A futura change somente poderá ser promovida depois de:

- suplementação forense analisada;
- candidate temporal TVKIDS provar zero DTS offline;
- NGINX candidate TV usar arquivo/blocos dedicados e não alterar `studiosat-radio.conf` nem `zz-studiosat-radio-portal.conf`;
- hashes/PIDs/health das cinco rádios registrados como invariantes PRE/POST;
- `nginx -t` em candidate antes de qualquer reload;
- nenhum restart de MediaMTX;
- rollback TVKIDS explícito e independente das rádios;
- health final validar produto público correto, não apenas HTTP 200.