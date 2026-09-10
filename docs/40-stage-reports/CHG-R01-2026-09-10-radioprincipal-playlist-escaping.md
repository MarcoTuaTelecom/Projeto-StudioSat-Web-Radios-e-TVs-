# CHG-R01 — Rádio Principal — correção determinística da playlist ffconcat

Status: **ACTIVE — APPLY TRANSACIONAL v1.1 AUTORIZADO**  
Owner: Engenharia Rádio  
Escopo mutável: **somente generator específico da Rádio Principal + playlist da Rádio Principal + restart da unit da Rádio Principal**  
Interlock: **nenhum Core global e nenhuma outra station podem ser reiniciados/alterados**

## Problema comprovado

O generator atual `/usr/local/sbin/tps-generate-playlist-radioprincipal-fixed` monta linhas `file '...'` sem escapar apóstrofo. O asset `Ain't No Mountain High Enough_spotdown.org.mp3` é escrito como:

```text
file '/srv/tpsmedia/repository/channels/radioprincipal/ready/Ain't No Mountain High Enough_spotdown.org.mp3'
```

O parser ffconcat encerra a string no apóstrofo e tenta abrir um path truncado, produzindo `Impossible to open .../Aint` e loop prematuro.

## Baseline e restart antecipado

CHG-004B está `DONE / PASS / LOCKED`. Após o lock, foi executado manualmente antes da promoção planejada:

```text
systemctl restart tps-radioprincipal-playout.service
```

O restart ocorreu em `2026-09-10 17:31:47 UTC` e retornou warning `NeedDaemonReload=yes`. Nenhum `daemon-reload` foi executado.

Diagnóstico read-only pós-restart comprovou:

```text
Principal MainPID anterior: 1135303
Principal MainPID pós-restart: 1363987
Principal ActiveState/SubState: active/running
ExecStartPre carregado: /usr/local/sbin/tps-generate-playlist-radioprincipal-fixed
ExecStart carregado: /usr/local/sbin/tps-playout-radio radioprincipal
NeedDaemonReload: yes
Generator SHA atual: d7140c872191f6b9efabeb8ef6bd813eba898f9978822e7f5ab15c7e819a5f18
Playlist SHA atual: 9bded92a31b437063adacb968c1b0985a4c8a82dd4e2783a1ef3335896e49cfe
Playlist: 18 itens
MediaMTX radioprincipal: ready=true
RTSP: mp3 audio, 44100 Hz, 2 canais no instante medido
```

A playlist pós-restart continuou byte-idêntica à baseline e manteve a linha inválida do `Ain't...`. O journal mostrou o erro antigo antes do restart e o restart em si; o contador de 15 minutos incluía uma ocorrência do PID anterior. Portanto o restart não corrigiu a causa, apenas reiniciou a mesma configuração defeituosa.

## Prova de isolamento do restart antecipado

Os demais PIDs permaneceram exatamente como no baseline:

```text
radiopop        1135350
radiorock       0
radioclassicas  1135491
radiocountry    1135456
tvkids          1031405
tvteens         841849
tvviva          841863
tvmaisjovem     841879
MediaMTX        217466
NGINX           1060
```

Resultado: o restart afetou somente a Principal.

## Decisão de menor mudança

- manter FFmpeg 6.1.1;
- manter `tps-playout-radio`;
- manter unit/path/publicação/MediaMTX/NGINX;
- manter semântica atual da Principal: scan recursivo de `ready/`, MP3/M4A/AAC, exclusão case-insensitive de `test/teste`;
- corrigir **somente** escaping ffconcat e atomicidade do generator específico;
- não alterar generator global;
- não alterar TV;
- **não executar `systemctl daemon-reload` nesta Change**. A unit carregada já aponta para os paths corretos e nenhum unit/drop-in será alterado.

## Candidates vigentes

