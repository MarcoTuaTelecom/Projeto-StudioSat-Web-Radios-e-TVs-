# StudioSat Web — Arquitetura Mestra da Plataforma v1.0

## Regra-mãe

O StudioSat Web deve parecer uma única plataforma para operação e distribuição, mas não deve virar um único processo, um único perfil de mídia ou um único engine.

**Compartilhar infraestrutura; isolar domínio de falha; nunca fundir semânticas diferentes.**

## Hierarquia

```text
StudioSat Web Core
├── Radio Studio Sat
│   ├── Principal
│   ├── Pop
│   ├── Rock
│   ├── Clássicas
│   └── Country
└── Televisão
    ├── TVKIDS / TVKIDS Web
    ├── TVTEENS
    ├── TVVIVA
    └── TVMAISJOVEM
```

## O que converge

- MediaMTX como router/distribuidor;
- NGINX/TLS como edge/origin;
- systemd policy e templates;
- observabilidade;
- backup e rollback;
- segurança;
- inventário/catálogo base;
- framework de ingest/QC;
- contratos de Station/Event/Profile/Health;
- CDN e futura redundância.

## O que pode ser padronizado, mas deve permanecer isolado

- diretórios por estação;
- units/cgroups;
- logs;
- estado;
- rollback;
- profile selection;
- health por canal;
- pipelines de ingest.

## O que é proibido fundir

- engine de playout;
- canonical profile;
- scheduler/relógio editorial;
- live semantics;
- fallback;
- playback behavior;
- metadata específica;
- QC temporal específico;
- output model.

## Base factual do host

Snapshot de 09/09/2026:

- Ubuntu 24.04.4 LTS em Google Compute Engine;
- 2 vCPU;
- ~7,8 GiB RAM, ~6,8 GiB disponíveis no snapshot;
- sem GPU física detectada;
- FFmpeg 6.1.1;
- MediaMTX ativo;
- NGINX ativo em 80/443;
- 9 canais configurados: 5 rádios + 4 TVs;
- novos engines não estavam instalados no baseline;
- playout atual majoritariamente leve por stream-copy.

Esse estado deve sempre ser reconfirmado pelo preflight antes de qualquer mudança.

## Arquitetura-alvo

```text
                         STUDIO SAT WEB CORE
                identidade • catálogo • políticas
                API • observabilidade • segurança
                              │
                 ┌────────────┴────────────┐
                 │                         │
         RADIO MEDIA PLANE          TV MEDIA PLANE
         engines isolados           engines isolados
                 │                         │
                 └────────────┬────────────┘
                              │
                           MediaMTX
                              │
                            NGINX
                              │
                         CDN / Internet
                              │
                  portais • players • apps
```

## Rádio — semântica

- áudio contínuo é prioridade;
- vídeo é sincronizado e adaptativo;
- app em background usa áudio-only;
- foreground/TV pode usar A/V;
- locutor/câmera e videoclipe pertencem à mesma timeline;
- comerciais e vinhetas também são eventos audiovisuais;
- falha de vídeo não pode derrubar o áudio;
- um scheduler de áudio separado de vídeo é proibido.

## TV — semântica

- continuidade A/V é prioridade;
- frame rate, resolução e timebase são determinísticos;
- áudio deve existir no asset canônico;
- filler é audiovisual;
- canonicalização e correções pesadas acontecem offline;
- playout de produção prefere `-c copy` quando possível.

## Ingest/QC comum

```text
incoming
→ probe
→ identificar domain/profile
→ normalização offline
→ probe pós-normalização
→ decode integral
→ hash/inventário
→ QC específico do domínio
→ canonical
→ READY manifest
```

A ferramenta pode ser comum, mas cada job deve declarar:

```yaml
channel: string
media_domain: radio | tv
profile_version: string
asset_role: string
```

## MediaMTX

MediaMTX não decide programação.

- publishers locais devem usar loopback quando possível;
- HLS origin e API/métricas devem ser internos quando compatível;
- live remoto deve usar ingress autenticado/ACL específico;
- não fechar RTMP globalmente antes de mapear todos os publishers remotos;
- paths LAB nunca reutilizam paths de produção.

## NGINX

- camada comum de TLS/origin;
- vhosts e rotas explícitos;
- nenhuma lógica editorial no proxy;
- `nginx -t` antes de reload;
- manifest HLS e segmentos podem receber políticas de cache diferentes;
- CDN é o caminho de escala, não multiplicar encode no origin.

## systemd

```text
tps-media.slice
├── tps-radio.slice
│   └── uma unit por estação
└── tps-tv.slice
    └── uma unit por estação
```

Compartilhar template não significa compartilhar processo.

## Segurança

- público: NGINX 80/443 e administração controlada;
- APIs internas em loopback quando possível;
- credenciais por estúdio/canal;
- não reutilizar stream key global;
- não ativar protocolos sem caso de uso;
- Samba/139/445 deve ser validado antes de restringir/desabilitar;
- firewall só depois de mapear publishers e workflow de ingest.

## Performance

A arquitetura deve preservar a leveza do `-c copy` e evitar encode contínuo desnecessário.

- 2 vCPU não são base segura para vários transcodes A/V simultâneos;
- canonicalização é offline;
- live deve chegar idealmente já em perfil adequado;
- audiência escala via CDN;
- HA real exige segundo host/origin, não scripts adicionais no mesmo servidor.

## Blast radius

Falha de uma emissora não pode afetar outra. Falha de MediaMTX/NGINX tem impacto multi-canal, então componentes compartilhados devem ser pequenos, estáveis, observáveis e futuramente redundantes.

## Governança

Qualquer mudança de Core exige:

1. candidate/diff;
2. validação específica;
3. impacto em TV e Rádio conhecido;
4. rollback disponível;
5. teste em lab;
6. uma mudança por vez;
7. health antes/depois.

## Diretiva final

**StudioSat Web é uma plataforma única, mas não um sistema monolítico. A convergência correta é por contratos, infraestrutura e governança; não pela fusão dos engines, profiles ou relógios editoriais.**
