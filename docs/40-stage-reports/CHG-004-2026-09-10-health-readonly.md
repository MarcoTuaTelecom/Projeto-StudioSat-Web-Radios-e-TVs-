# CHG-004 — Health read-only dos 9 canais

Status: **READY FOR EXECUTION**  
Owner: Core  
Candidate: `candidates/CHG-004/studiosat-health-readonly.sh`  
Safety class: `read-only`

## SYNC que liberou a execução

- CHG-001: DONE/PASS.
- CHG-002: DONE/PASS.
- Core Contract v0.1 aceito pelo Core.
- Engenharia TV: aceite registrado.
- Engenharia Rádio: `docs/10-radio/RADIO_ACCEPTANCE_CORE_CONTRACT_v0.1.md` = ACCEPTED.
- Diretriz vigente: Rádio-first com Core compatível com TV.
- Nenhum commit concorrente da Engenharia TV foi observado entre o checkpoint `c72132d...` e a publicação da diretriz Rádio-first.

Antes da execução no host, o operador deve obrigatoriamente fazer `git fetch/pull` e conferir o novo HEAD. Se houver commits posteriores, a execução para e volta a SYNC.

## Objetivo

Criar a primeira implementação executável do envelope `STUDIOSAT-HEALTH-1` sem alterar playout, MediaMTX, NGINX, playlists, mídia ou systemd.

O health serve a duas funções:

1. baseline para a trilha Rádio, especialmente antes de recuperar Radio Rock;
2. controle de não-regressão das quatro TVs enquanto o Core/Rádio evolui, **sem executar correção TV**.

## Candidate revisado

`candidates/CHG-004/studiosat-health-readonly.sh`

A revisão confirmou que o script:

- exige apenas `curl`, `jq`, `systemctl`, `journalctl`;
- consulta MediaMTX API em loopback;
- segue redirects HLS;
- lê journal dos últimos 15 minutos;
- consulta endpoints públicos;
- cria somente `/tmp/studiosat-health-<timestamp>/`;
- não possui start/stop/restart/reload;
- não gera playlist;
- não escreve em mídia/configuração;
- não corrige Rock;
- não reinicia TVs.

## Checks por station

Base comum:

```text
station_id
station_class
systemd state
MediaMTX ready/tracks
HLS HTTP final
HLS freshness
public root HTTP
recent errors
schema_version
```

Extensão inicial TV, apenas como controle:

```text
Non-monotonic DTS nos últimos 15 minutos
```

A extensão TV completa continua pertencendo à Engenharia TV. A extensão Rádio completa (silence/metadata/live/A-V/audio-only) será construída pela Engenharia Rádio nas próximas fases.

## Lógica provisória

`failed`:

- unit não está `active`; ou
- MediaMTX path não está `ready`.

`degraded`:

- HLS local ou endpoint público falha; ou
- TV possui Non-monotonic DTS recente; ou
- journal possui erro/fatal/failed/connection refused recente.

`healthy`:

- checks acima passam e não há condição de degradação observada.

Essa classificação é baseline operacional, não health final de cada domínio.

## PRECHECK obrigatório

No host:

```bash
cd /root/Projeto-StudioSat-Web-Radios-e-TVs-

git fetch origin
git checkout main
git pull --ff-only

git status --short
git rev-parse HEAD
git log -5 --oneline
```

Se houver working tree alterada ou commit novo não revisado, **STOP** e retornar ao SYNC.

Depois:

```bash
bash -n candidates/CHG-004/studiosat-health-readonly.sh
echo $?
sha256sum candidates/CHG-004/studiosat-health-readonly.sh
```

`bash -n` deve retornar 0.

## EXECUTE

Somente após PRECHECK PASS:

```bash
sudo candidates/CHG-004/studiosat-health-readonly.sh
```

## Saída esperada

```text
/tmp/studiosat-health-<timestamp>/health.json
/tmp/studiosat-health-<timestamp>/health.tsv
```

Copiar os dois arquivos para análise privada. Não commitá-los automaticamente no repositório público.

## Critérios de PASS

- nenhuma alteração de lifecycle/configuração/mídia;
- 9 stations aparecem;
- `radiorock` reflete o estado real;
- HLS é avaliado após redirect;
- MediaMTX API e systemd participam da classificação;
- TVs servem como controle de não-regressão;
- resultado permite preparar CHG-005R sem depender apenas de `systemctl is-active`.

## Critérios de BLOCK/FAIL

- falta de dependência exigida;
- MediaMTX API não acessível e resultado fica inconclusivo;
- working tree/HEAD diverge antes da execução;
- qualquer comportamento mutável inesperado;
- saída incompleta.

## Rollback

Não há rollback de produção esperado. O script cria somente arquivos temporários em `/tmp`.

## Depois da execução

1. enviar `health.json` e `health.tsv` para análise Core/Rádio;
2. reler `main` e commits da Engenharia TV;
3. atualizar este Stage Report com fatos reais;
4. corrigir candidate se necessário e publicar versão final aceita em `scripts/`;
5. atualizar Change Queue;
6. abrir CHG-005R para recuperação da Radio Rock;
7. manter qualquer achado TV como evidência para a Engenharia TV, sem corrigir a vertical TV nesta frente.
