# StudioSat Web — Change Queue

Regra: **uma alteração ativa por vez no host de produção**. Engenharia de TV e Rádio podem preparar documentação/candidates em paralelo, mas apenas uma change pode modificar o host por vez.

Protocolo obrigatório: `docs/30-execucao/PROTOCOLO_EXECUCAO_SINCRONIZACAO_v0.1.md`.

Diretriz vigente: **IN-PLACE FIRST / NO CONTAINERS / NO VMs / NO DUPLICATE PLATFORM**.

## Baseline oficial

CHG-004B está **DONE / PASS / LOCKED** com snapshot `2026-09-10T16:57:41Z`.

## Prioridade operacional vigente

Por determinação mais recente do owner em `2026-09-12`, a prioridade mutável imediata volta a ser **CHG-TVKIDS-001 — reconstrução integral da TVKIDS até produto HEALTHY em produção**.

As changes de Rádio ficam **PAUSED / PRESERVADAS**, sem descarte do trabalho já realizado. Nenhuma mutação Rádio deve ocorrer em paralelo com CHG-TVKIDS-001. O executor TVKIDS possui lock global, espera por mutações em andamento e valida que nenhum PID de outra emissora ou do MediaMTX mudou durante o cutover.

## Trilha crítica atual

| ID | Mudança | Dono | Estado | Gate |
|---|---|---|---|---|
| CHG-TVKIDS-001 | Reconstrução integral da cadeia TVKIDS | TV | **ACTIVE / PRIORIDADE ATIVA** | certificar canonical 15/15 → zero DTS → manifest/plan dedicado → cutover somente TVKIDS → MediaMTX/RTSP/HLS → quatro FQDNs → health final/rollback |
| CHG-R01 | Principal — escaping/playlist atômica | Rádio | **APPLY PASS / PAUSED PARA TVKIDS** | preservar estado atual |
| CHG-R02 | Rock — recovery legado | Rádio + Core | **RECOVERY EXECUTADA / PAUSED PARA TVKIDS** | validar na matriz Rádio quando retomada |
| CHG-R03 | Cinco rádios — AAC-LC 48 kHz estéreo + HLS real | Rádio + Core | **READY / PAUSED PARA TVKIDS** | retomar após CHG-TVKIDS-001 fechar ou reverter |
| CHG-RWEB01 | Radio Web — player sem www + portal com www + NGINX isolado | Rádio + Core | **READY / PAUSED PARA TVKIDS** | retomar após CHG-R03 |
| CHG-R04 | Separação generator Rádio/TV | Rádio + TV + Core | **PENDENTE** | preservar isolamento por domínio |
| CHG-TV-002+ | TVTEENS/TVVIVA/TVMAISJOVEM | Engenharia TV | **PENDENTE** | replicar somente após TVKIDS comprovadamente saudável |

## CHG-TVKIDS-001 — execução autorizada agora

Executor único:

```text
scripts/tv/tvkids-rebuild-production-v1.sh
```

O executor, em uma única change transacional:

1. exige `HEAD == origin/main` e verifica SHA de todos os arquivos do pacote;
2. obtém lock global de mudança e espera mutações concorrentes encerrarem;
3. preserva backup privado do generator, unit, NGINX, playlists, manifests e estado atual;
4. prova que a playlist efetivamente aberta pelo FFmpeg é 100% `canonical/` e corresponde ao conjunto canonical conhecido;
5. certifica todos os assets: perfil H.264 1280x720p30 yuv420p + AAC 48 kHz stereo e decode integral;
6. testa a timeline completa em dois ciclos e loop; se necessário, reconstrói **todos** os assets offline com timestamps determinísticos e exige 100% de sucesso — nenhum asset é silenciosamente descartado;
7. publica `ready.manifest.tsv`, `current.ffconcat`, `previous.ffconcat` e mantém `playlist.txt` como compatibilidade de transição;
8. instala builder e health dedicados TVKIDS e converte o dispatch do generator compartilhado para o builder TV dedicado;
9. faz cutover somente de `tps-tvkids-playout.service`;
10. exige MediaMTX `tvkids ready=true`, RTSP H.264/AAC correto e HLS local HTTP 200 com `#EXTM3U`;
11. corrige os aliases públicos TVKIDS no NGINX somente quando necessário, com `nginx -t` antes do reload;
12. exige root e HLS HTTP 200 nos quatro FQDNs públicos;
13. exige zero `Non-monotonic DTS` e zero erro fatal no journal do novo processo;
14. compara PIDs antes/depois e exige que nenhuma outra emissora nem MediaMTX tenha reiniciado;
15. em qualquer falha pós-mutação, executa rollback da TVKIDS e dos artefatos alterados.

Resultado de fechamento obrigatório:

```text
CHG_TVKIDS_001_RESULT=PASS
TVKIDS_PRODUCT=HEALTHY
```

## Rádio — estado preservado para retomada

CHG-R03 permanece preparado para converter as cinco rádios para AAC-LC 48 kHz estéreo/HLS, e CHG-RWEB01 permanece preparado para separar os webroots/NGINX de Rádio sem remover os hostnames TV. Esses candidates não são descartados; apenas deixam de ser a change mutável ativa enquanto TVKIDS é reconstruída.
