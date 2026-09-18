# RESET-03 — Restore real da Rádio Principal usando backups do root

A listagem real de /root revelou restore points que o RESET-02 não pesquisou:
- STUDIOSAT-FORENSIC-NS1-20260917T023826Z;
- STUDIOSAT-NS1-CLEANUP-BACKUP-20260916-085221;
- studiosat-radioprincipal-mirror-v3-backup-20260916T000819Z;
- studiosat-radioprincipal-v2-backup-20260916-075244.

RESET-03 procura dentro desses backups uma configuração de selector que tenha simultaneamente RadioBOSS Harbor, radioprincipal-ns1 RTMP e fallback rb antes de ns1. Antes de qualquer troca, exige radioprincipal-ns1 pronto e valida o candidate com liquidsoap --check. Depois reinicia apenas o selector e faz rollback se o público não voltar.

Objetivo emergencial: RadioBOSS em primeiro lugar, NS1 shadow em segundo, security em último, evitando silêncio quando o Harbor oscilar.