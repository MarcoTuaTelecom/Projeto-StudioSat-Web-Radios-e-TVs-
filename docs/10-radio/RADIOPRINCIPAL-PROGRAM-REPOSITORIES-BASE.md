# Repositórios-base de programação — Rádio Principal

Diretórios no NS1:

- `/srv/tpsmedia/repository/channels/radioprincipal/programacoes/manha`
- `/srv/tpsmedia/repository/channels/radioprincipal/programacoes/tarde`
- `/srv/tpsmedia/repository/channels/radioprincipal/programacoes/noite`

O operador pode enviar os MP3 para essas pastas por SFTP/SSH.

O sincronizador V2 lê a autoridade atual do RadioBOSS e o `media-map` canônico a cada 5 segundos. Para cada arquivo já presente no `mirror-store`, cria hardlink no repositório de programa correspondente, preservando o nome original do arquivo. Não duplica bytes quando o filesystem permite hardlink.

O link `programacoes/atual` aponta para a programação detectada pelo caminho do item atual do RadioBOSS (manhã/tarde/noite).

Importante: estes repositórios são base da reconstrução V2. Eles não substituem diretamente o selector/shadow público durante a fase de construção; isso evita downtime. O execution engine V2 será ligado a eles e testado em path isolado antes de qualquer cutover.
