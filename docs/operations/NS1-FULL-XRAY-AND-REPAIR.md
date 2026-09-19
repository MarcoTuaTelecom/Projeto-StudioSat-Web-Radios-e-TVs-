# NS1 Full X-Ray + Repair

Script: scripts/operations/NS1-FULL-XRAY-AND-REPAIR-NOW.sh

Audits hardware, OS, CPU/RAM/load/storage, network, ports, process/service resource use, Nginx, MediaMTX and the five radio stations.

For each radio it measures RTMP, local/public HLS, codec, sample rate, channels, bitrate, playlist size, 10-second EBU R128 audio probe and HLS sequence advancement.

It also reads the current RadioBOSS control age for Radio Principal.

Repairs are bounded: start/restart base services only when down; restart a thematic playout only when its own RTMP is undecodable; when Radio Principal control is stale, install the stable no-seek shadow while V32 stays public.

It writes a complete bundle under /root/studiosat-xray-<UTC>.tar.gz and prints a compact final summary.