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

## Testes já executados antes da liberação

- `python3 -m py_compile`: OK;
- self-test XML: OK;
- envelope/timestamp alterado sem alteração semântica: `PLAYLIST_CHANGED=0`;
- troca real de ordem: nova `playlist_revision_id`;
- asset ausente: `transfer_job` criado;
- playlist em JSON: OK;
- `librarymanifest` com lista de caminhos: OK;
- runner em fluxo funcional local: valida blob, compila, executa self-test e instala a cópia validada.

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

- candidate Git blob: `f38f77c0ede31b65556b5fd2d5c544f3d544648b`
- runner Git blob: `a8240c60c88345c31398351a8e4ad6d949e776e4`
- candidate SHA256 testado localmente: `f7d6f3f7a934aa0d72696f2717ada11d5e861e37ef2e95a01106f2298c180e07`
- runner SHA256 testado localmente: `f42b0e2026c9b5aab363e4760640d2664d384330852107625343d8a723fdf53f`

## Rollback

Nenhuma produção é alterada. Para remover o candidate:

```bash
rm -f /root/authority-replica-candidate.py
rm -rf /var/lib/studiosat/radio-v2/candidates/radioprincipal-authority-replica
```

Não executar esse rollback enquanto houver futura unit candidate instalada; nesta etapa C04 ainda não há unit systemd.
