import Cocoa

@MainActor
class AppleTTSService: NSObject, NSSpeechSynthesizerDelegate {

    private var synthesizer: NSSpeechSynthesizer?
    private var continuation: CheckedContinuation<Void, Never>?

    /// テキストを読み上げ、完了まで待機する
    func speakAndWait(text: String, language: SpeechLanguage) async {
        let voiceId = selectVoice(for: language)
        let synth = NSSpeechSynthesizer(voice: voiceId)
        synth?.delegate = self

        let googleRate = UserDefaults.standard.double(forKey: "speakingRate")
        let rate = googleRate > 0 ? googleRate : 1.0
        synth?.rate = mapSpeakingRate(rate)

        synthesizer = synth

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont
            if synth?.startSpeaking(text) != true {
                cont.resume()
                self.continuation = nil
            }
        }
    }

    /// 読み上げを即座に停止する
    func stop() {
        synthesizer?.stopSpeaking()
        // 待機中の continuation があれば解放する（二重読み上げ防止）
        if let cont = continuation {
            cont.resume()
            continuation = nil
        }
    }

    /// 言語に応じた音声を選択する
    /// voice: nil で NSSpeechSynthesizer を生成するとシステム設定
    /// （アクセシビリティ > 読み上げコンテンツ > システムの声）が使われる。
    /// その音声の言語が一致しない場合のみ該当言語の音声にフォールバック。
    private func selectVoice(for language: SpeechLanguage) -> NSSpeechSynthesizer.VoiceName? {
        let targetPrefix: String
        switch language {
        case .japanese: targetPrefix = "ja"
        case .english:  targetPrefix = "en"
        }

        // システムの声（voice: nil）のロケールを確認
        if let systemSynth = NSSpeechSynthesizer(voice: nil),
           let voiceName = systemSynth.voice() {
            let attrs = NSSpeechSynthesizer.attributes(forVoice: voiceName)
            if let localeId = attrs[.localeIdentifier] as? String,
               localeId.hasPrefix(targetPrefix) {
                return voiceName
            }
        }

        // システムの声が対象言語でない場合、該当言語の音声を探す
        for voice in NSSpeechSynthesizer.availableVoices {
            let attrs = NSSpeechSynthesizer.attributes(forVoice: voice)
            if let localeId = attrs[.localeIdentifier] as? String,
               localeId.hasPrefix(targetPrefix) {
                return voice
            }
        }

        // どれも見つからなければシステムの声をそのまま使う
        return nil
    }

    /// Google TTS の速度 (0.5-2.0, 1.0=標準) を NSSpeechSynthesizer の速度にマッピング
    /// NSSpeechSynthesizer.rate はワード/分（デフォルト約180-200）
    private func mapSpeakingRate(_ googleRate: Double) -> Float {
        // Google 0.5 -> 100wpm, Google 1.0 -> 190wpm, Google 2.0 -> 350wpm
        let mapped = 100 + (googleRate - 0.5) * (250.0 / 1.5)
        return Float(max(80, min(400, mapped)))
    }

    // MARK: - NSSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        Task { @MainActor in
            continuation?.resume()
            continuation = nil
        }
    }
}
