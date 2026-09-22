# Rollback

O V2 começa em `/listen-v2/`; o legado continua em `/listen/`.

Para retirar o serviço:

```bash
sudo systemctl disable --now studiosat-v2-web.service
```

Restaure o backup do Nginx informado pelo instalador, valide com `nginx -t` e recarregue.
