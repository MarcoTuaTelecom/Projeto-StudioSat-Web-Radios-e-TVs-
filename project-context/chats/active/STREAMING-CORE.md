# WORKSTREAM: STREAMING-CORE

## Identidade

- `WORKSTREAM_ID`: `STREAMING-CORE`
- Estado: `ACTIVE`
- Chat: `02 — STREAMING CORE — MediaMTX / Nginx / HLS — C01`
- Repositório principal: `MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-`
- Âncora obrigatória: `project-context/anchors/02-STREAMING-CORE-ANCHOR.md`

## Missão atual

Reconstruir o estado real da camada de streaming comum e separar claramente transporte/infraestrutura das regras editoriais e de failover.

## Baseline histórico conhecido

O registry observado em 2026-09-10 registrou:

- `radioprincipal` com `publish_path: radioprincipal`;
- MediaMTX ready preliminarmente para a Rádio Principal naquele momento;
- caminhos públicos para as cinco rádios e quatro TVs;
- múltiplos lab paths por canal.

Esse estado é apenas referência histórica e precisa ser reconfirmado.

O Portal documenta MediaMTX HLS em `127.0.0.1:8888` atrás do Nginx, mas isso também precisa ser validado contra a configuração viva antes de ser tratado como verdade operacional.

## Objetivo do C01

Produzir uma topologia viva e inequívoca de:

- MediaMTX;
- Nginx;
- TLS/hosts;
- HLS;
- paths;
- publishers;
- serviços systemd envolvidos;
- classificação `PUBLIC / AUTHORITATIVE_INPUT / SHADOW / TEST / LAB / LEGACY / UNKNOWN`.

## Primeira saída obrigatória

Uma matriz:

```text
ITEM | HISTÓRICO/REGISTRY | ESTADO VIVO | CLASSIFICAÇÃO | EVIDÊNCIA | AÇÃO
```

## Dependência com Rádio Principal

`RADIOPRINCIPAL-NS1` não deve alterar o Core de streaming para corrigir mirror/playback.

`STREAMING-CORE` deve fornecer paths e health estáveis para:

- entrada RadioBOSS;
- shadow NS1;
- futuro selector;
- HLS público.

## Fora do escopo

- playlist/schedule/librarymanifest;
- materialização de mídia do mirror;
- playback editorial;
- scheduler/hora certa;
- lógica de selector/prioridade;
- Portal/CMS;
- Mobile.

## Próximo passo único

Executar inventário somente leitura do MediaMTX + Nginx + paths/publishers e comparar com registry/configuração documentada.

## Definition of Done do C01

- [ ] configuração MediaMTX efetivamente carregada identificada;
- [ ] configuração Nginx efetivamente carregada identificada;
- [ ] portas/protocolos confirmados;
- [ ] paths principais classificados;
- [ ] publishers atuais identificados;
- [ ] hosts/TLS/redirects observados;
- [ ] HLS público testado read-only;
- [ ] diferenças para o registry classificadas;
- [ ] primeiro desvio prioritário escolhido;
- [ ] nenhum reparo amplo executado durante o baseline.

Quando cumprir:

`STREAMING_BASELINE=COMPLETE`

## Não reabrir sem nova evidência

- Core de streaming é responsabilidade deste workstream, não do Mobile/Portal;
- estado do registry de 2026-09-10 é histórico, não prova de estado atual;
- path público não deve ser alterado para testar hipótese quando shadow/test path pode cumprir a função.
