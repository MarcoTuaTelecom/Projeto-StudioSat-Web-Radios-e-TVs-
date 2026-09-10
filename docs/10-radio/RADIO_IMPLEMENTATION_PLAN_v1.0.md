# Radio Studio Sat — Plano Mestre de Implementação v1.0

Status: **ATIVO — TRILHA PRINCIPAL**
Data: 2026-09-10
Owner: Engenharia Rádio

## Objetivo final

Entregar as cinco emissoras Radio Studio Sat — Principal, Pop, Rock, Clássicas e Country — estáveis, isoladas e operacionais, com uma única timeline editorial por station e experiências A/V + áudio-only derivadas dela, incluindo live, metadata, fallback, health e rollback.

A implantação deve preservar a produção atual até que cada substituto esteja comprovado.

## Regra de convivência com TV

A Engenharia Rádio não implementa a vertical TV. Porém, todo componente compartilhado que esta frente inaugurar deve cumprir `docs/00-core/SHARED_FOUNDATION_HANDOFF_TO_TV_v0.1.md`.

Toda alteração Core é neutra e extensível. Nenhum componente compartilhado será criado de forma que obrigue TV a adotar scheduler, canonical ou engine Rádio.

## Estado de partida confirmado — CHG-001

```text
radioprincipal   active / MediaMTX ready
radiopop         active / MediaMTX ready
radiorock        failed / MediaMTX not ready
radioclassicas   active / MediaMTX ready
radiocountry     active / MediaMTX ready
```

Rádio atual:

```text
playlist.txt
→ tps-playout-radio
→ FFmpeg concat
→ -c:a copy
→ RTMP localhost
→ MediaMTX
→ HLS/publicação
```

Mídia `ready/` observada é majoritariamente MP3. O canonical Rádio existente ainda é apenas material de teste/draft e não deve ser tratado como contrato final sem a fase de perfil.

## Sequência obrigatória

### R0 — CHG-004 Health read-only

Objetivo: estabelecer health real e repetível antes de qualquer reparo/migração.

Mede:

- systemd;
- MediaMTX path ready;
- tracks;
- HLS local + freshness;
- endpoint público;
- erros recentes;
- regressão nas quatro TVs como controle, sem alterar TV.

Gate: script read-only executado e Stage Report publicado.

### R1 — CHG-005R Radio Rock — recuperação do legado

Objetivo: voltar a ter cinco rádios operacionais antes de modernizar.

Não será usado Liquidsoap nesta fase.

Procedimento planejado:

1. SYNC GitHub;
2. coletar unit/status/journal Rock;
3. confirmar `ready/`, `canonical/` e playlist atual;
4. confirmar regra do gerador atual;
5. identificar asset real não-test apropriado para recuperação ou preparar ingest/canonical por procedimento Rádio;
6. gerar candidate playlist sem tocar produção;
7. validar ffprobe/decode do asset;
8. registrar hash;
9. executar somente mudança necessária;
10. iniciar Rock somente quando `ExecStartPre` puder concluir;
11. validar systemd + MediaMTX + HLS + áudio público;
12. observar estabilidade;
13. registrar rollback e Stage Report.

É proibido mascarar o problema com loop de restart.

### R2 — congelar contrato de mídia Rádio LAB

Objetivo: transformar o profile draft em profile de laboratório testável.

Corpus mínimo:

```text
3 músicas com videoclipe
1 música sem videoclipe + visual/fallback
1 comercial audiovisual
1 vinheta/jingle
1 fallback de station
1 entrada live de teste
```

Perfil inicial LAB será versionado; não vira produção final até testes.

Princípios:

- conform/transcode pesado offline;
- on-air preferencialmente copy/remux;
- AAC 48 kHz stereo para as rendições novas;
- vídeo H.264/yuv420p/30 CFR como baseline LAB, sujeito a validação;
- GOP alinhado para distribuição HLS;
- áudio das duas rendições deve representar o mesmo programa.

### R3 — CHG-008A Country LAB — estrutura isolada

Country é a primeira station candidata.

Estrutura alvo de laboratório:

```text
/srv/studiosat/radio/lab/country/
├── incoming/
├── canonical/
├── ready/
├── graphics/
├── playlists/
├── state/
└── logs/
```

Nenhum arquivo de produção é movido nesta fase.

Paths reservados:

```text
lab-radio-country-av
lab-radio-country-audio
lab-radio-country-live   # somente se aprovado pelo Core
```

