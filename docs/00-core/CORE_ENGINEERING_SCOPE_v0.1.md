# StudioSat Web — Core Engineering Scope v0.1

Status: **NORMATIVO PARA COORDENAÇÃO**

## Missão

Manter uma única plataforma StudioSat Web sem fundir os domínios de mídia. O Core coordena e governa os componentes compartilhados, garante compatibilidade entre Rádio e TV e controla a ordem das mudanças no host de produção.

## Autoridade do Core

O Core é responsável por:

- arquitetura mestre e contratos comuns;
- `channels-registry` real das 9 stations;
- `CORE CONTRACT` e versionamento de schemas;
- nomenclatura de paths e laboratórios;
- MediaMTX compartilhado;
- NGINX/TLS compartilhado;
- portas, ingress, auth/ACL e superfície de rede;
- política systemd/slices globais;
- health envelope comum e observabilidade;
- backup/rollback global;
- Change Queue;
- compatibilidade entre `RadioEngineAdapter` e `TvEngineAdapter`;
- aprovação de mudanças que toquem componentes compartilhados.

## Fora de escopo do Core

O Core **não implementa nem escolhe por decreto**:

- scheduler interno de Rádio;
- scheduler interno de TV;
- filler/fallback específico de cada domínio;
- engine universal;
- canonical profile único para TV e Rádio;
- semântica de live de Rádio ou TV;
- regras editoriais específicas de cada station.

O Core define interfaces, contratos, gates, ownership e integração. Cada domínio implementa sua semântica atrás do adapter correspondente.

## Regra de convivência

**Paralelismo de engenharia: SIM. Paralelismo de alteração do host: NÃO.**

TV e Rádio podem desenvolver código, profiles, testes, documentação e candidates simultaneamente. Alterações no host de produção entram em uma única Change Queue e apenas uma pode estar em estado `EXECUTING` por vez.

## Regra de sincronização obrigatória

Antes de iniciar qualquer etapa:

1. ler o `main` atual;
2. registrar o commit HEAD usado como baseline;
3. revisar mudanças desde o último checkpoint do domínio;
4. confirmar que não existe mudança concorrente em Core/host;
5. validar dependências e conflitos;
6. atualizar o plano/candidate se outra engenharia mudou algo relevante.

Depois de cada etapa:

1. registrar comandos realmente executados;
2. registrar arquivos realmente alterados;
3. registrar hashes/versões finais;
4. registrar métricas e validações antes/depois;
5. registrar falhas encontradas e correções aplicadas;
6. salvar no repositório a **versão final dos scripts que funcionaram**;
7. registrar rollback testado ou disponível;
8. atualizar o Stage Report e a Change Queue;
9. revisar novamente o `main` antes de liberar a próxima etapa.

## Regra de scripts

Nenhum script corrigido deve ficar apenas no servidor. Toda correção precisa gerar:

- versão no GitHub;
- motivo da correção;
- SHA-256 ou blob SHA anterior quando disponível;
- validação (`bash -n`, `liquidsoap --check`, `nginx -t`, validação MediaMTX etc.);
- evidência do resultado;
- rollback ou versão anterior preservada.

## Regra de componentes Core

### NGINX

```text
candidate/diff
→ nginx -t
→ health origin
→ reload
→ health público
→ Stage Report
```

### MediaMTX

```text
candidate/diff
→ validate config
→ inventário publishers/readers
→ impacto dos paths
→ gate TV + Rádio
→ reload/restart somente se necessário
→ health das 9 stations
→ Stage Report
```

### systemd global/slices

```text
candidate
→ systemd-analyze verify quando aplicável
→ lab/uma station primeiro
→ health
→ expansão gradual
→ Stage Report
```

## Regra de segurança do repositório

O repositório é público. Nunca versionar:

- senhas, tokens ou stream keys;
- chaves privadas/certificados privados;
- backups privados;
- `.env` real;
- dumps não redigidos;
- preflight bruto que exponha segredos ou topologia sensível.

Preflights completos permanecem fora do GitHub. O repositório recebe apenas achados sanitizados, hashes e relatórios técnicos necessários.

## Próximo gate

`CHG-001 — Core Preflight somente leitura`.

Nenhuma mudança estrutural no host é autorizada antes da análise do pacote e publicação do Stage Report correspondente.
