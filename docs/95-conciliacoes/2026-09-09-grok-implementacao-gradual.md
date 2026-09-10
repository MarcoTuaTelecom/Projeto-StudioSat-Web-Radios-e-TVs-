**StudioSat Web — Implementação Gradual no Host Atual (ns1)**

**Versão 1.0 • 09/09/2026**

**Base:** DOC-000 (Arquitetura Mestre) + DOC-010 + Runbook Mestre + estado real do servidor

---

### Princípio fundamental deste documento

O servidor **já tem 9 emissoras no ar** (5 rádios + 4 TVs) usando FFmpeg + MediaMTX + Nginx.

**Não se reconstrói por cima.**

Constrói-se **ao lado**, prova-se em laboratório, corta-se **uma emissora por vez** e mantém-se rollback imediato.

Qualquer mudança global (MediaMTX, Nginx, firewall, FFmpeg do sistema, usuário tpsmedia) exige gate conjunto TV + Rádio.

---

## 1. Mapa atual do servidor (o que já existe e deve ser preservado)

| Componente | Estado atual | Dono lógico | Regra |
|---|---|---|---|
| Host | Ubuntu 24.04, 2 vCPU, ~7,8 GiB RAM, sem GPU | Core | Não atualizar FFmpeg/kernel sem janela |
| MediaMTX | tps-mediamtx.service (portas 1935, 8888, 9997) | Core | Não reiniciar até inventário completo |
| Nginx | Vários confs em /etc/nginx/conf.d/ | Core | nginx -t antes de qualquer reload |
| Playout | 9 units tps-<canal>-playout.service | Por canal | Isolamento já existe — preservar |
| Gerador de playlist | /usr/local/sbin/tps-generate-playlist (só canonical/ + m4a/mp4) | Legado | Problema conhecido |
| Mídia | /srv/tpsmedia/repository/channels/<canal>/{ready,canonical,playlists,...} | Por canal | Não mover agora |
| Usuário | tpsmedia | Core | Não mudar ownership global ainda |
| Certificados | studiosatweb-completo + outros | Core | Manter |

**Paths públicos atuais a preservar:**
- Rádio portal: www.radio.studiosatweb.com.br
- Rádio player: radio.studiosatweb.com.br / *.studiosatweb.com.br (sem www = tela cheia)
- TVs: www.tvkids..., tvkids..., etc.

## 2. Tecnologias por domínio

### 2.1 Núcleo compartilhado (Core)
- **MediaMTX:** router de paths; não usar como scheduler; não reiniciar para criar lab se afetar produção.
- **Nginx:** origin/TLS + proxy HLS + portais; não colocar lógica editorial em regex.
- **systemd:** uma unit por emissora + slices futuros; não colocar várias emissoras no mesmo processo.
- **Certbot:** renovação dos certificados existentes; não criar novos certificados sem inventário.
- **Ingest/QC:** framework comum incoming → probe → conformação offline → QC → canonical → READY; profiles diferentes por classe; não normalizar em tempo real no playout.

### 2.2 Televisão
- FFmpeg `-c copy` no playout atual e primeiro cutover.
- ffconcat como playlist de produção e candidate; publicação atômica.
- Canonical TV: H.264 1280×720p30 + AAC 48 kHz; decode integral antes de READY.
- Lab path separado do público.
- Health: vídeo + áudio + DTS + freshness HLS; zero Non-monotonic DTS após cutover.

### 2.3 Rádio
- Liquidsoap 2.4.x como piloto preferencial em lab isolado.
- FFmpeg legado continua até cutover.
- Dual rendition: mesma timeline → A/V + áudio-only.
- Live: input RTMP + switch/timeout/fallback.
- Canonical rádio separado do profile TV.
- Lab paths separados da produção.

## 3. Ordem de execução real

### FASE 0 — Freeze + Backup + Preflight
1. Snapshot da VM no Google Cloud.
2. Validar e executar o preflight somente leitura.
3. Confirmar que nenhum serviço mudou de estado.
4. Guardar `.tar.gz` + `.sha256` shareable.
5. Não enviar backup privado.

