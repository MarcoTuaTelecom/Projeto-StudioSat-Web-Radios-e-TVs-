# Studio Sat — Rádio Principal — estrutura operacional humana

Caminho oficial para operação manual:

`/srv/studiosat/radio-principal/`

## Grade
- `grade/manha`
- `grade/tarde`
- `grade/noite`
- `grade/ATUAL` aponta para a grade detectada no RadioBOSS.

## Elementos
- `elementos/comerciais`
- `elementos/vinhetas`
- `elementos/hora-certa`
- `elementos/temperatura`

## Operação
- `operacao/importar`
- `operacao/quarentena`
- `estado`

O técnico pode usar SFTP diretamente nessa árvore. O sincronizador V2 importa por hardlink os assets já existentes no legado, preservando os MP3 manuais e sem reiniciar a produção.

## API local do operador
Base: `http://127.0.0.1:8810`

- GET `/api/v1/status`
- GET `/api/v1/programas`
- GET `/api/v1/programas/manha`
- GET `/api/v1/programas/tarde`
- GET `/api/v1/programas/noite`
- POST `/api/v1/operacao/nota`

Durante a reconstrução, qualquer `POST /api/v1/producao/*` retorna HTTP 423. A API não pode reiniciar/parar a Rádio Principal até o novo execution engine e os gates serem aprovados.

Próxima etapa: autenticação HTTPS e painel web do técnico, depois canonical effective queue e execution engine V2 isolado.
