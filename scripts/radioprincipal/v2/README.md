# Rádio Principal V2

Esta árvore é exclusiva para reconstrução paralela da Rádio Principal.

## Proibido

- usar `radioprincipal` como output de desenvolvimento;
- usar `radioprincipal-ns1` como output de desenvolvimento;
- reiniciar selector público;
- reiniciar MediaMTX/Nginx para validar candidate;
- substituir units públicos durante construção;
- apagar stores antigos antes de auditoria de referências.

## Paths permitidos

- `radioprincipal-v2-shadow`
- `radioprincipal-v2-test`

## Runtime V2

- código: `/opt/studiosat/radio-v2-next/radioprincipal/`
- estado: `/var/lib/studiosat/radio-v2-next/radioprincipal/`
- logs: systemd/journal de units com prefixo `studiosat-radioprincipal-v2-`

## Componentes a construir

1. authority-reader
2. asset-reconciler
3. media-transfer-client/agent protocol
4. canonical-state
5. execution-engine
6. saytime adapter
7. temperature adapter
8. commercial/scheduler adapter
9. shadow publisher
10. test selector
11. validator/soak-test
12. cutover/rollback separado

Todo componente deve passar pelo `NO-DOWNTIME-GUARD.sh`.
