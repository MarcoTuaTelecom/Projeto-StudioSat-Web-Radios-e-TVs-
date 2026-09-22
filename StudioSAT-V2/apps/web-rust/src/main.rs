//! StudioSAT V2 web/API + transporte RAW AAC.
//!
//! O V2.2 adiciona uma rota de menor nivel para radio:
//!
//! HLS publico ja validado -> FFmpeg demux/copy -> AAC/ADTS continuo
//! -> HTTP chunked -> HTMLMediaElement/AVPlayer/Media3.
//!
//! O FFmpeg NAO reencoda: -c:a copy. O relay remove HLS/MSE do cliente
//! e transmite somente os frames AAC que ja estavam no HLS.
//!
//! A aplicacao nunca acessa PCM, nunca altera sample rate e nunca altera
//! playbackRate.

use axum::{
    Json, Router,
    body::Body,
    extract::{Path, State},
    http::{
        HeaderValue, StatusCode,
        header::{ACCESS_CONTROL_ALLOW_ORIGIN, CACHE_CONTROL, CONTENT_TYPE},
    },
    response::{Html, Redirect, Response},
    routing::get,
};
use bytes::Bytes;
use serde::Serialize;
use std::{
    collections::HashMap,
    convert::Infallible,
    env,
    net::SocketAddr,
    process::Stdio,
    sync::Arc,
    time::Duration,
};
use studiosat_core::STATIONS;
use tokio::{
    io::AsyncReadExt,
    process::Command,
    sync::broadcast,
    time::sleep,
};
use tower_http::{services::ServeDir, trace::TraceLayer};

#[derive(Clone)]
struct AppState {
    relays: Arc<HashMap<String, broadcast::Sender<Bytes>>>,
}

#[derive(Serialize)]
struct Health<'a> {
    status: &'a str,
    service: &'a str,
    version: &'a str,
    transport: &'a str,
    stations: usize,
}

async fn health() -> Json<Health<'static>> {
    Json(Health {
        status: "ok",
        service: "studiosat-v2-web",
        version: env!("CARGO_PKG_VERSION"),
        transport: "raw-aac-adts-copy",
        stations: STATIONS.len(),
    })
}

async fn stations() -> Json<&'static [studiosat_core::Station]> {
    Json(STATIONS)
}

async fn index() -> Html<&'static str> {
    Html(include_str!("../static/index.html"))
}

/// Entrega AAC/ADTS continuo, sem MSE e sem segmentacao HLS no cliente.
///
/// Cada assinatura recebe apenas frames futuros. O canal e live: se um cliente
/// lento ficar para tras, frames antigos sao descartados em vez de acumular
/// audio e depois soltar tudo acelerado.
async fn live_aac(
    Path(id): Path<String>,
    State(state): State<AppState>,
) -> Result<Response<Body>, StatusCode> {
    let tx = state.relays.get(&id).ok_or(StatusCode::NOT_FOUND)?;
    let mut rx = tx.subscribe();

    let stream = async_stream::stream! {
        loop {
            match rx.recv().await {
                Ok(frame) => yield Ok::<Bytes, Infallible>(frame),
                Err(broadcast::error::RecvError::Lagged(skipped)) => {
                    tracing::warn!(station=%id, skipped, "cliente raw AAC atrasou; descartando backlog");
                    continue;
                }
                Err(broadcast::error::RecvError::Closed) => break,
            }
        }
    };

    let mut response = Response::new(Body::from_stream(stream));
    let headers = response.headers_mut();
    headers.insert(CONTENT_TYPE, HeaderValue::from_static("audio/aac"));
    headers.insert(CACHE_CONTROL, HeaderValue::from_static("no-store, no-cache, must-revalidate"));
    headers.insert(ACCESS_CONTROL_ALLOW_ORIGIN, HeaderValue::from_static("*"));
    headers.insert("x-accel-buffering", HeaderValue::from_static("no"));
    headers.insert("x-studiosat-transport", HeaderValue::from_static("raw-aac-adts-copy"));
    Ok(response)
}

/// Extrai frames ADTS completos do buffer.
///
/// Um cliente novo sempre comeca em fronteira de frame AAC; isso evita iniciar
/// no meio de um payload arbitrario recebido do stdout do FFmpeg.
fn publish_adts_frames(buffer: &mut Vec<u8>, tx: &broadcast::Sender<Bytes>) -> usize {
    let mut cursor = 0usize;
    let mut published = 0usize;

    while buffer.len().saturating_sub(cursor) >= 7 {
        if buffer[cursor] != 0xFF || (buffer[cursor + 1] & 0xF0) != 0xF0 {
            cursor += 1;
            continue;
        }

        let frame_len = (((buffer[cursor + 3] & 0x03) as usize) << 11)
            | ((buffer[cursor + 4] as usize) << 3)
            | (((buffer[cursor + 5] & 0xE0) as usize) >> 5);

        if frame_len < 7 || frame_len > 16 * 1024 {
            cursor += 1;
            continue;
        }

        if buffer.len() - cursor < frame_len {
            break;
        }

        let frame = Bytes::copy_from_slice(&buffer[cursor..cursor + frame_len]);
        let _ = tx.send(frame);
        published += 1;
        cursor += frame_len;
    }

    if cursor > 0 {
        buffer.drain(..cursor);
    }

    if buffer.len() > 1024 * 1024 {
        tracing::error!(bytes=buffer.len(), "buffer ADTS invalido excedeu limite; limpando");
        buffer.clear();
    }

    published
}

