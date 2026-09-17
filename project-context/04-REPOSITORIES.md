# Studio Sat — Mapa de repositórios

## `Projeto-StudioSat-Web-Radios-e-TVs-`

**Papel:** Core / OPS / coordenação / contexto mestre.

### Deve conter

- contratos Core;
- registry de canais;
- health/observabilidade;
- MediaMTX/Nginx compartilhado;
- NS1/NS2;
- RadioBOSS/mirror;
- runbooks;
- recovery operacional;
- candidates e stage reports;
- contexto mestre e handoffs.

### Não deve conter

- credenciais reais;
- chaves privadas;
- dumps privados;
- código de UI móvel que pertença ao app.

## `portal`

**Papel:** produto web.

### Deve conter

- portal público;
- admin/CMS;
- API editorial;
- modelo de dados;
- uploads/public assets sob contrato;
- configuração de deploy exclusiva desse produto web;
- testes/CI do portal.

### Pode receber futuramente

- PWA/player web;
- página de download do aplicativo.

## `Radio-Studio-Sat-Mobile-App`

**Papel:** aplicativo cliente.

### Deve conter

- Expo/React Native;
- Android/iOS;
- componentes e hooks;
- consumo de API/HLS/metadata;
- assets do app;
- EAS;
- build/release específico do app.

### Deve deixar de conter progressivamente

- scripts de recuperação de servidor;
- scripts de alteração de Nginx/MediaMTX;
- reparo de portal;
- validação operacional completa de NS1;
- publicação direta em diretórios do portal.

## Regra para novos arquivos

Antes de criar um arquivo novo, pergunte qual das três perguntas abaixo descreve melhor a responsabilidade:

1. **Altera/observa a plataforma ou servidor?** -> Core/OPS.
2. **Entrega experiência web/CMS/API?** -> Portal.
3. **Entrega o aplicativo Android/iOS?** -> Mobile.

Se um script responder "sim" a mais de uma pergunta, ele provavelmente precisa ser dividido em dois scripts conectados por um contrato simples.
