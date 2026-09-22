//! Núcleo canônico da StudioSAT V2.
//!
//! Este crate contém somente modelos e configuração estática de domínio.
//! Ele não abre, decodifica, reamostra nem processa áudio.

use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct Station {
    pub id: &'static str,
    pub name: &'static str,
    pub short_name: &'static str,
    pub description: &'static str,
    pub stream_url: &'static str,
    pub metadata_url: &'static str,
}

pub const STATIONS: &[Station] = &[
    Station { id: "radioprincipal", name: "Rádio Studio Sat", short_name: "Principal", description: "Grandes sucessos e programação principal", stream_url: "https://radio.studiosatweb.com.br/radioprincipal/index.m3u8", metadata_url: "https://radio.studiosatweb.com.br/assets/now/radioprincipal.json" },
    Station { id: "radiopop", name: "Rádio Studio Sat Pop", short_name: "Pop", description: "Hits, lançamentos e cultura pop", stream_url: "https://radio.studiosatweb.com.br/radiopop/index.m3u8", metadata_url: "https://radio.studiosatweb.com.br/assets/now/radiopop.json" },
    Station { id: "radiorock", name: "Rádio Studio Sat Rock", short_name: "Rock", description: "Clássicos, novidades e atitude", stream_url: "https://radio.studiosatweb.com.br/radiorock/index.m3u8", metadata_url: "https://radio.studiosatweb.com.br/assets/now/radiorock.json" },
    Station { id: "radioclassicas", name: "Rádio Studio Sat Clássicas", short_name: "Clássicas", description: "Música clássica e obras essenciais", stream_url: "https://radio.studiosatweb.com.br/radioclassicas/index.m3u8", metadata_url: "https://radio.studiosatweb.com.br/assets/now/radioclassicas.json" },
    Station { id: "radiocountry", name: "Rádio Studio Sat Country", short_name: "Country", description: "Country, raízes e novos nomes", stream_url: "https://radio.studiosatweb.com.br/radiocountry/index.m3u8", metadata_url: "https://radio.studiosatweb.com.br/assets/now/radiocountry.json" },
];
