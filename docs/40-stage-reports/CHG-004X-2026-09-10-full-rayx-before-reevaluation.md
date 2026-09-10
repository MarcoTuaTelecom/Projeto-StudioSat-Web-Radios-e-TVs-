# CHG-004X — Full Ray-X v2 antes da reavaliação integral

Status: **READY FOR EXECUTION**  
Data: 2026-09-10  
Owner: Engenharia Rádio + Core  
Safety class: **READ-ONLY**  
Princípios: **IN-PLACE FIRST / NO CONTAINERS / NO DUPLICATE PLATFORM**

## Motivo da mudança de ordem

O restart controlado da Radio Country foi suspenso antes da execução. A decisão vigente é fotografar novamente o estado completo do host e somente depois reavaliar o projeto inteiro.

Nenhum restart da Country deve ocorrer antes do fechamento desta change.

## Objetivo

Coletar uma fotografia atual e suficientemente completa para decidir, com base no sistema real:

- o que já funciona e deve ser preservado;
- o que precisa apenas ser corrigido in-place;
- o que realmente precisa ser substituído;
- se um novo engine Rádio é necessário e qual problema ele resolve;
- a causa atual da Radio Rock;
- o risco real de restart da Country;
- a semântica atual de `ready/`, `canonical/` e playlists;
- o comportamento atual de `ExecStartPre` por station;
- o estado de MediaMTX, NGINX/TLS, portas, firewall local e Samba;
- os contratos compartilhados que a Engenharia TV deverá herdar sem retrabalho.

## Candidate

`candidates/CHG-004X/studiosat-full-rayx-v2.sh`

O candidate foi submetido a `bash -n` antes da publicação.

## O que o raio-X coleta

### Host

CPU, RAM, swap, load, disco, inodes, mounts, kernel, OS, versões e pacotes relevantes, processos e amostras de recursos.

### systemd

Para as 9 stations e para componentes compartilhados:

- unit completa;
- estado;
- PID;
- timestamp de start;
- `ExecStart`;
- `ExecStartPre`;
- restart policy;
- limites de CPU/RAM;
- drop-ins;
- dependências;
- journal recente;
- hashes dos arquivos de unit relevantes.

### Scripts

Inventário, metadata, SHA-256 e cópia sanitizada dos scripts `tps-*`/`studiosat*` em `/usr/local/sbin` e `/usr/local/bin`.

### MediaMTX

Processo, listeners, unit, configs candidatas, hashes, configs sanitizadas, API de paths/config e estado observado das 9 stations.

### NGINX/TLS

`nginx -t`, configuração sanitizada, server names, routes/proxies, arquivos/hashes, certificados e timers Certbot. `certbot renew --dry-run` NÃO é executado.

### Rede/segurança

Listeners TCP/UDP, endereços, rotas, resolução DNS e firewall local disponível (UFW/iptables/nftables).

### Samba/ingest

Processos, listeners, `testparm`, `smbstatus` e configuração sanitizada.

### Filesystem e mídia

Para cada station:

- árvore atual até profundidade controlada;
- ownership/permissões/mtime/tamanho;
- sizes por subdiretório;
- symlinks e hardlinks;
- inventários `incoming`, `quarantine`, `canonical`, `ready`, `playlists`, `state`, `graphics`, `logs`, `archive`;
- contagem de conteúdo elegível em `ready/`;
- playlist ativa, hash e referências ausentes;
- até 3 amostras de metadata `ffprobe`, sem decode integral.

### Streams

Para as 9 stations:

- `systemd`;
- MediaMTX `ready`/tracks;
- HLS local seguindo redirects;
- freshness HLS;
- endpoint público conhecido.

TV é observada apenas como controle de compatibilidade e não-regressão. Esta change não implementa nem corrige a vertical TV.

## Garantia operacional

O script NÃO executa:

```text
apt install/remove
systemctl start/stop/restart/reload/enable/disable
reboot
nginx reload
certbot renew
playlist generation
mv/rm de mídia
edição de MediaMTX
edição de NGINX
edição de systemd
containers
VMs
```

O único efeito esperado é criar `/tmp/studiosat-full-rayx-<host>-<timestamp>/`, seu `.tar.gz` e `.sha256`.

## PRECHECK

```bash
cd /root/Projeto-StudioSat-Web-Radios-e-TVs-
git fetch origin
git checkout main
git pull --ff-only
git status --short
git rev-parse HEAD
git log -8 --oneline
```

Se o working tree estiver alterado ou houver commit concorrente ainda não revisado, STOP e retornar ao SYNC.

Depois:

```bash
bash -n candidates/CHG-004X/studiosat-full-rayx-v2.sh
echo "BASH_N_EXIT=$?"
sha256sum candidates/CHG-004X/studiosat-full-rayx-v2.sh
```

`BASH_N_EXIT` deve ser `0`.

## EXECUTE

```bash
sudo bash candidates/CHG-004X/studiosat-full-rayx-v2.sh
```

## Saída esperada

```text
ARCHIVE=/tmp/studiosat-full-rayx-<host>-<timestamp>.tar.gz
ARCHIVE_SHA256=/tmp/studiosat-full-rayx-<host>-<timestamp>.tar.gz.sha256
READ_ONLY=YES
```

## Pós-execução

1. verificar SHA do archive;
2. enviar `.tar.gz` + `.sha256` em canal privado;
3. não publicar pacote bruto no GitHub público;
4. não reiniciar Country;
5. Engenharia Rádio/Core analisará o pacote integral;
6. reler `main` e mudanças da Engenharia TV;
7. publicar relatório sanitizado;
8. reescrever matriz P0/P1/P2, registry e Change Queue conforme necessário;
9. reavaliar integralmente `RADIO_IMPLEMENTATION_PLAN` e `SHARED_FOUNDATION_HANDOFF_TO_TV`;
10. somente então liberar o primeiro comando mutável.

## Gate de conclusão

CHG-004X fecha somente quando a análise produzir uma decisão explícita para:

- Country;
- Rock;
- Principal/Pop/Clássicas;
- generator/playlist;
- canonical/ready;
- engine Rádio;
- MediaMTX;
- NGINX/TLS;
- ingest/Samba;
- systemd;
- security;
- pontos compartilhados com TV;
- sequência revisada de implantação.
