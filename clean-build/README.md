# Studio Sat — Clean Build NS1

Início do novo histórico operacional da reconstrução limpa do NS1.

- Data de início: 2026-09-23
- Branch: `clean-build-ns1-2026-09-23`
- Baseline preservada: commit `7f8406530058aa5a6e0c16c8589bed7a9cf895ae`
- Regra: não reescrever, apagar ou alterar o histórico anterior do projeto.
- Novo histórico: somente mudanças da reconstrução limpa do NS1 entram nesta branch.
- Arquitetura-alvo: 1 MediaMTX canônico, 5 playouts P2, 5 paths RTMP/HLS, Nginx, portal/player e handoff controlado para RadioBOSS.
- Componentes proibidos na reconstrução limpa: segundo MediaMTX, Icecast, Liquidsoap operacional, túneis antigos ou estruturas paralelas não aprovadas.

## Fases

1. Stop e quarentena do legado/duplicidades.
2. Remoção do legado de rádio comprovado.
3. Construção das cinco rádios, portal e handoff RadioBOSS.
4. Certificação somente leitura.

Os resultados reais de cada fase devem ser adicionados aqui somente depois de executados e certificados no NS1.