**Gate F0:** produção continua exatamente como estava + pacote de evidência existe. **Pare aqui** até análise.

### FASE 1 — Rebaseline e channels-registry
- Mapear 9 units reais, paths MediaMTX, playlists, publishers e endpoints.
- Classificar riscos P0/P1/P2.
- Criar channels-registry com station_id, domain, unit, media_root, paths e owner.

### FASE 2 — P0 operacional compartilhado
- Confirmar backup íntegro.
- `certbot renew --dry-run` controlado.
- Readiness check antes de restart de publisher.
- Mapear todos os publishers antes de bind/auth.
- Ainda não: firewall, autenticação MediaMTX, remoção de portas, mudança de usuário.

### FASE 3 — TVKIDS
1. Hash/inventário de canonical e ready.
2. Decode integral fora de pico.
3. candidate.ffconcat somente com assets aprovados.
4. Path de laboratório separado.
5. Observar transições, meta zero Non-monotonic DTS.
6. Cutover controlado apenas TVKIDS.
7. Observar 24 h.

### FASE 4 — Radio Country LAB
1. Criar árvore isolada.
2. Instalar Liquidsoap somente se não conflitar com FFmpeg/libs; senão VM/container isolado.
3. Corpus lab: 3 clips A/V + comercial + vinheta + fallback.
4. Duas saídas da mesma source: A/V + áudio-only.
5. Paths lab separados.
6. Testar 24 h, fallback, live, foreground/background.
7. Shadow real ≥24 h.

### FASE 5 — Cutover Country
- Troca somente do roteamento/publicação do endpoint Country.
- FFmpeg legado pronto para rollback.
- Observação 24–72 h.
- Desabilitar unit legada só depois; não apagar.

### FASE 6 — Hardening compartilhado
- MediaMTX auth publish/API loopback/protocolos não usados.
- Nginx server_name/cache HLS.
- systemd slices tps-tv/tps-radio.
- TLS com mecanismo único de renew.
- Firewall somente após mapear publishers.
- Validar pelo menos 1 TV + 1 Rádio.

### FASE 7–10 — Replicação
- TVs: TVTEENS → TVVIVA → TVMAISJOVEM.
- Rádios: Pop → Clássicas → Rock → Principal.
- Uma estação por vez, sempre com shadow + rollback.

### FASE 11+ — Control Plane, legado, CDN/HA
Somente depois dos engines reais comprovados.

## 4. Tecnologias por emissora

### Rádios
- `radioprincipal`: FFmpeg atual; Liquidsoap por último; maior heterogeneidade.
- `radiopop`: FFmpeg atual; candidato Liquidsoap.
- `radiorock`: FFmpeg atual/estado precisa ser reconfirmado; corrigir inventário antes.
- `radioclassicas`: FFmpeg atual; candidato Liquidsoap.
- `radiocountry`: FFmpeg atual; primeiro piloto Liquidsoap.

Cada rádio terá path A/V + áudio-only, unit própria, canonical próprio e fallback editorial.

### TVs
- `tvkids`: FFmpeg `-c copy`, canonical — primeiro piloto.
- `tvteens`, `tvviva`, `tvmaisjovem`: replicação do padrão validado, uma por vez.

## 5. Regras de ouro
1. Nunca reiniciar MediaMTX ou Nginx sem gates específicos.
2. Nunca alterar gerador globalmente sem preflight.
3. Nunca mover ready/canonical de produção apenas para organizar.
4. Lab sempre em path distinto.
5. Cutover atômico + rollback em minutos.
6. Health mede produto, não só processo.
7. Falha de uma emissora não pode derrubar outras.

## 6. Próximo passo concreto
Executar somente Fase 0 e enviar o pacote shareable. Depois gerar Matriz P0 atualizada e comandos exatos da primeira mudança segura.
