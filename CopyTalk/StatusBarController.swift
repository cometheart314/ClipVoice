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

        // オーディオパイプラインを事前に暖めておく（頭切れ防止）
        await audioPlayer.warmUp()
        if Task.isCancelled { return }

        let prefetchMinChars = 100

        // 先読みキューを文字数ベースで埋める
        var prefetchQueue: [Task<Data, Error>] = []
        var nextPrefetchIndex = 0
        var prefetchedChars = 0

        func fillPrefetchQueue() {
            while nextPrefetchIndex < chunks.count && prefetchedChars < prefetchMinChars {
                let chunk = chunks[nextPrefetchIndex]
                prefetchQueue.append(fetchAudio(for: chunk, language: language))
                prefetchedChars += chunk.count
                nextPrefetchIndex += 1
            }
            // 最低1つは先読みを追加
            if nextPrefetchIndex < chunks.count && prefetchQueue.count <= prefetchQueue.count {
                let chunk = chunks[nextPrefetchIndex]
                prefetchQueue.append(fetchAudio(for: chunk, language: language))
                prefetchedChars += chunk.count
                nextPrefetchIndex += 1
            }
        }

        fillPrefetchQueue()

        for index in 0..<chunks.count {
            if Task.isCancelled { break }

            do {
                let audioData = try await prefetchQueue[index].value
                if Task.isCancelled { break }

                // 再生開始前に先読みキューを補充
                prefetchedChars -= chunks[index].count
                fillPrefetchQueue()

                await audioPlayer.playAndWait(data: audioData)

                // 段落の区切りでは間を入れる
                if paragraphBreaks.contains(index) && !Task.isCancelled {
                    await audioPlayer.playSilence(duration: 0.6)
                }
            } catch {
                if !Task.isCancelled {
                    print("TTS error for chunk \(index): \(error)")
                }
                break
            }
        }
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
