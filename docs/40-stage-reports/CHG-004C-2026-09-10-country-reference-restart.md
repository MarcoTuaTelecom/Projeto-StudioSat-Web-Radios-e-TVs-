# CHG-004C — Radio Country — Reference Restart da stack atual

Status: **READY FOR EXECUTION**  
Data: 2026-09-10  
Owner: Engenharia Rádio + Core  
Safety: mudança controlada em uma única station  
Princípio: **IN-PLACE FIRST / NO CONTAINERS / NO DUPLICATE PLATFORM**

## Objetivo

Reiniciar exclusivamente `tps-radiocountry-playout.service` usando o conteúdo e estrutura já existentes para comprovar o comportamento real da stack atual antes de qualquer remodelagem de engine.

Country não é incidente no baseline CHG-001; estava `active` e MediaMTX `ready`. O restart é um teste de referência/resiliência solicitado para validar o que funciona e o que precisa ser remodelado.

## Proibido nesta change

- reiniciar o host;
- reiniciar MediaMTX;
- reiniciar NGINX;
- reiniciar outras rádios;
- reiniciar TVs;
- criar `/srv/studiosat/...`;
- instalar pacotes;
- containers/VMs;
- editar gerador/playlist/unit antes de observar o comportamento atual.

## PRECHECK — obrigatório

### 1. Sincronização GitHub

```bash
cd /root/Projeto-StudioSat-Web-Radios-e-TVs-
git fetch origin
git checkout main
git pull --ff-only
git status --short
git rev-parse HEAD
git log -6 --oneline
```

Working tree deve estar limpa. Se houver commit novo não revisado, STOP e voltar ao SYNC.

### 2. Identidade e estado Country

```bash
sudo systemctl show tps-radiocountry-playout.service \
  -p LoadState -p ActiveState -p SubState -p MainPID \
  -p ExecMainStartTimestamp -p ExecStartPre -p ExecStart \
  --no-pager

sudo systemctl status tps-radiocountry-playout.service --no-pager --full
```

### 3. Hashes dos componentes atuais

```bash
sudo sha256sum \
  /usr/local/sbin/tps-generate-playlist \
  /usr/local/sbin/tps-playout-radio \
  /srv/tpsmedia/repository/channels/radiocountry/playlists/playlist.txt
```

### 4. Conteúdo elegível em ready

```bash
READY=/srv/tpsmedia/repository/channels/radiocountry/ready

sudo find "$READY" -maxdepth 1 -type f \
  \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.mp4' -o -iname '*.aac' \) \
  ! -iname '*teste*' ! -iname '*test*' \
  -printf '%f\n' | sort

COUNT=$(sudo find "$READY" -maxdepth 1 -type f \
  \( -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.mp4' -o -iname '*.aac' \) \
  ! -iname '*teste*' ! -iname '*test*' | wc -l)

echo "COUNTRY_ELIGIBLE_READY=$COUNT"
```

`COUNTRY_ELIGIBLE_READY` deve ser maior que zero.

### 5. Inspecionar a regra atual do gerador antes do restart

```bash
sudo sed -n '1,260p' /usr/local/sbin/tps-generate-playlist
```

Confirmar que a lógica observada corresponde ao baseline atual e que não há comportamento destrutivo inesperado.

### 6. MediaMTX e HLS antes

```bash
curl -fsS http://127.0.0.1:9997/v3/paths/list \
  | jq -c '.items[] | select(.name=="radiocountry") | {name,ready,tracks,bytesReceived}'

curl -sS -L -o /tmp/country-before.m3u8 \
  -w 'COUNTRY_HLS_BEFORE_HTTP=%{http_code}\n' \
  --max-time 8 \
  http://127.0.0.1:8888/radiocountry/index.m3u8
```

Esperado: `ready=true` e HTTP 200.

### 7. Controle das demais stations antes

```bash
for s in \
  radioprincipal radiopop radiorock radioclassicas radiocountry \
  tvkids tvteens tvviva tvmaisjovem; do
  printf '%-18s ' "$s"
  systemctl is-active "tps-${s}-playout.service" || true
done
```

## EXECUTE

Somente se PRECHECK estiver coerente:

```bash
sudo systemctl restart tps-radiocountry-playout.service
```

Não executar nenhum outro restart.

## VERIFY imediato

```bash
sudo systemctl show tps-radiocountry-playout.service \
  -p ActiveState -p SubState -p MainPID -p ExecMainStartTimestamp \
  --no-pager

sudo systemctl status tps-radiocountry-playout.service --no-pager --full

sudo journalctl -u tps-radiocountry-playout.service \
  --since '-5 minutes' --no-pager -o short-iso | tail -n 200
```

### MediaMTX após restart

```bash
for i in $(seq 1 15); do
  OUT=$(curl -fsS http://127.0.0.1:9997/v3/paths/list 2>/dev/null \
    | jq -c '.items[] | select(.name=="radiocountry") | {name,ready,tracks,bytesReceived}' || true)
  echo "$OUT"
  echo "$OUT" | grep -q '"ready":true' && break
  sleep 2
done
```

### HLS após restart

```bash
curl -sS -L -o /tmp/country-after-1.m3u8 \
  -w 'COUNTRY_HLS_AFTER_HTTP=%{http_code}\n' \
  --max-time 8 \
  http://127.0.0.1:8888/radiocountry/index.m3u8

sleep 4

curl -sS -L -o /tmp/country-after-2.m3u8 \
  -w 'COUNTRY_HLS_AFTER2_HTTP=%{http_code}\n' \
  --max-time 8 \
  http://127.0.0.1:8888/radiocountry/index.m3u8

cmp -s /tmp/country-after-1.m3u8 /tmp/country-after-2.m3u8 \
  && echo 'COUNTRY_HLS_FRESHNESS=UNCHANGED_4S' \
  || echo 'COUNTRY_HLS_FRESHNESS=CHANGING'
```

### Verificar áudio do output

```bash
timeout 10 ffprobe -v error \
  -show_entries stream=codec_type,codec_name,sample_rate,channels \
  -of compact=p=0:nk=1 \
  http://127.0.0.1:8888/radiocountry/index.m3u8 || true
```

### Controle das demais stations depois

```bash
for s in \
  radioprincipal radiopop radiorock radioclassicas radiocountry \
  tvkids tvteens tvviva tvmaisjovem; do
  printf '%-18s ' "$s"
  systemctl is-active "tps-${s}-playout.service" || true
done
```

## PASS

- Country active/running;
- MainPID/start timestamp confirmam restart;
- MediaMTX Country ready;
- HLS HTTP 200;
- HLS avança;
- áudio detectável;
- sem restart loop;
- nenhuma regressão nas demais stations.

## FAIL/BLOCK

- zero assets elegíveis;
- gerador atual divergente/perigoso;
- Country já apresenta falha antes do restart;
- MediaMTX não ready antes sem explicação;
- HLS não responde antes;
- restart não retorna a active/ready;
- outras stations sofrem regressão.

Em FAIL, não instalar engine novo e não reiniciar serviços compartilhados. Coletar evidência e corrigir a causa no legado atual.

## Documentação pós-execução

Registrar no fechamento:

- HEAD executado;
- hashes dos três componentes;
- contagem ready elegível;
- PID/timestamp antes/depois;
- estado MediaMTX/HLS antes/depois;
- linhas relevantes do journal;
- resultado das demais stations;
- qualquer correção necessária.

Somente após isso CHG-004C vira DONE e CHG-005R (Radio Rock) é liberada.
