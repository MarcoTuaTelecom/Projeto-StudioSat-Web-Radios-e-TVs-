# CHG-004 — Health read-only dos 9 canais

Status: **DRAFT / BLOCKED POR CHG-003**  
Owner: Core  
Candidate: `candidates/CHG-004/studiosat-health-readonly.sh`  
Último SYNC antes deste plano: `b07e66e01b0c9d93dfac98a65812311f00312f3e`

## Objetivo

Criar a primeira implementação executável do envelope `STUDIOSAT-HEALTH-1` sem alterar playout, MediaMTX, NGINX, playlists, mídia ou systemd.

O health deve corrigir duas limitações observadas no Core Preflight v1.0:

1. HLS local deve seguir redirects HTTP antes de concluir falha;
2. Rádio não pode ser declarada offline apenas porque `ffprobe` de leitura RTMP falhou — MediaMTX API/path/source também deve participar da decisão.

## Gate atual

**NÃO EXECUTAR AINDA.**

CHG-003 permanece pendente do aceite formal da Engenharia de Rádio ao `CORE CONTRACT v0.1`. A Engenharia de TV já aceitou o contrato e a estratégia conjunta.

Enquanto o aceite Rádio não estiver publicado no GitHub, este arquivo e o script são somente candidates para revisão.

## Candidate publicado

`candidates/CHG-004/studiosat-health-readonly.sh`

### Safety class

`read-only`

### Efeitos permitidos

- ler systemd;
- ler journal;
- consultar MediaMTX API local;
- consultar HLS local;
- consultar endpoints públicos por HTTP;
- criar somente `/tmp/studiosat-health-<timestamp>/`.

### Proibido

- start/stop/restart/reload;
- editar configuração;
- gerar playlist;
- mover mídia;
- instalar pacote;
- alterar firewall/TLS/MediaMTX/NGINX;
- corrigir Radio Rock;
- reiniciar TVs.

## Checks por station

Base comum:

```text
station_id
station_class
systemd state
MediaMTX ready/source/tracks
HLS HTTP final
HLS freshness
public root HTTP
recent errors
schema_version
```

Extensão inicial TV:

```text
Non-monotonic DTS nos últimos 15 minutos
```

A extensão TV completa (FPS/resolution/timestamp integrity por stream) e a extensão Rádio completa (silence/metadata/live/A-V/audio-only) serão incrementais; não serão simuladas no primeiro health.

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

Essa classificação é operacional inicial e será refinada com as extensões de domínio.

## PRECHECK planejado após desbloqueio

1. reler `main`;
2. confirmar `CHG-003 = DONE/ACCEPTED`;
3. confirmar que nenhuma outra change está EXECUTING;
4. `git pull --ff-only` no host;
5. `bash -n candidates/CHG-004/studiosat-health-readonly.sh`;
6. registrar hash do candidate;
7. registrar estado visual das 9 units;
8. executar apenas o candidate.

## Comando planejado — NÃO EXECUTAR ENQUANTO BLOCKED

```bash
cd /root/Projeto-StudioSat-Web-Radios-e-TVs-
git fetch origin
git checkout main
git pull --ff-only

bash -n candidates/CHG-004/studiosat-health-readonly.sh
sha256sum candidates/CHG-004/studiosat-health-readonly.sh
sudo candidates/CHG-004/studiosat-health-readonly.sh
```

## Saída esperada

```text
/tmp/studiosat-health-<timestamp>/health.json
/tmp/studiosat-health-<timestamp>/health.tsv
```

## Critérios de PASS

- nenhuma alteração de lifecycle/configuração/mídia;
- 9 stations aparecem no resultado;
- `radiorock` deve refletir o estado real, não ser mascarada;
- TVKIDS deve refletir DTS recente caso ainda exista;
- HLS deve ser avaliado após redirect;
- MediaMTX API e systemd devem participar da classificação;
- resultado deve ser suficiente para decidir CHG-005 sem depender apenas de `systemctl is-active`.

## Rollback

Não há rollback de produção esperado. O script cria somente arquivos temporários em `/tmp`. Nenhuma limpeza será feita como efeito colateral da execução.

## Depois da execução

1. anexar o resultado privado ao chat/coordenação, não ao GitHub público;
2. atualizar este Stage Report com fatos reais;
3. corrigir o script se necessário;
4. publicar versão final aceita em `scripts/`;
5. atualizar Change Queue;
6. reler `main` e mudanças de TV/Rádio;
7. só então decidir CHG-005/CHG-006.
