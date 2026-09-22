/*
 * StudioSAT V2 Web Player
 * Coordena apenas o elemento <audio>. Não lê PCM, não cria WebAudio,
 * não calcula VU a partir do som e não altera playbackRate.
 */
(() => {
  'use strict';
  const audio = document.getElementById('audio');
  const play = document.getElementById('play');
  const mute = document.getElementById('mute');
  const favorite = document.getElementById('favorite');
  const engine = document.getElementById('engine');
  const state = document.getElementById('state');
  const stationName = document.getElementById('station-name');
  const stationDescription = document.getElementById('station-description');
  const artist = document.getElementById('artist');
  const track = document.getElementById('track');
  const stationsNode = document.getElementById('stations');

  let selected = null;
  let hls = null;
  let metadataTimer = null;

  function teardown() {
    if (hls) { try { hls.destroy(); } catch (_) {} hls = null; }
    audio.pause();
    audio.removeAttribute('src');
    audio.load();
  }

  function attach(url) {
    teardown();
    state.textContent = 'CONECTANDO';
    if (audio.canPlayType('application/vnd.apple.mpegurl')) {
      engine.textContent = 'motor: HLS nativo';
      audio.src = url;
      audio.load();
      return;
    }
    if (window.Hls && window.Hls.isSupported()) {
      engine.textContent = 'motor: MSE/HLS.js';
      hls = new window.Hls({
        enableWorker: true,
        lowLatencyMode: false,
        maxLiveSyncPlaybackRate: 1.0,
        liveSyncDurationCount: 6,
        maxBufferLength: 60,
        maxMaxBufferLength: 120,
        backBufferLength: 30
      });
      hls.attachMedia(audio);
      hls.on(window.Hls.Events.MEDIA_ATTACHED, () => hls.loadSource(url));
      hls.on(window.Hls.Events.ERROR, (_, data) => {
        if (!data.fatal) return;
        state.textContent = 'ERRO';
        if (data.type === window.Hls.ErrorTypes.NETWORK_ERROR) {
          try { hls.startLoad(); } catch (_) {}
        } else if (data.type === window.Hls.ErrorTypes.MEDIA_ERROR) {
          try { hls.recoverMediaError(); } catch (_) {}
        }
      });
      return;
    }
    engine.textContent = 'motor: HLS indisponível';
    state.textContent = 'NÃO SUPORTADO';
  }

  async function refreshMetadata() {
    if (!selected) return;
    try {
      const response = await fetch(`${selected.metadata_url}?v=${Date.now()}`, { cache: 'no-store' });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      artist.textContent = data.artist || data.performer || selected.name;
      track.textContent = data.track || data.title || data.song || 'Programação ao vivo';
    } catch (_) {
      artist.textContent = selected.name;
      track.textContent = 'Programação ao vivo';
    }
  }

  function favoritesSet() {
    try { return new Set(JSON.parse(localStorage.getItem('studiosat-v2-favorites') || '[]')); }
    catch (_) { return new Set(); }
  }

  function updateFavorite() {
    if (!selected) return;
    favorite.textContent = favoritesSet().has(selected.id) ? '♥ Favorita' : '♡ Favoritar';
  }

  function selectStation(station, autoplay = false) {
    selected = station;
    stationName.textContent = station.name;
    stationDescription.textContent = station.description;
    document.querySelectorAll('[data-station]').forEach((node) => node.classList.toggle('active', node.dataset.station === station.id));
    attach(station.stream_url);
    clearInterval(metadataTimer);
    refreshMetadata();
    metadataTimer = setInterval(refreshMetadata, 8000);
    updateFavorite();
    if (autoplay) audio.play().catch(() => {});
  }

  play.addEventListener('click', async () => {
    if (!selected) return;
    if (!audio.paused) { audio.pause(); return; }
    try { await audio.play(); } catch (_) { state.textContent = 'TOQUE NOVAMENTE'; }
  });
  mute.addEventListener('click', () => { audio.muted = !audio.muted; mute.textContent = audio.muted ? 'Mudo' : 'Som'; });
  favorite.addEventListener('click', () => {
    if (!selected) return;
    const values = favoritesSet();
    values.has(selected.id) ? values.delete(selected.id) : values.add(selected.id);
    localStorage.setItem('studiosat-v2-favorites', JSON.stringify([...values]));
    updateFavorite();
  });

  audio.addEventListener('playing', () => { state.textContent = 'AO VIVO'; play.textContent = 'Ⅱ Pausar'; document.body.classList.add('playing'); });
  audio.addEventListener('pause', () => { state.textContent = 'PAUSADO'; play.textContent = '▶ Ouvir'; document.body.classList.remove('playing'); });
  audio.addEventListener('waiting', () => { state.textContent = 'BUFFER'; });
  audio.addEventListener('stalled', () => { state.textContent = 'REDE'; });
  audio.addEventListener('error', () => { state.textContent = 'ERRO'; });

  fetch('/listen-v2/api/stations', { cache: 'no-store' })
    .then((r) => r.json())
    .then((stations) => {
      for (const station of stations) {
        const button = document.createElement('button');
        button.type = 'button';
        button.dataset.station = station.id;
        button.className = 'station';
        button.innerHTML = `<strong>${station.short_name}</strong><span>${station.description}</span>`;
        button.addEventListener('click', () => selectStation(station, !audio.paused));
        stationsNode.appendChild(button);
      }
      if (stations.length) selectStation(stations[0], false);
    })
    .catch(() => { state.textContent = 'API INDISPONÍVEL'; });
})();
