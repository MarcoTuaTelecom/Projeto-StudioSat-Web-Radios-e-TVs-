# CHG-004X — FULL RAY-X v3.1 antes da reavaliação integral

Status: **READY FOR EXECUTION**  
Data: 2026-09-10  
Owner: Engenharia Rádio + Core  
Safety class: **READ-ONLY COM PROBES LIMITADOS**  
Princípios: **IN-PLACE FIRST / NO CONTAINERS / NO DUPLICATE PLATFORM**

## Correção de escopo

O antigo v2 foi considerado insuficiente para a definição de “raio-X completo” exigida pelo projeto. Ele era um preflight ampliado e não inventariava com profundidade suficiente todos os serviços, rotinas, processos, ferramentas, domínios, arquivos, formatos e origens/saídas por emissora.

**v2 está SUPERSEDED. Não executar.**

Candidate vigente:

```text
candidates/CHG-004X/studiosat-full-rayx-v3.sh
```

## Objetivo

Permitir reconstruir, com evidência do host, a cadeia completa:

```text
ROTINA/OPERADOR
→ SERVICE/PROCESSO
→ SCRIPT/EXECSTART/EXECSTARTPRE
→ DIRETÓRIO/PLAYLIST
→ ASSET REAL
→ CODEC/FORMATO/TAMANHO/BITRATE
→ FFMPEG/ENGINE
→ MEDIAMTX
→ HLS/RTSP/RTMP
→ NGINX/TLS
→ DOMÍNIO/SUBDOMÍNIO
→ CLIENTE
```

A reavaliação do projeto só começa depois desse mapa existir.

## Escopo obrigatório v3.1

### Host e recursos

- hardware/CPU/RAM/swap/kernel/OS;
- discos, filesystems, mounts, inodes;
- load, top, vmstat/iostat quando disponíveis;
- erros/warnings recentes de kernel.

### Todas as ferramentas e pacotes

- todos os pacotes conhecidos pelo `dpkg-query`;
- pacotes marcados manualmente;
- Snap/Flatpak se existirem;
- Python/npm/gems quando existirem;
- paths e versões de ferramentas/runtimes comuns de mídia, web, rede, compilação e bancos;
- `/usr/local/bin` e `/usr/local/sbin` relevantes, com metadata/hashes e conteúdo sanitizado dos scripts TPS/StudioSat.

### Todos os serviços

- todos os services carregados;
- todos running;
- todos failed;
- todos unit files;
- sockets/path/mount units;
- para cada service ativo/falhado: unit, show, status, ExecStart/Pre/Post, WorkingDirectory, PID, usuário/grupo, restart policy, drop-ins, uso de recursos.

### Todas as rotinas

- todos os systemd timers e seus arquivos/detalhes;
- `/etc/crontab`;
- cron.d/hourly/daily/weekly/monthly;
- crontabs de usuários;
- anacron;
- `atq` quando disponível;
- init.d/rc.local;
- inventário logrotate.

### Todos os processos e “pastas em execução”

- `ps` completo;
- árvore de processos;
- para cada PID acessível: executável, CWD, root e contagem de file descriptors;
- processos de mídia detalhados;
- arquivos da biblioteca StudioSat atualmente abertos por processos, via `lsof` quando disponível.

### Rede

- endereços, rotas, rules, neighbors;
- todos listeners TCP/UDP e processos associados;
- conexões estabelecidas;
- resumo de sockets;
- counters das interfaces em janela de 5 s;
- firewall local UFW/nftables/iptables quando disponível.

### Filesystem operacional

Inventário/uso de espaço de `/srv`, `/var/www`, `/opt`, `/usr/local`, `/etc/nginx`, `/etc/systemd/system`, além da árvore específica de cada station. Para cada station registra ownership, permissões, tamanho, inode, link count, mtime, symlinks e hardlinks.

### NGINX, sites, domínios e subdomínios

- `nginx -t`;
- configuração completa sanitizada;
- arquivos e hashes de config;
- `server_name`, `listen`, `root`, `alias`, `location`, `proxy_pass`, `fastcgi_pass`, redirects;
- detecção adicional de Apache/Caddy/HAProxy se existirem;
- nomes descobertos no NGINX somados aos nomes dos certificados Certbot;
- DNS A/AAAA/CNAME quando `dig` estiver disponível;
- HTTP e HTTPS reais seguindo redirects;
- URL efetiva, connect time, TTFB, total time, bytes e speed_download;
- certificado TLS remoto, validade, issuer e SAN.

**Limite factual:** registros DNS que existam somente no provedor DNS e não apareçam no NGINX/certificados deste host não podem ser enumerados com garantia apenas pelo servidor. Esse inventário exige acesso à zona/provedor DNS. O raio-X identifica e testa todos os hostnames descobertos localmente e registra padrões/wildcards não diretamente testáveis.

### MediaMTX

- unit/show/status/journal;
- processo;
- listeners;
- configs candidatas, hashes e cópia sanitizada;
- API global/paths;
- sessões RTMP/RTSP/HLS/WebRTC/SRT quando endpoints da versão suportarem;
- métricas quando disponíveis;
- estado/path/tracks individual das nove stations.

### Samba/ingest

