# StudioSat Web — Shared Foundation Handoff para Engenharia TV v0.1

Status: **NORMATIVO — INTERFACE ENTRE A FUNDAÇÃO INICIAL E A VERTICAL TV**
Data: 2026-09-10
Owner: Core

## Objetivo

Definir exatamente o que a Engenharia Rádio/Core pode construir primeiro e como a Engenharia TV deve se integrar depois, sem desfazer mudanças, duplicar configurações ou transformar o Core em uma implementação específica de Rádio.

## Princípio

> Core compartilhado deve ser estendido, não substituído.

A Engenharia TV não precisa copiar a arquitetura interna de Rádio. Ela precisa respeitar os contratos e pontos de extensão comuns.

## 1. Namespaces

Reservas permanentes:

```text
Produção existente:
radioprincipal
radiopop
radiorock
radioclassicas
radiocountry
tvkids
tvteens
tvviva
tvmaisjovem

LAB Rádio:
lab-radio-<station>-av
lab-radio-<station>-audio

LAB TV:
lab-tv-<station>-av
```

Nenhuma vertical pode reutilizar namespace da outra.

## 2. MediaMTX

### Core é dono de

- arquivo/configuração global;
- listeners e bindings;
- autenticação global/base;
- defaults;
- métricas/API;
- convenção de paths;
- política de ingress.

### Rádio/TV fornecem

- path desejado;
- protocolo de publish/read;
- necessidade de live;
- ACL/autenticação;
- fallback esperado;
- requisito de latência.

### Regra de integração

A Engenharia TV **não deve substituir o `mediamtx.yml` global** para encaixar suas stations. Necessidades TV entram como candidate Core com diff e gate cruzado.

Paths de produção atuais não serão renomeados apenas para estética.

## 3. NGINX/TLS

### Core é dono de

- listener 80/443;
- política TLS;
- includes compartilhados;
- headers/policies comuns;
- upstream/proxy conventions;
- reload gate.

### Cada domínio pode possuir vhosts próprios

Rádio e TV mantêm server blocks/domain routes específicos, desde que não redefinam defaults globais ou listeners compartilhados de modo incompatível.

### Regra de mudança

```text
candidate/diff
→ nginx -t
→ health origin Rádio + TV de controle
→ reload
→ health público Rádio + TV
```

Nenhuma vertical substitui toda a configuração NGINX para resolver somente seu domínio.

## 4. systemd

Regra permanente:

```text
1 station = 1 unit/processo de playout principal
```

Core pode definir slices/templates/hardening compartilhados. Cada domínio mantém sua unit e seus parâmetros específicos.

Futuro namespace recomendado:

```text
studiosat-radio-<station>.service
studiosat-tv-<station>.service
```

A migração dos nomes legados só ocorre por change própria; os nomes atuais `tps-*` continuam até cutover documentado.

## 5. Filesystem

Estrutura alvo separada por domínio:

```text
/srv/studiosat/
├── core/
├── radio/
│   └── stations/<station>/...
└── tv/
    └── stations/<station>/...
```

A criação desses paths será feita em changes autorizadas. Este documento reserva a estrutura; não declara que ela já existe.

TV não grava dentro de `/srv/studiosat/radio/`; Rádio não grava dentro de `/srv/studiosat/tv/`.

## 6. Registry

Fonte comum:

```text
registry/channels-registry.yaml
```

Cada station possui `station_class`, adapter, profile, outputs e health. A Engenharia TV atualiza seus campos por change/revisão sem alterar semântica de stations Rádio.

## 7. Health

Envelope comum:

```text
station_id
state
last_event
output_freshness
errors
schema_version
```

Extensões separadas:

```text
radio: {...}
tv: {...}
```

TV não precisa implementar health de Rádio; Rádio não precisa implementar checks DTS/FPS próprios de TV. O Core agrega ambos.

## 8. Event/Control Contract

O Core fala em eventos e capacidades, não em flags de engine.

```text
Core
 ├── RadioEngineAdapter
 └── TvEngineAdapter
```

É proibido exigir que TV aceite timeline musical de Rádio ou que Rádio aceite scheduler linear de TV.

## 9. Canonical media

Perfis são independentes e versionados.

```text
STUDIOSAT-RADIO-AV-V1
STUDIOSAT-RADIO-AUDIO-V1
TVKIDS-V1
STUDIOSAT-TV-...
```

Mesmo codec não autoriza fusão de profiles.

## 10. Ingress remoto/live

Ainda não congelado globalmente.

Até o Core Compatibility Gate é proibido:

- fechar todos os publishers externos em loopback;
- abrir novo listener público sem ACL;
- presumir que Rádio e TV usam o mesmo live transport.

Cada domínio deverá declarar origem, protocolo, autenticação, latência e comportamento de fallback.

## 11. Portas

A reserva/alteração de portas pertence ao Core. Nenhuma vertical escolhe porta pública unilateralmente.

Antes de adicionar listener:

```text
ss/listeners
→ firewall host
→ firewall VPC/GCP
→ conflito com serviços
→ risco
→ candidate
→ rollback
```

## 12. Arquivos que a Engenharia TV deve ler antes de iniciar execução

```text
docs/00-core/CORE_CONTRACT_v0.1.md
docs/00-core/SHARED_FOUNDATION_HANDOFF_TO_TV_v0.1.md
docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md
docs/30-execucao/CHANGE_QUEUE.md
registry/channels-registry.yaml
docs/40-stage-reports/<últimos Core/Rádio>
```

## 13. Interlocks herdados da produção atual

Até changes próprias liberarem:

- não reiniciar TVs por modernização apenas para aplicar nova estrutura;
- não endurecer MediaMTX antes de mapear ingress externo e firewall de nuvem;
- não trocar FFmpeg do sistema por requisito de um único domínio;
- não substituir scripts globais sem medir impacto nos dois domínios;
- não usar um erro de uma station para justificar restart em massa.

## 14. Condição de handoff

A fundação é considerada pronta para integração TV quando:

- Core Contract está aceito;
- registry real existe;
- health comum está comprovado;
- namespaces estão congelados;
- shared config ownership está documentado;
- qualquer alteração global já aplicada possui Stage Report e rollback;
- Engenharia TV consegue adicionar uma station LAB sem editar artefatos internos da Rádio.

## Resultado esperado

A Engenharia Rádio pode avançar primeiro sem produzir dívida estrutural para TV. A Engenharia TV entra pelos contratos documentados e **não precisa desfazer o que já funciona**.
