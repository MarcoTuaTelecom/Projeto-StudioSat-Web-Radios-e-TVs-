# Rádio Principal — Plano de Fechamento da Biblioteca, Sincronismo e Execução

## Estado real em 2026-09-18

A Rádio Principal V3.2 resolveu o **plano de áudio**:
- RadioBOSS -> SSH -> Icecast -> V3.2;
- fallback NS1;
- publisher público único;
- seleção por PCM real;
- old selector fora do caminho público.

Isso NÃO resolve ainda o **plano editorial**.

O NS1 já recebe snapshots do RadioBOSS em:

```
radioboss-sync/current/
  playlist.json
  schedule.json
  librarymanifest.json
  playback.json
  heartbeat.json
```

Também já existem MP3s fisicamente no NS1 em pastas humanas/correspondentes.

O que falta é ligar essas duas coisas ao runtime.

---

## Falha funcional atual

Hoje existem três blocos desconectados:

1. **RadioBOSS envia estado**
   - playlist;
   - playback;
   - schedule;
   - library manifest.

2. **NS1 possui mídia**
   - grade manhã;
   - grade tarde;
   - grade noite;
   - elementos;
   - mirror store / object store.

3. **V3.2 transmite áudio**

Mas NÃO existe ainda uma camada final que faça:

```
item do RadioBOSS
 -> resolver no catálogo NS1
 -> confirmar asset local
 -> montar fila canônica
 -> posicionar shadow
 -> manter current/next/pos_ms
```

Esse é o próximo bloco obrigatório.

---

## Módulos que faltam

### 1. Library Indexer

Varre as pastas reais do NS1 e cria um índice persistente:

```
asset_id
sha256
basename
normalized_name
artist
title
size
duration
local_path
program_bucket
```

Pastas mínimas:
- `/srv/studiosat/radio-principal/grade/manha`;
- `/srv/studiosat/radio-principal/grade/tarde`;
- `/srv/studiosat/radio-principal/grade/noite`;
- `/srv/studiosat/radio-principal/elementos`;
- repositório canônico/mirror store já existente.

Regra:
**se o MP3 já está no NS1, ele deve ser resolvido localmente; não deve ser marcado missing nem retransmitido.**

### 2. RadioBOSS Resolver

Consome:
- `librarymanifest.json`;
- `playlist.json`;
- `playback.json`;
- `schedule.json`.

Para cada item físico:
1. tentar SHA quando disponível;
2. tentar path/name exato normalizado;
3. tentar basename normalizado;
4. tentar artist/title;
5. somente depois classificar como missing.

### 3. Canonical Effective Queue

Persistir a fila efetiva do RadioBOSS:

```
sequence
playlistpos
kind
virtual
source_path
local_path
sha256
current
next
pos_ms
duration_ms
schedule_event
```

Kinds:
- media;
- saytime;
- commercial;
- jingle;
- scheduler;
- temperature;
- outros comandos virtuais.

`saytime=...` nunca pode virar missing físico.

### 4. Shadow Execution Engine

Substituir o legado `mirror-playout.py`.

O novo engine deve:
- ler a Canonical Effective Queue;
- tocar o current;
- iniciar em `pos_ms`;
- acompanhar drift;
- preparar next;
- reseek se necessário;
- continuar se RadioBOSS cair;
- executar itens virtuais;
- publicar em `radioprincipal-ns1`.

### 5. Asset Sync

Transferir somente o que realmente faltar:

Prioridade:
1. current;
2. next;
3. próximos itens;
4. eventos/comerciais iminentes;
5. restante.

Fluxo:

```
missing real
 -> pedir ao agente Windows
 -> SHA256
 -> upload
 -> verify
 -> local_path READY
 -> queue resolvida
```

### 6. Failover editorial

V3.2 já sabe alternar fonte de áudio.

O que falta é garantir que o `radioprincipal-ns1` esteja no mesmo:
- programa;
- item;
- posição aproximada;
- next;
- scheduler.

Quando isso estiver pronto, failover passa a ser editorialmente transparente.

---

## O que reaproveitar

Não reescrever:
- túnel SSH;
- Icecast V3.2;
- Core V3.2;
- MediaMTX;
- snapshots do radioboss-sync;
- media-transfer;
- object store;
- SHA256;
- estrutura humana /srv/studiosat/radio-principal;
- backup/rollback.

Reescrever/substituir:
- resolução de biblioteca;
- mirror-controller churn;
- `mirror-playout.py`;
- matched_index;
- lógica que trata virtual item como arquivo;
- qualquer playlist local independente do RadioBOSS.

---

## Gates de conclusão

O bloco biblioteca/sync só estará concluído quando:

1. alteração no RadioBOSS aparecer no NS1 em <=5s;
2. `librarymanifest.json` for consumido pelo resolver;
3. MP3 já existente no NS1 resolver para `local_path`;
4. current e next estiverem corretos;
5. `playlistpos` e `pos_ms` estiverem corretos;
6. `saytime` e scheduler não aparecerem como missing;
7. current/next local tiverem `READY`;
8. missing real disparar transferência automática;
9. `radioprincipal-ns1` seguir a mesma fila;
10. failover preservar item/posição aproximada.

---

## Ordem de implementação

```
A. Library Indexer
B. RadioBOSS Resolver
C. Canonical Effective Queue
D. Shadow Execution Engine
E. Asset Sync automático
F. Failover editorial
G. Console/observabilidade
```

Nada antes de A-B-C deve tentar “adivinhar” a programação por diretório ou índice físico.
