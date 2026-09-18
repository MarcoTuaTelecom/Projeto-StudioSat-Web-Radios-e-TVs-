# Rádio Principal V3.2

V3.2 elimina o ponto fraco do V3.1: o estado `live` só é considerado verdadeiro quando existem bytes PCM reais provenientes do decoder do RadioBOSS.

Dois decoders ficam quentes e são drenados continuamente:
- live: Icecast2 / RadioBOSS;
- fallback: radioprincipal-ns1.

Um único encoder público FFmpeg permanece vivo. O supervisor troca somente qual buffer PCM alimenta o encoder.

Promoção para live: 5 segundos contínuos de PCM real.
Retorno ao fallback: gap de PCM live >= 0,50 s.

O instalador exige que `ffprobe http://127.0.0.1:18005/radioprincipal-rb` entregue áudio ANTES do cutover. Se não entregar, tenta um único restart do Icecast e aguarda o reconnect do RadioBOSS. Se continuar sem áudio, aborta sem cortar o core atual.