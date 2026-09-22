import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: PlayerEngine
    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Text("Studio Sat V2").font(.largeTitle).bold()
                Text(engine.station.name).font(.title2)
                Text(engine.isPlaying ? "AO VIVO" : "PAUSADO").font(.caption).bold()
                Button(engine.isPlaying ? "Pausar" : "Ouvir") { engine.toggle() }.buttonStyle(.borderedProminent)
                List(Station.all) { station in Button(station.name) { engine.select(station) } }
                Text("HLS → AVPlayer → CoreAudio").font(.caption).foregroundStyle(.secondary)
            }.padding()
        }
    }
}
