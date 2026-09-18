# ÂNCORA 02 — STREAMING CORE / MediaMTX + Nginx + HLS

## Identidade fixa

- `WORKSTREAM_ID`: `STREAMING-CORE`
- Nome recomendado do chat: `02 — STREAMING CORE — MediaMTX / Nginx / HLS — C01`
- Repositório mestre: `MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-`
- Missão: consolidar e estabilizar a camada comum de streaming da plataforma, sem absorver lógica editorial do RadioBOSS, lógica de Portal ou lógica do aplicativo.

---

# 1. RESULTADO FINAL DESTA FRENTE

Este chat deve terminar com uma camada de streaming que possa ser descrita, testada e operada por contrato.

Resultado esperado:

> **MediaMTX, Nginx, HLS, TLS, publishers, paths e health documentados e validados; caminhos públicos e internos claramente separados; configuração canônica identificada; testes read-only reproduzíveis; nenhuma dependência oculta de conversas antigas; interface estável para Rádio, TV, Portal e Failover.**

O objetivo não é “melhorar streaming para sempre”.

Quando os contratos estiverem estáveis e os critérios de saída cumpridos, esta frente deve ser marcada `READY_FOR_HANDOFF` ou `DONE`.

---

# 2. ESCOPO EXATO

## 2.1 MediaMTX

Responsável por:

- inventário de paths;
- publishers atuais;
- readers quando relevante;
- portas/protocolos;
- readiness;
- regras de path;
- comportamento quando publisher desaparece;
- diferenças entre path público, shadow, teste e laboratório;
- configuração canônica e localização real em produção.

Não decidir qual música deve tocar.

## 2.2 Nginx

Responsável por:

- virtual hosts;
- reverse proxy;
- roteamento HLS;
- headers;
- cache/no-cache;
- CORS;
- redirecionamentos;
- integração HTTPS;
- exposição pública dos paths.

Não editar conteúdo editorial do Portal para mascarar erro de infraestrutura.

## 2.3 HLS

Responsável por validar:

- resposta HTTP final;
- presença de `#EXTM3U`;
- atualização da playlist;
- disponibilidade dos segmentos;
- latência observável quando relevante;
- continuidade durante troca de publisher quando a arquitetura prever isso.

## 2.4 TLS / domínio

Responsável por:

- certificados usados;
- hosts atendidos;
- cadeia válida;
- redirects HTTP→HTTPS;
- comportamento dos subdomínios das emissoras.

## 2.5 Health

Criar/usar checks objetivos para:

- serviço MediaMTX;
- Nginx;
- path readiness;
- publisher presente/ausente;
- HLS público válido;
- endpoint final após redirects.

---

# 3. BASELINE HISTÓRICO DE REFERÊNCIA

O registry do projeto observado em 2026-09-10 registrou os paths públicos das cinco rádios e quatro TVs, com `radioprincipal` publicado via MediaMTX e health preliminar marcado como ativo/ready naquele momento.

Esse estado é **histórico**, não deve ser assumido como atual.

A nova conversa deve reconfirmar o estado vivo antes de qualquer mudança.

---

# 4. CONTRATOS COM OUTROS WORKSTREAMS

## 4.1 Com `RADIOPRINCIPAL-NS1`

Este workstream recebe:

- publisher/entrada RadioBOSS;
- publisher/saída shadow NS1;
- health necessário de cada fonte.

E fornece:

- paths MediaMTX estáveis;
- exposição HLS;
- health/readiness de transporte.

Não decide a lógica editorial de mirror.

## 4.2 Com `FAILOVER-SELECTOR`

Fornece:

- caminhos de entrada;
- paths de saída;
- readiness dos publishers;
- comportamento de MediaMTX/Nginx durante troca.

O selector decide prioridade, não este chat.

## 4.3 Com `PORTAL-WEB` e `MOBILE-APP`

Fornece contrato público:

`https://radio.studiosatweb.com.br/<station-id>/index.m3u8`

ou o contrato que vier a ser formalmente promovido.

Portal/Mobile não devem precisar conhecer portas internas ou configuração do MediaMTX.

## 4.4 Com `TV-CORE`

Compartilha apenas a infraestrutura e os contratos Core realmente comuns.

Não altera motor/planner de TV.

---

# 5. NÃO É RESPONSABILIDADE DESTE CHAT

Não deve:

- alterar playlist RadioBOSS;
- corrigir mirror de mídia;
- escolher `playback.json`;
- implementar scheduler/hora certa;
- desenvolver selector de prioridade;
- decidir política OBS/live;
- escrever CMS;
- mudar UI Portal;
- alterar aplicativo móvel;
- corrigir conteúdo editorial;
- reconstruir motores TV/Rádio.

Problemas dessas áreas devem virar dependência explícita.

---

# 6. FASES OBRIGATÓRIAS

## Fase A — Inventário somente leitura

Coletar:

- versão e processo do MediaMTX;
- arquivo/configuração efetivamente carregada;
- portas escutando;
- API/metrics disponíveis, se habilitadas;
- paths configurados;
- publishers atuais;
- serviços systemd relacionados;
- configuração Nginx ativa;
- symlinks de `sites-enabled`/equivalente;
- hosts/certificados;
- rotas públicas HLS;
- redirects.

**Saída:** topologia real atual.

## Fase B — Mapa canônico de paths

Classificar cada path como:

