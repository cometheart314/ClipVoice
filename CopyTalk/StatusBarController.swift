import Cocoa

@MainActor
class StatusBarController {

    private let statusItem: NSStatusItem
    let menu = NSMenu()
    private let readClipboardItem = NSMenuItem()
    private let stopItem = NSMenuItem()
    private let statusMenuItem = NSMenuItem()

    private let ttsService = TTSService()
    private let appleTTSService = AppleTTSService()
    private let audioPlayer = AudioPlayer()
    private let textProcessor = TextProcessor()

    private var isSpeaking = false
    private var currentTask: Task<Void, Never>?

    // クリップボード監視用
    private var clipboardTimer: Timer?
    private var lastChangeCount: Int
    private var lastClipboardContent: String?
    private var lastClipboardChangeTime: Date?
    private var lastSpeakTime: Date?

    init() {
        lastChangeCount = NSPasteboard.general.changeCount

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "ClipVoice") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "CT"
            }
        }

        buildMenu()
        statusItem.menu = menu

        if UserDefaults.standard.bool(forKey: "doubleCopySpeak") {
            startClipboardMonitoring()
        }

        // 設定変更の監視
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let enabled = UserDefaults.standard.bool(forKey: "doubleCopySpeak")
            if enabled && self.clipboardTimer == nil {
                self.startClipboardMonitoring()
            } else if !enabled && self.clipboardTimer != nil {
                self.stopClipboardMonitoring()
            }
            self.applyPlaybackSettings()
        }

        applyPlaybackSettings()
        MonitorWindowController.shared.onStop = { [weak self] in
            self?.stopSpeaking()
        }
    }

    private func buildMenu() {
        readClipboardItem.title = "Read Clipboard".localized
        readClipboardItem.action = #selector(readClipboard)
        readClipboardItem.target = self
        readClipboardItem.keyEquivalent = ""
        menu.addItem(readClipboardItem)

        stopItem.title = "Stop".localized
        stopItem.action = #selector(stopSpeaking)
        stopItem.target = self
        stopItem.isEnabled = false
        menu.addItem(stopItem)

        menu.addItem(NSMenuItem.separator())

        statusMenuItem.title = ""
        statusMenuItem.isHidden = true
        menu.addItem(statusMenuItem)

        let prefsItem = NSMenuItem(title: "Settings...".localized, action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        let supportItem = NSMenuItem(title: "Support Page".localized, action: #selector(openSupportPage), keyEquivalent: "")
        supportItem.target = self
        menu.addItem(supportItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit ClipVoice".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    // MARK: - Clipboard Monitoring

    private func startClipboardMonitoring() {
        lastChangeCount = NSPasteboard.general.changeCount
        lastClipboardContent = nil
        lastClipboardChangeTime = nil
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    private func stopClipboardMonitoring() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
    }

    private func checkClipboard() {
        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard let content = pasteboard.string(forType: .string), !content.isEmpty else {
            lastClipboardContent = nil
            lastClipboardChangeTime = nil
            return
        }

        let now = Date()

        // 読み上げ開始直後のクリップボード変更は無視（トリプルクリック防止）
        if let speakTime = lastSpeakTime, now.timeIntervalSince(speakTime) < 1.0 {
            return
        }

        if let prevContent = lastClipboardContent,
           let prevTime = lastClipboardChangeTime,
           content == prevContent,
           now.timeIntervalSince(prevTime) < 1.0 {
            // Cmd+C 連打を検出 → 読み上げ開始
            lastClipboardContent = nil
            lastClipboardChangeTime = nil
            lastSpeakTime = now
            speakText(content)
        } else {
            lastClipboardContent = content
            lastClipboardChangeTime = now
        }
    }

    // MARK: - Actions

    @objc private func readClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            return
        }
        speakText(text)
    }

    @objc private func stopSpeaking() {
        currentTask?.cancel()
        currentTask = nil
        audioPlayer.stop()
        appleTTSService.stop()
        updateSpeakingState(false)
    }

    @objc private func openPreferences() {
        PreferencesWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSupportPage() {
        if let url = URL(string: "https://cometheart314.github.io/ClipVoice/") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Speech

    func speakText(_ text: String) {
        // 読み上げ中なら停止してから新しいテキストを読み上げ
        if isSpeaking {
            stopSpeaking()
            // 前の Task が完全に停止するまで少し待つ
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }

        let useGoogleTTS = KeychainHelper.getAPIKey() != nil

        updateSpeakingState(true)

        if useGoogleTTS {
            currentTask = Task { [weak self] in
                guard let self = self else { return }
                await self.speakWithGoogleTTS(text)
                // キャンセル時は stopSpeaking() 側で状態を更新済み
                // （ここで更新すると次に始まった読み上げの状態を壊してしまう）
                if Task.isCancelled { return }
                await MainActor.run {
                    self.updateSpeakingState(false)
                }
            }
        } else {
            // Apple TTS: async を使わず直接メインスレッドで実行
            let language = textProcessor.detectLanguage(text)
            let (paragraphs, paragraphBreaks) = textProcessor.splitIntoParagraphsOnly(text)
            let texts = paragraphs.map { ($0, language) }
            let monitor = MonitorWindowController.isEnabled ? MonitorWindowController.shared : nil
            monitor?.show(segments: paragraphs, paragraphBreaks: paragraphBreaks)
            appleTTSService.speak(texts: texts, onWord: { index, range in
                monitor?.highlight(segment: index, inner: range)
            }) { [weak self] in
                self?.updateSpeakingState(false)
            }
        }
    }

    private func speakWithGoogleTTS(_ text: String) async {
        let model = await MainActor.run { TTSModel.current }
        let (chunks, paragraphBreaks) = textProcessor.splitText(text, model: model)
        guard !chunks.isEmpty else { return }

        let monitor = MonitorWindowController.isEnabled ? MonitorWindowController.shared : nil
        monitor?.show(segments: chunks, paragraphBreaks: paragraphBreaks)

        let language = textProcessor.detectLanguage(text)
        let fadeSamples = 480
        let silenceBytes = Data(count: Int(24000 * 0.6) * MemoryLayout<Int16>.size)

        // 先読みバッファサイズ（現在再生中 + 次の N チャンクを先読み）
        let lookahead = 3

        // 先読みタスクを管理する配列
        var prefetchTasks: [Task<Data, Error>] = []

        // 最初の lookahead 分を先読み開始
        for i in 0..<min(lookahead, chunks.count) {
            prefetchTasks.append(fetchAudio(for: chunks[i], language: language))
        }

        await audioPlayer.warmUp()

        for (index, _) in chunks.enumerated() {
            if Task.isCancelled { return }

            // 次のチャンクの先読みを開始
            let nextPrefetch = index + lookahead
            if nextPrefetch < chunks.count {
                prefetchTasks.append(fetchAudio(for: chunks[nextPrefetch], language: language))
            }

            // 現在のチャンクの音声データを取得
            do {
                var audioData = try await prefetchTasks[index].value
                Self.applyFades(&audioData, fadeSamples: fadeSamples)
                // 段落間の無音を含まない、音声そのものの長さ（モニターのハイライト推定用）
                let speechDuration = Double(audioData.count / MemoryLayout<Int16>.size) / 24000

                if paragraphBreaks.contains(index) {
                    audioData.append(silenceBytes)
                }

                if Task.isCancelled { return }
                monitor?.highlight(segment: index, estimatedDuration: speechDuration)
                await audioPlayer.playAndWait(data: audioData)
            } catch {
                if Task.isCancelled { return }
                print("TTS error for chunk \(index): \(error)")
                // エラーが発生したチャンクをスキップして次へ続行
                continue
            }
        }
    }

    // speakWithAppleTTS は廃止 — AppleTTSService.speak(texts:completion:) を直接使用

    /// PCM音声データの先頭と末尾にフェードイン/フェードアウトを適用
    private static func applyFades(_ data: inout Data, fadeSamples: Int) {
        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard sampleCount > fadeSamples * 2 else { return }

        data.withUnsafeMutableBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }

            // フェードイン
            for i in 0..<fadeSamples {
                let gain = Float(i) / Float(fadeSamples)
                ptr[i] = Int16(Float(ptr[i]) * gain)
            }

            // フェードアウト
            for i in 0..<fadeSamples {
                let position = sampleCount - fadeSamples + i
                let gain = Float(fadeSamples - i) / Float(fadeSamples)
                ptr[position] = Int16(Float(ptr[position]) * gain)
            }
        }
    }

    /// チャンクの音声データを非同期に取得する Task を返す
    private func fetchAudio(for chunk: String, language: SpeechLanguage) -> Task<Data, Error> {
        return Task {
            try await self.ttsService.synthesize(text: chunk, language: language)
        }
    }

    /// 速度・音量の設定を再生中の音声に反映する（モニターウィンドウのスライダー操作など）
    private func applyPlaybackSettings() {
        audioPlayer.volume = Float(UserDefaults.standard.double(forKey: MonitorWindowController.volumeKey))
        appleTTSService.applyCurrentSettings()
    }

    private func updateSpeakingState(_ speaking: Bool) {
        isSpeaking = speaking
        MonitorWindowController.shared.setSpeaking(speaking)
        readClipboardItem.isEnabled = !speaking
        stopItem.isEnabled = speaking

        if speaking {
            statusMenuItem.title = "Reading...".localized
            statusMenuItem.isHidden = false
            if let button = statusItem.button {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                if let image = NSImage(systemSymbolName: "speaker.wave.3", accessibilityDescription: "ClipVoice - Speaking")?.withSymbolConfiguration(config) {
                    image.isTemplate = true
                    button.image = image
                }
            }
        } else {
            statusMenuItem.isHidden = true
            if let button = statusItem.button {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                if let image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "ClipVoice")?.withSymbolConfiguration(config) {
                    image.isTemplate = true
                    button.image = image
                }
            }
        }
    }
}

// MARK: - Localization Helper

extension String {
    var localized: String {
        NSLocalizedString(self, comment: "")
    }
}
