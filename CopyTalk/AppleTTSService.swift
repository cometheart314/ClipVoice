import AVFoundation

class AppleTTSService: NSObject, AVSpeechSynthesizerDelegate {

    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// テキストを読み上げ、完了まで待機する
    func speakAndWait(text: String, language: SpeechLanguage) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language.rawValue)

        let googleRate = UserDefaults.standard.double(forKey: "speakingRate")
        let rate = googleRate > 0 ? googleRate : 1.0
        utterance.rate = mapSpeakingRate(rate)

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont
            synthesizer.speak(utterance)
        }
    }

    /// 読み上げを即座に停止する
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// Google TTS の速度 (0.5-2.0, 1.0=標準) を AVSpeechUtterance の速度にマッピング
    private func mapSpeakingRate(_ googleRate: Double) -> Float {
        // Google 0.5 -> AV 0.3, Google 1.0 -> AV 0.5, Google 2.0 -> AV 0.75
        let mapped = Float(0.25 + (googleRate - 0.5) * (0.5 / 1.5))
        return max(AVSpeechUtteranceMinimumSpeechRate,
                   min(AVSpeechUtteranceMaximumSpeechRate, mapped))
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        continuation?.resume()
        continuation = nil
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        continuation?.resume()
        continuation = nil
    }
}
