# StudioSat Web — Política dos Scripts

Este diretório contém a **fonte de verdade** dos scripts aceitos pelo projeto.

## Regra principal

Se um script for ajustado/corrigido durante uma etapa, a versão que realmente funcionou deve ser trazida para este diretório e documentada **antes da próxima Change**.

## Cabeçalho obrigatório para novos scripts

```text
Nome:
Versão:
Owner: Core | TV | Rádio
Safety class: read-only | candidate | production-change
Change ID:
Propósito:
Pré-condições:
Rollback/remoção:
```

## Validações mínimas

### Bash

```bash
bash -n script.sh
```

Quando aplicável, validar também com `shellcheck` em ambiente de desenvolvimento, sem instalar ferramentas no host de produção apenas para isso.

### Liquidsoap

```bash
liquidsoap --check arquivo.liq
```

### NGINX

```bash
nginx -t
```

### systemd

Usar `systemd-analyze verify` quando o candidate puder ser validado dessa forma e sempre revisar `systemctl cat` após implantação.

### MediaMTX

Usar o mecanismo de validação compatível com a versão real detectada no preflight; nunca presumir flags de outra versão.

## Correção de script em produção

Toda correção deve registrar no Stage Report:

1. sintoma;
2. causa encontrada;
3. versão/hash anterior;
4. diff lógico da correção;
5. comando de validação;
6. teste funcional;
7. impacto em outras stations;
8. rollback;
9. versão final/hash;
10. commit que passou a ser fonte da verdade.

## Segurança

Nunca salvar em scripts versionados:

- passwords;
- tokens;
- stream keys;
- private keys;
- endpoints contendo credenciais embutidas.

Usar referências a arquivos de segredo/variáveis com permissões apropriadas no host; a documentação pública deve conter apenas placeholders.

## Scripts atuais

- `studiosat-core-preflight.sh` — Core / `read-only`; próxima ação operacional CHG-001.
- `studiosat-radio-preflight.sh` — Rádio / `read-only`; coletor específico, subordinado ao preflight Core quando a Change Queue assim determinar.
