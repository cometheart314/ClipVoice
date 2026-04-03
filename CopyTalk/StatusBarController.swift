import Cocoa

class StatusBarController {

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
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

    init() {
        lastChangeCount = NSPasteboard.general.changeCount

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "CopyTalk") {
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

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit CopyTalk".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    // MARK: - Clipboard Monitoring

    private func startClipboardMonitoring() {
        lastChangeCount = NSPasteboard.general.changeCount
        lastClipboardContent = nil
        lastClipboardChangeTime = nil
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
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

        if let prevContent = lastClipboardContent,
           let prevTime = lastClipboardChangeTime,
           content == prevContent,
           now.timeIntervalSince(prevTime) < 0.5 {
            // Cmd+C 連打を検出 → 読み上げ開始
            lastClipboardContent = nil
            lastClipboardChangeTime = nil
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

    // MARK: - Speech

    func speakText(_ text: String) {
        // 読み上げ中なら停止してから新しいテキストを読み上げ
        if isSpeaking {
            stopSpeaking()
        }

        let useGoogleTTS = KeychainHelper.getAPIKey() != nil

        updateSpeakingState(true)

        currentTask = Task { [weak self] in
            guard let self = self else { return }

            if useGoogleTTS {
                await self.speakWithGoogleTTS(text)
            } else {
                await self.speakWithAppleTTS(text)
            }

            await MainActor.run {
                self.updateSpeakingState(false)
            }
        }
    }

    private func speakWithGoogleTTS(_ text: String) async {
        let (chunks, paragraphBreaks) = textProcessor.splitText(text)
        guard !chunks.isEmpty else { return }

        // テキスト全体から言語を1回だけ判定し、全チャンクで同じ音声を使う
        let language = textProcessor.detectLanguage(text)

        // 全チャンクの音声を取得
        var fetchTasks: [Task<Data, Error>] = []
        for chunk in chunks {
            fetchTasks.append(fetchAudio(for: chunk, language: language))
        }

        // 全チャンクの音声データを取得し、フェード処理して結合
        let silenceBytes = Data(count: Int(24000 * 0.6) * MemoryLayout<Int16>.size) // 0.6秒
        let fadeSamples = 480 // フェード区間（約20ms @ 24kHz）
        var combinedData = Data()

        for (index, task) in fetchTasks.enumerated() {
            if Task.isCancelled { return }

            do {
                var audioData = try await task.value
                Self.applyFades(&audioData, fadeSamples: fadeSamples)
                combinedData.append(audioData)

                if paragraphBreaks.contains(index) {
                    combinedData.append(silenceBytes)
                }
            } catch {
                if !Task.isCancelled {
                    print("TTS error for chunk \(index): \(error)")
                }
                return
            }
        }

        if Task.isCancelled { return }

        // オーディオパイプラインを暖めてから一括再生
        await audioPlayer.warmUp()
        if Task.isCancelled { return }
        await audioPlayer.playAndWait(data: combinedData)
    }

    private func speakWithAppleTTS(_ text: String) async {
        let (paragraphs, paragraphBreaks) = textProcessor.splitIntoParagraphsOnly(text)
        guard !paragraphs.isEmpty else { return }

        let language = textProcessor.detectLanguage(text)

        for (index, paragraph) in paragraphs.enumerated() {
            if Task.isCancelled { break }

            await appleTTSService.speakAndWait(text: paragraph, language: language)

            if paragraphBreaks.contains(index) && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 600_000_000) // 0.6秒
            }
        }
    }

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

    private func updateSpeakingState(_ speaking: Bool) {
        isSpeaking = speaking
        readClipboardItem.isEnabled = !speaking
        stopItem.isEnabled = speaking

        if speaking {
            statusMenuItem.title = "Reading...".localized
            statusMenuItem.isHidden = false
            if let button = statusItem.button {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                if let image = NSImage(systemSymbolName: "speaker.wave.3", accessibilityDescription: "CopyTalk - Speaking")?.withSymbolConfiguration(config) {
                    image.isTemplate = true
                    button.image = image
                }
            }
        } else {
            statusMenuItem.isHidden = true
            if let button = statusItem.button {
                let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
                if let image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "CopyTalk")?.withSymbolConfiguration(config) {
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
