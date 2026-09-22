# iOS V2 — teste em iPhone

O código nativo está em:

\`\`\`text
StudioSAT-V2/native/ios/
\`\`\`

Tecnologia:

\`\`\`text
SwiftUI -> AVPlayer -> AVFoundation/CoreAudio
\`\`\`

Não existe WKWebView no caminho da mídia.

## Estado atual

O projeto-fonte existe e a CI pode compilar para iOS Simulator sem assinatura. Isso prova compilação, mas um binário de Simulator não instala em iPhone físico.

## Para instalar em um iPhone físico

É necessário assinar a aplicação com uma conta Apple Developer. Há duas rotas:

1. Xcode em um Mac conectado ao iPhone, usando o Team da Studio Sat.
2. TestFlight/App Store Connect com certificado/perfil/API key de distribuição.

Sem a assinatura Apple não existe IPA instalável legitimamente em um iPhone físico.

## Build local em Mac

\`\`\`bash
brew install xcodegen
cd StudioSAT-V2/native/ios
xcodegen generate
open StudioSatV2.xcodeproj
\`\`\`

No Xcode:
- escolha o Team da Studio Sat;
- escolha o iPhone conectado;
- Run.

## Transporte

A primeira build nativa usa AVPlayer com os HLS oficiais, porque o HLS cru já foi aprovado auditivamente e o AVPlayer é o mecanismo nativo da Apple.

O transporte RAW AAC do portal V2.2 também fica disponível para testes comparativos em Safari:
\`\`\`text
https://www.radio.studiosatweb.com.br/listen-v2/live/radioprincipal/stream.aac
\`\`\`
