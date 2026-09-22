# PRIMEIRA EXECUÇÃO NO NS1

Esta implantação é paralela e não altera `/listen/`.

## Opção A — GitHub

```bash
cd /root
rm -rf studiosat-v2-src
git clone --branch feature/studiosat-v2-rust-native --single-branch \
  https://github.com/MarcoTuaTelecom/Projeto-StudioSat-Web-Radios-e-TVs-.git \
  studiosat-v2-src

cd /root/studiosat-v2-src/StudioSAT-V2

bash deploy/bootstrap-toolchain.sh
bash deploy/build-web.sh
sudo bash deploy/install-ns1.sh
bash deploy/smoke-test.sh
```

## Resultado esperado

```text
systemctl status studiosat-v2-web.service
http://127.0.0.1:8792/health
https://www.radio.studiosatweb.com.br/listen-v2/
```

## Teste auditivo obrigatório

Compare a Principal no V2 com:
- HLS cru: https://radio.studiosatweb.com.br/radioprincipal/index.m3u8
- referência: https://radio.studiosatweb.com.br/diag-bypass/

Não promover `/listen-v2/` para `/listen/` enquanto a audição humana não for estável e equivalente ao HLS cru.
