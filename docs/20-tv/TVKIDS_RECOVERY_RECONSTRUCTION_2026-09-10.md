# TVKIDS — Reconstrução operacional após execução intercalada — 2026-09-10

## Resumo

O incidente observado não demonstra colapso da TVKIDS. O transcript mistura comandos reais, saídas de comandos posteriormente coladas de volta no shell e execução paralela de uma change do domínio Rádio. A prioridade é reconstruir o estado factual antes de qualquer nova mutação.

## Fatos confirmados do transcript

1. O arquivo `scripts/tv/tvkids-p0-lock-current-and-certify.sh` sofreu somente mudança local de modo `100644 => 100755`.
2. `git restore --worktree` devolveu o arquivo rastreado ao estado do repositório.
3. Um arquivo não rastreado chamado literalmente `100755` apareceu e foi removido com `rm -f -- 100755`.
4. Após essa remoção, `git status --porcelain=v1 -uall` voltou vazio naquele momento.
5. O `git pull --ff-only` trouxe corretamente o relatório P1 e `tvkids-p2-dts-boundary-diagnostic.sh`.
6. A mensagem `Permission denied` associada ao P2 não prova falha do P2. O transcript mostra que uma linha do output do `git pull` foi interpretada como comando direto; o arquivo estava com modo 0644. O método suportado é `bash scripts/tv/tvkids-p2-dts-boundary-diagnostic.sh`.
7. Grande parte dos `command not found` foi produzida porque cabeçalhos, prompt, tabelas, nomes de assets, status do Git e saídas do systemd foram enviados novamente ao Bash como entrada.
8. Uma tentativa de CHG-R01 Rádio Principal abortou no gate `FATAL=GENERATOR_DRIFT`. Esse abort ocorreu no gate de artefato antes da mutação daquela execução.
9. O repositório posteriormente recebeu evidência de outra execução CHG-R01 com resultado imediato PASS, PID Rádio Principal `1383293`, MediaMTX ready e RTSP MP3/48kHz/2ch. A rotação completa permaneceu pendente no relatório.
10. Não há evidência no transcript de que a TVKIDS tenha sido reiniciada durante essa sequência.

## O que não pode ser inferido

O transcript está intercalado e fora de ordem cronológica em vários trechos. Por isso ele não serve como baseline atual para PID, playlist, health, DTS ou configuração NGINX da TVKIDS. Esses pontos precisam ser relidos do host.

## Relação com o P1 TVKIDS

O P1 anterior havia comprovado:

```text
running playlist: 15 canonical / 0 ready
playlist em disco após P1: 15 canonical / 0 ready
SHA comum: 2807c6c604f4601f92b990c047c857519fcb3760c58827ad308be297bcf951d0
PID preservado: 1031405 naquela execução
restart guard: TVKIDS usa canonical; demais canais continuam no comportamento anterior
```

Como houve atividade posterior no host, esses dados passam a ser histórico e serão revalidados antes do P2.

## Causa operacional principal do caos observado

### Contaminação do shell por output

O operador colou no shell blocos que continham simultaneamente:

- comandos;
- prompt `root@ns1:...#`;
- output de `git status` e `git pull`;
- linhas de tabelas;
- nomes de assets;
- output de `systemctl`/`journalctl`.

O Bash tentou executar cada linha como comando. Isso explica `command not found`, `syntax error`, `Permission denied` e o arquivo acidental `100755`.

### Execução intercalada TV + Rádio

Enquanto a trilha TVKIDS estava entre P1 e P2, CHG-R01 da Rádio Principal também foi executada. Isso contraria o propósito da fila única de changes para alterações do host. A execução Rádio não prova regressão TVKIDS, mas invalida a ideia de continuar usando o baseline anterior sem SYNC.

### O `GENERATOR_DRIFT` da Rádio não deve ser atribuído à TV sem prova

O P1 TVKIDS alterou `/usr/local/sbin/tps-generate-playlist`. CHG-R01 validava o generator específico `/usr/local/sbin/tps-generate-playlist-radioprincipal-fixed`. São artefatos distintos. O transcript não contém evidência suficiente para afirmar causalidade entre o P1 TV e o `GENERATOR_DRIFT` daquela tentativa Rádio.

## Reconstrução correta a partir deste ponto

### R0 — Rebaseline read-only

Executar `scripts/tv/tvkids-recovery-rebaseline-v1.sh`.

Ele captura, em uma única execução:

- Git HEAD e working tree;
- processos de changes/observers visíveis;
- systemd/PID/cmdline TVKIDS;
- playlist aberta pelo processo;
- playlist em disco e hashes;
- restart guard do generator;
- inventário canonical/ready;
- MediaMTX path e RTSP;
- HLS local;
- NGINX `-t` e contexto dos 4 FQDNs;
- HTTP de raiz, `/tvkids.html` e HLS nos 4 FQDNs;
- journal TVKIDS 60 min e contagem DTS;
- PIDs das 9 stations + Core;
- gate automático para P2.

### R1 — P2 temporal

Se o rebaseline provar playlist ON-AIR = playlist em disco = canonical, o coordenador executa automaticamente `tvkids-p2-dts-boundary-diagnostic.sh`.

O P2 mede:

- cada asset individual;
- cada boundary A→B;
- boundary último→primeiro;
- playlist 1 ciclo;
- playlist 2 ciclos;
- timing de vídeo/áudio/container;
- DTS do processo ON-AIR.

### R2 — Correção temporal

Somente o resultado P2 determina a mutação:

- DTS dentro de asset → reconformar apenas assets defeituosos offline;
- DTS apenas em boundary → corrigir contrato/timestamps/concat;
- DTS apenas no loop → corrigir semântica de loop;
- offline limpo e ON-AIR com DTS → investigar pacing `-re`, `-stream_loop`, concat/FLV/RTMP e ciclo longo.

### R3 — FQDN/NGINX

Separadamente, corrigir a apresentação pública dos quatro nomes da mesma station `tvkids`, preservando um único stream/path. A candidate NGINX será construída a partir do `nginx -T` atual capturado em R0, seguida de `nginx -t`, reload e verificação dos quatro FQDNs.

### R4 — Restart controlado TVKIDS

Depois de canonical temporalmente aprovado e candidate NGINX aprovado, executar um restart apenas da unit TVKIDS com verificação de:

- PID novo;
- MediaMTX ready;
- RTSP H264/AAC;
- HLS fresco;
- quatro FQDNs;
- zero erro de abertura;
- zero DTS no período de aceitação;
- PIDs das outras stations preservados.

### R5 — Stage Report e baseline novo

Publicar hashes, métricas, estado dos quatro FQDNs, PID, playlist, MediaMTX, NGINX e health. Esse baseline substitui o histórico P1 como ponto de partida da TVKIDS.

## Regra de execução daqui em diante

Cada ação operacional será entregue como um único script versionado no GitHub e invocado explicitamente com `bash caminho/do/script.sh`. O operador precisa copiar apenas o bloco de comando, enquanto todo output é enviado de volta como evidência e nunca reutilizado como entrada do shell.