- services/listeners;
- `testparm`;
- `smbstatus`;
- `smb.conf` sanitizado;
- paths e propriedades relevantes dos shares.

### Todas as nove emissoras

Para `radioprincipal`, `radiopop`, `radiorock`, `radioclassicas`, `radiocountry`, `tvkids`, `tvteens`, `tvviva`, `tvmaisjovem`:

- unit e estado real;
- PID/processo/cmdline/CWD/executável;
- FDs/lsof quando disponível;
- journal recente;
- árvore física completa da station;
- `du`, permissões, symlinks/hardlinks;
- origem corrente inferível por playlist + FDs abertos;
- playlist ativa, hash, stat, conteúdo sanitizado;
- TODAS as referências `file` e se existem ou não;
- `ready`, `canonical` e demais diretórios existentes.

### Todos os assets locais das stations

Para todos os arquivos de mídia reconhecidos nas extensões coletadas, sem limitar a três amostras:

```text
path relativo
bytes
extensão
MIME
mtime
inode
hardlink count
format_name
duration
bit_rate
audio codec
sample rate
channels
video codec
width
height
pix_fmt
r_frame_rate
avg_frame_rate
```

O `ffprobe` é limitado por timeout e não faz transcode nem decode integral.

### Formatos de saída e testes reais

Por station:

- MediaMTX ready/tracks;
- HLS local com HTTP final;
- comparação do manifest após 4 s para freshness;
- download de segmento quando resolvível, medindo connect/TTFB/total/speed/size;
- `ffprobe` HLS;
- `ffprobe` RTSP TCP;
- `ffprobe` RTMP;
- probes HTTP/HTTPS de roots e caminhos HLS públicos candidatos conhecidos;
- nenhuma falha de um protocolo é automaticamente interpretada como outage sem confrontar as demais evidências.

### Velocidade

O raio-X mede desempenho do caminho real, não executa um benchmark agressivo externo:

```text
HTTP connect time
HTTP TTFB
HTTP total time
HTTP bytes
HTTP speed_download
HLS segment speed_download
HLS segment size
network RX/TX delta de 5 s
vmstat/iostat quando disponíveis
```

Não será usado speedtest.net nem teste saturando link de produção nesta change.

## Garantia operacional

É proibido ao FULL RAY-X:

```text
systemctl start/stop/restart/reload/enable/disable
reboot
apt install/remove/upgrade
nginx reload
certbot renew
playlist generation
edição de unit/config
mv/rm de mídia
containers/VMs
```

O único efeito persistente fora de leituras/probes é criar o diretório e pacote de evidência em `/tmp`.

## Custo esperado

Ao contrário do antigo preflight, este inventário faz `ffprobe` sequencial de todos os assets reconhecidos. Portanto pode demorar. Ele não executa em paralelo para evitar pico desnecessário de CPU/I/O. Recomenda-se executá-lo com prioridade reduzida (`nice`, e `ionice` se disponível).

## PRECHECK

```bash
cd /root/Projeto-StudioSat-Web-Radios-e-TVs-
git fetch origin
git checkout main
git pull --ff-only
git status --short
git rev-parse HEAD
git log -8 --oneline

bash -n candidates/CHG-004X/studiosat-full-rayx-v3.sh
echo "BASH_N_EXIT=$?"
sha256sum candidates/CHG-004X/studiosat-full-rayx-v3.sh
```

Working tree deve estar limpa e `BASH_N_EXIT=0`.

## EXECUTE

Preferido, se `ionice` existir:

```bash
sudo nice -n 15 ionice -c2 -n7 bash candidates/CHG-004X/studiosat-full-rayx-v3.sh
```

Fallback sem `ionice`:

```bash
sudo nice -n 15 bash candidates/CHG-004X/studiosat-full-rayx-v3.sh
```

## Saída

```text
FULL_RAYX_COMPLETE=YES
RAYX_VERSION=3.1
READ_ONLY=YES
OUTPUT_DIR=/tmp/studiosat-full-rayx-v3-...
ARCHIVE=/tmp/studiosat-full-rayx-v3-....tar.gz
ARCHIVE_SHA256=/tmp/studiosat-full-rayx-v3-....tar.gz.sha256
```

Validar:

```bash
sha256sum -c /tmp/studiosat-full-rayx-v3-*.tar.gz.sha256
```

## Depois

Enviar `.tar.gz` e `.sha256` em canal privado. Não publicar o pacote bruto no GitHub público. Nenhum restart de Country/Rock/TV/Core será autorizado até a análise integral.

## Gate de fechamento

CHG-004X só fecha quando o conteúdo coletado permitir publicar:

- AS-IS completo;
- mapa ferramenta → rotina → serviço → script → diretório → asset → engine → MediaMTX → NGINX → domínio;
- matriz por station de origem, playlist, formatos de entrada e saída, tamanho e velocidade;
- inventário de todos sites/domínios/subdomínios localmente descobertos e testados;
- KEEP / FIX / REFACTOR / REPLACE / REMOVE;
- nova matriz P0/P1/P2;
- plano Rádio reavaliado;
- handoff Core/TV revisado;
- nova Change Queue;
- primeira mudança mutável com rollback explícito.
