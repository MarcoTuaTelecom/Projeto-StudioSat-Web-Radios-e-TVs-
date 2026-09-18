# RESET-01B — RadioBOSS-only public selector

RESET-01A abortou com segurança porque a configuração ativa havia mudado de `[rb, local, security]` para `[rb, local]`.

RESET-01B suporta os dois estados observados e normaliza o selector para:

```
[rb, security]
```

Regras:
- exige Harbor 18005 LISTEN;
- exige conexão RadioBOSS ESTABLISHED antes de mudar qualquer configuração;
- cria candidate fora da produção;
- garante `security = blank(...)`;
- valida candidate com `liquidsoap --check`;
- instala somente se a validação passar;
- reinicia somente o selector uma vez;
- se selector/Harbor não voltar a LISTEN, restaura a configuração anterior;
- não reinicia MediaMTX ou Nginx;
- não altera playlists ou mídia;
- remove `local_grade` apenas do fallback público.
