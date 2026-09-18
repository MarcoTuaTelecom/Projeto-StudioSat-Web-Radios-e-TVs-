#!/usr/bin/env python3
import json
import os
import signal
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

LIVE_URL = os.environ.get("LIVE_URL", "http://127.0.0.1:18005/radioprincipal-rb")
FALLBACK_RTMP = os.environ.get("FALLBACK_RTMP", "rtmp://127.0.0.1:1935/radioprincipal-ns1")
PUBLIC_RTMP = os.environ.get("PUBLIC_RTMP", "rtmp://127.0.0.1:1935/radioprincipal")
STATE_PATH = Path(os.environ.get("STATE_PATH", "/run/studiosat/radioprincipal-v3-state.json"))
LIVE_STABLE_SEC = int(os.environ.get("LIVE_STABLE_SEC", "15"))
HEALTH_INTERVAL = float(os.environ.get("HEALTH_INTERVAL", "2"))
LIVE_FAIL_CHECKS = int(os.environ.get("LIVE_FAIL_CHECKS", "2"))

running = True
publisher = None
current_source = None
live_stable_since = None
live_fail_streak = 0

def log(msg):
    print(f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} {msg}", flush=True)

def write_state(extra=None):
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    data = {
        "updated_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source": current_source,
        "publisher_pid": publisher.pid if publisher and publisher.poll() is None else None,
        "live_url": LIVE_URL,
        "fallback_rtmp": FALLBACK_RTMP,
        "public_rtmp": PUBLIC_RTMP,
        "live_stable_sec": LIVE_STABLE_SEC,
    }
    if extra:
        data.update(extra)
    tmp = STATE_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    tmp.replace(STATE_PATH)

def terminate_publisher():
    global publisher
    if not publisher:
        return
    if publisher.poll() is None:
        publisher.terminate()
        try:
            publisher.wait(timeout=2)
        except subprocess.TimeoutExpired:
            publisher.kill()
            publisher.wait(timeout=2)
    publisher = None

def ffmpeg_command(source):
    common_out = [
        "-map", "0:a:0", "-vn",
        "-af", "aresample=48000:async=1:first_pts=0",
        "-c:a", "aac", "-profile:a", "aac_low",
        "-b:a", "128k", "-ar", "48000", "-ac", "2",
        "-flvflags", "no_duration_filesize",
        "-f", "flv", PUBLIC_RTMP
    ]
    if source == "live":
        return [
            "/usr/bin/ffmpeg", "-hide_banner", "-loglevel", "warning", "-nostdin",
            "-rw_timeout", "5000000",
            "-reconnect", "1", "-reconnect_streamed", "1", "-reconnect_delay_max", "2",
            "-i", LIVE_URL,
            *common_out
        ]
    return [
        "/usr/bin/ffmpeg", "-hide_banner", "-loglevel", "warning", "-nostdin",
        "-rw_timeout", "5000000",
        "-i", FALLBACK_RTMP,
        *common_out
    ]

def start_publisher(source):
    global publisher, current_source
    terminate_publisher()
    cmd = ffmpeg_command(source)
    log(f"START_PUBLISHER source={source} public={PUBLIC_RTMP}")
    publisher = subprocess.Popen(cmd)
    current_source = source
    write_state({"event": "publisher_started"})
    time.sleep(0.6)
    if publisher.poll() is not None:
        rc = publisher.returncode
        log(f"PUBLISHER_EARLY_EXIT source={source} rc={rc}")
        publisher = None
        return False
    return True

def live_http_healthy():
    req = urllib.request.Request(
        LIVE_URL,
        headers={"User-Agent": "StudioSat-RadioPrincipal-V3/1.0", "Icy-MetaData": "0"},
        method="GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=2.5) as r:
            code = getattr(r, "status", 200)
            data = r.read(1024)
            return code == 200 and len(data) >= 128
    except Exception:
        return False

def live_ffprobe_healthy():
    cmd = [
        "/usr/bin/ffprobe", "-v", "error",
        "-rw_timeout", "4000000",
        "-show_entries", "stream=codec_name,sample_rate,channels",
        "-of", "csv=p=0",
        LIVE_URL,
    ]
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=6)
        return p.returncode == 0 and bool(p.stdout.strip())
    except Exception:
        return False

def on_signal(signum, frame):
    global running
    running = False

signal.signal(signal.SIGTERM, on_signal)
signal.signal(signal.SIGINT, on_signal)

log("RADIOPRINCIPAL_V3_CORE_START")
write_state({"event": "startup"})

if not start_publisher("fallback"):
    log("FATAL_FALLBACK_PUBLISHER_START_FAILED")
    sys.exit(20)

try:
    while running:
        alive = publisher is not None and publisher.poll() is None

        if not alive:
            rc = None if publisher is None else publisher.returncode
            log(f"PUBLISHER_EXIT source={current_source} rc={rc}")
            if current_source == "live":
                start_publisher("fallback")
                live_stable_since = None
                live_fail_streak = 0
            else:
                time.sleep(1)
                start_publisher("fallback")

        healthy = live_http_healthy()
        now = time.monotonic()

        if healthy:
            live_fail_streak = 0
            if live_stable_since is None:
                live_stable_since = now
                log("LIVE_CANDIDATE_STARTED")
            stable_for = now - live_stable_since

            if current_source != "live" and stable_for >= LIVE_STABLE_SEC:
                log(f"LIVE_CANDIDATE_STABLE seconds={stable_for:.1f}")
                if live_ffprobe_healthy():
                    log("LIVE_FFPROBE_OK_SWITCHING")
                    if not start_publisher("live"):
                        log("LIVE_SWITCH_FAILED_RETURN_FALLBACK")
                        start_publisher("fallback")
                    else:
                        log("LIVE_ON_AIR")
                else:
                    log("LIVE_FFPROBE_FAILED_KEEP_FALLBACK")
                    live_stable_since = None
        else:
            live_stable_since = None
            if current_source == "live":
                live_fail_streak += 1
                if live_fail_streak >= LIVE_FAIL_CHECKS:
                    log(f"LIVE_HEALTH_FAILED streak={live_fail_streak} SWITCH_FALLBACK")
                    start_publisher("fallback")
                    live_fail_streak = 0
                    log("FALLBACK_ON_AIR")
            else:
                live_fail_streak = 0

        write_state({"live_http_healthy": healthy})
        time.sleep(HEALTH_INTERVAL)
finally:
    log("RADIOPRINCIPAL_V3_CORE_STOP")
    terminate_publisher()
    write_state({"event": "stopped"})
