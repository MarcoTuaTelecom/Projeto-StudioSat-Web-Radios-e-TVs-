# Rádio Principal — scripts NS1

Este diretório guarda a fonte de verdade dos scripts read-only usados para reconfirmar o estado vivo da Rádio Principal antes de qualquer candidate ou mudança de produção.

## Arquivos

- `STUDIOSAT-RADIOPRINCIPAL-FULL-XRAY-V2.sh` — coletor read-only do baseline/forense NS1. Gera `/root/XRAY-RADIOPRINCIPAL-NS1-V2-<UTC>.txt` e observa o data-plane por 90 s por padrão.
- `RUN-RADIOPRINCIPAL-BASELINE.sh` — executor reproduzível. Baixa o XRAY canônico desta branch, valida o Git blob SHA aprovado, instala a cópia em `/root` e executa o baseline.

## Recuperar e executar no NS1 como root

```bash
cd /root
curl -fL 'https://raw.githubusercontent.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-/reorg/project-context-v2/scripts/radioprincipal/RUN-RADIOPRINCIPAL-BASELINE.sh' \
  -o /root/RUN-RADIOPRINCIPAL-BASELINE.sh
chmod 700 /root/RUN-RADIOPRINCIPAL-BASELINE.sh
bash -n /root/RUN-RADIOPRINCIPAL-BASELINE.sh
/root/RUN-RADIOPRINCIPAL-BASELINE.sh
```

Durante a janela de observação, deixar o RadioBOSS tocar normalmente. Não usar Next/Pause/Stop, não reiniciar serviços e não alterar selector, Harbor, MediaMTX ou Nginx.

## Modos auxiliares

```bash
# Apenas baixar/validar/instalar o XRAY canônico
/root/RUN-RADIOPRINCIPAL-BASELINE.sh --download-only

# Executar a cópia local já instalada, ainda validando o blob aprovado
/root/RUN-RADIOPRINCIPAL-BASELINE.sh --local

# Alterar somente a duração da observação
OBSERVE_SECONDS=120 /root/RUN-RADIOPRINCIPAL-BASELINE.sh
```

## Integridade registrada

- Change ID: `RADIOPRINCIPAL-NS1-C03`
- XRAY Git blob aprovado: `5128ecfb411bb4244cac7b383a2fef62bfc68aac`
- Segurança: `read-only`, exceto pelos arquivos de relatório/temporários criados para a própria coleta.

Se o XRAY for alterado no GitHub, o executor atual deve falhar pela verificação do blob. Uma nova versão só deve ser liberada após revisão e atualização explícita do hash esperado no executor.
