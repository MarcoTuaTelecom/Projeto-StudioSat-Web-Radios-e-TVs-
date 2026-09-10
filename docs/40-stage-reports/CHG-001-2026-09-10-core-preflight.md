# CHG-001 — Core Preflight somente leitura

Status: **PASS / CLOSED**  
Owner: Core  
Execução observada: 2026-09-10T13:01:38Z  
Script executado: `scripts/studiosat-core-preflight.sh` v1.0  
Checkpoint GitHub de referência: `c9a36974ea7322c08c1ed8d9256196c657aeadc7`

## Evidência privada recebida

Arquivo: `studiosat-core-preflight-ns1-20260910T130138Z.tar.gz`

SHA-256 verificado:

```text
7ea85bf48b70efe8de2ee1032b7dbdd7b56a17b79e49aa06e7b1380cefc35c43
```

O `.sha256` recebido confere com o arquivo. O manifesto interno contém 238 arquivos e todos os hashes internos foram verificados sem divergência.

**O pacote bruto não foi commitado no GitHub.** Este relatório é sanitizado.

## Resultado do host

- Host: `ns1.tpsolutions.com.br` / Google Compute Engine.
- OS: Ubuntu 24.04.4 LTS.
- CPU: 2 vCPU AMD EPYC 7B13.
- RAM: 7.8 GiB total; ~6.9 GiB disponível no momento da coleta.
- Disco root: 96 GiB; ~81 GiB disponível.
- Load average: 0.23 / 0.23 / 0.20.
- FFmpeg: 6.1.1 Ubuntu.
- Liquidsoap: não instalado.
- ffplayout: não instalado.
- Docker: não instalado.
- NGINX: ativo; `nginx -t` PASS.
- MediaMTX: `tps-mediamtx.service` ativo.

## Estado real das 9 stations

| Station | systemd | MediaMTX | Output observado |
|---|---|---|---|
| radioprincipal | active | ready | MPEG-1/2 Audio |
| radiopop | active | ready | MPEG-1/2 Audio |
| radiorock | **failed** | **not ready** | sem source |
| radioclassicas | active | ready | MPEG-1/2 Audio |
| radiocountry | active | ready | MPEG-1/2 Audio |
| tvkids | active | ready | H264 High 1280x720 + AAC 48 kHz stereo |
| tvteens | active | ready | H264 High 1280x720 + AAC 48 kHz stereo |
| tvviva | active | ready | H264 High 1280x720 + AAC 48 kHz stereo |
| tvmaisjovem | active | ready | H264 High 1280x720 + AAC 48 kHz stereo |

Resultado: **8 stations publicando/ready; Radio Rock fora do ar no media plane.**

## Processos e arquitetura confirmados

Rádios ativas:

```text
playlist.txt
→ /usr/local/sbin/tps-playout-radio
→ FFmpeg -re -stream_loop -1 -f concat
→ -map 0:a:0 -c:a copy
→ RTMP 127.0.0.1:1935/<station>
→ MediaMTX
```

TVs:

```text
playlist.txt
→ /usr/local/sbin/tps-playout-tv
→ FFmpeg -re -stream_loop -1 -f concat
→ -map 0:v:0 -map 0:a:0 -c copy
→ RTMP 127.0.0.1:1935/<station>
→ MediaMTX
```

Todas as units observadas usam `User=tpsmedia` e permanecem isoladas por processo. Rádio possui MemoryMax 512 MiB / CPUQuota 50%; TV possui MemoryMax 1 GiB / CPUQuota 100%.

## MediaMTX

Confirmado:

- API administrativa: loopback em 9997;
- RTMP/HLS e vários protocolos adicionais: listeners em todas as interfaces;
- HLS Always Remux ativo;
- paths explícitos para as 9 stations;
- 8 paths ready e `radiorock` not ready;
- metrics desabilitado;
- autenticação observada permissiva.

O host não demonstrou filtragem local restritiva: UFW inativo e policy INPUT permissiva. **Isso não prova exposição pública**, porque o preflight não coletou firewall VPC/GCP. A exposição externa deve ser medida antes de qualquer hardening.

## NGINX / TLS

`nginx -t` passou. A configuração confirma dois grupos principais:

- sem `www`: player/tela de emissora + proxy dos paths de mídia;
- com `www`: portais.

Os quatro endpoints-raiz explicitamente testados no preflight retornaram HTTP 200: portal Radio, player Radio, portal TVKIDS e portal TVKIDS Web.

O certificado `studiosatweb-completo` cobre os hostnames StudioSat observados e estava válido durante a coleta. `certbot renew --dry-run` **não foi executado**, corretamente.

## Mídia observada

