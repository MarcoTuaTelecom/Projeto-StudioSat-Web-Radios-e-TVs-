# StudioSat Web — Shared Foundation Handoff para Engenharia TV v0.2 — IN-PLACE

Status: **NORMATIVO — SUBSTITUI v0.1 PARA NOVAS EXECUÇÕES**  
Data: 2026-09-10  
Owner: Core

## Princípio central

A plataforma existente é a fundação oficial. A Engenharia TV deve estender o Core existente e a sua própria árvore atual, sem substituir a base compartilhada e sem criar uma segunda plataforma permanente.

## Regras herdadas da decisão Rádio/Core

1. **NO CONTAINERS / NO VMs** como política atual do projeto.
2. Roots de produção permanecem em `/srv/tpsmedia/repository/channels/<station>`.
3. Não criar `/srv/studiosat/...` como segunda árvore permanente.
4. MediaMTX, NGINX/TLS, registry e health comum são únicos.
5. `station_id` e paths públicos existentes são preservados sempre que possível.
6. LAB é temporário e limitado ao componente em teste; não duplica biblioteca inteira.
7. Toda mudança usa candidate/precheck/rollback e entra na Change Queue única.

## Filesystem

Base comum existente:

```text
/srv/tpsmedia/repository/channels/<station>/
```

Cada domínio pode evoluir seu próprio root internamente, por change:

```text
incoming/
quarantine/
canonical/
ready/
playlists/
state/
graphics/
logs/
lab/       # temporário
```

Rádio não dita semântica TV. TV não altera semântica Rádio.

## MediaMTX

Instância compartilhada atual é preservada. Não criar segunda instância permanente para a TV.

Necessidades TV entram como change Core com:

- path;
- publish/read protocol;
- live requirement;
- auth/ACL;
- latency;
- fallback;
- impacto cruzado.

Paths LAB TV usam namespace `lab-tv-<station>-...` e não reutilizam paths Rádio.

## NGINX/TLS

NGINX/TLS atuais são preservados e evoluídos por candidate/diff. A Engenharia TV pode possuir vhosts específicos, mas não substitui defaults/listeners globais para resolver apenas TV.

Gate:

```text
candidate
→ nginx -t
→ health origem Rádio + TV
→ reload controlado
→ health público Rádio + TV
```

## systemd

Identidades `tps-*` existentes permanecem enquanto funcionarem. Não renomear somente por estética.

Regra permanente:

```text
1 station = 1 processo principal de playout
```

TV pode evoluir sua unit por drop-in/candidate próprio sem tocar units Rádio.

## Health

Envelope Core único, extensões por domínio:

```text
core fields
├── radio: {...}
└── tv: {...}
```

A Engenharia TV acrescenta FPS/resolution/timestamp/DTS/filler/etc. sem reescrever checks Rádio.

## Canonical e ready

Perfis são independentes. `ready/` continua compatível com o legado enquanto necessário. Se a TV decidir transformar `ready` em estado lógico/manifesto, deve fazê-lo dentro da própria vertical e comprovar compatibilidade antes do cutover.

## Engines

Core não impõe engine. Rádio e TV podem usar engines diferentes.

A troca de engine deve preservar o máximo possível de:

- station_id;
- filesystem root;
- MediaMTX production path;
- public URL;
- registry identity;
- health contract.

## Regra para LAB

Permitido:

```text
produção atual ON-AIR
+
processo candidato temporário
+
path LAB exclusivo
```

Proibido:

```text
segunda plataforma completa
segunda biblioteca
segundo MediaMTX
segundo NGINX
segunda política TLS
```

## O que a Engenharia TV deve ler antes de executar

```text
docs/95-conciliacoes/2026-09-10-decisao-in-place-no-containers-country-first.md
docs/00-core/CORE_CONTRACT_v0.1.md
docs/00-core/SHARED_FOUNDATION_HANDOFF_TO_TV_v0.2_IN_PLACE.md
docs/30-execucao/CHANGE_QUEUE.md
registry/channels-registry.yaml
docs/40-stage-reports/<últimos Core/Rádio>
```

## Resultado esperado

A Engenharia Rádio pode concluir sua vertical primeiro sem criar uma arquitetura que obrigue a Engenharia TV a mover mídia, substituir MediaMTX/NGINX, renomear services ou desmontar o Core. A Engenharia TV entra pela mesma base existente e evolui somente sua vertical e os pontos comuns por changes coordenadas.
