# StudioSat Web — Runbook Mestre de Execução

## Contexto

O servidor já possui 9 canais configurados: 5 rádios e 4 TVs. A modernização não será feita sobrepondo a produção. Cada mudança deve ser reversível, isolada e validada por gates.

## Regra operacional principal

> Não reconstruir por cima. Construir ao lado, provar em laboratório, migrar uma emissora por vez e manter rollback imediato.

## Fase 0 — Freeze + snapshot + preflight

### Objetivo
Fotografar o estado real do host antes de qualquer mudança.

### Ações
1. Congelar alterações não essenciais.
2. Criar snapshot da VM/disco no Google Cloud.
3. Guardar backup privado das configurações críticas.
4. Instalar apenas o script `scripts/studiosat-core-preflight.sh` em `/root`.
5. Validar sintaxe:

```bash
sudo bash -n /root/studiosat-core-preflight.sh
```

6. Executar:

```bash
sudo /root/studiosat-core-preflight.sh
```

7. Guardar o `.tar.gz` e `.sha256` shareable.
8. Confirmar que nenhum serviço mudou de estado.

### Gate F0
- produção permanece igual;
- pacote de evidência existe;
- nenhum restart/reload ocorreu.

**Parar aqui até análise do pacote.**

## Fase 1 — Rebaseline + channels-registry

A partir da evidência real:

- identificar as 9 units reais;
- mapear paths MediaMTX;
- mapear publishers/readers;
- mapear playlists/schedules;
- mapear diretórios de mídia;
- mapear endpoints públicos;
- classificar cada canal como HEALTHY/DEGRADED/FAILED;
- classificar riscos P0/P1/P2.

Criar `registry/channels-registry.yaml` com o contrato definido em `docs/00-core/CORE_CONTRACT_v0.1.md`.

### Gate F1
Todos os canais têm identidade, domínio, implementação atual, media root, paths, endpoints e owner conhecidos.

## Fase 2 — Health comum em modo somente leitura

Implementar primeiro health sem alterar playout:

Comum:
- systemd/PID;
- publisher MediaMTX;
- HLS HTTP;
- freshness;
- bytes/atividade;
- erros críticos.

Extensão TV:
- vídeo;
- áudio;
- FPS;
- resolução;
- integridade temporal/DTS;
- filler readiness.

Extensão Rádio:
- áudio;
- A/V;
- áudio-only;
- metadata;
- live state;
- silêncio inesperado.

### Gate F2
Os 9 canais possuem status baseado no produto final, não apenas em `systemctl is-active`.

## Fase 3 — Corrigir incidentes P0 do legado

Antes da modernização, reparar somente incidentes atuais que prejudiquem a operação.

Exemplo histórico: `radiorock` apareceu FAILED em snapshot anterior. Reconfirmar antes de agir.

Regras:
- não instalar novo engine para resolver incidente legado;
- corrigir uma estação por vez;
- manter rollback;
- não tocar em componentes Core desnecessariamente.

## Fase 4 — TVKIDS canonical / TVLAB

Primeiro piloto de TV: provar canonical, QC, playlist atômica e `-c copy`, sem instalar engine novo.

### Sequência
1. Hash/inventário profundo de `tvkids/canonical` e candidatos.
2. Decode integral fora de pico, baixa prioridade.
3. Rejeitar/quarentenar qualquer asset inválido.
4. Gerar `candidate.ffconcat` somente com mídia aprovada.
5. Publicar no path de laboratório `lab-tv-tvkids-av` ou nome aprovado pelo registry.
6. Observar múltiplas transições.
7. Meta: zero `Non-monotonic DTS`.
8. Medir CPU/RAM/freshness.
9. Cutover somente da TVKIDS em janela controlada.
10. Observar 24 h.

### Gate TVKIDS
- HLS saudável;
- vídeo+áudio íntegros;
- zero regressão temporal;
- CPU estável;
- rollback testado.

## Fase 5 — Radio Country LAB

Primeiro piloto de Rádio: Country.

### Preparação
Criar árvore isolada sem mover produção:

```bash
sudo install -d -o tpsmedia -g tpsmedia -m 0755 \
  /srv/studiosat/radio/lab/country/{incoming,canonical,ready,logs}
```

### Regras de engine
- Liquidsoap 2.4.x é candidato inicial, não obrigação final.
- Não atualizar FFmpeg/libs do sistema apenas para instalar Liquidsoap.
- Se houver conflito de dependência, usar VM/container/ambiente isolado.

