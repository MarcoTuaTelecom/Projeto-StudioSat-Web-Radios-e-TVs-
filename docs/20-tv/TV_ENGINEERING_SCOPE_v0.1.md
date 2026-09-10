# StudioSat Web — Engenharia de TV — Scope v0.1

## Missão

Modernizar **TVKIDS** primeiro e depois **TVTEENS, TVVIVA e TVMAISJOVEM**, preservando a produção existente e obedecendo ao `CORE CONTRACT v0.1`.

## Autoridade do domínio TV

A Engenharia de TV é responsável por:

- inventário e certificação do canonical TV;
- hash/deduplicação de assets TV;
- decode integral e QC TV;
- candidate playlist/plan;
- continuidade e transições de TV;
- filler/fallback TV;
- live TV;
- `TvEngineAdapter`;
- extensão de health TV;
- rollback por emissora de TV.

## Fora de escopo de edição direta

A Engenharia de TV **não altera isoladamente**:

```text
/etc/nginx
MediaMTX global
firewall
TLS/Certbot global
ports registry
ownership global tpsmedia
slices globais
Core Registry
```

Necessidades nesses componentes entram na **Core Change Queue** e passam por gate conjunto quando afetarem TV + Rádio.

## Station de referência

`tvkids` é a primeira station da vertical TV.

### Perfil Stage-1 TVKIDS

```text
Container: MP4
Vídeo: H.264/AVC
Resolução: 1280x720
FPS: 30 CFR
Pixel format: yuv420p
Áudio: AAC-LC
Sample rate: 48 kHz
Canais: stereo
Playout: stream copy quando certificado
```

O objetivo do Stage-1 é preservar a eficiência do `-c copy`, removendo do on-air a heterogeneidade que hoje causa fragilidade temporal.

## TVKIDS LAB — pacote de engenharia

```text
TVKIDS-LAB/
├── tvkids-profile-v1.yaml
├── qc-tv.sh
├── candidate-playlist-builder.sh
├── tvkids-lab.service.candidate
├── health-tv-extension.sh
├── rollback-tvkids.sh
├── test-plan.md
└── expected-results.md
```

O pacote pode ser desenvolvido sem tocar no host. Execução somente quando a Change Queue liberar a mudança correspondente.

## Critérios mínimos do TVKIDS LAB

- mídia candidata passou hash, probe e decode integral;
- playlist contém apenas assets certificados;
- saída A/V válida;
- HLS fresco;
- múltiplas transições sem erro;
- `Non-monotonic DTS = 0` no período de aceitação;
- CPU/RAM dentro do envelope;
- rollback testável em minutos;
- nenhuma outra station afetada.

## TV Engine

### Current

FFmpeg + ffconcat.

### Stage-1

Canonical + FFmpeg `-c copy`.

### Future candidate

ffplayout / engine profissional / outro, somente se benchmark e teste 24/7 demonstrarem vantagem operacional sem regressão de performance, continuidade ou isolamento.

A plataforma depende do `TvEngineAdapter`, não das flags de uma implementação específica.

## Ordem da vertical TV

```text
TVKIDS → TVTEENS → TVVIVA → TVMAISJOVEM
```

Uma por vez, cada uma com canonical, QC, lab/shadow, gate, cutover, observação e rollback próprios.

## Regra de convivência com Rádio

**Paralelismo de engenharia: SIM. Paralelismo de alteração do host: NÃO.**

TV e Rádio podem preparar código, profiles, testes e documentação simultaneamente, mas mudanças reais no host de produção entram em uma fila única coordenada pelo Core.
