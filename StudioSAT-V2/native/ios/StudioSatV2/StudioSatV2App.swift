import SwiftUI

@main
struct StudioSatV2App: App {
    @StateObject private var engine = PlayerEngine()
    var body: some Scene { WindowGroup { ContentView().environmentObject(engine) } }
}
