# V2.2 — transporte RAW AAC no nível abaixo do HLS/MSE

## Motivo

O HLS cru da Rádio Principal e o player de referência reproduzem corretamente, enquanto browsers baseados em MSE ainda apresentaram, em média, oscilações e silêncio periódico.

A telemetria de playbackRate não explica sozinha esse comportamento: um player MSE pode saltar pequenos buracos do buffer ou nudging de currentTime sem alterar playbackRate.

## Nova arquitetura do portal

O navegador deixa de receber HLS como transporte principal.

\`\`\`text
HLS público já validado
        ↓
FFmpeg no servidor
        ↓
demux somente: -c:a copy
        ↓
AAC-LC em ADTS contínuo
        ↓
Rust broadcast live
        ↓
Nginx proxy_buffering off
        ↓
<audio src="...aac">
        ↓
decoder nativo do navegador
\`\`\`

Não existe nova compressão. O AAC contido no HLS é copiado para ADTS.

## Propriedade contra áudio empilhado

O broadcast Tokio é live. Cada cliente assina frames futuros. Se um cliente ficar atrasado, o receiver reporta lag e os frames antigos são descartados; não são drenados depois em velocidade maior.

## Fronteira de frames

O Rust analisa o cabeçalho ADTS e só publica frames AAC completos. Assim um novo ouvinte começa em fronteira válida de frame, não no meio de um chunk arbitrário do stdout do FFmpeg.

## Rotas

\`\`\`text
/listen-v2/live/radioprincipal.aac
/listen-v2/live/radiopop.aac
/listen-v2/live/radiorock.aac
/listen-v2/live/radioclassicas.aac
/listen-v2/live/radiocountry.aac
\`\`\`

## Fallback

Se o browser não declarar suporte a audio/aac, o portal permite somente HLS nativo do próprio navegador. Não existe fallback HLS.js/MSE no V2.2.

## Critério de aprovação

1. testar primeiro o link .aac diretamente;
2. testar o portal V2.2;
3. trocar repetidamente de emissora;
4. ouvir pelo menos 10 minutos;
5. comparar com /diag-bypass/ e o HLS cru.

O portal só é aprovado quando não houver silêncio, aceleração ou desaceleração perceptíveis.
