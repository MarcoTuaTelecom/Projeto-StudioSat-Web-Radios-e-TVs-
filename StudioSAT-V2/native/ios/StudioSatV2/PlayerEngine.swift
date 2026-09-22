import AVFoundation
import Foundation

/// Engine iOS nativo. AVPlayer recebe HLS diretamente.
@MainActor
final class PlayerEngine: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var station = Station.all[0]
    private let player = AVPlayer()

    init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
        select(station)
    }

    func select(_ next: Station) {
        let wasPlaying = isPlaying
        station = next
        player.replaceCurrentItem(with: AVPlayerItem(url: next.streamURL))
        if wasPlaying { play() }
    }

    func play() { player.play(); isPlaying = true }
    func pause() { player.pause(); isPlaying = false }
    func toggle() { isPlaying ? pause() : play() }
}
