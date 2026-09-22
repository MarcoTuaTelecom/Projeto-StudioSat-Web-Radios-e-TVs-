package br.com.studiosat.v2

/** Catálogo nativo. Nenhuma estação contém lógica de reprodução. */
data class Station(val id: String, val name: String, val streamUrl: String)

object Stations {
    val all = listOf(
        Station("radioprincipal", "Rádio Studio Sat", "https://radio.studiosatweb.com.br/radioprincipal/index.m3u8"),
        Station("radiopop", "Studio Sat Pop", "https://radio.studiosatweb.com.br/radiopop/index.m3u8"),
        Station("radiorock", "Studio Sat Rock", "https://radio.studiosatweb.com.br/radiorock/index.m3u8"),
        Station("radioclassicas", "Studio Sat Clássicas", "https://radio.studiosatweb.com.br/radioclassicas/index.m3u8"),
        Station("radiocountry", "Studio Sat Country", "https://radio.studiosatweb.com.br/radiocountry/index.m3u8")
    )
}
