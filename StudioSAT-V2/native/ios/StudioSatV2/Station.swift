import Foundation

/// Modelo puro. Não contém qualquer processamento de áudio.
struct Station: Identifiable, Hashable {
    let id: String
    let name: String
    let streamURL: URL

    static let all: [Station] = [
        .init(id: "radioprincipal", name: "Rádio Studio Sat", streamURL: URL(string: "https://radio.studiosatweb.com.br/radioprincipal/index.m3u8")!),
        .init(id: "radiopop", name: "Studio Sat Pop", streamURL: URL(string: "https://radio.studiosatweb.com.br/radiopop/index.m3u8")!),
        .init(id: "radiorock", name: "Studio Sat Rock", streamURL: URL(string: "https://radio.studiosatweb.com.br/radiorock/index.m3u8")!),
        .init(id: "radioclassicas", name: "Studio Sat Clássicas", streamURL: URL(string: "https://radio.studiosatweb.com.br/radioclassicas/index.m3u8")!),
        .init(id: "radiocountry", name: "Studio Sat Country", streamURL: URL(string: "https://radio.studiosatweb.com.br/radiocountry/index.m3u8")!)
    ]
}