```text
candidates/CHG-R01/tps-generate-playlist-radioprincipal-fixed-v2.sh
candidates/CHG-R01/validate-radioprincipal-playlist-v1.sh
candidates/CHG-R01/observe-radioprincipal-rotation-v1.sh
candidates/CHG-R01/apply-radioprincipal-fix-v1.1.sh
```

`apply-radioprincipal-fix-v1.sh` está superseded por `v1.1`; não executar o v1.

## Apply transacional v1.1

O executor v1.1 aborta antes de mutar se qualquer artefato locked tiver drift. Ele exige exatamente:

```text
old generator SHA = d7140c872191f6b9efabeb8ef6bd813eba898f9978822e7f5ab15c7e819a5f18
old playlist SHA  = 9bded92a31b437063adacb968c1b0985a4c8a82dd4e2783a1ef3335896e49cfe
unit SHA          = d57cd94cba7c8fc4975cba927c922ffaae2d32e460ccf3aa88558cb1acccec58
safety drop-in    = 102238932b4292834f864d3f0470e5ca3e603d18a29346e8d9ebf7316dcb5d48
fixed drop-in     = 2e15e711c624aed3e393abe294446574dc50fbab2eae5559304f90ebf70e83e3
eligible assets   = 18
```

Fluxo automático e gated:

1. working tree limpa e syntax check dos candidates;
2. confirmar hashes locked e contrato `ExecStartPre/ExecStart` carregado;
3. capturar PIDs e hashes das nove playlists antes;
4. gerar candidate em `/tmp` como `tpsmedia`;
5. validar 18/18 linhas, 18/18 ffprobe e full concat traversal;
6. criar backup privado em `/var/backups/studiosat/CHG-R01/<timestamp>/`;
7. promover generator v2 atomicamente no mesmo path;
8. gerar `playlist.txt` atomicamente como `tpsmedia`;
9. revalidar a playlist de produção 18/18;
10. confirmar Principal e MediaMTX ainda ativos;
11. executar **um restart controlado somente da Principal**;
12. exigir novo PID, MediaMTX ready, RTSP áudio e zero novo `Impossible to open`/`NO_READY_MEDIA` desde o restart;
13. provar que nenhum PID/playlist fora da Principal mudou;
14. gerar pacote shareable em `/tmp`.

O executor possui rollback automático para `generator.previous` + `playlist.previous` se houver falha depois da primeira mutação. Se a falha ocorrer após o restart, restaura os arquivos anteriores e reinicia somente a Principal.

## Gate imediato

Obrigatório ao final do apply:

```text
CHG_R01_IMMEDIATE_RESULT=PASS
ROTATION_18_OF_18=PENDING_OBSERVER
```

A Change ainda não será fechada nessa etapa. Depois deve ser executado o observer read-only até:

```text
ROTATION_RESULT=PASS
SEEN=18/18
```

O log deve demonstrar que itens posteriores a `Ain't No Mountain High Enough...` foram realmente abertos pelo FFmpeg.

## HLS e profile de áudio

HLS Rádio HTTP 500 continua incidente separado `INC-RADIO-003` e não será misturado nesta Change. O RTSP observado em `44100 Hz / stereo` também não será normalizado aqui; canonical/profile Rádio é Change posterior. CHG-R01 resolve exclusivamente integridade de playlist, abertura 18/18 e progressão sem loop prematuro.

## PASS final — defeito CHG-R01

```text
18/18 assets elegíveis presentes e reproduzíveis
18/18 linhas ffconcat corretas
0 referência truncada
full concat traversal PASS
generator corrigido e atômico
playlist de produção corrigida e atômica
restart limpo da Principal
MediaMTX ready=true
RTSP PASS
0 novo Impossible to open
0 NO_READY_MEDIA
rotação real SEEN=18/18
itens após Ain't... realmente executados
nenhuma outra station/Core reiniciou ou regrediu
rollback conhecido e preservado
documentação/hashes atualizados
```

Somente após todos esses gates `INC-RADIO-001` vira `RESOLVED` e CHG-R02 pode ser liberada.