| Station | ready | canonical |
|---|---:|---:|
| radioprincipal | 19 | 1 |
| radiopop | 11 | 1 |
| radiorock | 1 | 1 |
| radioclassicas | 12 | 1 |
| radiocountry | 19 | 1 |
| tvkids | 13 | 15 |
| tvteens | 1 | 1 |
| tvviva | 1 | 1 |
| tvmaisjovem | 1 | 1 |

Amostras das rádios confirmam `ready/` majoritariamente MP3 48 kHz stereo, com alguns arquivos de teste 44.1 kHz mono. O canonical de teste das rádios é AAC-LC 48 kHz stereo.

Amostras TV canonical confirmam H.264 High 1280x720 30 CFR, yuv420p, timebase vídeo 1/90000 e AAC-LC 48 kHz stereo. As amostras `ready/` das TVs restantes não são equivalentes ao canonical observado.

## Achado crítico: gerador global mudou depois do start das TVs

O `/usr/local/sbin/tps-generate-playlist` atual foi modificado em 2026-09-09 16:25 UTC e agora:

- usa `ready/`;
- aceita `.mp3`, `.m4a`, `.mp4`, `.aac`;
- exclui nomes `teste`/`test`;
- publica playlist atomicamente com temporário + `mv`.

O backup imediatamente anterior usava `canonical/` e aceitava apenas `.m4a`/`.mp4`.

Os quatro processos TV atualmente no ar foram iniciados **antes** da mudança de 16:25. Logo, reiniciar uma TV agora pode regenerar sua playlist com semântica diferente da sessão atual.

**Decisão: não reiniciar nenhuma TV por modernização até o domínio TV validar candidate/canonical.**

## Radio Principal

`radioprincipal` possui drop-in que troca o ExecStartPre global por `/usr/local/sbin/tps-generate-playlist-radioprincipal-fixed`.

A versão observada desse gerador especial escreve diretamente `playlist.txt` e não possui a atomicidade do gerador global atual. Preservar por enquanto; Principal continua por último na migração.

## Radio Rock

Confirmado:

- unit failed;
- MediaMTX not ready;
- único `ready/` observado é arquivo de teste;
- gerador atual exclui esse arquivo;
- journal registra `FATAL=NO_READY_MEDIA:radiorock`.

Nenhuma correção foi realizada durante CHG-001.

## TVKIDS

TVKIDS permanece ativa e ready, mas o journal apresenta `Non-monotonic DTS` persistentemente até poucos minutos antes da coleta. Portanto seu estado preliminar é **DEGRADED**, não HEALTHY.

Isso reforça o plano TVKIDS canonical → QC integral → TVLAB → zero DTS → cutover monitorado.

## Dois falsos negativos do preflight v1.0

### HLS

A coleta marcou `FAIL:302` para os nove paths porque o probe não seguia redirect HTTP. Isso **não é evidência de outage HLS**.

### RTMP read das rádios

`ffprobe rtmp://...` falhou nas rádios, mas a API MediaMTX demonstrou quatro paths de rádio `ready=true`, source RTMP presente, bytes chegando e track MPEG-1/2 Audio.

Logo, `ffprobe RTMP` isolado não será usado como health definitivo de rádio.

## Segurança — achado P0 sanitizado

O preflight revelou uma configuração Samba gravável/guest com privilégio excessivo fora do escopo mínimo de ingest. O detalhe exato permanece na evidência privada para não ampliar superfície de ataque num repositório público.

Antes de remediar:

1. mapear sessões/clientes Samba reais;
2. mapear regra VPC/GCP que controla 139/445;
3. definir share mínimo necessário para ingest;
4. preparar candidate + rollback;
5. executar em change própria.

## Resultado da CHG-001

**PASS.** O objetivo de fotografar a plataforma foi atingido sem mudança intencional de lifecycle/configuração/mídia. O pacote e seu hash são íntegros e suficientes para iniciar o registry real.

A coleta também revelou lacunas no próprio script; elas foram corrigidas na versão canônica v1.1 antes do próximo uso:

- seguir redirects no probe HLS;
- capturar unit real `tps-mediamtx.service`, status/journal/dependências;
- capturar conteúdo/hash da playlist ativa;
- capturar `smbstatus`;
- capturar estado final das units para comparação;
- corrigir comando de versão FFmpeg/NGINX;
- não interpretar probe RTMP de rádio como health absoluto.

## Próximo gate

- CHG-002: `registry/channels-registry.yaml` real — **DONE/PASS**.
- CHG-003: `CORE CONTRACT v0.1` — **Core + Engenharia TV aceitos; aceite formal da Engenharia Rádio ainda pendente**.
- CHG-004: Health read-only — candidate pode ser revisada, mas **execução bloqueada até CHG-003 fechar**.
