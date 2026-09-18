#!/usr/bin/env python3
import json
import os
import select
import signal
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

LIVE_URL = os.environ.get("LIVE_URL", "http://127.0.0.1:18005/radioprincipal-rb")
ICECAST_STATUS = os.environ.get("ICECAST_STATUS", "http://127.0.0.1:18005/status-json.xsl")
FALLBACK_RTMP = os.environ.get("FALLBACK_RTMP", "rtmp://127.0.0.1:1935/radioprincipal-ns1")
PUBLIC_RTMP = os.environ.get("PUBLIC_RTMP", "rtmp://127.0.0.1:1935/radioprincipal")
STATE_PATH = Path(os.environ.get("STATE_PATH", "/run/studiosat/radioprincipal-v31-state.json"))
LIVE_STABLE_SEC = float(os.environ.get("LIVE_STABLE_SEC", "15"))
LIVE_STALL_SEC = float(os.environ.get("LIVE_STALL_SEC", "1.5"))
CHECK_INTERVAL = float(os.environ.get("CHECK_INTERVAL", "1"))
CHUNK_BYTES = 3840  # 20 ms of s16le / 48kHz / stereo
SILENCE = b"\x00" * CHUNK_BYTES

running = True
decoder = None
publisher = None
source = "fallback"
source_started = 0.0
live_seen_since = None
last_audio_at = 0.0
last_state_write = 0.0
metadata_title = None

def log(msg):
    print(f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} {msg}", flush=True)

def state(extra=None):
    global last_state_write
    now = time.monotonic()
    if extra is None and now - last_state_write < 1:
        return
    data = {
        "updated_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "source": source,
        "source_started_monotonic": source_started,
        "live_seen_since_monotonic": live_seen_since,
        "last_audio_at_monotonic": last_audio_at,
        "metadata_title": metadata_title,
        "publisher_pid": publisher.pid if publisher and publisher.poll() is None else None,
        "decoder_pid": decoder.pid if decoder and decoder.poll() is None else None,
        "live_url": LIVE_URL,
        "fallback_rtmp": FALLBACK_RTMP,
        "public_rtmp": PUBLIC_RTMP,
    }
    if extra:
        data.update(extra)
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    tmp.replace(STATE_PATH)
    last_state_write = now

def terminate(proc):
    if not proc:
        return
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)

def publisher_cmd():
    return [
        "/usr/bin/ffmpeg", "-hide_banner", "-loglevel", "warning", "-nostdin",
        "-f", "s16le", "-ar", "48000", "-ac", "2", "-i", "pipe:0",
        "-map", "0:a:0", "-vn",
        "-c:a", "aac", "-profile:a", "aac_low", "-b:a", "128k",
        "-ar", "48000", "-ac", "2",
        "-flvflags", "no_duration_filesize",
        "-f", "flv", PUBLIC_RTMP
    ]

def decoder_cmd(which):
    url = LIVE_URL if which == "live" else FALLBACK_RTMP
    return [
        "/usr/bin/ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin",
        "-rw_timeout", "5000000",
        "-fflags", "+discardcorrupt+nobuffer",
        "-flags", "low_delay",
        "-probesize", "32768",
        "-analyzeduration", "0",
        "-i", url,
        "-map", "0:a:0", "-vn",
        "-ac", "2", "-ar", "48000",
        "-f", "s16le", "pipe:1"
    ]

def start_publisher():
    global publisher
    terminate(publisher)
    log(f"PUBLIC_ENCODER_START target={PUBLIC_RTMP}")
    publisher = subprocess.Popen(
        publisher_cmd(),
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=None,
        bufsize=0,
    )
    time.sleep(0.4)
    if publisher.poll() is not None:
        raise RuntimeError(f"public encoder exited rc={publisher.returncode}")

def start_decoder(which):
    global decoder, source, source_started, last_audio_at
    terminate(decoder)
    log(f"SOURCE_SWITCH_BEGIN target={which}")
    decoder = subprocess.Popen(
        decoder_cmd(which),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=None,
        bufsize=0,
    )
    source = which
    source_started = time.monotonic()
    last_audio_at = source_started
    state({"event": "source_decoder_started"})
    log(f"SOURCE_SWITCH_DONE source={which}")

