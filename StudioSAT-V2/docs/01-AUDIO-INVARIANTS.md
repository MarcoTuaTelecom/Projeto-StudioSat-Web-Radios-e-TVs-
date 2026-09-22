# Invariantes de áudio

1. HLS é aberto diretamente pelo motor de mídia do cliente.
2. A aplicação não decodifica PCM para desenhar VU.
3. O player não altera `playbackRate` para alcançar a borda ao vivo.
4. Metadados não podem pausar, buscar ou substituir o stream.
5. Troca de emissora só ocorre por ação explícita.
6. Web não usa AudioContext/MediaElementSource/AnalyserNode/GainNode.
7. Android usa Media3; iOS usa AVPlayer.
8. O servidor V2 não transcodifica mídia.
9. Nginx só entrega a aplicação V2.
10. Toda mudança exige comparação com HLS cru + teste auditivo humano.