### Corpus de teste
- 3 videoclipes A/V;
- 1 comercial;
- 1 vinheta;
- 1 fallback;
- depois live do estúdio.

### Saídas obrigatórias
Mesma timeline editorial:

```text
PROGRAM SOURCE
├── A/V
└── AUDIO-ONLY
```

Paths sugeridos:

```text
lab-radio-country-av
lab-radio-country-audio
```

### Testes
- troca entre assets;
- fallback por falta/corrupção;
- metadata;
- foreground/background;
- live entra sem restart;
- live sai sem restart;
- retorno automático à grade;
- falha do lab não afeta produção;
- shadow da grade real por pelo menos 24 h.

### Gate Country LAB
A/V + áudio-only sincronizados, live/fallback aprovados, produção antiga intacta.

## Fase 6 — Core Compatibility Gate

Antes do primeiro cutover Radio, congelar dependências compartilhadas necessárias à nova Rádio:

- MediaMTX paths;
- publisher local vs ingress remoto;
- ACL/auth;
- portas;
- NGINX/origin;
- TLS;
- health;
- naming;
- rollback.

Não fechar RTMP em loopback até conhecer todos os publishers remotos de Rádio e TV.

### Gate Core
1 TV e 1 Rádio LAB continuam funcionando após qualquer candidate de Core.

## Fase 7 — Cutover Radio Country

1. Capturar configs anteriores.
2. Confirmar old + new streams saudáveis.
3. Mudar somente roteamento/publicação do endpoint Country.
4. Validar web/mobile foreground/mobile background/TV compatível.
5. Observar 24–72 h.
6. Manter FFmpeg legado disponível para rollback.
7. Só depois desabilitar a unit antiga; não apagar.

## Fase 8 — Migrar demais rádios

Ordem inicial sugerida, sujeita ao novo preflight:

```text
Country → Pop → Clássicas → Rock → Principal
```

Principal fica por último por heterogeneidade/exceções históricas.

Sempre:
- lab;
- shadow;
- health;
- cutover;
- observação;
- rollback disponível.

## Fase 9 — Migrar demais TVs

Depois da TVKIDS validada:

```text
TVKIDS → TVTEENS → TVVIVA → TVMAISJOVEM
```

Uma por vez. Cada uma recebe canonical/QC/playlist/health próprios.

## Fase 10 — Padronizar systemd e ingest/QC

Somente após pilotos:

```text
tps-media.slice
├── tps-radio.slice
└── tps-tv.slice
```

Templates podem ser comuns, processos não.

Ingest/QC pode compartilhar framework, mas `profile_id` é explícito e separado por domínio.

## Fase 11 — Control Plane funcional

Construir software de controle somente depois de conhecer os engines comprovados.

O Core fala com:

```text
RadioEngineAdapter
TvEngineAdapter
```

Não incorpora flags internas específicas dos engines.

## Fase 12 — Hardening consolidado

Aplicar mudanças compartilhadas uma por vez:

### MediaMTX
- candidate + validate;
- inventário publisher/reader;
- auth/ACL;
- API/métricas em loopback quando compatível;
- desabilitar protocolos comprovadamente não usados;
- health de todas as stations depois.

### NGINX
- diff/candidate;
- `nginx -t`;
- health origin;
- reload, não restart;
- health público.

### TLS
- um único mecanismo de renovação comprovado.

### Firewall
Somente após mapear publishers, ingest e administração.

## Fase 13 — CDN / HA

Quando audiência ou criticidade justificar:

```text
Origin A + Origin B
MediaMTX A + MediaMTX B
health/failover
CDN
```

Não simular HA criando mais scripts no mesmo host.

## Fase 14 — Descomissionar legado

Somente depois de estabilidade comprovada:

- desabilitar units antigas;
- arquivar scripts históricos;
- preservar rollback versionado por janela definida;
- mover candidatos a quarantine antes de excluir;
- remover código obsoleto em mudanças separadas.

## Fila única de mudanças

Exemplo inicial:

```text
CHG-000 Freeze
CHG-001 Core Preflight
CHG-002 Channels Registry
CHG-003 Core Contract v0.1
CHG-004 Health Read-only
CHG-005 Incidentes P0
CHG-006 TVKIDS LAB
CHG-007 TVKIDS Cutover
CHG-008 Country LAB
CHG-009 Country Live/Shadow
CHG-010 Core Compatibility Gate
CHG-011 Country Cutover
CHG-012 Rádio seguinte
...
```

Engenharia de Rádio e TV podem preparar trabalho em paralelo, mas o host recebe **uma mudança ativa por vez**.
