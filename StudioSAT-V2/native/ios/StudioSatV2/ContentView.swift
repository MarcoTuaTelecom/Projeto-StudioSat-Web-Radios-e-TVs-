import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: PlayerEngine

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Studio Sat V2").font(.largeTitle).bold()
                Text(engine.station.name).font(.title2)
                Text(engine.isPlaying ? "AO VIVO" : "PAUSADO").font(.caption).bold()

                Picker(
                    "Transporte",
                    selection: Binding(
                        get: { engine.transport },
                        set: { engine.setTransport($0) }
                    )
                ) {
                    ForEach(RadioTransport.allCases) { transport in
                        Text(transport.rawValue).tag(transport)
                    }
                }
                .pickerStyle(.segmented)

                Button(engine.isPlaying ? "Pausar" : "Ouvir") {
                    engine.toggle()
                }
                .buttonStyle(.borderedProminent)

                List(Station.all) { station in
                    Button(station.name) { engine.select(station) }
                }

                Text(
                    engine.transport == .rawAAC
                        ? "AAC/ADTS contínuo → AVPlayer → CoreAudio"
                        : "HLS → AVPlayer → CoreAudio"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}
