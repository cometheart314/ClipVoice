import Cocoa

class AppleTTSService: NSObject, NSSpeechSynthesizerDelegate {

    private var synthesizer: NSSpeechSynthesizer?
    private var pendingTexts: [(String, SpeechLanguage)] = []
    private var onAllFinished: (() -> Void)?

    /// テキスト配列を順番に読み上げ、すべて完了したら completion を呼ぶ
    func speak(texts: [(String, SpeechLanguage)], completion: @escaping () -> Void) {
        stop()
        pendingTexts = texts
        onAllFinished = completion
        speakNext()
    }

    /// 読み上げを即座に停止する
    func stop() {
        synthesizer?.stopSpeaking()
        synthesizer = nil
        pendingTexts.removeAll()
        let cb = onAllFinished
        onAllFinished = nil
        cb?()
    }

    private func speakNext() {
        guard !pendingTexts.isEmpty else {
            let cb = onAllFinished
            onAllFinished = nil
            cb?()
            return
        }

        let (text, language) = pendingTexts.removeFirst()
        let voice = voiceForLanguage(language)
        let synth = NSSpeechSynthesizer(voice: voice)!
        synth.delegate = self
        synthesizer = synth

        let rate = UserDefaults.standard.double(forKey: "speakingRate")
        synth.rate = mapSpeakingRate(rate > 0 ? rate : 1.0)

        if !synth.startSpeaking(text) {
            speakNext()
        }
    }

    /// 言語に応じた音声名を返す
    private func voiceForLanguage(_ language: SpeechLanguage) -> NSSpeechSynthesizer.VoiceName {
        let targetPrefix: String
        switch language {
        case .japanese: targetPrefix = "ja"
        case .english:  targetPrefix = "en"
        }

        let defaultVoice = NSSpeechSynthesizer.defaultVoice
        let defaultAttrs = NSSpeechSynthesizer.attributes(forVoice: defaultVoice)
        if let localeId = defaultAttrs[.localeIdentifier] as? String,
           localeId.hasPrefix(targetPrefix) {
            return defaultVoice
        }

        for voice in NSSpeechSynthesizer.availableVoices {
            let attrs = NSSpeechSynthesizer.attributes(forVoice: voice)
            if let localeId = attrs[.localeIdentifier] as? String,
               localeId.hasPrefix(targetPrefix) {
                return voice
            }
        }

        return defaultVoice
    }

    private func mapSpeakingRate(_ googleRate: Double) -> Float {
        let mapped = 100 + (googleRate - 0.5) * (250.0 / 1.5)
        return Float(max(80, min(400, mapped)))
    }

    // MARK: - NSSpeechSynthesizerDelegate

    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        speakNext()
    }
}
