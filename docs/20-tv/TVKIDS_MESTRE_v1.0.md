# TVKIDS / TVKIDS Web — Documento Mestre v1.0

## Objetivo

Transformar o fluxo de TV atual em uma cadeia de broadcast determinística, preservando a produção existente e usando a TVKIDS como primeiro modelo validado da vertical TV.

## Princípios

1. Uma emissora = um domínio de falha.
2. MediaMTX e NGINX podem ser compartilhados; processo, playlist, estado, mídia, logs e rollback são por canal.
3. Playout de produção não deve normalizar mídia em tempo real.
4. `ready` deve significar “apto para ir ao ar”.
5. Mudanças de playlist devem ser atômicas.
6. Health mede HLS/stream real, não apenas PID.
7. Não migrar todas as TVs simultaneamente.

## Perfil canônico TVKIDS v1

- Container: MP4
- Vídeo: H.264/AVC
- Resolução: 1280x720
- Aspecto: 16:9 sem stretch
- FPS: 30 CFR
- Pixel format: yuv420p
- Video timebase: 1/90000
- Áudio: AAC-LC
- Sample rate: 48000 Hz
- Canais: stereo / 2
- Áudio ausente: proibido; gerar silêncio estéreo offline se necessário
- Playout: stream copy
- Metadata: opcional, sem streams extras inesperados

## Pipeline de ingest/QC

```text
incoming
→ probe estrutural
→ normalização offline
→ probe pós-normalização
→ decode integral
→ QC/hash
→ canonical
→ READY manifest
```

Normalização nunca sobrescreve origem; escreve temporário, valida e publica atomicamente.

## Playlist segura

```text
candidate.ffconcat
→ validar
→ previous.ffconcat = current anterior
→ mv candidate → current no mesmo filesystem
```

Preflight obrigatório:
- paths existem;
- todos pertencem a canonical;
- todos possuem áudio;
- assinaturas estruturais compatíveis;
- nenhum arquivo vazio;
- nenhum item em incoming/quarantine;
- ao menos um item;
- candidate diferente da atual quando houver mudança.

## Playout Stage-1

Enquanto assets forem canônicos e compatíveis:

```bash
ffmpeg -hide_banner -loglevel warning -nostdin \
  -re -stream_loop -1 \
  -f concat -safe 0 \
  -i /srv/tpsmedia/repository/channels/tvkids/playlists/current.ffconcat \
  -map 0:v:0 -map 0:a:0 \
  -c copy \
  -f flv rtmp://127.0.0.1:1935/tvkids
```

Não colocar no playout principal:
- libx264;
- scale;
- fps;
- aresample;
- loudnorm;
- geração de silêncio;
- correção de aspecto.

Essas funções pertencem ao ingest offline.

## TV Engine Contract

### Current
FFmpeg + ffconcat.

### Stage-1
FFmpeg + canonical + `-c copy`.

### Future candidate
ffplayout / engine profissional / outro, apenas se benchmark provar benefício operacional sem regressão de performance/continuidade.

O Core depende de `TvEngineAdapter`, não de flags específicas do FFmpeg.

## Isolamento

Cada TV mantém:
- processo;
- systemd unit;
- cgroup;
- playlist;
- estado;
- diretório de mídia;
- logs;
- limites;
- rollback.

Infraestrutura compartilhável:
- MediaMTX;
- NGINX/TLS;
- observabilidade;
- framework de ingest/QC;
- templates systemd.

## TVKIDS LAB — ordem

1. Não reiniciar TVKIDS antes do canonical estar validado.
2. Criar backup/snapshot.
3. Hash/inventário profundo de canonical.
4. Decode integral em baixa prioridade, fora de pico.
5. Corrigir/quarentenar qualquer canonical que falhe.
6. Gerar `candidate.ffconcat` apenas com canonical aprovado.
7. Publicar em path LAB separado, preferencialmente `lab-tv-tvkids-av`.
8. Observar múltiplas transições.
9. Meta: zero `Non-monotonic DTS`.
10. Fazer cutover apenas da TVKIDS em janela monitorada.
11. Observar 24 h.
12. Manter rollback imediato.

## Health TV

Além do envelope comum:
- vídeo presente;
- áudio presente;
- resolução esperada;
- FPS esperado;
- timestamp/timebase íntegros;
- HLS manifest recente;
- segmento recente;
- filler pronto;
- erros DTS = 0 em produção canônica.

## SLOs iniciais

- disponibilidade do playout > 99,9% após estabilização;
- Non-monotonic DTS = 0;
- arquivo sem áudio em TV = 0;
- perfil fora do canonical em READY = 0;
- restart em cascata = 0;
- queda de uma emissora afetando outra = 0;
- transcode no playout normal = 0;
- mídia não certificada no ar = 0.

## Replicação

Somente depois da TVKIDS comprovada:

```text
TVKIDS → TVTEENS → TVVIVA → TVMAISJOVEM
```

Uma por vez, cada uma com seu canonical, QC, lab, cutover, health e rollback próprios.

## ffplayout

Não é requisito para corrigir a plataforma atual. Deve ser avaliado depois da estabilização do canonical, em ambiente adequado, comparando:
- CPU/RAM;
- continuidade;
- scheduling;
- filler;
- recuperação;
- operação 24/7;
- capacidade de controlar várias instâncias isoladas.

Se apenas substituir um FFmpeg leve por mais complexidade, não adotar.
