/*
 * StudioSAT V2.1 Web Player
 *
 * PRINCÍPIO:
 * uma emissora = uma sessão de mídia nova.
 *
 * Na troca de rádio o elemento <audio>, MediaSource, decoder e Hls são
 * destruídos. Um novo <audio> é criado do zero antes de abrir o próximo HLS.
 *
 * O código NÃO:
 * - lê PCM;
 * - cria AudioContext/WebAudio;
 * - altera playbackRate;
 * - faz seek para perseguir live edge;
 * - usa recoverMediaError();
 * - reaproveita buffers entre estações.
 */
(() => {
  'use strict';

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
  const telemetry = document.getElementById('telemetry');

  let audio = document.getElementById('audio');
  let selected = null;
  let hls = null;
  let metadataTimer = null;
  let telemetryTimer = null;
  let session = 0;
  let muted = false;
  let wantsPlayback = false;

  function bufferedAhead(media) {
    try {
      const t = media.currentTime;
      for (let i = 0; i < media.buffered.length; i += 1) {
        if (t >= media.buffered.start(i) && t <= media.buffered.end(i)) {
          return Math.max(0, media.buffered.end(i) - t);
        }
      }
    } catch (_) {}
    return 0;
  }

  function updateTelemetry() {
    if (!audio) return;
    telemetry.textContent =
      `rate=${Number(audio.playbackRate || 1).toFixed(3)} · buffer=${bufferedAhead(audio).toFixed(1)}s · sessão=${session}`;
  }

  function bindAudioEvents(media, generation) {
    const valid = () => generation === session && media === audio;

    media.addEventListener('playing', () => {
      if (!valid()) return;
      state.textContent = 'AO VIVO';
      play.textContent = 'Ⅱ Pausar';
      document.body.classList.add('playing');
      updateTelemetry();
    });

    media.addEventListener('pause', () => {
      if (!valid()) return;
      state.textContent = wantsPlayback ? 'CONECTANDO' : 'PAUSADO';
      play.textContent = wantsPlayback ? 'Ⅱ Pausar' : '▶ Ouvir';
      if (!wantsPlayback) document.body.classList.remove('playing');
      updateTelemetry();
    });

    media.addEventListener('waiting', () => {
      if (!valid()) return;
      state.textContent = 'BUFFER';
      updateTelemetry();
    });

    media.addEventListener('stalled', () => {
      if (!valid()) return;
      state.textContent = 'REDE';
      updateTelemetry();
    });

    media.addEventListener('canplay', () => {
      if (!valid()) return;
      updateTelemetry();
      if (wantsPlayback && media.paused) media.play().catch(() => {});
    });

    media.addEventListener('error', () => {
      if (!valid()) return;
      state.textContent = 'ERRO — TOQUE OUVIR';
      wantsPlayback = false;
      play.textContent = '▶ Ouvir';
      document.body.classList.remove('playing');
      updateTelemetry();
    });

    media.addEventListener('ratechange', () => {
      if (!valid()) return;
      // Observação apenas. O V2 nunca escreve em playbackRate.
      updateTelemetry();
      if (Math.abs(media.playbackRate - 1) > 0.001) {
        state.textContent = `VELOCIDADE ${media.playbackRate.toFixed(3)}x`;
        console.error('StudioSAT V2: playbackRate mudou sem comando da aplicação', media.playbackRate);
      }
    });
  }

  function destroySession() {
    session += 1;

    if (hls) {
      try { hls.stopLoad(); } catch (_) {}
      try { hls.detachMedia(); } catch (_) {}
      try { hls.destroy(); } catch (_) {}
      hls = null;
    }

    if (audio) {
      try { audio.pause(); } catch (_) {}
      try { audio.removeAttribute('src'); } catch (_) {}
      try { audio.load(); } catch (_) {}
    }

    clearInterval(telemetryTimer);
  }

  function createFreshAudio() {
    const old = audio;
    const fresh = document.createElement('audio');
    fresh.id = 'audio';
    fresh.preload = 'none';
    fresh.playsInline = true;
    fresh.autoplay = false;
    fresh.muted = muted;

    old.replaceWith(fresh);
    audio = fresh;

    const generation = session;
    bindAudioEvents(fresh, generation);
    telemetryTimer = setInterval(updateTelemetry, 500);
    updateTelemetry();
    return { media: fresh, generation };
  }

  function attachFresh(station) {
    destroySession();
    state.textContent = 'CONECTANDO';
    const { media, generation } = createFreshAudio();
    const url = station.stream_url;

    if (media.canPlayType('application/vnd.apple.mpegurl')) {
      engine.textContent = 'motor: HLS nativo · sessão limpa';
      media.src = url;
      media.load();
      if (wantsPlayback) {
        media.addEventListener('canplay', () => {
          if (generation === session && wantsPlayback) media.play().catch(() => {});
        }, { once: true });
      }
      return;
    }

    if (window.Hls && window.Hls.isSupported()) {
      engine.textContent = 'motor: MSE/HLS.js 1.6.13 · sessão limpa';

      // Configuração deliberadamente conservadora.
      // Sem liveMaxLatencyDuration*, sem catch-up, sem recovery de media.
      const instance = new window.Hls({
        enableWorker: true,
        lowLatencyMode: false,
        maxLiveSyncPlaybackRate: 1.0
      });
      hls = instance;

      instance.on(window.Hls.Events.ERROR, (_, data) => {
        if (generation !== session || instance !== hls) return;
        console.warn('StudioSAT V2 HLS', data.type, data.details, 'fatal=', data.fatal);
        if (data.fatal) {
          // Não tentamos "consertar" decoder/buffer por cima da sessão atual.
          // O próximo toque em Ouvir cria uma sessão totalmente nova.
          state.textContent = 'RECONEXÃO — TOQUE OUVIR';
          wantsPlayback = false;
          try { media.pause(); } catch (_) {}
          play.textContent = '▶ Ouvir';
          document.body.classList.remove('playing');
        }
      });

      instance.on(window.Hls.Events.MEDIA_ATTACHED, () => {
        if (generation !== session || instance !== hls) return;
        instance.loadSource(url);
      });

      instance.on(window.Hls.Events.MANIFEST_PARSED, () => {
        if (generation !== session || instance !== hls) return;
        if (wantsPlayback) {
          const startWhenReady = () => {
            if (generation === session && wantsPlayback) media.play().catch(() => {});
          };
          if (media.readyState >= HTMLMediaElement.HAVE_FUTURE_DATA) startWhenReady();
          else media.addEventListener('canplay', startWhenReady, { once: true });
        }
      });

      instance.attachMedia(media);
      return;
    }

    engine.textContent = 'motor: HLS indisponível';
    state.textContent = 'NÃO SUPORTADO';
    wantsPlayback = false;
  }

  async function refreshMetadata() {
    const station = selected;
    if (!station) return;
    try {
      const response = await fetch(`${station.metadata_url}?v=${Date.now()}`, { cache: 'no-store' });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      if (!selected || selected.id !== station.id) return;
      artist.textContent = data.artist || data.performer || station.name;
      track.textContent = data.track || data.title || data.song || 'Programação ao vivo';
    } catch (_) {
      if (!selected || selected.id !== station.id) return;
      artist.textContent = station.name;
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

  function selectStation(station) {
    if (selected && station.id === selected.id) return;

    const resume = wantsPlayback || (audio && !audio.paused);
    selected = station;
    wantsPlayback = resume;

    stationName.textContent = station.name;
    stationDescription.textContent = station.description;
    document.querySelectorAll('[data-station]').forEach((node) => {
      node.classList.toggle('active', node.dataset.station === station.id);
    });

    attachFresh(station);

    clearInterval(metadataTimer);
    refreshMetadata();
    metadataTimer = setInterval(refreshMetadata, 8000);
    updateFavorite();
  }

  play.addEventListener('click', async () => {
    if (!selected) return;

    if (wantsPlayback && audio && !audio.paused) {
      wantsPlayback = false;
      audio.pause();
      return;
    }

    // Se a sessão terminou em erro, cria tudo de novo antes de tocar.
    if (!audio || audio.error || state.textContent.startsWith('RECONEXÃO')) {
      wantsPlayback = true;
      attachFresh(selected);
      return;
    }

    wantsPlayback = true;
    state.textContent = 'CONECTANDO';
    try {
      await audio.play();
    } catch (_) {
      state.textContent = 'TOQUE NOVAMENTE';
      wantsPlayback = false;
    }
  });

  mute.addEventListener('click', () => {
    muted = !muted;
    if (audio) audio.muted = muted;
    mute.textContent = muted ? 'Mudo' : 'Som';
  });

  favorite.addEventListener('click', () => {
    if (!selected) return;
    const values = favoritesSet();
    values.has(selected.id) ? values.delete(selected.id) : values.add(selected.id);
    localStorage.setItem('studiosat-v2-favorites', JSON.stringify([...values]));
    updateFavorite();
  });

  fetch('/listen-v2/api/stations', { cache: 'no-store' })
    .then((response) => {
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return response.json();
    })
    .then((stations) => {
      for (const station of stations) {
        const button = document.createElement('button');
        button.type = 'button';
        button.dataset.station = station.id;
        button.className = 'station';
        button.innerHTML = `<strong>${station.short_name}</strong><span>${station.description}</span>`;
        button.addEventListener('click', () => selectStation(station));
        stationsNode.appendChild(button);
      }
      if (stations.length) {
        selected = stations[0];
        stationName.textContent = selected.name;
        stationDescription.textContent = selected.description;
        document.querySelector('[data-station="' + selected.id + '"]')?.classList.add('active');
        attachFresh(selected);
        refreshMetadata();
        metadataTimer = setInterval(refreshMetadata, 8000);
        updateFavorite();
      }
    })
    .catch((error) => {
      console.error(error);
      state.textContent = 'API INDISPONÍVEL';
    });
})();
