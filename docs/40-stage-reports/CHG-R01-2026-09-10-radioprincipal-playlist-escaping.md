# CHG-R01 — Rádio Principal — correção determinística da playlist ffconcat

Status: **PREPARED / BLOCKED somente até CHG-004B = DONE/PASS/LOCKED**  
Owner: Engenharia Rádio  
Escopo mutável: **somente generator específico da Rádio Principal + playlist da Rádio Principal + restart da unit da Rádio Principal**  
Interlock: **nenhum Core global e nenhuma outra station podem ser reiniciados/alterados**

## Problema comprovado

O generator atual `/usr/local/sbin/tps-generate-playlist-radioprincipal-fixed` monta linhas `file '...'` sem escapar apóstrofo. O asset `Ain't No Mountain High Enough_spotdown.org.mp3` gera erro `Impossible to open` e interrompe a progressão normal da grade. CHG-004B confirmou 3 ocorrências em apenas 30 minutos.

## Decisão de menor mudança

- manter FFmpeg 6.1.1;
- manter `tps-playout-radio`;
- manter unit/path/publicação/MediaMTX/NGINX;
- manter semântica atual da Principal: scan recursivo de `ready/`, formatos MP3/M4A/AAC, exclusão case-insensitive de `test/teste`;
- corrigir **somente** escaping ffconcat e atomicidade do generator específico;
- não alterar generator global nesta Change;
- não alterar TV.

## Candidates versionados

- `candidates/CHG-R01/tps-generate-playlist-radioprincipal-fixed-v2.sh`
- `candidates/CHG-R01/validate-radioprincipal-playlist-v1.sh`
- `candidates/CHG-R01/observe-radioprincipal-rotation-v1.sh`

## Gate 0 — baseline obrigatório

CHG-R01 só pode executar depois de CHG-004B estar `DONE / PASS / LOCKED`. Até lá apenas preparação/revisão de candidate é permitida.

## Fase A — PRECHECK, zero mutação

1. SYNC do `main`, working tree limpa.
2. `bash -n` nos três candidates.
3. registrar SHA-256 dos três candidates.
4. confirmar exatamente 18 assets elegíveis atuais da Principal.
5. registrar PID/start timestamp da Principal.
6. registrar hash do generator atual e da playlist atual.
7. confirmar MediaMTX ready e RTSP PASS.
8. registrar PIDs das outras oito stations, MediaMTX e NGINX para prova de não impacto.

## Fase B — gerar e provar playlist candidate, sem tocar produção

Gerar `/tmp/CHG-R01-radioprincipal-playlist.candidate` usando o generator v2 executado como `tpsmedia`.

Gate obrigatório do validator:

```text
ELIGIBLE_COUNT=18
PLAYLIST_COUNT=18
MISSING_OR_TRUNCATED_LINES=0
FFPROBE_FAILURES=0
FULL_CONCAT_TRAVERSAL=PASS
RESULT=PASS
```

O validator compara cada asset elegível com sua linha ffconcat escapada e executa `ffprobe` individual. Depois percorre a playlist inteira sem `-re`, com `-c:a copy -f null -`, para provar que os 18 itens podem ser abertos sequencialmente. Um teste `-t 5` isolado não é aceito como prova de 18/18, pois alcançaria apenas o início da grade.

## Fase C — backup antes da primeira mutação

Criar diretório privado:

```text
/var/backups/studiosat/CHG-R01/<timestamp>/
```

Guardar:

- generator atual como `generator.previous`;
- playlist atual como `playlist.previous`;
- hashes SHA-256;
- `systemctl cat/show` da unit;
- health PRE específico da Principal.

O backup não vai ao GitHub público.

## Fase D — promover generator v2

Instalar o candidate validado no **mesmo path atual**:

```text
/usr/local/sbin/tps-generate-playlist-radioprincipal-fixed
```

Não criar novo service, nova árvore ou novo daemon. A promoção deve usar arquivo temporário no mesmo filesystem + rename/move atômico. Confirmar SHA-256 pós-promoção.

Enquanto a Principal atual continua rodando, essa troca do script não altera o processo FFmpeg já ativo; o ExecStartPre só será executado no restart controlado.