/// Mantem um unico demuxer FFmpeg por emissora.
///
/// Entrada: HLS ja aprovado pelo teste auditivo.
/// Saida: mesmos pacotes AAC, somente remuxados para ADTS com -c:a copy.
///
/// Se o HLS ou a rede local falharem, o processo e recriado. Os ouvintes nao
/// recebem backlog: continuam a partir dos proximos frames disponiveis.
async fn relay_loop(id: String, source_url: String, tx: broadcast::Sender<Bytes>) {
    let ffmpeg = env::var("STUDIOSAT_FFMPEG").unwrap_or_else(|_| "/usr/bin/ffmpeg".to_string());

    loop {
        tracing::info!(station=%id, source=%source_url, "iniciando relay AAC copy");

        let mut command = Command::new(&ffmpeg);
        command
            .arg("-hide_banner")
            .arg("-loglevel")
            .arg("warning")
            .arg("-nostdin")
            .arg("-rw_timeout")
            .arg("15000000")
            .arg("-reconnect")
            .arg("1")
            .arg("-reconnect_streamed")
            .arg("1")
            .arg("-reconnect_delay_max")
            .arg("2")
            .arg("-i")
            .arg(&source_url)
            .arg("-map")
            .arg("0:a:0")
            .arg("-vn")
            .arg("-sn")
            .arg("-dn")
            .arg("-c:a")
            .arg("copy")
            .arg("-f")
            .arg("adts")
            .arg("pipe:1")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .kill_on_drop(true);

        let mut child = match command.spawn() {
            Ok(child) => child,
            Err(error) => {
                tracing::error!(station=%id, %error, "falha ao iniciar FFmpeg relay");
                sleep(Duration::from_secs(2)).await;
                continue;
            }
        };

        let Some(mut stdout) = child.stdout.take() else {
            tracing::error!(station=%id, "FFmpeg sem stdout");
            let _ = child.kill().await;
            sleep(Duration::from_secs(2)).await;
            continue;
        };

        let mut pending = Vec::<u8>::with_capacity(64 * 1024);
        let mut chunk = [0u8; 16 * 1024];
        let mut total_frames = 0u64;

        loop {
            match stdout.read(&mut chunk).await {
                Ok(0) => break,
                Ok(n) => {
                    pending.extend_from_slice(&chunk[..n]);
                    total_frames += publish_adts_frames(&mut pending, &tx) as u64;
                }
                Err(error) => {
                    tracing::warn!(station=%id, %error, "erro lendo relay FFmpeg");
                    break;
                }
            }
        }

        match child.wait().await {
            Ok(status) => tracing::warn!(station=%id, %status, total_frames, "relay FFmpeg encerrou; reiniciando"),
            Err(error) => tracing::warn!(station=%id, %error, total_frames, "erro aguardando relay FFmpeg"),
        }

        sleep(Duration::from_secs(1)).await;
    }
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "studiosat_web=info,tower_http=info".into()),
        )
        .init();

    let static_dir =
        env::var("STUDIOSAT_STATIC_DIR").unwrap_or_else(|_| "apps/web-rust/static".to_string());
    let bind = env::var("STUDIOSAT_BIND").unwrap_or_else(|_| "127.0.0.1:8792".to_string());
    let addr: SocketAddr = bind.parse()?;

    let mut relay_map = HashMap::new();
    for station in STATIONS {
        let (tx, _) = broadcast::channel::<Bytes>(4096);
        relay_map.insert(station.id.to_string(), tx.clone());

        tokio::spawn(relay_loop(
            station.id.to_string(),
            station.stream_url.to_string(),
            tx,
        ));
    }

    let state = AppState {
        relays: Arc::new(relay_map),
    };

    let app = Router::new()
        .route("/", get(|| async { Redirect::temporary("/listen-v2/") }))
        .route("/health", get(health))
        .route("/api/v2/stations", get(stations))
        .route("/listen-v2/api/stations", get(stations))
        .route("/listen-v2/live/{id}.aac", get(live_aac))
        .route("/listen-v2", get(|| async { Redirect::permanent("/listen-v2/") }))
        .route("/listen-v2/", get(index))
        .nest_service("/listen-v2/static", ServeDir::new(static_dir))
        .with_state(state)
        .layer(TraceLayer::new_for_http());

    tracing::info!(%addr, "StudioSAT V2.2 iniciado: RAW AAC + fallback HLS nativo");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}
