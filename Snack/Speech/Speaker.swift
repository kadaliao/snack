import AVFoundation

/// Says answers aloud, offline, in the language learnt. It plays with the ringer
/// switch and over music without stopping it.
@MainActor
final class Speaker {
    static let shared = Speaker()

    private let synthesizer = AVSpeechSynthesizer()

    private init() {
        Audio.configure()
    }

    func say(_ text: String, language: String, slowly: Bool = false) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Self.voice(language))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (slowly ? 0.6 : 0.95)
        synthesizer.speak(utterance)
    }

    private static func voice(_ language: String) -> String {
        switch language.lowercased() {
        case "en": "en-US"
        case "ja": "ja-JP"
        case "zh": "zh-CN"
        case "ko": "ko-KR"
        default: language
        }
    }
}