## Fase E — promover playlist nova antes do restart

Executar o generator corrigido como usuário `tpsmedia` para gerar `playlist.txt` atomicamente. O FFmpeg atual mantém FD para a playlist antiga, portanto o replace atômico não deve interromper a sessão corrente; isso deve ser confirmado pelo PID e MediaMTX antes do restart.

Reexecutar o validator contra a playlist de produção nova. Exigir 18/18 e full traversal PASS.

## Fase F — restart único e controlado

Registrar PRE no `RESTART_REGISTER.md` depois da execução.

Executar somente:

```text
systemctl restart tps-radioprincipal-playout.service
```

Proibido nesta Change:

```text
reboot
restart/reload MediaMTX
restart/reload NGINX
restart de Pop/Rock/Clássicas/Country
qualquer restart de TV
systemctl daemon-reload
```

Nenhum unit file será alterado, portanto `daemon-reload` não é necessário.

## Fase G — verificação imediata

Exigir:

- `systemd active/running`;
- novo MainPID e novo start timestamp;
- MediaMTX `radioprincipal` ready=true;
- RTSP ffprobe PASS com áudio;
- portal público 200;
- zero novo `Impossible to open` desde o restart;
- zero `NO_READY_MEDIA`;
- PIDs das outras oito stations, MediaMTX e NGINX sem mudança.

HLS Rádio já é incidente separado `INC-RADIO-003`; HTTP 500 de HLS não reprova isoladamente CHG-R01, mas deve permanecer explicitamente registrado como dívida existente, não mascarada.

## Fase H — prova de rotação completa

Executar o observer read-only após o restart. Ele acompanha os arquivos de `ready/` realmente abertos pelo PID da Principal via `/proc/<pid>/fd`, registra transições em `/tmp` e termina apenas quando os 18 assets elegíveis tiverem sido observados ou houver timeout.

Gate:

```text
ROTATION_RESULT=PASS
SEEN=18/18
```

Além disso, o log de transições deve comprovar que itens posteriores a `Ain't No Mountain High Enough...` foram realmente abertos pelo FFmpeg.

## Fase I — health POST e fechamento

Executar o mesmo health baseline usado no PRE e comparar:

- nenhum hash estático fora do escopo mudou;
- generator Principal mudou somente para a versão aprovada;
- playlist Principal mudou para a versão corrigida;
- outras playlists não mudaram;
- nenhuma outra station regrediu;
- MediaMTX/NGINX não reiniciaram;
- `Impossible to open` desde o restart = 0.

Depois:

1. publicar script final comprovado em `scripts/`;
2. atualizar `critical-artifacts-baseline.yaml`;
3. atualizar `channels-registry.yaml`;
4. atualizar `INCIDENT_REGISTER.md` — `INC-RADIO-001` só vira RESOLVED com todos os gates;
5. preencher `RESTART_REGISTER.md`;
6. fechar este Stage Report com hashes PRE/POST e evidências sanitizadas;
7. atualizar `CHANGE_QUEUE.md`;
8. reler `main` antes de liberar CHG-R02.

## Rollback

Se a Principal não voltar após o restart:

1. não tocar MediaMTX/NGINX/outras stations;
2. restaurar `generator.previous` para o path original atomicamente;
3. reiniciar **somente** a Principal;
4. verificar retorno ao estado AS-IS conhecido;
5. marcar `ROLLED_BACK`, preservar logs e não avançar.

O rollback devolve o estado anterior conhecido, que é degradado; por isso não conta como resolução, apenas como restauração de serviço.

## PASS final — "funcionando e perfeito" para este defeito

```text
18/18 assets elegíveis presentes e reproduzíveis
18/18 linhas ffconcat corretas
0 referência truncada
full concat traversal PASS
restart limpo da Principal
MediaMTX ready=true
RTSP PASS
0 novo Impossible to open
0 loop prematuro
rotação real SEEN=18/18
itens após Ain't... realmente executados
nenhuma outra station/Core reiniciou ou regrediu
rollback conhecido
documentação/hashes atualizados
```
