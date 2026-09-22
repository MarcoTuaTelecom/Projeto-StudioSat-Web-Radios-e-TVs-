//! Portal/API StudioSAT V2.
//!
//! Responsabilidades:
//! - servir a interface V2;
//! - expor catálogo e healthcheck;
//! - nunca proxyar/transcodificar HLS;
//! - nunca tocar em PCM, sample rate ou playbackRate.

use axum::{
    Json, Router,
    response::{Html, Redirect},
    routing::get,
};
use serde::Serialize;
use std::{env, net::SocketAddr};
use studiosat_core::STATIONS;
use tower_http::{services::ServeDir, trace::TraceLayer};

#[derive(Serialize)]
struct Health<'a> {
    status: &'a str,
    service: &'a str,
    version: &'a str,
}

async fn health() -> Json<Health<'static>> {
    Json(Health { status: "ok", service: "studiosat-v2-web", version: env!("CARGO_PKG_VERSION") })
}

async fn stations() -> Json<&'static [studiosat_core::Station]> {
    Json(STATIONS)
}

async fn index() -> Html<&'static str> {
    Html(include_str!("../static/index.html"))
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "studiosat_web=info,tower_http=info".into()),
        )
        .init();

    let static_dir = env::var("STUDIOSAT_STATIC_DIR").unwrap_or_else(|_| "apps/web-rust/static".to_string());
    let bind = env::var("STUDIOSAT_BIND").unwrap_or_else(|_| "127.0.0.1:8792".to_string());
    let addr: SocketAddr = bind.parse()?;

    let app = Router::new()
        .route("/", get(|| async { Redirect::temporary("/listen-v2/") }))
        .route("/health", get(health))
        .route("/api/v2/stations", get(stations))
        .route("/listen-v2/api/stations", get(stations))
        .route("/listen-v2", get(|| async { Redirect::permanent("/listen-v2/") }))
        .route("/listen-v2/", get(index))
        .nest_service("/listen-v2/static", ServeDir::new(static_dir))
        .layer(TraceLayer::new_for_http());

    tracing::info!(%addr, "StudioSAT V2 iniciado");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}
