import AVFoundation

/// The sound effects: right, wrong, and a lesson done. They play with the ringer
/// switch and over music, like the answers read aloud.
@MainActor
final class Sounds {
    enum Effect: String, CaseIterable {
        case right, wrong, done
    }

    static let shared = Sounds()

    private var players: [Effect: AVAudioPlayer] = [:]

    private init() {
        Audio.configure()
        for effect in Effect.allCases {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url)
            else { continue }
            player.volume = 0.7
            player.prepareToPlay()
            players[effect] = player
        }
    }

    func play(_ effect: Effect) {
        guard UserDefaults.standard.bool(forKey: Prefs.sounds), let player = players[effect] else { return }
        player.currentTime = 0
        player.play()
    }
}

enum Audio {
    /// Ambient: silent with the ringer switch off, and mixed with whatever plays.
    @MainActor static func configure() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
    }
}
