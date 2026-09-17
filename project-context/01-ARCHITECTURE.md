# Studio Sat — Arquitetura canônica de repositórios

## Objetivo

Separar produto, operação e histórico para reduzir acoplamento técnico, facilitar rollback e permitir que novos chats e novos engenheiros carreguem apenas o contexto necessário.

## Camadas

```text
ChatGPT Project / engenharia
            |
            v
Projeto-StudioSat-Web-Radios-e-TVs-   (CORE / OPS / MASTER)
            |
     +------+------+
     |             |
     v             v
portal          Radio-Studio-Sat-Mobile-App
WEB/CMS/API     MOBILE CLIENT
     |             |
     +------ API/HLS contracts ------+
                    |
                    v
             Produção NS1/NS2
          Nginx + MediaMTX + playout
```

## 1. Core / OPS

O repositório Core é a autoridade para infraestrutura e coordenação transversal.

Estrutura alvo:

```text
project-context/
  00-MASTER.md
  01-ARCHITECTURE.md
  02-DECISIONS.md
  03-NEXT-STEPS.md
  04-REPOSITORIES.md
  05-HANDOFF-TEMPLATE.md
  checkpoints/

docs/
  00-core/
  10-radio/
  20-tv/
  30-execucao/
  40-stage-reports/
  90-evidencias/
  95-conciliacoes/

registry/

scripts/
  health/
  deploy/
  recovery/
  mirror/
  radioboss/
  mediamtx/
  nginx/
  context/

candidates/
legacy/
```

### Regra

Um script que altera NS1/NS2, Nginx, MediaMTX, CMS, mirror, RadioBOSS ou health transversal não pertence ao repositório Mobile.

## 2. Portal

Estrutura alvo, preservando o produto atual:

```text
portal/
  public/
    index.html
  admin/
    index.html
  backend/
    server.py
  data/
    content.json
  deploy/
    nginx/
    systemd/
  docs/
  tests/
  .github/workflows/
```

Em uma fase posterior, o player/PWA e a página de download atualmente mantidos no repositório Mobile podem ser promovidos para este repositório, porque são superfícies web, não código nativo Android/iOS.

## 3. Mobile

Estrutura alvo:

```text
Radio-Studio-Sat-Mobile-App/
  App.tsx
  src/
    components/
    config/
    hooks/
    screens/
    services/
    types/
  assets/
  scripts/
    build/
    release/
    assets/
  docs/
  .github/workflows/
  app.json
  eas.json
  package.json
  package-lock.json
  tsconfig.json
```

### Regra

O Mobile pode consumir Portal/API/HLS, mas não deve configurar Nginx, reparar NS1 nem escrever diretamente em `/var/www/...`.

## 4. Contratos entre repositórios

### Conteúdo

Portal publica `/api/content`.

O Mobile consome o contrato sem conhecer o armazenamento interno do CMS.

### HLS

Core/OPS mantém a disponibilidade dos streams.

Portal e Mobile consomem os streams por URL pública.

### Metadata

Core/OPS é responsável pela geração/publicação do metadata operacional.

Clientes consomem `/assets/now/<station-id>.json`.

## 5. Fonte única de configuração

Evitar repetir hosts em vários arquivos. A direção alvo é:

- base URLs em uma única configuração de runtime/build do Mobile;
- lista editorial de emissoras vinda do `/api/content` quando disponível;
- defaults locais apenas como fallback seguro;
- IDs técnicos das cinco emissoras permanecem estáveis.

## 6. Migração sem quebra

A reorganização deve ser feita em fases:

1. documentar autoridade e baseline;
2. copiar scripts de OPS para o Core sem apagar a origem;
3. validar hashes e comportamento;
4. promover os scripts copiados como canônicos;
5. só depois remover duplicatas do Mobile;
6. mover superfícies web/PWA apenas após deploy paralelo e comparação;
7. refatorar código interno do app depois da separação operacional.

Nenhum passo exige interrupção do streaming para reorganizar Git.
