import AVFoundation
import Combine
import Foundation

enum RadioTransport: String, CaseIterable, Identifiable {
    case rawAAC = "RAW AAC"
    case nativeHLS = "HLS nativo"

    var id: String { rawValue }
}

/// Engine iOS nativo.
///
/// Não existe WKWebView. O usuário pode comparar dois caminhos nativos:
/// - RAW AAC: stream ADTS contínuo do V2.2;
/// - HLS nativo: HLS oficial diretamente no AVPlayer.
@MainActor
final class PlayerEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var station = Station.all[0]
    @Published private(set) var transport: RadioTransport = .rawAAC

    private let player = AVPlayer()

    init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
        replaceItem()
    }

    private var currentURL: URL {
        switch transport {
        case .rawAAC: station.rawAACURL
        case .nativeHLS: station.hlsURL
        }
    }

    private func replaceItem() {
        let wasPlaying = isPlaying
        player.pause()
        player.replaceCurrentItem(with: AVPlayerItem(url: currentURL))
        if wasPlaying { player.play() }
    }

    func select(_ next: Station) {
        station = next
        replaceItem()
    }

    func setTransport(_ next: RadioTransport) {
        guard next != transport else { return }
        transport = next
        replaceItem()
    }

    func play() {
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func toggle() {
        isPlaying ? pause() : play()
    }
}
