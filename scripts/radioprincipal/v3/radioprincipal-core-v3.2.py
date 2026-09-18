#!/usr/bin/env python3
import json
import os
import selectors
import signal
import subprocess
import time
import urllib.request
from pathlib import Path

LIVE_URL = os.environ.get("LIVE_URL", "http://127.0.0.1:18005/radioprincipal-rb")
ICECAST_STATUS = os.environ.get("ICECAST_STATUS", "http://127.0.0.1:18005/status-json.xsl")
FALLBACK_RTMP = os.environ.get("FALLBACK_RTMP", "rtmp://127.0.0.1:1935/radioprincipal-ns1")
PUBLIC_RTMP = os.environ.get("PUBLIC_RTMP", "rtmp://127.0.0.1:1935/radioprincipal")
STATE_PATH = Path(os.environ.get("STATE_PATH", "/run/studiosat/radioprincipal-v32-state.json"))

PROMOTE_SEC = float(os.environ.get("PROMOTE_SEC", "5"))
LIVE_GAP_SEC = float(os.environ.get("LIVE_GAP_SEC", "0.50"))
FALLBACK_GAP_SEC = float(os.environ.get("FALLBACK_GAP_SEC", "1.50"))
RESTART_DECODER_SEC = float(os.environ.get("RESTART_DECODER_SEC", "1"))
STATE_INTERVAL_SEC = float(os.environ.get("STATE_INTERVAL_SEC", "1"))

RATE = 48000
CHANNELS = 2
BYTES_PER_SAMPLE = 2
CHUNK = int(RATE * CHANNELS * BYTES_PER_SAMPLE * 0.02)  # 20ms
MAX_BUFFER = CHUNK * 10  # 200ms
SILENCE = b"\x00" * CHUNK

running = True
sel = selectors.DefaultSelector()
publisher = None
decoders = {"live": None, "fallback": None}
buffers = {"live": bytearray(), "fallback": bytearray()}
last_bytes = {"live": 0.0, "fallback": 0.0}
last_decoder_start = {"live": 0.0, "fallback": 0.0}
selected = "fallback"
live_good_since = None
last_state = 0.0
counters = {"live_bytes": 0, "fallback_bytes": 0, "switches": 0}
metadata_title = None

def log(msg):
    print(f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())} {msg}", flush=True)

def safe_terminate(proc):
    if not proc:
        return
    try:
        if proc.poll() is None:
            proc.terminate()
            proc.wait(timeout=2)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass

def publisher_cmd():
    return [
        "/usr/bin/ffmpeg",
        "-hide_banner", "-loglevel", "warning", "-nostdin",
        "-re",
        "-f", "s16le", "-ar", str(RATE), "-ac", str(CHANNELS), "-i", "pipe:0",
        "-map", "0:a:0", "-vn",
        "-c:a", "aac", "-profile:a", "aac_low",
        "-b:a", "128k", "-ar", "48000", "-ac", "2",
        "-flvflags", "no_duration_filesize",
        "-f", "flv", PUBLIC_RTMP,
    ]

def decoder_cmd(name):
    url = LIVE_URL if name == "live" else FALLBACK_RTMP
    return [
        "/usr/bin/ffmpeg",
        "-hide_banner", "-loglevel", "error", "-nostdin",
        "-rw_timeout", "5000000",
        "-fflags", "+discardcorrupt+nobuffer",
        "-flags", "low_delay",
        "-probesize", "32768",
        "-analyzeduration", "0",
        "-i", url,
        "-map", "0:a:0", "-vn",
        "-ac", str(CHANNELS), "-ar", str(RATE),
        "-f", "s16le", "pipe:1",
    ]

def start_publisher():
    global publisher
    safe_terminate(publisher)
    log(f"PUBLIC_ENCODER_START {PUBLIC_RTMP}")
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

def unregister_decoder(name):
    proc = decoders.get(name)
    if proc and proc.stdout:
        try:
            sel.unregister(proc.stdout)
        except Exception:
            pass
    safe_terminate(proc)
    decoders[name] = None

def start_decoder(name):
    now = time.monotonic()
    unregister_decoder(name)
    buffers[name].clear()
    last_decoder_start[name] = now
    url = LIVE_URL if name == "live" else FALLBACK_RTMP
    log(f"DECODER_START name={name} url={url}")
    proc = subprocess.Popen(
        decoder_cmd(name),
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=None,
        bufsize=0,
    )
    os.set_blocking(proc.stdout.fileno(), False)
    sel.register(proc.stdout, selectors.EVENT_READ, data=name)
    decoders[name] = proc

def ensure_decoders():
    now = time.monotonic()
    for name in ("fallback", "live"):
        proc = decoders.get(name)
        dead = proc is None or proc.poll() is not None
        if dead and now - last_decoder_start[name] >= RESTART_DECODER_SEC:
            start_decoder(name)

def append_audio(name, data):
    now = time.monotonic()
    last_bytes[name] = now
    counters[name + "_bytes"] += len(data)
    b = buffers[name]
    b.extend(data)
    if len(b) > MAX_BUFFER:
        del b[:-MAX_BUFFER]