Gate: diretórios/ownership aprovados e nenhum conflito com TV/Core.

### R4 — CHG-008B engine candidate

Objetivo: provar `RadioEngineAdapter`.

Liquidsoap 2.4.x permanece primeiro candidato.

Antes de instalar:

1. verificar pacote/versão compatível;
2. analisar dependências;
3. rejeitar instalação que force upgrade arriscado de FFmpeg/libs do sistema;
4. escolher ambiente isolado se necessário;
5. registrar candidate + rollback.

Capacidades obrigatórias:

```text
playlist/timeline
current event
AUTO/LIVE/FALLBACK
A/V
áudio-only
mesma timeline
metadata
fallback
live sem restart
health
```

Gate: candidate executa Country LAB sem tocar `/radiocountry` de produção.

### R5 — dual rendition

Objetivo:

```text
              TIMELINE COUNTRY
                    │
             PROGRAM SOURCE
                    │
              ┌─────┴─────┐
              │           │
             A/V       AUDIO-ONLY
              │           │
        foreground/TV   background/car
```

Critérios:

- mesma sequência editorial;
- mesmo evento corrente;
- áudio coerente entre rendições;
- não manter decode de vídeo desnecessário no cliente em background;
- mudança de rendition não troca station.

### R6 — fallback e falhas

Testar deliberadamente:

- asset ausente;
- asset inválido;
- vídeo ausente;
- live cai;
- MediaMTX temporariamente indisponível no LAB;
- engine reinicia;
- metadata stale.

Falha Country não pode afetar Pop/Clássicas/Principal nem TVs.

### R7 — live locutor/câmera

Antes de abrir porta ou listener:

- declarar origem do encoder;
- escolher RTMP/SRT/outro;
- definir autenticação/ACL;
- medir latência;
- definir fallback;
- validar firewall host + GCP/VPC;
- passar por Core Change Gate.

Live deve entrar/sair sem restart do engine e retornar automaticamente à grade.

### R8 — shadow Country ≥24h

Rodar engine candidate em paralelo sob path LAB.

Comparar:

- continuidade;
- evento atual;
- metadata;
- CPU/RAM;
- logs;
- A/V;
- áudio-only;
- live/fallback;
- impacto nas demais stations.

Não realizar cutover apenas porque o LAB funcionou por poucos minutos.

### R9 — CHG-010 Core Compatibility Gate

Antes do cutover Country, revisar com a Engenharia TV:

- MediaMTX;
- NGINX/TLS;
- paths/naming;
- ingress;
- auth/ACL;
- health;
- systemd policy;
- rollback;
- compatibilidade com futuras stations TV.

Objetivo: impedir que uma decisão feita para Country bloqueie TV depois.

### R10 — CHG-011 Country cutover

Somente após R0–R9 PASS.

Procedimento:

- backup/candidate final;
- health antes;
- cutover único;
- validar origem → MediaMTX → HLS → público;
- validar A/V + áudio-only;
- validar metadata;
- observar 24–72h;
- manter legado apto a rollback durante a janela definida.

### R11 — migração das rádios restantes

Ordem inicial:

```text
Country → Pop → Clássicas → Rock → Principal
```

Cada station repete seus próprios:

```text
precheck
canonical/QC
LAB/shadow
gate
cutover
observação
rollback
Stage Report
```

Principal permanece por último enquanto existir exceção especial de gerador não-atômico.

## Critérios de conclusão da vertical Rádio

A Rádio só está pronta quando as cinco stations comprovarem:

- processo isolado;
- HLS/output estável;
- A/V válido;
- áudio-only válido;
- mesma timeline;
- metadata correta;
- fallback;
- live conforme station;
- recovery após falha;
- CPU/RAM dentro do envelope;
- nenhuma dependência indevida da vertical TV;
- rollback conhecido;
- documentação e scripts finais no GitHub.

## Artefatos obrigatórios por etapa

```text
docs/40-stage-reports/CHG-...md
scripts/ ou candidates/...
profiles/radio/...
registry/channels-registry.yaml
CHANGE_QUEUE.md
```

Se um script for corrigido no host, a versão final que funcionou deve voltar ao GitHub antes da próxima etapa.

## Próxima ação autorizável

Fechar CHG-003 com o aceite Rádio e, após SYNC, executar **CHG-004 Health read-only**. Nenhuma instalação de engine ou alteração de produção precede esse health baseline.