def icecast_source():
    global metadata_title
    try:
        with urllib.request.urlopen(ICECAST_STATUS, timeout=1.2) as r:
            obj = json.loads(r.read().decode("utf-8", "replace"))
        src = obj.get("icestats", {}).get("source")
        if not src:
            metadata_title = None
            return False
        sources = src if isinstance(src, list) else [src]
        for item in sources:
            listenurl = str(item.get("listenurl", ""))
            if listenurl.endswith("/radioprincipal-rb"):
                metadata_title = item.get("title")
                return True
        metadata_title = None
        return False
    except Exception:
        metadata_title = None
        return False

def probe_live_audio():
    cmd = [
        "/usr/bin/ffprobe", "-v", "error",
        "-rw_timeout", "4000000",
        "-show_entries", "stream=codec_name,sample_rate,channels",
        "-of", "csv=p=0",
        LIVE_URL
    ]
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=6)
        return p.returncode == 0 and bool(p.stdout.strip())
    except Exception:
        return False

def switch_to_fallback(reason):
    global live_seen_since
    if source != "fallback":
        log(f"FAILOVER_TO_FALLBACK reason={reason}")
        start_decoder("fallback")
    live_seen_since = None

def on_signal(signum, frame):
    global running
    running = False

signal.signal(signal.SIGTERM, on_signal)
signal.signal(signal.SIGINT, on_signal)

log("RADIOPRINCIPAL_V31_START")
start_publisher()
start_decoder("fallback")
state({"event": "startup_complete"})

next_health = 0.0
try:
    while running:
        now = time.monotonic()

        if publisher.poll() is not None:
            log(f"PUBLIC_ENCODER_EXIT rc={publisher.returncode}; restarting")
            start_publisher()

        if decoder.poll() is not None:
            rc = decoder.returncode
            log(f"SOURCE_DECODER_EXIT source={source} rc={rc}")
            if source == "live":
                switch_to_fallback("decoder_exit")
            else:
                time.sleep(0.25)
                start_decoder("fallback")

        ready, _, _ = select.select([decoder.stdout], [], [], 0.02)
        if ready:
            data = os.read(decoder.stdout.fileno(), CHUNK_BYTES)
            if data:
                last_audio_at = now
                if len(data) < CHUNK_BYTES:
                    data += b"\x00" * (CHUNK_BYTES - len(data))
                try:
                    publisher.stdin.write(data)
                    publisher.stdin.flush()
                except (BrokenPipeError, OSError):
                    log("PUBLIC_ENCODER_PIPE_BROKEN")
                    start_publisher()
            else:
                if source == "live":
                    switch_to_fallback("live_eof")
                else:
                    start_decoder("fallback")
        else:
            # Keep the public encoder alive while source decoder is reconnecting.
            if now - last_audio_at > 0.20:
                try:
                    publisher.stdin.write(SILENCE)
                    publisher.stdin.flush()
                except (BrokenPipeError, OSError):
                    start_publisher()

        if now >= next_health:
            next_health = now + CHECK_INTERVAL
            live_present = icecast_source()

            if source == "live":
                if now - last_audio_at >= LIVE_STALL_SEC:
                    switch_to_fallback(f"live_stall_{now-last_audio_at:.2f}s")
            else:
                if live_present:
                    if live_seen_since is None:
                        live_seen_since = now
                        log("LIVE_CANDIDATE_SEEN")
                    elif now - live_seen_since >= LIVE_STABLE_SEC:
                        log(f"LIVE_CANDIDATE_STABLE seconds={now-live_seen_since:.1f}")
                        if probe_live_audio():
                            log("LIVE_AUDIO_PROBE_OK")
                            start_decoder("live")
                            live_seen_since = None
                            log("LIVE_ON_AIR")
                        else:
                            log("LIVE_AUDIO_PROBE_FAILED_KEEP_FALLBACK")
                            live_seen_since = None
                else:
                    live_seen_since = None

            state({
                "icecast_live_present": live_present,
                "public_encoder_alive": publisher.poll() is None,
                "source_decoder_alive": decoder.poll() is None,
            })
finally:
    log("RADIOPRINCIPAL_V31_STOP")
    terminate(decoder)
    terminate(publisher)
    state({"event": "stopped"})
