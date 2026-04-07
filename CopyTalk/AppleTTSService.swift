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
    /// システムのデフォルト音声が対象言語なら使う。
    /// そうでなければ高品質な音声を優先して選択する。
    /// 優先順: com.apple.voice.* (非compact) > com.apple.voice.compact.* > その他
    /// ノベルティ音声 (com.apple.speech.synthesis.voice.*) と
    /// eloquence 音声 (com.apple.eloquence.*) は除外
    private func voiceForLanguage(_ language: SpeechLanguage) -> NSSpeechSynthesizer.VoiceName {
        let targetPrefix: String
        switch language {
        case .japanese: targetPrefix = "ja"
        case .english:  targetPrefix = "en"
        }

        // デフォルト音声が対象言語ならそれを使う
        let defaultVoice = NSSpeechSynthesizer.defaultVoice
        let defaultAttrs = NSSpeechSynthesizer.attributes(forVoice: defaultVoice)
        if let localeId = defaultAttrs[.localeIdentifier] as? String,
           localeId.hasPrefix(targetPrefix) {
            return defaultVoice
        }

        // 対象言語の音声を品質別に分類（主要ロケール優先）
        let preferredLocale: String
        switch language {
        case .japanese: preferredLocale = "ja_JP"
        case .english:  preferredLocale = "en_US"
        }

        var premium: [NSSpeechSynthesizer.VoiceName] = []
        var premiumOther: [NSSpeechSynthesizer.VoiceName] = []
        var compact: [NSSpeechSynthesizer.VoiceName] = []
        var compactOther: [NSSpeechSynthesizer.VoiceName] = []

        for voice in NSSpeechSynthesizer.availableVoices {
            let attrs = NSSpeechSynthesizer.attributes(forVoice: voice)
            guard let localeId = attrs[.localeIdentifier] as? String,
                  localeId.hasPrefix(targetPrefix) else { continue }

            let id = voice.rawValue
            if id.hasPrefix("com.apple.speech.synthesis.voice.") { continue }
            if id.hasPrefix("com.apple.eloquence.") { continue }

            let isPreferredLocale = localeId == preferredLocale

            if id.hasPrefix("com.apple.voice.compact.") {
                if isPreferredLocale { compact.append(voice) } else { compactOther.append(voice) }
            } else if id.hasPrefix("com.apple.voice.") {
                if isPreferredLocale { premium.append(voice) } else { premiumOther.append(voice) }
            }
        }

        return premium.first ?? compact.first ?? premiumOther.first ?? compactOther.first ?? defaultVoice
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
