# StudioSat Web — Restart Register

Status: **ATIVO / OBRIGATÓRIO**  
Data de início: 2026-09-10

## Regra

Nenhum restart de station, MediaMTX, NGINX ou host é considerado procedimento trivial. Todo restart deve registrar:

```text
change_id
componente
owner
data/hora UTC
motivo
PID/start timestamp antes
health antes
comando executado
exit/status
PID/start timestamp depois
health depois
journal relevante
impacto em outras stations
resultado PASS/FAIL/ROLLED_BACK
rollback executado, se houver
commit do Stage Report
```

Restart sem sequência operacional prevista deve ser registrado como desvio dentro da Change ativa correspondente.

## Baseline locked antes da primeira Change mutável

CHG-004B: `DONE / PASS / LOCKED`, snapshot `2026-09-10T16:57:41Z`.

| Componente | Estado baseline | PID baseline | Start baseline |
|---|---|---:|---|
| radioprincipal | active/degraded | 1135303 | 2026-09-09 16:25:08 UTC |
| radiopop | active/degraded | 1135350 | 2026-09-09 16:25:10 UTC |
| radiorock | failed | 0 | — |
| radioclassicas | active/degraded | 1135491 | 2026-09-09 16:25:20 UTC |
| radiocountry | active/degraded | 1135456 | 2026-09-09 16:25:19 UTC |
| tvkids | active/degraded | 1031405 | 2026-09-09 12:59:08 UTC |
| tvteens | active | 841849 | 2026-09-09 00:48:57 UTC |
| tvviva | active | 841863 | 2026-09-09 00:48:57 UTC |
| tvmaisjovem | active | 841879 | 2026-09-09 00:48:57 UTC |
| tps-mediamtx.service | active | 217466 | registrado no baseline |
| nginx.service | active | 1060 | registrado no baseline |

## Entradas executadas

### 2026-09-10 17:31:47 UTC — CHG-R01 — restart antecipado da Rádio Principal

```text
change_id: CHG-R01
componente: tps-radioprincipal-playout.service
owner: Engenharia Rádio
motivo: tentativa manual de reinício antes da promoção do generator corrigido
comando: systemctl restart tps-radioprincipal-playout.service
pre_pid: 1135303
pre_start: 2026-09-09 16:25:08 UTC
post_pid: 1363987
post_start: 2026-09-10 17:31:47 UTC
post_state: active/running
ExecStartPre: /usr/local/sbin/tps-generate-playlist-radioprincipal-fixed
ExecStart: /usr/local/sbin/tps-playout-radio radioprincipal
NeedDaemonReload: yes
MediaMTX: ready=true
RTSP: PASS, mp3, 44100 Hz, stereo no instante medido
old_generator_sha256: d7140c872191f6b9efabeb8ef6bd813eba898f9978822e7f5ab15c7e819a5f18
playlist_sha256: 9bded92a31b437063adacb968c1b0985a4c8a82dd4e2783a1ef3335896e49cfe
playlist_items: 18
resultado: SERVICE_RESTARTED_BUT_DEFECT_NOT_FIXED
```

A playlist permaneceu byte-idêntica à baseline e ainda contém a referência não escapada para `Ain't No Mountain High Enough...`. O restart não corrigiu a causa do loop prematuro.

Prova de não impacto: Pop, Rock, Clássicas, Country, TVKIDS, TVTEENS, TVVIVA, TVMAISJOVEM, MediaMTX e NGINX mantiveram seus PIDs do baseline.

O warning `NeedDaemonReload=yes` foi preservado como observação. Nenhum `daemon-reload` foi autorizado/executado nesta etapa. CHG-R01 seguirá usando a unit já carregada, que aponta para os paths esperados, e não modifica unit/drop-ins.

### Próxima entrada prevista

CHG-R01 aplicará o generator corrigido após validação 18/18 e fará um único restart final controlado da Principal. Essa nova entrada só será marcada PASS depois do health pós-restart e da prova de rotação real 18/18.
