# Modo de operação simultânea — Chats 00, 01 e 02

## Objetivo

Permitir trabalho paralelo no ChatGPT sem duplicação, conflito ou loop.

## Chats ativos

### 00 — MASTER — Coordenação Studio Sat — C01

`WORKSTREAM_ID: MASTER-COORD`

Decide prioridade, registra dependências e cobra conclusão. Não faz debug profundo.

### 01 — RÁDIO PRINCIPAL — RadioBOSS → NS1 — C02

`WORKSTREAM_ID: RADIOPRINCIPAL-NS1`

Conclui mirror/playback/runtime/scheduler/shadow da Rádio Principal. Não altera Core de streaming global.

### 02 — STREAMING CORE — MediaMTX / Nginx / HLS — C01

`WORKSTREAM_ID: STREAMING-CORE`

Conclui topologia e contratos de MediaMTX/Nginx/HLS/TLS. Não altera lógica editorial RadioBOSS/mirror.

---

# Regra de autoridade

```text
00 MASTER
   │
   ├── coordena / decide prioridade / registra
   │
   ├──────────────┐
   ▼              ▼
01 RADIO        02 STREAMING
PRINCIPAL       CORE
   │              │
   └──── handoff ─┘
```

00 não substitui 01/02.
01 não muda 02 para contornar bug do mirror.
02 não muda 01 para contornar bug de transporte.

---

# Regra de modificação simultânea

É permitido trabalhar simultaneamente quando os arquivos/componentes são diferentes.

É proibido dois chats aplicarem mudança mutável no mesmo serviço/arquivo de produção ao mesmo tempo.

Antes de qualquer mudança com impacto público, registrar no MASTER:

- workstream dono;
- componente;
- janela/change;
- rollback;
- outro workstream potencialmente afetado.

---

# Contrato 01 → 02

01 pode informar a 02:

- nome/path esperado da entrada RadioBOSS;
- nome/path esperado do shadow NS1;
- health necessário para considerar publisher utilizável.

01 não deve editar Nginx/MediaMTX global para produzir esses paths sem coordenação.

# Contrato 02 → 01

02 entrega a 01:

- path confirmado para RadioBOSS;
- path confirmado para shadow NS1;
- readiness/publisher observável;
- endpoint de teste/HLS quando aplicável;
- limitações de transporte conhecidas.

02 não decide qual item deve tocar.

---

# Comunicação com 00

01 e 02 não devem enviar logs gigantes ao MASTER.

Enviar somente:

```text
WORKSTREAM:
MILESTONE:
RESULT: PASS | FAIL | PARTIAL
EVIDENCE:
DEPENDENCY:
NEXT_SINGLE_STEP:
DOD_PROGRESS:
```

00 atualiza MASTER/NEXT-STEPS a partir disso.

---

# Política anti-loop compartilhada

1. máximo uma hipótese mutável por vez;
2. duas tentativas sem progresso → diagnóstico;
3. três erros básicos consecutivos → suspender mutações;
4. fatos > suposições > memória do chat;
5. não criar nova arquitetura para erro localizado;
6. não criar nova frente para evitar concluir a atual;
7. backlog não é trabalho ativo;
8. todo marco precisa de critério de saída.

---

# Critério para abrir novos chats

Não abrir `03 FAILOVER` como workstream mutável até:

- 01 estar `READY_FOR_HANDOFF` ou ter interfaces estáveis suficientes;
- 02 estar `READY_FOR_HANDOFF` ou ter paths/health estáveis suficientes;
- 00 registrar que a dependência foi satisfeita.

---

# Regra para troca de ciclo

Se um chat ficar lento:

- atualizar o ACTIVE STATE;
- registrar último marco e próximo passo;
- abrir novo ciclo com o mesmo `WORKSTREAM_ID`;
- não criar um novo workstream.

Exemplo:

`01 — RÁDIO PRINCIPAL — ... — C02` → `C03`

O arquivo ACTIVE e a âncora permanecem os mesmos.
