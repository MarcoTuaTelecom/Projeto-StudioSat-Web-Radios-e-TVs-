# CHG-001 — Core Preflight somente leitura

Status: **PLANNED / READY FOR EXECUTION**
Owner: Core
Script canônico: `scripts/studiosat-core-preflight.sh`
Script blob SHA antes da execução: `d194b3e3433d8a8975d5c03e5bd7821bd53b853e`
Baseline de documentação imediatamente antes da execução: atualizar no momento do PRECHECK.

## Objetivo

Fotografar o estado real atual do host e das 9 stations sem alterar serviços, configuração ou mídia. A evidência será usada para criar o `channels-registry` real e impedir que Rádio/TV trabalhem sobre pressupostos antigos.

## Escopo autorizado

Somente leitura da produção. Escrita apenas em `/tmp/studiosat-core-preflight-*` para os artefatos de diagnóstico.

É proibido nesta change:

- instalar/remover pacote;
- iniciar/parar/reiniciar/recarregar serviços;
- editar NGINX/MediaMTX/systemd;
- alterar firewall;
- mover/renomear mídia;
- executar `certbot renew --dry-run`;
- corrigir Radio Rock ou TVKIDS durante a coleta;
- realizar qualquer mudança oportunista descoberta pelo diagnóstico.

## Auditoria prévia do script

Revisão Core confirmou:

- não contém `apt`/instalação;
- não contém operações de lifecycle systemd;
- não recarrega NGINX;
- consulta `nginx -t`/`nginx -T` sem aplicar mudanças;
- não executa renovação Certbot;
- faz probes locais RTMP/HLS com timeouts;
- lê MediaMTX API/metrics se disponíveis;
- inventaria units, processes, listeners, mídia e scripts atuais;
- escreve/move/chmod/tar somente dentro da árvore temporária de diagnóstico;
- redige padrões comuns de segredo, sem prometer redaction perfeita.

## PRECHECK obrigatório

Antes de rodar:

1. confirmar que nenhuma outra engenharia está executando mudança no host;
2. confirmar snapshot/backup exigido pelo runbook, quando disponível;
3. confirmar que o script usado é o mesmo do GitHub;
4. validar sintaxe Bash;
5. registrar horário e estado visual geral dos canais;
6. não executar nenhuma outra Change em paralelo.

## Comandos planejados

Assumindo o script já colocado em `/root/studiosat-core-preflight.sh`:

```bash
sudo -i

sha256sum /root/studiosat-core-preflight.sh
bash -n /root/studiosat-core-preflight.sh

/root/studiosat-core-preflight.sh
```

Se o arquivo ainda não estiver em `/root`, transferir a versão canônica do GitHub para o host e então:

```bash
sudo install -o root -g root -m 0750 \
  /CAMINHO/DE/UPLOAD/studiosat-core-preflight.sh \
  /root/studiosat-core-preflight.sh

sudo bash -n /root/studiosat-core-preflight.sh
sudo /root/studiosat-core-preflight.sh
```

A cópia do script para `/root` é a única preparação local permitida além da saída em `/tmp`; ela não altera serviços nem mídia.

## Saída esperada

```text
/tmp/studiosat-core-preflight-<host>-<timestamp>.tar.gz
/tmp/studiosat-core-preflight-<host>-<timestamp>.tar.gz.sha256
```

## Regra de segurança da evidência

O pacote bruto não será commitado neste repositório público. Mesmo com redaction, ele pode conter topologia interna, nomes de arquivos e informação operacional.

Enviar `.tar.gz` e `.sha256` por canal privado para análise Core.

O GitHub receberá depois somente:

- resumo sanitizado;
- `channels-registry` sem segredos;
- matriz P0/P1/P2;
- alterações necessárias;
- scripts finais corrigidos;
- hashes de evidência quando seguro;
- este Stage Report atualizado.

## Gates de PASS

- script termina sem alterar lifecycle de serviços;
- pacote `.tar.gz` existe;
- `.sha256` existe e confere;
- produção permanece no mesmo estado operacional de antes da coleta;
- evidência permite identificar units/paths/configs/streams necessários para CHG-002.

## Gates de FAIL/BLOCK

- qualquer serviço muda de estado por ação do script;
- script tenta alterar configuração/mídia;
- pacote fica incompleto a ponto de não mapear a plataforma;
- hash não confere;
- conflito com uma Change concorrente.

## Rollback

Não há rollback de produção esperado porque esta é uma change read-only. Os únicos artefatos locais criados são o script copiado para `/root` e a árvore/pacote em `/tmp`; não remover nada durante a execução. A limpeza, se desejada, é change separada/documentada.

## Próxima etapa somente após fechamento

Após receber e analisar a evidência:

1. atualizar este relatório com o que realmente ocorreu;
2. publicar achados sanitizados;
3. gerar `registry/channels-registry.yaml` real;
4. classificar P0/P1/P2;
5. reler `main` e alterações da Engenharia de TV/Rádio;
6. só então liberar CHG-002.
