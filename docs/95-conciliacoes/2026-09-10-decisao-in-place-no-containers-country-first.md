# Decisão Arquitetural — IN-PLACE FIRST / NO CONTAINERS / COUNTRY FIRST

Status: **NORMATIVO**  
Data: 2026-09-10  
Owner: Engenharia Rádio + Core

## Decisão

A plataforma existente é a base oficial da StudioSat Web. Não será construída uma segunda plataforma paralela no mesmo host.

### Regras permanentes

1. **NO CONTAINERS / NO VMs** para a implementação deste projeto, por decisão de arquitetura.
2. **IN-PLACE FIRST**: preservar e evoluir `/srv/tpsmedia/repository/channels/<station>`.
3. Preservar MediaMTX, NGINX, TLS, station IDs, paths públicos e isolamento por processo existentes, alterando somente quando houver necessidade técnica comprovada.
4. Não criar `/srv/studiosat/...` como nova árvore permanente de produção.
5. Não criar segundo MediaMTX, segundo NGINX, segundo registry ou segunda biblioteca de mídia.
6. Shadow é permitido somente de forma **mínima e temporária**, no componente candidato à substituição, usando a biblioteca existente em leitura e path LAB separado.
7. Depois do cutover aprovado, o shadow temporário deve ser removido.
8. `ready/` continua fisicamente compatível com o legado enquanto o playout depender disso; qualquer evolução para estado lógico/manifest deve ocorrer por change própria.
9. Refatoração in-place nunca significa editar produção sem candidate, precheck, validação, backup pequeno/versionado e rollback.

## Country como station de referência imediata

O baseline CHG-001 observou `radiocountry` com:

- `tps-radiocountry-playout.service` ativo;
- path `radiocountry` ready no MediaMTX;
- conteúdo em `ready/`;
- publicação atual por FFmpeg legado.

Portanto Country não é tratada como incidente. Ela será usada como **reference station** para validar imediatamente o comportamento real de restart da stack atual antes de remodelar engines.

### Objetivo do restart Country

Comprovar, usando a estrutura existente:

```text
ready/ + playlist generator
→ playlist.txt
→ tps-radiocountry-playout.service
→ FFmpeg
→ RTMP localhost
→ MediaMTX /radiocountry
→ HLS
```

### O que NÃO será criado

- nova árvore de Country;
- nova cópia da biblioteca;
- novo MediaMTX;
- novo NGINX;
- novo service permanente;
- container/VM;
- novo domínio/path de produção.

### Segurança do restart

Antes do restart devem ser confirmados, no instante da execução:

1. unit real e ExecStartPre/ExecStart;
2. `ready/` com pelo menos um asset elegível pelas regras atuais do gerador;
3. playlist atual existente e hash registrada;
4. gerador atual e hash registrada;
5. MediaMTX `radiocountry` ready antes do restart;
6. HLS local/publicação atual acessível;
7. nenhuma outra change EXECUTING.

Somente depois será executado restart **apenas** de `tps-radiocountry-playout.service`.

Não reiniciar MediaMTX, NGINX, outras rádios ou TVs.

### PASS do restart

Após restart:

- systemd volta a `active`;
- MainPID/ExecMainStartTimestamp confirmam nova execução;
- ExecStartPre conclui sem erro;
- MediaMTX `radiocountry` volta a `ready=true`;
- HLS local responde e avança;
- áudio é detectável;
- journal não entra em restart loop;
- outras stations permanecem inalteradas.

### FAIL

Se Country não retornar, interromper a sequência e diagnosticar a falha no próprio legado. Não instalar engine novo para mascarar defeito de playlist/asset/ExecStartPre.

## Relação com Radio Rock

Radio Rock continua um incidente separado. O restart Country serve para provar o comportamento da stack saudável. Depois dele, a recuperação de Rock usará o mesmo modelo in-place, corrigindo somente asset/playlist/gerador necessários.

## Handoff para Engenharia TV

A Engenharia TV herda a mesma filosofia para a vertical dela:

- manter roots atuais;
- não duplicar Core;
- usar candidate/previous;
- LAB temporário apenas onde necessário;
- mudanças compartilhadas entram pela Change Queue/Core.

A Engenharia Rádio não executa correções TV.
