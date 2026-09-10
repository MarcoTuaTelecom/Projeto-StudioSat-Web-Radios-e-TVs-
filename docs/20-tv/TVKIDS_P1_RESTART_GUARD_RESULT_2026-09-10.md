# TVKIDS — P1 Restart Guard — Resultado 2026-09-10

## Objetivo

Eliminar a divergência entre a playlist que mantinha a TVKIDS efetivamente no ar e a playlist que seria regenerada em um restart futuro.

## Estado comprovado antes da mudança

Serviço:

```text
tps-tvkids-playout.service
MainPID=1031405
```

Playlist realmente aberta pelo FFmpeg:

```text
/proc/1031405/fd/3
→ /srv/tpsmedia/repository/channels/tvkids/playlists/playlist.txt (deleted)
```

Assinatura da playlist ON-AIR:

```text
SHA256=2807c6c604f4601f92b990c047c857519fcb3760c58827ad308be297bcf951d0
itens=15
canonical=15
ready=0
```

Playlist existente em disco antes do P1:

```text
SHA256=338b3cbccd7c4b040b86f88b25b94e4028dbae563eed62966fe9a0666c8f9658
canonical=0
ready=13
```

A geração determinística a partir de `canonical/` produziu exatamente a mesma assinatura da playlist ON-AIR:

```text
SHA256=2807c6c604f4601f92b990c047c857519fcb3760c58827ad308be297bcf951d0
itens=15
```

## Mudança aplicada

O gerador compartilhado `/usr/local/sbin/tps-generate-playlist` passou a manter o comportamento legado `ready/` para os demais canais e a usar `canonical/` especificamente para `tvkids`:

```bash
MEDIA_ROOT="${BASE}/ready"

# TVKIDS_RESTART_GUARD: TVKIDS usa somente mídia canonical certificada.
if [[ "$CH" == "tvkids" ]]; then
  MEDIA_ROOT="${BASE}/canonical"
fi
```

Em seguida foi regenerada somente a playlist em disco da TVKIDS.

## Estado comprovado depois da mudança

```text
PLAYLIST_OK=tvkids|ITEMS=15|FILE=/srv/tpsmedia/repository/channels/tvkids/playlists/playlist.txt

new_disk_sha=2807c6c604f4601f92b990c047c857519fcb3760c58827ad308be297bcf951d0
files=15
canonical=15
ready=0
```

O PID permaneceu o mesmo durante toda a operação:

```text
PID antes = 1031405
PID depois = 1031405
```

Portanto não houve troca do processo on-air durante o P1.

## Resultado operacional

O estado foi alinhado:

```text
PLAYLIST ON-AIR
     =
PLAYLIST EM DISCO
     =
GERAÇÃO A PARTIR DE canonical/
```

Todas as três representações têm a mesma assinatura SHA-256:

```text
2807c6c604f4601f92b990c047c857519fcb3760c58827ad308be297bcf951d0
```

Isso elimina o risco específico observado no P0 de um restart regenerar uma playlist baseada em `ready/` heterogêneo.

## Segunda execução do P1

A segunda execução encontrou:

```text
disk_sha=2807c6c604f4601f92b990c047c857519fcb3760c58827ad308be297bcf951d0
canonical=15
ready=0
```

e encerrou na precondição que esperava o estado anterior `ready/`.

Esse encerramento documenta que o P1 já havia sido aplicado. Não representa reversão da primeira execução.

## Próxima fase

P2 diagnostica integridade temporal sem alterar o playout:

1. cada asset canônico isoladamente;
2. cada boundary consecutivo;
3. boundary último → primeiro;
4. playlist completa em 1 ciclo;
5. playlist completa em 2 ciclos;
6. comparação com os avisos DTS do processo ON-AIR.

Objetivo: localizar objetivamente a origem dos `Non-monotonic/Non-monotonous DTS` antes do primeiro restart controlado da TVKIDS.
