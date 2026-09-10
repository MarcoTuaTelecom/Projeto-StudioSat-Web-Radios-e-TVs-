# StudioSat Web — Dependency Map AS-IS v1.0

Status: **OFICIAL — derivado do FULL RAY-X v3.1**  
Data: 2026-09-10

## Cadeia compartilhada observada

```text
OPERADOR / INGEST
       │
       ├── filesystem / Samba (quando usado)
       │
       ▼
/srv/tpsmedia/repository/channels/<station>/
       │
       ├── ready/
       ├── canonical/
       └── playlists/playlist.txt
       │
       ▼
PLAYLIST GENERATOR via ExecStartPre
       │
       ├── global /usr/local/sbin/tps-generate-playlist
       └── radioprincipal usa generator especial por drop-in
       │
       ▼
PLAYOUT SCRIPT via ExecStart
       │
       ├── Rádio: /usr/local/sbin/tps-playout-radio <station>
       └── TV:    /usr/local/sbin/tps-playout-tv <station>
       │
       ▼
FFmpeg 6.1.1
       │
       ├── Rádio: map áudio + copy → FLV/RTMP
       └── TV: map vídeo+áudio + copy → FLV/RTMP
       │
       ▼
rtmp://127.0.0.1:1935/<station>
       │
       ▼
tps-mediamtx.service
       │
       ├── production path por station
       ├── RTSP
       ├── HLS quando codec compatível
       ├── WebRTC/SRT listeners existentes
       └── API local 127.0.0.1:9997
       │
       ▼
NGINX 80/443 + TLS
       │
       ▼
portais/domínios/players
```

## Dependências por station

| Station | Unit | ExecStartPre | ExecStart | Publish path | Estado AS-IS |
|---|---|---|---|---|---|
| radioprincipal | `tps-radioprincipal-playout.service` | generator especial | `tps-playout-radio radioprincipal` | `radioprincipal` | active/degraded |
| radiopop | `tps-radiopop-playout.service` | generator global | `tps-playout-radio radiopop` | `radiopop` | active |
| radiorock | `tps-radiorock-playout.service` | generator global | `tps-playout-radio radiorock` | `radiorock` | failed |
| radioclassicas | `tps-radioclassicas-playout.service` | generator global | `tps-playout-radio radioclassicas` | `radioclassicas` | active |
| radiocountry | `tps-radiocountry-playout.service` | generator global | `tps-playout-radio radiocountry` | `radiocountry` | active |
| tvkids | `tps-tvkids-playout.service` | generator global | `tps-playout-tv tvkids` | `tvkids` | active/degraded, TV-owned |
| tvteens | `tps-tvteens-playout.service` | generator global | `tps-playout-tv tvteens` | `tvteens` | active, TV-owned, restart interlock |
| tvviva | `tps-tvviva-playout.service` | generator global | `tps-playout-tv tvviva` | `tvviva` | active, TV-owned, restart interlock |
| tvmaisjovem | `tps-tvmaisjovem-playout.service` | generator global | `tps-playout-tv tvmaisjovem` | `tvmaisjovem` | active, TV-owned, restart interlock |

## Componentes que criam blast radius compartilhado

### 1. `tps-generate-playlist`

É chamado por Rádio e TV e atualmente possui semântica de `ready/` e filtragem de `test/teste`. Uma alteração nele pode mudar o comportamento do próximo restart de várias stations. **É o maior acoplamento de aplicação identificado.**

Regra: antes de qualquer edição, separar a semântica Rádio e TV por Change coordenada; nunca alterar o global para resolver apenas uma station.

### 2. MediaMTX

Todos os publishers atuais entram no mesmo daemon. Reiniciar MediaMTX afeta as stations publicadas mesmo que cada playout tenha processo próprio.

Regra: mudança global exige impacto cruzado, health das 9 stations e rollback. Não reiniciar MediaMTX para corrigir uma station.

### 3. NGINX/TLS

Todos os portais e rotas públicas dependem do mesmo NGINX/listeners 80/443 e de certificados compartilhados.

Regra: `candidate → nginx -t → health origin → reload → health público`.

### 4. Filesystem `/srv/tpsmedia/repository/channels`

É a base única de mídia. Não criar segunda biblioteca. Cada domínio só altera sua station; mudanças de ownership/permissão no ancestral são Core changes.

### 5. FFmpeg do sistema

Rádio e TV usam `/usr/bin/ffmpeg`. Upgrade major global pode afetar todas as stations.

Regra: manter 6.1.1 enquanto não existir Change explícita com benchmark e rollback. Nenhuma ferramenta candidata pode impor upgrade silencioso.

### 6. Samba/ingest

Pode escrever no filesystem usado pelo playout. Segurança e ownership de ingest são Core; workflow editorial é por domínio.

## Limites de ownership

```text
CORE
├── MediaMTX global
├── NGINX/TLS
├── firewall/ports
├── Samba compartilhado
├── registry/health envelope
├── shared systemd policy
└── Change Queue

RÁDIO
├── radio generator
├── radio playlist/timeline
├── radio playout
├── radio canonical/QC
├── A/V + audio-only
├── metadata/fallback
└── live Rádio

TV
├── TV generator/playlist semantics
├── TV canonical/QC
├── TV engine/timeline/filler
└── live TV
```

## Regra antirregressão

Uma change em Rádio deve poder provar:

- arquivos Core fora do escopo mantiveram hash;
- services TV não sofreram restart involuntário;
- MediaMTX/NGINX permaneceram saudáveis quando não pertencem ao escopo;
- station IDs e production paths permaneceram estáveis.

Uma change TV deve aplicar a mesma regra em sentido inverso.

Este mapa é a referência obrigatória para avaliar blast radius antes de cada execução.