# CHG-000 — Revisão do repositório e congelamento do protocolo de coordenação

Status: **PASS — DOCUMENTAÇÃO/GOVERNANÇA; NENHUMA ALTERAÇÃO NO HOST**
Owner: Core
Baseline commit revisado: `7511fdbd11ca15023289a785225edae148602328`
Data: 2026-09-10

## Objetivo

Revisar integralmente a estrutura atual do repositório antes de qualquer nova etapa operacional e incorporar as contribuições recentes da Engenharia de TV ao processo comum.

## Mudanças detectadas desde o checkpoint Core anterior

Base anterior: `c4f6889a6828f7c7d79f29238683bfc3c00a3761`.

Foram detectados exatamente dois commits novos antes desta revisão:

1. `1ea570077eaf0147ac63fcb2d4af3f0959309318` — `docs(tv): add engineering scope and TVKIDS Stage-1 responsibilities`
   - adicionou `docs/20-tv/TV_ENGINEERING_SCOPE_v0.1.md`;
2. `7511fdbd11ca15023289a785225edae148602328` — `docs(consensus): record formal TV-Radio-Core engineering agreement`
   - adicionou `docs/95-conciliacoes/2026-09-10-acordo-tv-radio-core.md`.

Nenhum dos dois commits alterou scripts, NGINX, MediaMTX, registry, baseline técnico ou runbook mestre.

## Revisão da Engenharia de TV

### Aceito

- TV não altera isoladamente NGINX, MediaMTX global, firewall, TLS/Certbot global, ownership compartilhado, slices globais ou Core Registry.
- TVKIDS permanece a station de referência Stage-1 da vertical TV.
- FFmpeg + canonical + `-c copy` é Stage-1, não obrigação eterna de engine.
- `TvEngineAdapter` é o contrato da plataforma.
- uma station por vez;
- paralelismo de engenharia permitido;
- paralelismo de alteração do host proibido.

### Acordo conjunto aceito pelo Core

- Core compartilhado; engines separados;
- profiles Radio e TV separados;
- Liquidsoap é candidato do RadioEngineAdapter, não decreto;
- primeiro cutover Radio exige Core Compatibility Gate;
- contracts/naming/health devem existir antes dos labs;
- mudanças Core passam por gate cruzado.

## Auditoria do `scripts/studiosat-core-preflight.sh`

O script atual foi relido no `main` antes da autorização de CHG-001.

Confirmado:

- efeito de escrita limitado a `/tmp/studiosat-core-preflight-*` e criação do tar/hash final;
- não executa `apt`;
- não executa `systemctl start/stop/restart/reload/enable/disable`;
- não executa reload de NGINX;
- `nginx -t` e `nginx -T` são usados apenas para inspeção/validação;
- `certbot renew --dry-run` é explicitamente **não executado** no preflight;
- lê units, processes, listeners, MediaMTX, NGINX, TLS, filesystem de mídia e streams locais;
- usa probes RTMP/HLS passivos com timeout;
- cria arquivos e faz `mv/chmod/tar` somente na árvore temporária de diagnóstico;
- possui redaction de padrões comuns de password/token/secret/stream key.

### Limitação de segurança conhecida

Redaction por expressão regular não é prova absoluta de ausência de segredo. Portanto o `.tar.gz` completo **não deve ser commitado no repositório público**. Ele deve ser analisado como evidência privada; somente achados sanitizados entram em `docs/90-evidencias/` e `docs/40-stage-reports/`.

## Novas regras publicadas nesta revisão

- `docs/00-core/CORE_ENGINEERING_SCOPE_v0.1.md`;
- `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`;
- `docs/40-stage-reports/README.md`.

Esses documentos obrigam Core, TV e Rádio a reler o `main` antes e depois de cada change e a versionar o script que realmente funcionou antes de avançar.

## Impacto no host

Nenhum. Esta etapa alterou apenas documentação no GitHub.

## Resultado

**PASS.** As novas contribuições da Engenharia de TV não conflitam com o Core Contract atual e foram incorporadas ao processo de coordenação.

## Próximo gate

`CHG-001 — Core preflight somente leitura`.

Antes da execução, confirmar snapshot/backup conforme runbook. Depois da execução, enviar o `.tar.gz` e `.sha256` em canal privado para análise. Não publicar o pacote bruto no GitHub.
