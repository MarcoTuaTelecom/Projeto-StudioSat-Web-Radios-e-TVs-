# Diretriz Operacional — Rádio-first com Core compatível com TV

Status: **NORMATIVO PARA A ORDEM DE IMPLEMENTAÇÃO**
Data: 2026-09-10

## Motivo

A prioridade operacional do projeto foi refinada: esta frente de engenharia tem como objetivo principal concluir a estrutura das cinco emissoras **Radio Studio Sat**. A Engenharia de TV permanece responsável por TVKIDS, TVTEENS, TVVIVA e TVMAISJOVEM.

Esta diretriz **não desfaz** o acordo TV–Rádio–Core sobre separação de domínios, Change Queue, Core Compatibility Gate e NON-MERGE RULES. Ela altera somente a prioridade da trilha de implementação.

## Regra principal

> A Rádio pode iniciar a fundação compartilhada, mas nenhum componente comum será desenhado de forma radio-específica. O Core deve nascer com contratos e pontos de extensão que permitam à Engenharia TV entrar depois sem substituir, renomear ou reescrever o que foi validado.

## Responsabilidade desta frente

### Entrega obrigatória

- recuperar e estabilizar o legado Rádio quando necessário;
- implantar health comum não destrutivo;
- definir e provar canonical Rádio;
- provar `RadioEngineAdapter`;
- construir A/V + áudio-only da mesma timeline;
- construir live locutor/câmera;
- fallback e metadata Rádio;
- realizar shadow e cutover station por station;
- concluir Principal, Pop, Rock, Clássicas e Country;
- preservar contratos compartilhados para integração TV.

### Fora do escopo de implementação desta frente

- canonical/QC TV;
- scheduler/continuity/filler TV;
- `TvEngineAdapter`;
- correção de DTS TV;
- TVKIDS/TVTEENS/TVVIVA/TVMAISJOVEM, exceto checks de não-regressão e compatibilidade Core.

## O que é Core e não pode ser moldado somente para Rádio

- MediaMTX global;
- NGINX/TLS;
- ports/naming;
- registry;
- Health/Event/Profile schema comuns;
- ingress/auth/ACL comum;
- systemd slices/templates globais;
- observabilidade;
- backup/rollback global;
- Change Queue.

## Compatibilidade reversa obrigatória para TV

Toda decisão Core implementada antes da vertical TV deve atender simultaneamente:

1. namespace separado para Rádio e TV;
2. ausência de dependência do Core em Liquidsoap, FFmpeg ou ffplayout específicos;
3. possibilidade de adicionar station TV sem editar semântica Rádio;
4. possibilidade de adicionar health TV como extensão do envelope comum;
5. possibilidade de adicionar paths TV sem renomear paths Rádio;
6. possibilidade de publicar A/V TV sem depender da dual-rendition Rádio;
7. política de ingress capaz de acomodar live TV e live Rádio de forma isolada;
8. systemd por station, sem processo universal;
9. rollback por station;
10. mudanças compartilhadas sempre via Core Change Gate.

## Ordem revisada da trilha crítica

```text
CHG-004  Health read-only comum
    ↓
CHG-005R Recuperação/normalização de incidentes Rádio P0, começando por Rock
    ↓
CHG-008A Country LAB — pré-requisitos + canonical + corpus
    ↓
CHG-008B Country LAB — RadioEngineAdapter + A/V + áudio-only
    ↓
CHG-009A Country — fallback/metadata/falhas
    ↓
CHG-009B Country — live locutor/câmera
    ↓
CHG-009C Country — shadow ≥24h
    ↓
CHG-010  Core Compatibility Gate Rádio + TV
    ↓
CHG-011  Country cutover
    ↓
CHG-012  Pop
    ↓
CHG-013  Clássicas
    ↓
CHG-014  Rock
    ↓
CHG-015  Principal
```

A sequência das quatro stations restantes pode mudar se métricas e risco justificarem, mas Principal permanece candidato natural a último por sua exceção histórica de gerador.

## Trilha TV

A Engenharia de TV pode desenvolver documentação, candidates, profiles e testes em paralelo. Execução no host continua entrando na mesma Change Queue e nunca ocorre simultaneamente com uma change Rádio/Core.

As antigas CHG-006/007 de TV deixam de ser pré-condição da trilha Rádio. Elas permanecem válidas como changes da Engenharia TV e serão agendadas pelo Core sem conflito com a trilha principal.

## Resultado

A plataforma continua única. A implementação passa a ser **Rádio-first**, com Core arquitetado desde o primeiro dia para permitir a entrada da TV sem refatoração destrutiva.
