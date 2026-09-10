# StudioSat Web — Protocolo de Execução e Sincronização v0.1

Status: **OBRIGATÓRIO PARA CORE, TV E RÁDIO**

## Objetivo

Evitar duplicidade, conflitos de configuração e perda de rastreabilidade enquanto várias engenharias trabalham sobre a mesma plataforma e o mesmo host de produção.

## Regra absoluta

> **Nenhuma etapa começa apenas porque o plano anterior dizia que ela era a próxima. Antes de cada etapa, o repositório é relido e o estado real da plataforma é reconfirmado.**

## Ciclo obrigatório de cada mudança

### A. SYNC — antes de preparar ou executar

1. Ler o `main` atual.
2. Registrar `baseline_commit`.
3. Comparar o `main` com o último checkpoint do domínio.
4. Ler mudanças do outro domínio desde o checkpoint.
5. Confirmar a Change ativa e dependências.
6. Confirmar que nenhuma outra alteração de host está em execução.
7. Identificar arquivos compartilhados afetados.
8. Reavaliar risco e rollback.

Saída obrigatória: `SYNC PASS` ou `SYNC BLOCKED`.

### B. PLAN — candidate antes do host

Todo change precisa possuir:

- objetivo;
- owner;
- escopo;
- arquivos afetados;
- comandos planejados;
- candidate/diff;
- validação prévia;
- métricas prévias;
- rollback;
- critério PASS/FAIL;
- impacto esperado em TV, Rádio e Core.

Nenhum comando mutável é executado enquanto o PLAN estiver incompleto.

### C. PRECHECK — imediatamente antes da execução

No host:

- confirmar data/hora;
- confirmar serviços relevantes no mesmo estado esperado;
- confirmar CPU/RAM/disco;
- confirmar health dos canais de controle;
- confirmar backup/snapshot exigido;
- confirmar que o candidate é exatamente a versão revisada;
- registrar hashes dos arquivos que serão substituídos.

Qualquer divergência material bloqueia a execução e volta para SYNC.

### D. EXECUTE — uma mudança ativa

- executar somente os comandos documentados;
- registrar stdout/stderr relevante;
- não aproveitar a janela para "corrigir mais uma coisa";
- se surgir defeito não previsto, interromper e registrar;
- aplicar rollback se o gate definido falhar.

### E. VERIFY — provar o produto

Validar o resultado no nível correto:

- processo;
- publisher/path;
- HLS/stream;
- áudio/vídeo conforme domínio;
- metadata/estado quando aplicável;
- CPU/RAM;
- logs/erros;
- isolamento: outros canais permanecem saudáveis.

`systemctl active` sozinho nunca fecha uma mudança.

### F. DOCUMENT — antes da próxima etapa

Criar/atualizar o Stage Report contendo:

- change ID;
- baseline commit;
- horário inicial/final;
- estado antes;
- comandos realmente executados;
- arquivos e hashes antes/depois;
- scripts usados;
- correções feitas durante a etapa;
- validações e métricas;
- resultado PASS/FAIL/ROLLED_BACK;
- incidentes;
- rollback utilizado ou disponível;
- pendências;
- próximo gate recomendado.

Se um script foi corrigido, a versão que efetivamente funcionou deve substituir ou versionar a candidate no GitHub **antes** de liberar a próxima change.

### G. PUBLISH — checkpoint GitHub

1. Atualizar scripts finais.
2. Atualizar documentação técnica afetada.
3. Publicar Stage Report sanitizado.
4. Atualizar Change Queue.
5. Registrar o commit final da etapa.
6. Reler o `main` para detectar mudanças concorrentes feitas enquanto a etapa era executada.

Somente então a etapa seguinte pode mudar de `BLOCKED` para `READY`.

## Branch/PR recomendado para mudanças executáveis

Para scripts/configuração/candidates que poderão chegar ao host:

```text
chg/CHG-XXX-descricao
```

Fluxo:

```text
branch candidate
→ revisão Core/domínio
→ execução controlada
→ atualização da branch com resultado real
→ revisão final
→ merge em main
→ próxima change
```

Documentos puramente informativos podem ser atualizados diretamente quando não competirem com uma mudança ativa, mas nunca podem alterar silenciosamente contratos normativos.

## Diretório dos relatórios de etapa

Todo change executado terá:

```text
docs/40-stage-reports/CHG-XXX-AAAA-MM-DD-descricao.md
```

O relatório publicado deve ser sanitizado. Evidência privada permanece fora do repositório público.

## Scripts: fonte da verdade

`scripts/` contém a versão canônica aceita. É proibido manter uma versão "que funciona" somente em `/usr/local/sbin`, `/root` ou outro path do host sem trazê-la de volta ao GitHub.

Cada script relevante deve registrar no cabeçalho:

- nome;
- versão;
- propósito;
- domínio/owner;
- safety class (`read-only`, `candidate`, `production-change`);
- change ID de origem quando aplicável.

## Arquivos compartilhados — gate adicional

Mudança em qualquer item abaixo exige revisão Core e verificação cruzada do outro domínio:

```text
MediaMTX
NGINX/TLS
firewall/rede
portas
usuários/ownership compartilhado
systemd slices/templates globais
channels-registry
schemas comuns
health envelope
naming de paths
```

## Critério de conclusão

Uma mudança só está `DONE` quando:

- objetivo foi atingido;
- produto foi validado;
- outros canais não regrediram;
- rollback está conhecido;
- scripts finais estão no GitHub;
- Stage Report está no GitHub;
- Change Queue foi atualizada;
- último `main` foi relido.

Se qualquer item faltar, a mudança permanece aberta.
