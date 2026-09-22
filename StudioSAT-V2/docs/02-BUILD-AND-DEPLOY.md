# Build e deploy

## Web

```bash
cd StudioSAT-V2
./deploy/bootstrap-toolchain.sh
./deploy/build-web.sh
sudo ./deploy/install-ns1.sh
```

Artefato Rust: `target/release/studiosat-web`.

O instalador publica em `/listen-v2/` sem substituir `/listen/`.

## Smoke test

```bash
./deploy/smoke-test.sh
```
