# StudioSat Web — Restart Register

Status: **ATIVO / OBRIGATÓRIO**  
Data de início: 2026-09-10

## Regra

Nenhum restart de station, MediaMTX, NGINX ou host é considerado procedimento trivial. Todo restart autorizado deve registrar:

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

Restart sem Change ID é **mudança não planejada** e deve ser registrado como incidente operacional.

## Baseline antes da primeira Change mutável

FULL RAY-X v3.1 observou os processos atuais e seus timestamps, mas não executou restart. A CHG-004B criará o health snapshot imediatamente anterior à primeira mutação.

| Componente | Estado observado no FULL RAY-X | PID observado | Start observado | Restart autorizado nesta fase? |
|---|---|---:|---|---|
| radioprincipal | active/degraded | 1135303 | 2026-09-09 16:25:08 UTC | NÃO até CHG-R01 |
| radiopop | active | 1135350 | 2026-09-09 16:25:10 UTC | NÃO |
| radiorock | failed | 0 | — | NÃO até CHG-R02/start controlado |
| radioclassicas | active | 1135491 | 2026-09-09 16:25:20 UTC | NÃO |
| radiocountry | active | 1135456 | 2026-09-09 16:25:19 UTC | NÃO enquanto baseline não estiver locked |
| tvkids | active/degraded | 1031405 | 2026-09-09 12:59:08 UTC | NÃO — TV-OWNED/interlock |
| tvteens | active | 841849 | 2026-09-09 00:48:57 UTC | NÃO — TV-OWNED/interlock |
| tvviva | active | 841863 | 2026-09-09 00:48:57 UTC | NÃO — TV-OWNED/interlock |
| tvmaisjovem | active | 841879 | 2026-09-09 00:48:57 UTC | NÃO — TV-OWNED/interlock |
| tps-mediamtx.service | active | observado no FULL RAY-X | — | NÃO para change de station |
| nginx.service | active | observado no FULL RAY-X | — | somente reload/restart em Change Core específica |

## Entradas executadas

Nenhum restart executado pela trilha nova até o início deste registro.

Toda nova entrada deve ser adicionada em ordem cronológica e vinculada ao Stage Report correspondente.