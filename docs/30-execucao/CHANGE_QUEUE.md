# StudioSat Web — Change Queue

Regra: **uma alteração ativa por vez no host de produção**. Engenharia de TV e Rádio podem preparar documentação/candidates em paralelo, mas apenas uma change pode modificar o host por vez.

Protocolo obrigatório: `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`.

Diretriz vigente: **IN-PLACE FIRST / NO CONTAINERS / NO VMs / NO DUPLICATE PLATFORM**.

## Baseline oficial

CHG-004B está **DONE / PASS / LOCKED** com snapshot `2026-09-10T16:57:41Z`.

## Prioridade operacional vigente

Por determinação mais recente do owner em `2026-09-10`, a prioridade mutável imediata passa a ser **colocar as cinco emissoras de Rádio Studio Sat no ar publicamente, com áudio funcional e player/portal corretos**. A trilha TVKIDS permanece preservada no GitHub e volta à prioridade assim que a recuperação pública das rádios fechar ou for revertida.

A recuperação Rádio deve continuar **uma estação por vez** internamente. A alteração compartilhada de NGINX só ocorre depois de as cinco saídas HLS locais passarem e deve preservar os hostnames e serviços de TV.

## Trilha crítica atual

| ID | Mudança | Dono | Estado | Gate |
|---|---|---|---|---|
| CHG-R01 | Principal — escaping/playlist atômica | Rádio | **APPLY PASS / ROTATION FINAL PENDING** | generator e playlist corrigidos; MediaMTX/RTSP PASS; 0 Impossible/NO_READY pós-fix |
| CHG-R02 | Rock — recovery legado | Rádio + Core | **RECOVERY EXECUTADA / validar na matriz final** | playlist de 10 itens e publicação observada em evidência posterior |
| CHG-R03 | Cinco rádios — AAC-LC 48 kHz estéreo + HLS real | Rádio + Core | **READY / PRIORIDADE ATIVA** | `apply-all-radios-aac-hls-v1.sh`; restart uma rádio por vez; RTSP AAC + HLS local/público por estação |
| CHG-RWEB01 | Radio Web — player sem www + portal com www + NGINX isolado | Rádio + Core | **READY APÓS CHG-R03 PASS** | webroots isolados já implantados; remover apenas hostnames Rádio dos blocos compartilhados; preservar TVs; nginx -t + reload + matriz pública |
| CHG-TVKIDS-001 | Reconstrução integral da cadeia TVKIDS | TV | **PAUSED / PRESERVADA PELO OVERRIDE DO OWNER** | pacote permanece intacto no GitHub; retomar após Rádio |
| CHG-R04 | Separação generator Rádio/TV | Rádio + TV + Core | **PENDENTE** | preservar isolamento por domínio |
| CHG-TV-002+ | TVTEENS/TVVIVA/TVMAISJOVEM | Engenharia TV | **PENDENTE** | retomar pela trilha TV após TVKIDS |

## Diagnóstico que determina CHG-R03

As cinco paths chegaram a ser observadas `ready=true` / `online=true` no MediaMTX, mas o HLS direto em `127.0.0.1:8888/<radio>/index.m3u8` termina em HTTP 500 com:

```text
{"status":"error","error":"muxer is waiting to be created"}
```

A publicação Rádio legado usa MPEG-1/2 Audio (MP3). Para a saída HLS atual do MediaMTX, o profile Rádio passa a AAC-LC 48 kHz estéreo. A mudança não reinicia MediaMTX nem NGINX e reinicia somente uma rádio de cada vez, com rollback do playout comum caso um gate falhe.

Candidates:

```text
candidates/CHG-R03/tps-playout-radio-v3-aac-all.sh
candidates/CHG-R03/apply-all-radios-aac-hls-v1.sh
```

## CHG-RWEB01 — identidade pública

Sem `www`:

```text
radio.studiosatweb.com.br
radioprincipal.studiosatweb.com.br
radiopop.studiosatweb.com.br
radiorock.studiosatweb.com.br
radioclassicas.studiosatweb.com.br
radiocountry.studiosatweb.com.br
```

Servem o **player de tela cheia**, com Play/Pause, volume, mute/alto-falante, fullscreen e seleção de emissora.

Com `www`:

```text
www.radio.studiosatweb.com.br
www.radioprincipal.studiosatweb.com.br
www.radiopop.studiosatweb.com.br
www.radiorock.studiosatweb.com.br
www.radioclassicas.studiosatweb.com.br
www.radiocountry.studiosatweb.com.br
```

Servem o **portal editorial Radio Studio Sat**, em fundo cinza-claro, com player fixo inferior e navegação entre as cinco emissoras.

Webroots isolados já criados no host:

```text
/var/www/studiosat-radio-player
/var/www/studiosat-radio-portal
```

O NGINX legado ainda mistura Rádio e TV em `/etc/nginx/conf.d/tps-9-emissoras.conf`; CHG-RWEB01 remove somente os FQDNs Rádio dessas quatro linhas `server_name`, mantém os FQDNs TV no bloco legado e instala um bloco Rádio dedicado.

Candidates:

```text
candidates/CHG-RWEB01/player/index.html
candidates/CHG-RWEB01/portal/index.html
candidates/CHG-RWEB01/nginx-radio-isolated-v1.conf
candidates/CHG-RWEB01/deploy-radio-web-isolated-v2.sh
candidates/CHG-RWEB01/apply-radio-public-web-v3.sh
```

## Execução autorizada agora

A forma preferencial é o executor único:

```text
candidates/CHG-RADIO-NOW/restore-five-radios-and-web-v1.sh
```

Ele executa, nesta ordem:

1. CHG-R03: cinco rádios para AAC/HLS, uma por vez, com validação por estação;
2. refresh dos webroots Rádio isolados;
3. CHG-RWEB01: split NGINX Rádio/TV, `nginx -t`, reload e validação pública;
4. matriz final exigindo as cinco rádios `active`, MediaMTX `ready=true`, HLS HTTP 200 + `#EXTM3U`, todos os roots sem/com `www` em HTTP 200.

Se qualquer fase falhar, a execução deve parar no `FATAL=` correspondente; não iniciar outra mutação manual em paralelo.