- `PUBLIC`;
- `AUTHORITATIVE_INPUT`;
- `SHADOW`;
- `TEST`;
- `LAB`;
- `LEGACY`;
- `UNKNOWN`.

Nenhum path deve continuar “misterioso”.

## Fase C — Configuração canônica

Identificar qual arquivo/configuração é efetivamente usado por:

- MediaMTX;
- Nginx;
- systemd/containers quando aplicável.

Diferenciar claramente:

- arquivo ativo;
- backup;
- candidate;
- legado;
- configuração não carregada.

## Fase D — Health contract

Definir testes read-only reproduzíveis.

Exemplo lógico:

```text
DNS/TLS
  ↓
Nginx HTTPS
  ↓
MediaMTX path
  ↓
HLS playlist 200 + #EXTM3U
  ↓
segmentos acessíveis
```

## Fase E — Correções mínimas

Somente após baseline e contrato.

Uma mudança por vez.

## Fase F — Validação cruzada

Testar pelo menos:

- Rádio Principal;
- demais rádios sem alterar lógica editorial;
- paths TV críticos;
- endpoint público usado pelo Portal/Mobile.

## Fase G — Handoff

Entregar contrato estável para:

- `RADIOPRINCIPAL-NS1`;
- `FAILOVER-SELECTOR`;
- `PORTAL-WEB`;
- `MOBILE-APP`;
- `TV-CORE`.

---

# 7. DEFINITION OF DONE

- [ ] inventário vivo de MediaMTX concluído;
- [ ] inventário vivo de Nginx concluído;
- [ ] portas/protocolos identificados;
- [ ] configuração ativa identificada;
- [ ] todos os paths relevantes classificados;
- [ ] publishers/readiness observáveis;
- [ ] hosts/TLS/redirects documentados;
- [ ] contrato HLS público testado;
- [ ] health read-only reproduzível;
- [ ] CORS/cache relevantes validados;
- [ ] caminhos legacy/test/lab separados do público;
- [ ] nenhuma correção depende de arquivo que não está carregado;
- [ ] rollback conhecido para mudanças aplicadas;
- [ ] ACTIVE STATE atualizado;
- [ ] handoff de contratos produzido.

Ao cumprir os critérios:

`STREAMING_CORE=READY_FOR_HANDOFF`

Não iniciar uma nova reengenharia depois disso dentro do mesmo marco.

---

# 8. PROTOCOLO ANTI-LOOP

## Erro em Nginx

Antes de editar:

1. `nginx -T`/equivalente para descobrir configuração carregada;
2. localizar o server block efetivo;
3. verificar conflito/duplicata;
4. só então criar candidate.

Nunca editar um arquivo apenas porque “parece ser o certo”.

## Erro em MediaMTX

Antes de editar:

1. confirmar processo;
2. confirmar config carregada;
3. confirmar path/publisher real;
4. confirmar log/health;
5. só então mudar uma regra.

## Duas tentativas sem progresso

Parar alterações e voltar a diagnóstico.

## Três falhas básicas de sintaxe/config

Suspender mutações, simplificar, validar localmente/sintaticamente e só então retomar.

---

# 9. REGRA DE SEGURANÇA OPERACIONAL

Toda mudança deve declarar:

```text
HOST:
COMPONENT: NGINX | MEDIAMTX | TLS | SYSTEMD
MODE: READ-ONLY | MUTABLE
PUBLIC_IMPACT: NONE | POSSIBLE | EXPECTED
BACKUP:
ROLLBACK:
VALIDATION:
```

Antes de reload:

- Nginx: validar sintaxe;
- MediaMTX: validar configuração conforme capacidade disponível;
- systemd: verificar unidade alvo;
- TLS: não substituir certificado sem confirmar hosts.

Não reiniciar múltiplos serviços como “tentativa”.

---

# 10. DISCIPLINA DE CÓDIGO/CONFIGURAÇÃO

Configuração entregue precisa ser:

- sintaticamente válida;
- mínima;
- sem placeholders ambíguos quando for para execução;
- sem misturar trechos antigos e novos;
- com caminho de destino explícito;
- acompanhada de comando de validação;
- acompanhada de rollback.

Erros de indentação YAML, chaves Nginx, quoting shell ou nomes de paths são falhas técnicas e devem ser corrigidos antes da entrega.

---

# 11. FORMATO OBRIGATÓRIO DE PROGRESSO

```text
STREAMING-CORE STATUS
PHASE:
SCOPE_TARGET:
LAST_CONFIRMED_TOPOLOGY:
LAST_CHANGE:
RESULT: PASS | FAIL | PARTIAL
PUBLIC_IMPACT:
BLOCKER:
NEXT_SINGLE_STEP:
DOD_PROGRESS: X/15
```

---

# 12. PRIMEIRO OBJETIVO DO C01

O C01 não deve começar “consertando tudo”.

Deve produzir primeiro:

1. topologia real de MediaMTX;
2. topologia real de Nginx;
3. mapa de paths da Rádio Principal e demais canais;
4. quais paths são público, entrada autoritativa, shadow, test, lab e legacy;
5. matriz entre registry histórico e estado vivo.

Formato obrigatório:

```text
ITEM | REGISTRY/HISTÓRICO | ESTADO VIVO | CLASSIFICAÇÃO | EVIDÊNCIA | AÇÃO
```

Somente depois escolher a primeira divergência realmente necessária ao Definition of Done.
