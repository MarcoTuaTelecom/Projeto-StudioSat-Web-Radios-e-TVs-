#!/usr/bin/env python3
import json
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

STATE = Path("/run/studiosat/radioprincipal-v32-state.json")
HLS = Path("/run/studiosat/radioprincipal-v32.m3u8")
MTX = "http://127.0.0.1:9997/v3/paths/get/radioprincipal"
ICE = "http://127.0.0.1:18005/status-json.xsl"

def get_json(url, timeout=1.5):
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return json.loads(r.read().decode("utf-8", "replace"))
    except Exception as e:
        return {"_error": str(e)}

def snapshot():
    now = time.time()
    try:
        state = json.loads(STATE.read_text())
    except Exception as e:
        state = {"_error": str(e)}

    mtx = get_json(MTX)
    ice = get_json(ICE)

    hls_age = None
    hls_ok = False
    try:
        hls_age = round(now - HLS.stat().st_mtime, 3)
        hls_ok = hls_age < 10 and HLS.read_text(errors="ignore").startswith("#EXTM3U")
    except Exception:
        pass

    selected = state.get("selected_source")
    selected_age = state.get("live_age_sec") if selected == "live" else state.get("fallback_age_sec")
    source_fresh = isinstance(selected_age, (int, float)) and selected_age < 2.0
    public_ready = bool(mtx.get("ready"))
    core_ok = selected in ("live", "fallback") and source_fresh
    ok = bool(core_ok and public_ready and hls_ok)

    return {
        "ok": ok,
        "updated_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "selected_source": selected,
        "selected_audio_age_sec": selected_age,
        "live_age_sec": state.get("live_age_sec"),
        "fallback_age_sec": state.get("fallback_age_sec"),
        "live_bytes": state.get("live_bytes"),
        "fallback_bytes": state.get("fallback_bytes"),
        "switches": state.get("switches"),
        "metadata_title": state.get("metadata_title"),
        "public_rtmp_ready": public_ready,
        "public_tracks": mtx.get("tracks"),
        "hls_ready": hls_ok,
        "hls_age_sec": hls_age,
        "icecast_source_present": bool(ice.get("icestats", {}).get("source")) if isinstance(ice, dict) else False,
        "core_state": state,
    }

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in ("/", "/healthz", "/readyz", "/state"):
            self.send_response(404)
            self.end_headers()
            return
        data = snapshot()
        status = 200 if (self.path in ("/", "/state") or data["ok"]) else 503
        body = json.dumps(data, ensure_ascii=False, indent=2).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass

ThreadingHTTPServer(("127.0.0.1", 8812), Handler).serve_forever()
