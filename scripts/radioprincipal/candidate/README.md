# Rádio Principal — Authority Replica Candidate C04

## Objetivo

Importar a autoridade editorial recebida do RadioBOSS para um banco SQLite **candidate isolado**, sem alterar selector, Harbor, `radioprincipal`, `radioprincipal-ns1`, MediaMTX, NGINX ou units de produção.

## Arquivos

- `authority-replica-candidate.py` — normaliza playlist/schedule, resolve assets pelo `librarymanifest` e índice local, registra checkpoints de playback e cria jobs para assets ausentes.
- `RUN-AUTHORITY-REPLICA-CANDIDATE.sh` — baixa a versão canônica, valida o Git blob, compila, roda self-test e executa o candidate.

## Fontes lidas no NS1

```text
/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/playlist.json
/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/schedule.json
/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/librarymanifest.json
/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/playback.json
/var/lib/studiosat/radio-v2/radioboss-sync/radioprincipal/current/heartbeat.json
/var/lib/studiosat/radio-v2/media-transfer/index.sqlite3
/srv/tpsmedia/repository/channels/radioprincipal/mirror-store/
```

## Único destino de escrita do candidate

```text
/var/lib/studiosat/radio-v2/candidates/radioprincipal-authority-replica/
  replica.sqlite3
  replica.sqlite3-wal
  replica.sqlite3-shm
  status.json
```

A cópia executável é instalada em `/root/authority-replica-candidate.py`.

## Semântica

- timestamp/revision externa mudando sem alteração do conteúdo: não cria nova revisão Studio Sat;
- ordem/conteúdo real da playlist mudando: cria nova revisão;
- playback é registrado como checkpoint sem fabricar nova revisão editorial;
- asset já existente: não cria transferência;
- asset ausente: cria `transfer_job` `QUEUED`; este candidate ainda **não transfere** o arquivo;
- `--watch --interval 10` reconcilia no máximo a cada 10 s.

## Primeira execução

Como root:

```bash
cd /root
curl -fsSL 'https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/candidate/RUN-AUTHORITY-REPLICA-CANDIDATE.sh' -o /root/RUN-AUTHORITY-REPLICA-CANDIDATE.sh
chmod 700 /root/RUN-AUTHORITY-REPLICA-CANDIDATE.sh
bash -n /root/RUN-AUTHORITY-REPLICA-CANDIDATE.sh
/root/RUN-AUTHORITY-REPLICA-CANDIDATE.sh --once
```

Depois devolver toda a saída do terminal e, se criado, `/var/lib/studiosat/radio-v2/candidates/radioprincipal-authority-replica/status.json`.

## Integridade

- candidate Git blob: `e0533ae66277ab773974addd0a03c422f8f7e70d`
- runner Git blob: `ed3057bf9e93a66e047d8bbab739756a26652c2f`
- candidate SHA256 testado localmente: `297fafcdfe153a4112636b757471c572d922f49c94798890f877665d0b27e494`
- runner SHA256 testado localmente: `99f8907f590ac5c135b7dc42ba1466108bafba9a4ccd727c52bc76b53d4f42c4`

## Rollback

Nenhuma produção é alterada. Para remover o candidate:

```bash
rm -f /root/authority-replica-candidate.py
rm -rf /var/lib/studiosat/radio-v2/candidates/radioprincipal-authority-replica
```

Não executar esse rollback enquanto houver futura unit candidate instalada; nesta etapa C04 ainda não há unit systemd.
