# Rádio Principal — Regras de Negócio do Console do Operador V1

## Objetivo

O técnico de operação da Rádio Principal deve conseguir operar, programar, auditar e manter o sistema sem depender de shell, paths internos ou conhecimento da implementação.

## Perfis

### Superadmin
- configura sistema;
- gerencia usuários/roles;
- altera integrações;
- autoriza cutover/manutenção crítica;
- consulta tudo.

### Administrador da Rádio
- gerencia usuários da emissora;
- programação;
- repositórios;
- comerciais;
- regras editoriais;
- relatórios;
- não altera infraestrutura global sem permissão específica.

### Programador
- cria/edita grades;
- playlists;
- schedules;
- comerciais;
- eventos;
- publica versões de programação.

### Operador
- acompanha NOW/NEXT;
- troca/aciona eventos permitidos;
- consulta sincronismo;
- acompanha downloads;
- registra ocorrência;
- não altera segurança/infraestrutura.

### Técnico
- acompanha saúde de serviços;
- transferências;
- storage;
- failover;
- logs técnicos;
- executa manutenção autorizada;
- ações críticas exigem reautenticação e audit log.

### Auditor/Consulta
- somente leitura de programação, histórico, relatórios e logs autorizados.

## Autenticação

- login por usuário/e-mail;
- senha armazenada com hash forte;
- sessão web segura;
- MFA obrigatório para Superadmin/Técnico e recomendado para Administrador;
- bloqueio/rate-limit após tentativas inválidas;
- expiração de sessão;
- recuperação de senha auditada;
- reautenticação para ações críticas.

## RBAC

Permissões granulares, por exemplo:
- users.read / users.write;
- roles.read / roles.write;
- programming.read / programming.write / programming.publish;
- assets.read / assets.upload / assets.delete;
- transfers.read / transfers.retry / transfers.cancel;
- commercials.read / commercials.write / commercials.publish;
- live.read / live.control;
- failover.read / failover.control;
- system.read / system.maintain;
- reports.read / reports.export;
- audit.read.

## Programação

O sistema mantém:
- grade Manhã;
- grade Tarde;
- grade Noite;
- versões publicadas;
- vigência;
- calendário;
- exceções;
- eventos;
- prioridade editorial.

RadioBOSS permanece autoridade durante operação conectada. O console administra dados e sincronismo, mas não deve criar uma programação independente escondida do RadioBOSS.

## Repositórios

Interface humana:
- Manhã;
- Tarde;
- Noite;
- Comerciais;
- Vinhetas;
- Hora Certa;
- Temperatura.

Para cada asset:
- nome;
- hash;
- tamanho;
- duração;
- origem;
- programa;
- estado;
- última sincronização;
- uso futuro;
- histórico de versões.

Delete físico nunca é imediato quando o asset estiver referenciado.

## Transferências

Fila visível ao técnico:
- PENDING;
- CHECKING;
- DOWNLOADING;
- VERIFYING;
- READY;
- RETRYING;
- FAILED;
- QUARANTINED.

Campos:
- origem Windows;
- destino NS1;
- SHA256;
- bytes totais;
- bytes transferidos;
- percentual;
- velocidade;
- ETA;
- tentativas;
- erro atual;
- prioridade;
- referência editorial.

Prioridade automática:
1. current;
2. next;
3. próximos itens;
4. eventos/comerciais iminentes;
5. restante do programa atual;
6. programas futuros.

## Tela principal

Deve mostrar:
- ON AIR / OFF AIR;
- fonte pública atual;
- RadioBOSS LIVE;
- shadow NS1;
- NOW;
- NEXT;
- posição;
- drift;
- programa;
- fila;
- downloads;
- missing;
- hora certa;
- temperatura;
- comerciais;
- selector/failover;
- alertas.

## Controle

Nenhuma ação crítica ocorre sem:
- permissão;
- confirmação;
- registro de usuário;
- timestamp;
- estado anterior;
- estado posterior;
- resultado.

Ações como restart de selector/MediaMTX, cutover e remoção de mídia devem exigir perfil técnico/admin e reautenticação.

## Relatórios

Obrigatórios:
- histórico ON AIR;
- histórico de faixas;
- execuções de comerciais;
- execuções de hora certa;
- execuções de temperatura;
- eventos de scheduler;
- failovers;
- duração de indisponibilidade LIVE;
- divergências RadioBOSS x NS1;
- assets ausentes;
- transfers;
- erros/retries;
- alterações de programação;
- ações de usuários;
- disponibilidade por período;
- exportação CSV/PDF.

## Auditoria

Audit log append-only contendo:
- usuário;
- role;
- IP;
- ação;
- recurso;
- antes/depois;
- resultado;
- motivo/comentário quando aplicável;
- timestamp UTC e local.

## Interface/API alvo

A API deve ser versionada em `/api/v1`.

Módulos:
- auth;
- users;
- roles;
- programming;
- schedules;
- assets;
- transfers;
- commercials;
- runtime;
- failover;
- reports;
- audit;
- health.

A interface web consome essa API.

## Segurança operacional

Durante reconstrução:
- console não pode reiniciar produção;
- comandos críticos permanecem bloqueados;
- desenvolvimento usa paths V2 isolados.

Após homologação:
- controles críticos são liberados somente para roles autorizadas.
