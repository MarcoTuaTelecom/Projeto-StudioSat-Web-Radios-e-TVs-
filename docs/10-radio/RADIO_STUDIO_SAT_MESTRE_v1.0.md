# Radio Studio Sat — Documento Mestre v1.0

## Produto

Radio Studio Sat é uma única experiência pública de marca com múltiplas emissoras temáticas. O usuário seleciona gênero, mas internamente troca de estação.

Emissoras atuais:

- radioprincipal
- radiopop
- radiorock
- radioclassicas
- radiocountry

Cada uma possui programação, locutor, publicidade, biblioteca e identidade editorial próprias.

## Regra fundamental

Cada emissora é audiovisual. Não existe uma “rádio” e uma “TV da rádio” separadas.

```text
EMISSORA
├── timeline editorial única
├── música
├── videoclipe
├── locutor/câmera
├── comerciais
├── vinhetas
├── metadata
├── fallback
├── saída A/V
└── saída áudio-only
```

## Experiência por dispositivo

- mobile foreground: A/V quando permitido;
- mobile background/tela apagada: áudio-only;
- web desktop: A/V com opção áudio-only;
- TV app: A/V contínuo;
- veículo: áudio obrigatório; vídeo apenas onde plataforma/política permitir.

Trocar de A/V para áudio-only não pode trocar `station_id`, `event_id` nem selecionar outro conteúdo.

## Estado atual legado

Fluxo observado no baseline:

```text
ready/
→ tps-generate-playlist
→ ffconcat playlist
→ tps-<radio>-playout.service
→ tps-playout-radio
→ FFmpeg
→ RTMP 127.0.0.1:1935/<canal>
→ MediaMTX
→ NGINX
→ Internet
```

FFmpeg legado permanece até cada cutover.

## Riscos conhecidos do snapshot

- heterogeneidade 44,1/48 kHz e mono/stereo em algumas rádios;
- attached-picture MJPEG não é vídeo operacional;
- radiorock apareceu FAILED em snapshot anterior;
- radioprincipal possuía exceção de gerador;
- health de processo não prova stream real;
- host de 2 vCPU/sem GPU não deve fazer cinco transcodes A/V pesados em runtime.

Tudo deve ser reconfirmado pelo Core preflight.

## Princípios

1. Um relógio editorial por estação.
2. A/V + áudio-only da mesma fonte/estado.
3. Canonicalizar antes do ar.
4. Copy/remux sempre que seguro.
5. Uma instância/processo por gênero.
6. Engine programa; MediaMTX distribui; NGINX publica.
7. Fallback é editorial, não restart loop.
8. Health mede produto.
9. Migração por shadow.
10. URLs públicas podem permanecer estáveis durante mudança de backend.

## Engine

### Current
FFmpeg + playlist legado.

### Candidate
Liquidsoap 2.4.x.

### Selected
Somente depois de gates de aceitação.

O contrato da plataforma é `RadioEngineAdapter`; Liquidsoap é a primeira implementação candidata.

## Modelo de evento

```yaml
event_id: string
station_id: string
type: music | live | ad | jingle | program | fallback
planned_start: timestamp
duration: number | open-ended
audio_asset: string | null
video_asset: string | null
fallback_visual: string | null
metadata: {}
priority: number
transition: string
```

## Perfil de laboratório inicial

Proposta a validar, não contrato definitivo:

- MP4 para assets A/V;
- H.264/AVC;
- 1280x720;
- 30 fps CFR;
- yuv420p;
- GOP 2 s;
- AAC-LC;
- 48 kHz;
- stereo;
- áudio ~128 kbps no lab;
- vídeo ~2–2,5 Mbps no lab;
- loudness medido no ingest.

Música sem clipe deve receber visual aprovado por conformação offline para evitar criação de vídeo pesada no on-air.

## Ingest/QC Rádio

```text
upload
→ incoming
→ ffprobe
→ inválido: quarantine
→ fora do profile: conformação offline
→ QC
→ canonical
→ aprovação editorial
→ READY
→ engine
```

Mínimos:
- tracks esperados;
- codec/resolução/FPS/audio layout corretos;
- duração A/V coerente;
- timestamps sem erro crítico;
- áudio não silencioso salvo marcação explícita;
- metadata obrigatória;
- checksum;
- arquivos de teste fora de READY.

## Live

Live é fonte de primeira classe.

```text
câmera + mesa/mic
→ encoder H.264/AAC
→ ingress autenticado
→ RadioEngineAdapter
→ prioridade live
→ switch/fallback
→ A/V + áudio-only
```

Regras:
- timeout;
- fallback automático;
- entrada/saída sem restart;
- metadata muda com estado live;
- áudio-only vem da mesma fonte live;
- credenciais em secrets, nunca no repo.

## Metadata

Rádio precisa de:

- artista;
- faixa;
- álbum;
- gênero;
- locutor;
- programa;
- artwork;
- campanha/comercial;
- estado AUTO/LIVE/FALLBACK.

Attached picture é artwork/metadata, não vídeo da emissora.

## Health Rádio

Além do envelope comum:

- A/V publicado;
- áudio-only publicado;
- freshness dos dois;
- áudio detectado;
- metadata age;
- silêncio inesperado;
- live/fallback state;
- codecs/perfil.

## Migração

Primeiro candidato: Country, devido à homogeneidade observada no snapshot.

Ordem inicial sugerida:

```text
Country → Pop → Clássicas → Rock → Principal
```

Pode mudar após novo preflight.

## Country LAB

1. Produção Country permanece intacta.
2. Criar árvore `/srv/studiosat/radio/lab/country/`.
3. Instalar engine candidato somente se não conflitar com libs do host.
4. Criar corpus: 3 clips + comercial + vinheta + fallback.
5. Publicar `lab-radio-country-av` e `lab-radio-country-audio`.
6. Validar A/V e áudio-only.
7. Testar foreground/background.
8. Introduzir falhas deliberadas.
9. Adicionar live.
10. Shadow da grade real ≥24 h.
11. Passar Core Compatibility Gate.
12. Cutover apenas Country.
13. Observar 24–72 h.
14. Manter legado para rollback.

## Critérios de aceitação

- 24 h sem interrupção perceptível;
- A/V decodifica corretamente;
- áudio-only sem vídeo e alinhado à mesma programação;
- foreground/background não muda estação;
- asset ausente/corrompido gera fallback;
- live entra/sai sem restart;
- now playing correto;
- publicidade correta por estação;
- falha de um gênero não afeta outros;
- health detecta stream morto/stale/silêncio/metadata stale;
- CPU mantém margem;
- rollback em minutos.

## Rollback

Novo path falhou:

```text
reverter roteamento para path antigo
→ validar HLS/player antigo
→ parar apenas unit nova
→ coletar logs
→ corrigir lab
→ novo shadow
```

Não remover mídia/playlist antiga no dia do cutover.
