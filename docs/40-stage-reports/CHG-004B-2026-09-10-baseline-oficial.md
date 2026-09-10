# CHG-004B — Baseline Oficial Operacional v1

Status: **READY — ÚNICA PRÓXIMA AÇÃO NO HOST**  
Data: 2026-09-10  
Owner: Core + Engenharia Rádio  
Safety: **READ-ONLY**

## Objetivo

Fechar o Item 1 do plano: transformar o FULL RAY-X v3.1 em baseline oficial bloqueado e gerar um snapshot de health imediatamente anterior à primeira mudança mutável.

## Entrada comprovada

- FULL RAY-X v3.1 executado em `2026-09-10T15:35:03Z`;
- Git HEAD da coleta: `d37ec74de015208df18e76a8a1a070d3ecdfa645`;
- working tree na coleta: limpa;
- archive SHA-256: `338c3f808aff8d70c5843daf88bfd7169fbb289704cabe937b60425511f26a6f`;
- manifest interno validado: `1035/1035` sem divergência;
- análise AS-IS publicada em `docs/90-evidencias/BASELINE_OFICIAL_AS_IS_2026-09-10_v1.0.md`;
- disposition publicada em `docs/00-core/COMPONENT_DISPOSITION_v1.0.md`;
- dependency map publicada em `docs/00-core/DEPENDENCY_MAP_AS_IS_v1.0.md`;
- incidents com owner publicados em `docs/30-execucao/INCIDENT_REGISTER.md`;
- hashes conhecidos publicados em `registry/critical-artifacts-baseline.yaml`;
- restart tracking publicado em `docs/30-execucao/RESTART_REGISTER.md`.

## Por que ainda existe uma execução read-only

O FULL RAY-X é a fotografia profunda AS-IS. Antes da primeira alteração, precisamos de uma fotografia curta e repetível que será executada **antes e depois de toda Change mutável**.

Ela também captura SHA-256 diretamente dos `FragmentPath` e `DropInPaths` crus das nove units, sem inferir hash a partir de `systemctl cat`.

## Candidate vigente

```text
candidates/CHG-004B/studiosat-health-baseline-v1.sh
```

Versão interna vigente:

```text
1.0-candidate.1
```

A candidate foi corrigida **antes de qualquer execução** para:

- tratar corretamente múltiplos `DropInPaths` mesmo com `IFS` restritivo;
- validar HLS como manifest real por `#EXTM3U`;
- quando `index.m3u8` for master playlist, seguir a media playlist para medir freshness real;
- não presumir a existência de `ready/`.

Git blob atual da candidate no repositório após a correção: `de6c5fec9a5ad04589ddd6d46a6bd3a37c120437`.

**Não existe SHA-256 raw pré-declarado como gate.** O SHA-256 raw da candidate realmente executada será obtido no próprio host imediatamente após `git pull` e registrado no fechamento desta Change. Isso evita tratar como vigente o hash de uma versão anterior.

## O snapshot coleta

### Core

- `tps-mediamtx.service` state/PID;
- `nginx.service` state/PID;
- `nginx -t`;
- MediaMTX API;
- uso do root filesystem;
- MemAvailable;
- load1;
- portal comum Rádio.

### Cada uma das nove stations

- systemd state/PID/start timestamp;
- MediaMTX ready/tracks;
- RTSP bounded `ffprobe`;
- HLS local e HTTP;
- validação de manifest real por `#EXTM3U`;
- HLS freshness usando media playlist quando houver master;
- portal público canônico `www`;
- `Impossible to open` nos últimos 30 minutos;
- `NO_READY_MEDIA` nos últimos 30 minutos;
- `Non-monotonic DTS` nos últimos 30 minutos;
- quantidade em `ready/`;
- SHA-256 da playlist.

### Hash registry

- scripts estáticos críticos;
- MediaMTX config;
- NGINX configs críticas;
- raw hash dos nove unit fragments;
- raw hash de todos os drop-ins carregados;
- hash dinâmico das nove playlists.

## Segurança operacional

O script não executa:

```text
systemctl start/stop/restart/reload/enable/disable
reboot
apt install/remove/upgrade
nginx reload
certbot renew
playlist generation
edição de qualquer config
mv/rm/chmod/chown em produção
```

Escreve apenas em `/tmp/studiosat-health-baseline-*` e cria seu `.tar.gz`/`.sha256`.

## PRECHECK

```bash
cd /root/Projeto-StudioSat-Web-Radios-e-TVs-
git fetch origin
git checkout main
git pull --ff-only

echo "===== WORKTREE ====="
git status --short

echo "===== HEAD ====="
git rev-parse HEAD

echo "===== LOG ====="
git log -10 --oneline
```

Regras:

- working tree deve estar limpa;
- nunca fazer reset para SHA antigo;
- se houver commit novo ainda não revisado, parar e voltar ao SYNC.

Depois:

```bash
bash -n candidates/CHG-004B/studiosat-health-baseline-v1.sh
echo "BASH_N_EXIT=$?"
grep '^VERSION=' candidates/CHG-004B/studiosat-health-baseline-v1.sh
sha256sum candidates/CHG-004B/studiosat-health-baseline-v1.sh
```

Obrigatório:

```text
BASH_N_EXIT=0
VERSION="1.0-candidate.1"
```

O SHA-256 raw impresso será a identidade executável da candidate e deve ser preservado para o Stage Report.

## EXECUTE

```bash
sudo nice -n 10 bash candidates/CHG-004B/studiosat-health-baseline-v1.sh
```

Nenhum outro comando mutável deve ser executado em seguida.

## Saída

O script produzirá:

```text
/tmp/studiosat-health-baseline-<host>-<timestamp>/
/tmp/studiosat-health-baseline-<host>-<timestamp>.tar.gz
/tmp/studiosat-health-baseline-<host>-<timestamp>.tar.gz.sha256
```

Validar:

```bash
SHA_FILE=$(ls -1t /tmp/studiosat-health-baseline-*.tar.gz.sha256 | head -n1)
sha256sum -c "$SHA_FILE"
```

## Gate PASS da CHG-004B

A Change vira PASS/DONE quando:

1. pacote hash válido;
2. health das nove stations recebido e analisado;
3. Core health recebido;
4. unit/drop-in hashes crus registrados;
5. hashes estáticos confrontados com FULL RAY-X;
6. diferenças entre FULL RAY-X e snapshot atual explicadas;
7. `critical-artifacts-baseline.yaml` atualizado e convertido para `locked`;
8. `channels-registry.yaml` atualizado para a evidência corrente;
9. `CHANGE_QUEUE.md` atualizado;
10. `main` relido após a documentação.

## Próxima change somente após PASS

A análise atual aponta `CHG-R01 — Rádio Principal — playlist/generator escaping` como primeira mudança mutável. Ela permanece bloqueada até o baseline estar `LOCKED`.