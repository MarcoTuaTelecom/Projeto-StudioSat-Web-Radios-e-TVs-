# RESET-02 — Restore 16/17 das rádios temáticas

Escopo: radiopop, radiorock, radioclassicas e radiocountry.

A Rádio Principal não volta para playlist estática; permanece sob RadioBOSS.

O script procura o restore point de playlist mais recente entre 16/09/2026 00:00 UTC e 18/09/2026 00:00 UTC, valida referências de mídia, ignora cópia idêntica à atual, aplica uma emissora por vez e exige service active + MediaMTX ready + HLS. Se uma emissora falhar, somente ela sofre rollback. Se não existir nenhum restore point válido, nenhuma alteração é aplicada.