# NS1 — restauração validada do estado de 11/09/2026

**Data da validação:** 21/09/2026  
**Host:** ns1.tpsolutions.com.br  
**Escopo:** Studio Sat Web — 5 rádios + 4 TVs + portal/player/aplicativos

## Decisão operacional

O ponto de restauração escolhido para o NS1 foi o estado de **11/09/2026**, anterior às 18:00 do Brasil.

O material de referência do portal usado na investigação foi:

```text
/root/QUARENTENA-PRE-REBUILD-20260920T180717Z/root-scripts/portal-prod-20260911-180716-k2juLq
```

Esse ponto comprovou as cinco rádios publicando HLS naquele período.

Também foi preservado um backup de segurança imediatamente antes da reversão do portal:

```text
/root/PRE-RESTORE-1109-20260921T005008Z
```

e um backup antes da restauração operacional das nove emissoras:

```text
/root/PRE-FINAL-RESTORE-9-20260921T005221Z
```

## Resultado validado da restauração

Após a restauração operacional:

| Emissora | systemd | HLS | RTSP |
|---|---|---|---|
| radioprincipal | active | 200 | AAC / áudio |
| radiopop | active | 200 | AAC / áudio |
| radiorock | active | 200 | AAC / áudio |
| radioclassicas | active | 200 | AAC / áudio |
| radiocountry | active | 200 | AAC / áudio |
| tvteens | active | 200 | H264 / vídeo + AAC / áudio |
| tvviva | active | 200 | H264 / vídeo + AAC / áudio |
| tvmaisjovem | active | 200 | H264 / vídeo + AAC / áudio |
| tvkids | active | pendente | pendente |

MediaMTX e NGINX ficaram **ativos**.

O portal e o player voltaram a responder:

```text
https://www.radio.studiosatweb.com.br/  -> HTTP 200
https://radio.studiosatweb.com.br/      -> HTTP 200
```

O CMS também ficou ativo e respondeu `HTTP 200` em `127.0.0.1:8789/api/health`.

A API pública válida nesse estado é:

```text
/api/public/content -> HTTP 200
```

## Situação da TVKIDS

A infraestrutura da TVKIDS foi restaurada e o serviço `tps-tvkids-playout.service` sobe como `active`.

Os arquivos de vídeo existentes foram testados individualmente com `ffprobe` e teste de decodificação FFmpeg, sem falha nos testes individuais.

A única pendência operacional restante está concentrada na **TVKIDS** e deve ser tratada no conteúdo/playlist da emissora, sem alterar as cinco rádios, as outras três TVs, MediaMTX ou NGINX.

### Próxima ação

1. Colocar/repor os vídeos corretos da programação da TVKIDS em:
   ```text
   /srv/tpsmedia/repository/channels/tvkids/ready
   ```
2. Regenerar a playlist da TVKIDS.
3. Reiniciar somente `tps-tvkids-playout.service`.
4. Validar:
   - serviço `active`;
   - HLS `HTTP 200`;
   - RTSP com H264 + AAC;
   - estabilidade do RTMP no MediaMTX.

## Estado de referência

**Conclusão:** o estado restaurado de 11/09 é o baseline operacional aprovado para recuperação do NS1. As cinco rádios, três TVs, MediaMTX, NGINX, portal, player e CMS foram recuperados. A pendência residual está isolada na TVKIDS e deve ser resolvida pela reposição/organização de mídia e nova validação do playout.

Não executar novas reconstruções globais, V2/V3/V8, mirrors, fallbacks adicionais ou alterações compartilhadas enquanto esse baseline estiver sendo usado como referência.