def icecast_metadata():
    global metadata_title
    try:
        with urllib.request.urlopen(ICECAST_STATUS, timeout=0.8) as r:
            obj = json.loads(r.read().decode("utf-8", "replace"))
        src = obj.get("icestats", {}).get("source")
        if not src:
            metadata_title = None
            return False
        items = src if isinstance(src, list) else [src]
        for item in items:
            if str(item.get("listenurl", "")).endswith("/radioprincipal-rb"):
                metadata_title = item.get("title")
                return True
        metadata_title = None
        return False
    except Exception:
        metadata_title = None
        return False

def switch(name, reason):
    global selected, live_good_since
    if selected == name:
        return
    selected = name
    counters["switches"] += 1
    if name == "fallback":
        live_good_since = None
    log(f"SOURCE_SWITCH source={name} reason={reason}")
    write_state({"event": "source_switch", "reason": reason}, force=True)

def write_state(extra=None, force=False):
    global last_state
    now = time.monotonic()
    if not force and now - last_state < STATE_INTERVAL_SEC:
        return
    data = {
        "updated_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "selected_source": selected,
        "publisher_pid": publisher.pid if publisher and publisher.poll() is None else None,
        "live_decoder_pid": decoders["live"].pid if decoders["live"] and decoders["live"].poll() is None else None,
        "fallback_decoder_pid": decoders["fallback"].pid if decoders["fallback"] and decoders["fallback"].poll() is None else None,
        "live_age_sec": None if not last_bytes["live"] else round(now - last_bytes["live"], 3),
        "fallback_age_sec": None if not last_bytes["fallback"] else round(now - last_bytes["fallback"], 3),
        "live_good_for_sec": None if live_good_since is None else round(now - live_good_since, 3),
        "metadata_title": metadata_title,
        "buffer_live_bytes": len(buffers["live"]),
        "buffer_fallback_bytes": len(buffers["fallback"]),
        **counters,
    }
    if extra:
        data.update(extra)
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2))
    tmp.replace(STATE_PATH)
    last_state = now

def feed_public():
    name = selected
    b = buffers[name]
    if len(b) >= CHUNK:
        data = bytes(b[:CHUNK])
        del b[:CHUNK]
    elif name == "live" and len(buffers["fallback"]) >= CHUNK:
        # Never let public audio disappear while live is transitioning.
        fb = buffers["fallback"]
        data = bytes(fb[:CHUNK])
        del fb[:CHUNK]
    else:
        data = SILENCE
    try:
        publisher.stdin.write(data)
        publisher.stdin.flush()
    except (BrokenPipeError, OSError):
        log("PUBLIC_ENCODER_PIPE_BROKEN")
        start_publisher()

def on_signal(signum, frame):
    global running
    running = False

signal.signal(signal.SIGTERM, on_signal)
signal.signal(signal.SIGINT, on_signal)

log("RADIOPRINCIPAL_V32_START")
start_publisher()
start_decoder("fallback")
start_decoder("live")
write_state({"event": "startup"}, force=True)

next_tick = time.monotonic()
next_metadata = 0.0

try:
    while running:
        now = time.monotonic()
        ensure_decoders()

        if publisher.poll() is not None:
            log(f"PUBLIC_ENCODER_EXIT rc={publisher.returncode}")
            start_publisher()

        events = sel.select(timeout=0.005)
        for key, _ in events:
            name = key.data
            try:
                data = os.read(key.fileobj.fileno(), 65536)
            except BlockingIOError:
                data = b""
            except OSError:
                data = b""
            if data:
                append_audio(name, data)

        now = time.monotonic()

        live_fresh = bool(last_bytes["live"]) and (now - last_bytes["live"] <= LIVE_GAP_SEC)
        fallback_fresh = bool(last_bytes["fallback"]) and (now - last_bytes["fallback"] <= FALLBACK_GAP_SEC)

        if live_fresh:
            if live_good_since is None:
                live_good_since = now
                log("LIVE_AUDIO_DETECTED")
        else:
            live_good_since = None

        if selected == "live":
            if not live_fresh:
                switch("fallback", "live_pcm_gap")
        else:
            if live_good_since is not None and now - live_good_since >= PROMOTE_SEC:
                switch("live", f"continuous_live_pcm_{PROMOTE_SEC:.1f}s")

        if now >= next_metadata:
            next_metadata = now + 2.0
            icecast_metadata()

        if now >= next_tick:
            next_tick += 0.02
            feed_public()
            # Avoid runaway if host was paused.
            if now - next_tick > 0.5:
                next_tick = now + 0.02

        write_state({
            "live_fresh": live_fresh,
            "fallback_fresh": fallback_fresh,
            "public_encoder_alive": publisher.poll() is None,
        })
finally:
    log("RADIOPRINCIPAL_V32_STOP")
    for name in ("live", "fallback"):
        unregister_decoder(name)
    safe_terminate(publisher)
    write_state({"event": "stopped"}, force=True)
