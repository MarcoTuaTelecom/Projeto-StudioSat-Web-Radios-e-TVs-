# StudioSat Web — Change Queue

Regra: **uma alteração ativa por vez no host de produção**. Engenharia de TV e Rádio podem preparar documentação/candidates em paralelo, mas apenas uma change pode modificar o host por vez.

Protocolo obrigatório: `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`.

Diretriz vigente: **IN-PLACE FIRST / NO CONTAINERS / NO VMs / NO DUPLICATE PLATFORM**.

## Baseline oficial

CHG-004B está **DONE / PASS / LOCKED** com snapshot `2026-09-10T16:57:41Z`.

## Trilha crítica atual

| ID | Mudança | Dono | Estado | Gate |
|---|---|---|---|---|
| CHG-R01 | Principal — escaping/playlist atômica | Rádio | **APPLY PASS / ROTATION FINAL PENDING** | generator e playlist corrigidos; PID 1383293; MediaMTX/RTSP PASS; 0 Impossible/NO_READY pós-fix |
| CHG-R01B | Principal — AAC 48 kHz estéreo + HLS real + limpeza de timestamps/FLV shutdown | Rádio | **ACTIVE / APPLY CANDIDATE READY** | AAC full traversal sem DTS → restart só Principal → RTSP AAC → HLS local → HLS via NGINX/TLS → novo PID sem erros |
| CHG-R02 | Rock — recovery legado | Rádio + Core | **BLOCKED por R01/R01B** | 10 assets → playlist → start somente Rock → MediaMTX/RTSP PASS |
| CHG-R03 | HLS das demais rádios | Rádio + Core | **BLOCKED por R01B/R02** | replicar profile comprovado sem quebra por station |
| CHG-R04 | Separação generator Rádio/TV | Rádio + TV + Core | **BLOCKED / DESIGN** | remover acoplamento restante |
| CHG-TV-* | TVKIDS/TVTEENS/TVVIVA/TVMAISJOVEM | Engenharia TV | **TV-OWNED** | preservar trabalho e interlocks |

## CHG-R01 — resultado já comprovado

Apply em `2026-09-10T18:15:42Z`:

```text
candidate/production playlist: 18/18
MISSING_OR_TRUNCATED_LINES=0
FFPROBE_FAILURES=0
FULL_CONCAT_TRAVERSAL=PASS
Principal PRE PID=1363987
Principal POST PID=1383293
ActiveState=active
SubState=running
MediaMTX ready=true
RTSP mp3 48000 stereo
impossible_to_open_post=0
no_ready_media_post=0
other_process_pids_unchanged=PASS
other_playlists_unchanged=PASS
```

Generator atual Principal:

```text
d2ba61daeeaaa89389fe1cc2ed277af68ac12c09b769c2eb9dda1feea9316fcd
```

Playlist atual Principal:

```text
154c3cb081f9a7d7f527ab184739b692c5a930db3fe8ff0659f241e9699b821c
```

O observer de rotação iniciado em foreground foi interrompido junto com a sessão SSH e deixou apenas `1/18`; isso é falha do método de observação, não evidência de falha do playout. Nova observação deverá ser destacada da sessão (`nohup`/transient unit) após o último restart da Principal.

## Por que CHG-R01B existe

A Principal ainda não pode ser declarada 100% para uso público/browser enquanto publica `MPEG-1/2 Audio (MP3)` no MediaMTX. O HLS do MediaMTX não aceita MP3 como codec de áudio para leitura HLS; o profile de entrega precisa ser AAC.

CHG-R01B usa mudança mínima e in-place:

- mantém filesystem, station ID, systemd unit, MediaMTX, NGINX e TLS;
- mantém o comportamento legado das demais rádios;
- altera `/usr/local/sbin/tps-playout-radio` somente no branch `radioprincipal`;
- Principal passa a AAC-LC, 48 kHz, estéreo, 192 kbps;
- `aresample=48000:async=1:first_pts=0` normaliza saída/timestamps;
- `-flvflags no_duration_filesize` elimina warnings de duration/filesize no encerramento de stream FLV;
- antes da mutação executa traversal completo AAC e exige zero warning DTS;
- depois reinicia somente a Principal;
- exige MediaMTX ready, RTSP AAC, HLS local real `#EXTM3U`, HLS via NGINX/TLS e journal do novo PID sem erros relevantes;
- em qualquer falha após promoção, restaura o playout anterior e reinicia somente a Principal.

Candidates:

```text
candidates/CHG-R01B/tps-playout-radio-v2-principal-aac.sh
candidates/CHG-R01B/apply-radioprincipal-aac-hls-v1.sh
```

## Próxima ação autorizada

1. sincronizar `main` sem reset;
2. `bash -n` nos dois candidates CHG-R01B;
3. confirmar worktree limpa;
4. executar `apply-radioprincipal-aac-hls-v1.sh` como root;
5. somente se `CHG_R01B_RESULT=PASS`, iniciar observer de rotação destacado da sessão;
6. fechar Principal apenas após `SEEN=18/18` e health POST.

Não executar `daemon-reload`, não reiniciar MediaMTX/NGINX e não tocar outra station durante CHG-R01B.
