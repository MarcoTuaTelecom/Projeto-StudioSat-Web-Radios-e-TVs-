# Rádio Principal V7 — Standard RadioBOSS Ingest

V7 removes machine-specific RadioBOSS integration from the live path.

Any RadioBOSS installation can connect with its normal Icecast2 broadcaster configuration:
- host: radio.studiosatweb.com.br
- port: 443
- TLS: enabled
- username: source
- mount: /radioprincipal-rb
- password: generated on NS1 during installation

No PowerShell agent, Windows service, SSH tunnel, or machine-specific Studio Sat software is required for live transmission.

The NS1 keeps Icecast on loopback only. Nginx exposes only the source mount over the already-existing HTTPS 443 virtual host. The existing V32 core consumes the local /radioprincipal-rb source and continues to provide fallback when no RadioBOSS is connected.

The installer validates the public HTTPS source path on /radioprincipal-preflight before disabling the obsolete SSH audio-tunnel login.
