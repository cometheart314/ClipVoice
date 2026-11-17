import Cocoa
import ServiceManagement

class PreferencesWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {

    static let shared: PreferencesWindowController = {
        let wc = PreferencesWindowController()
        return wc
    }()

    private var apiKeyField: NSTextField!
    private var modelPopup: NSPopUpButton!
    private var japaneseVoicePopup: NSPopUpButton!
    private var englishVoicePopup: NSPopUpButton!
    private var speakingRateSlider: NSSlider!
    private var speakingRateLabel: NSTextField!
    private var testJaButton: NSButton!
    private var testEnButton: NSButton!
    private var engineStatusLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var doubleCopySpeakCheckbox: NSButton!
    private var showInDockCheckbox: NSButton!
    private var launchAtLoginCheckbox: NSButton!
    private var showMonitorCheckbox: NSButton!
    private var infoLabel: NSTextField!

    // Google TTS 関連の UI 要素（非表示切り替え用）
    private var googleTTSViews: [NSView] = []
    // Google TTS 関連のラベル（非表示切り替え用）
    private var googleTTSLabels: [NSView] = []

    private var showAdvanced: Bool {
        get { UserDefaults.standard.bool(forKey: "showAdvancedSettings") }
        set { UserDefaults.standard.set(newValue, forKey: "showAdvancedSettings") }
    }

    private let ttsService = TTSService()
    private let appleTTSService = AppleTTSService()
    private let audioPlayer = AudioPlayer()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClipVoice Settings".localized
        window.isReleasedWhenClosed = false

        self.init(window: window)
        window.delegate = self
        setupUI()
        loadSettings()

        // モニターウィンドウ側で速度が変更されたらスライダーに反映する
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let saved = UserDefaults.standard.double(forKey: "speakingRate")
            let rate = saved > 0 ? saved : 1.0
            if abs(self.speakingRateSlider.doubleValue - rate) > 0.001 {
                self.speakingRateSlider.doubleValue = rate
                self.updateRateLabel(rate)
            }
        }
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let margin: CGFloat = 20
        let labelWidth: CGFloat = 110
        let fieldX: CGFloat = margin + labelWidth + 8
        let fieldWidth: CGFloat = 280
        var y: CGFloat = 450

        // API Key
        let apiKeyLabel = makeLabel("API Key:".localized, frame: NSRect(x: margin, y: y, width: labelWidth, height: 22), alignment: .right)
        contentView.addSubview(apiKeyLabel)
        googleTTSLabels.append(apiKeyLabel)
        apiKeyField = NSSecureTextField(frame: NSRect(x: fieldX, y: y, width: fieldWidth, height: 24))
        apiKeyField.placeholderString = "Enter Google Cloud API Key"
        apiKeyField.delegate = self
        apiKeyField.target = self
        apiKeyField.action = #selector(apiKeyChanged)
        contentView.addSubview(apiKeyField)
        googleTTSViews.append(apiKeyField)

        // Engine Status
        y -= 22
        engineStatusLabel = ClickableLinkLabel(labelWithString: "")
        engineStatusLabel.frame = NSRect(x: fieldX, y: y, width: fieldWidth, height: 20)
        engineStatusLabel.font = NSFont.systemFont(ofSize: 12)
        engineStatusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(engineStatusLabel)
        googleTTSViews.append(engineStatusLabel)

        // Model
        y -= 30
        let modelLabel = makeLabel("Model:".localized, frame: NSRect(x: margin, y: y + 2, width: labelWidth, height: 22), alignment: .right)
        contentView.addSubview(modelLabel)
        googleTTSLabels.append(modelLabel)
        modelPopup = NSPopUpButton(frame: NSRect(x: fieldX, y: y, width: 200, height: 26))
        for model in TTSModel.allCases {
            modelPopup.addItem(withTitle: model.displayName)
            modelPopup.lastItem?.representedObject = model.rawValue
        }
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)
        contentView.addSubview(modelPopup)
        googleTTSViews.append(modelPopup)

        // Japanese Voice
        y -= 30
        let jaVoiceLabel = makeLabel("Japanese Voice:".localized, frame: NSRect(x: margin, y: y + 2, width: labelWidth, height: 22), alignment: .right)
        contentView.addSubview(jaVoiceLabel)
        googleTTSLabels.append(jaVoiceLabel)
        japaneseVoicePopup = NSPopUpButton(frame: NSRect(x: fieldX, y: y, width: 200, height: 26))
        japaneseVoicePopup.target = self
        japaneseVoicePopup.action = #selector(voiceChanged)
        contentView.addSubview(japaneseVoicePopup)
        googleTTSViews.append(japaneseVoicePopup)

        testJaButton = NSButton(title: "Test".localized, target: self, action: #selector(testSpeakJapanese))
        testJaButton.bezelStyle = .rounded
        testJaButton.controlSize = .small
        testJaButton.font = NSFont.systemFont(ofSize: 11)
        testJaButton.frame = NSRect(x: fieldX + 208, y: y, width: 60, height: 26)
        contentView.addSubview(testJaButton)
        googleTTSViews.append(testJaButton)

        // English Voice
        y -= 36
        let enVoiceLabel = makeLabel("English Voice:".localized, frame: NSRect(x: margin, y: y + 2, width: labelWidth, height: 22), alignment: .right)
        contentView.addSubview(enVoiceLabel)
        googleTTSLabels.append(enVoiceLabel)
        englishVoicePopup = NSPopUpButton(frame: NSRect(x: fieldX, y: y, width: 200, height: 26))
        englishVoicePopup.target = self
        englishVoicePopup.action = #selector(voiceChanged)
        contentView.addSubview(englishVoicePopup)
        googleTTSViews.append(englishVoicePopup)

        testEnButton = NSButton(title: "Test".localized, target: self, action: #selector(testSpeakEnglish))
        testEnButton.bezelStyle = .rounded
        testEnButton.controlSize = .small
        testEnButton.font = NSFont.systemFont(ofSize: 11)
        testEnButton.frame = NSRect(x: fieldX + 208, y: y, width: 60, height: 26)
        contentView.addSubview(testEnButton)
        googleTTSViews.append(testEnButton)

        // Speaking Rate
        y -= 36
        contentView.addSubview(makeLabel("Speed:".localized, frame: NSRect(x: margin, y: y + 2, width: labelWidth, height: 22), alignment: .right))
        speakingRateSlider = NSSlider(frame: NSRect(x: fieldX, y: y, width: 220, height: 24))
        speakingRateSlider.minValue = 0.5
        speakingRateSlider.maxValue = 2.0
        speakingRateSlider.doubleValue = 1.0
        speakingRateSlider.numberOfTickMarks = 7
        speakingRateSlider.allowsTickMarkValuesOnly = false
        speakingRateSlider.isContinuous = true
        speakingRateSlider.target = self
        speakingRateSlider.action = #selector(speakingRateChanged)
        contentView.addSubview(speakingRateSlider)

        speakingRateLabel = NSTextField(labelWithString: "1.0x")
        speakingRateLabel.frame = NSRect(x: fieldX + 228, y: y + 2, width: 50, height: 22)
        speakingRateLabel.textColor = .secondaryLabelColor
        contentView.addSubview(speakingRateLabel)

        // Status Label
        y -= 16
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: fieldX, y: y, width: 280, height: 22)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(statusLabel)

        // Separator
        y -= 10
        let separator = NSBox(frame: NSRect(x: margin, y: y, width: 410, height: 1))
        separator.boxType = .separator
        contentView.addSubview(separator)

        // Speak on Double Copy
        y -= 30
        doubleCopySpeakCheckbox = NSButton(checkboxWithTitle: "Speak on Double Copy (⌘C ⌘C)".localized, target: self, action: #selector(doubleCopySpeakChanged))
        doubleCopySpeakCheckbox.frame = NSRect(x: fieldX, y: y, width: fieldWidth, height: 22)
        contentView.addSubview(doubleCopySpeakCheckbox)

        // Show in Dock
        y -= 26
        showInDockCheckbox = NSButton(checkboxWithTitle: "Show Icon in Dock".localized, target: self, action: #selector(showInDockChanged))
        showInDockCheckbox.frame = NSRect(x: fieldX, y: y, width: fieldWidth, height: 22)
        contentView.addSubview(showInDockCheckbox)

        // Launch at Login
        y -= 26
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login".localized, target: self, action: #selector(launchAtLoginChanged))
        launchAtLoginCheckbox.frame = NSRect(x: fieldX, y: y, width: fieldWidth, height: 22)
        contentView.addSubview(launchAtLoginCheckbox)

        // Show Monitor Window
        y -= 26
        showMonitorCheckbox = NSButton(checkboxWithTitle: "Show Monitor Window While Reading".localized, target: self, action: #selector(showMonitorChanged))
        showMonitorCheckbox.frame = NSRect(x: fieldX, y: y, width: fieldWidth, height: 22)
        contentView.addSubview(showMonitorCheckbox)

        // Defaults Button
        y -= 36
        let defaultsButton = NSButton(title: "Defaults".localized, target: self, action: #selector(resetToDefaults))
        defaultsButton.bezelStyle = .rounded
        defaultsButton.frame = NSRect(x: margin, y: y, width: 90, height: 28)
        contentView.addSubview(defaultsButton)

        // Info (最下段)
        y -= 60
        infoLabel = NSTextField(wrappingLabelWithString: "")
        infoLabel.frame = NSRect(x: margin, y: y, width: 410, height: 58)
        infoLabel.font = NSFont.systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        contentView.addSubview(infoLabel)

        // Version (右下) — 5回クリックで詳細モード切替
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let versionLabel = VersionClickLabel(labelWithString: "v\(version) (\(build))")
        versionLabel.font = NSFont.systemFont(ofSize: 10)
        versionLabel.textColor = .labelColor
        versionLabel.alignment = .right
        versionLabel.frame = NSRect(x: margin, y: y - 18, width: 410, height: 14)
        versionLabel.onSecretTap = { [weak self] in
            self?.toggleAdvancedMode()
        }
        contentView.addSubview(versionLabel)

        // 初期表示モードを適用
        applyAdvancedMode(animated: false)
    }

    private func makeLabel(_ title: String, frame: NSRect, alignment: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.frame = frame
        label.alignment = alignment
        return label
    }

    // MARK: - Voice Popup Management

    private func updateVoicePopups() {
        let model = selectedModel()

        // Japanese voices
        let jaVoices = VoiceOption.voices(for: .japanese, model: model)
        japaneseVoicePopup.removeAllItems()
        for voice in jaVoices {
            japaneseVoicePopup.addItem(withTitle: voice.displayName)
            japaneseVoicePopup.lastItem?.representedObject = voice.name
        }

        // English voices
        let enVoices = VoiceOption.voices(for: .english, model: model)
        englishVoicePopup.removeAllItems()
        for voice in enVoices {
            englishVoicePopup.addItem(withTitle: voice.displayName)
            englishVoicePopup.lastItem?.representedObject = voice.name
        }

        // 保存された値を復元
        if let savedJa = UserDefaults.standard.string(forKey: "japaneseVoice") {
            for (index, item) in japaneseVoicePopup.itemArray.enumerated() {
                if item.representedObject as? String == savedJa {
                    japaneseVoicePopup.selectItem(at: index)
                    break
                }
            }
        }

        if let savedEn = UserDefaults.standard.string(forKey: "englishVoice") {
            for (index, item) in englishVoicePopup.itemArray.enumerated() {
                if item.representedObject as? String == savedEn {
                    englishVoicePopup.selectItem(at: index)
                    break
                }
            }
        }
    }

    // MARK: - Settings

    private func loadSettings() {
        if let key = KeychainHelper.getAPIKey() {
            apiKeyField.stringValue = key
        } else {
            apiKeyField.stringValue = ""
        }

        // モデル選択を復元
        let currentModel = TTSModel.current
        for (index, item) in modelPopup.itemArray.enumerated() {
            if item.representedObject as? String == currentModel.rawValue {
                modelPopup.selectItem(at: index)
                break
            }
        }

        updateVoicePopups()

        let rate = UserDefaults.standard.double(forKey: "speakingRate")
        let effectiveRate = rate > 0 ? rate : 1.0
        speakingRateSlider.doubleValue = effectiveRate
        updateRateLabel(effectiveRate)

        statusLabel.stringValue = ""
        updateEngineState()

        doubleCopySpeakCheckbox.state = UserDefaults.standard.bool(forKey: "doubleCopySpeak") ? .on : .off
        showInDockCheckbox.state = UserDefaults.standard.bool(forKey: "showInDock") ? .on : .off
        launchAtLoginCheckbox.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        showMonitorCheckbox.state = MonitorWindowController.isEnabled ? .on : .off
    }

    private func saveSettings() {
        let key = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            KeychainHelper.saveAPIKey(key)
        } else {
            KeychainHelper.deleteAPIKey()
        }

        if let modelRaw = modelPopup.selectedItem?.representedObject as? String {
            UserDefaults.standard.set(modelRaw, forKey: "ttsModel")
        }

        if let jaVoice = japaneseVoicePopup.selectedItem?.representedObject as? String {
            UserDefaults.standard.set(jaVoice, forKey: "japaneseVoice")
        }

        if let enVoice = englishVoicePopup.selectedItem?.representedObject as? String {
            UserDefaults.standard.set(enVoice, forKey: "englishVoice")
        }

        UserDefaults.standard.set(speakingRateSlider.doubleValue, forKey: "speakingRate")
    }

    private func updateRateLabel(_ rate: Double) {
        speakingRateLabel.stringValue = String(format: "%.1fx", rate)
    }

    /// モデルポップアップから現在の TTSModel を取得
    private func selectedModel() -> TTSModel {
        if let rawValue = modelPopup.selectedItem?.representedObject as? String,
           let model = TTSModel(rawValue: rawValue) {
            return model
        }
        return .neural2
    }

    // MARK: - Actions

    @objc private func modelChanged(_ sender: NSPopUpButton) {
        // モデルが変わったら音声ポップアップを更新
        updateVoicePopups()
        saveSettings()
        updateEngineState()
    }

    @objc private func voiceChanged(_ sender: NSPopUpButton) {
        saveSettings()
    }

    @objc private func speakingRateChanged(_ sender: NSSlider) {
        updateRateLabel(sender.doubleValue)
        saveSettings()
    }

    @objc private func apiKeyChanged(_ sender: NSTextField) {
        saveSettings()
        updateEngineState()
    }

    func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField, field === apiKeyField {
            updateEngineState()
        }
    }

    private func updateEngineState() {
        let hasAPIKey = !apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        modelPopup.isEnabled = hasAPIKey
        japaneseVoicePopup.isEnabled = hasAPIKey
        englishVoicePopup.isEnabled = hasAPIKey

        if hasAPIKey {
            engineStatusLabel.attributedStringValue = NSAttributedString(
                string: "Using Google Cloud Text-to-Speech".localized,
                attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
            )
        } else {
            let text = NSMutableAttributedString(
                string: "Using Apple built-in voices".localized + " — ",
                attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]
            )
            let lang = (Locale.current.language.languageCode?.identifier ?? "en") == "ja" ? "ja" : "en"
            let link = NSAttributedString(
                string: "Get API Key".localized,
                attributes: [
                    .font: NSFont.boldSystemFont(ofSize: 12),
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .link: URL(string: "https://cometheart314.github.io/ClipVoice/\(lang)/api-setup.html")!
                ]
            )
            text.append(link)
            engineStatusLabel.allowsEditingTextAttributes = true
            engineStatusLabel.isSelectable = true
            engineStatusLabel.attributedStringValue = text
        }
    }

    // MARK: - Advanced Mode

    private func toggleAdvancedMode() {
        showAdvanced = !showAdvanced
        applyAdvancedMode(animated: true)
    }

    private func applyAdvancedMode(animated: Bool) {
        let show = showAdvanced
        let allGoogleViews = googleTTSViews + googleTTSLabels

        for view in allGoogleViews {
            view.isHidden = !show
        }

        // Info テキストを切り替え
        if show {
            infoLabel.stringValue = "ClipVoice reads clipboard text aloud using Apple's built-in voices. For higher quality, set a Google Cloud API key above. Google Cloud TTS is free up to 1 million characters per month.".localized
        } else {
            infoLabel.stringValue = "ClipVoice reads clipboard text aloud.\nSelect text and press ⌘C twice quickly to start reading.".localized
        }

        // ウィンドウの高さを調整
        let targetHeight: CGFloat = show ? 540 : 380
        guard let window = window else { return }
        var frame = window.frame
        let delta = targetHeight - frame.size.height
        frame.origin.y -= delta
        frame.size.height = targetHeight
        window.setFrame(frame, display: true, animate: animated)
    }

    @objc private func doubleCopySpeakChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "doubleCopySpeak")
    }

    @objc private func showInDockChanged(_ sender: NSButton) {
        let show = sender.state == .on
        UserDefaults.standard.set(show, forKey: "showInDock")
        NSApp.setActivationPolicy(show ? .regular : .accessory)
    }

    @objc private func showMonitorChanged(_ sender: NSButton) {
        let show = sender.state == .on
        UserDefaults.standard.set(show, forKey: MonitorWindowController.defaultsKey)
        if !show {
            MonitorWindowController.shared.close()
        }
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        let enable = sender.state == .on
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            sender.state = enable ? .off : .on
            let alert = NSAlert()
            alert.messageText = "Launch at Login".localized
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func resetToDefaults(_ sender: NSButton) {
        let alert = NSAlert()
        alert.messageText = "Reset to Defaults".localized
        alert.informativeText = "Are you sure you want to reset all settings to their default values?".localized
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset".localized)
        alert.addButton(withTitle: "Cancel".localized)

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // すべての UserDefaults を削除して出荷初期状態に戻す
        let defaults = UserDefaults.standard
        for key in ["googleCloudTTSAPIKey", "ttsModel", "japaneseVoice", "englishVoice",
                     "speakingRate", "doubleCopySpeak", "showInDock", "hasLaunchedBefore",
                     "showAdvancedSettings", MonitorWindowController.defaultsKey,
                     MonitorWindowController.volumeKey] {
            defaults.removeObject(forKey: key)
        }
        MonitorWindowController.shared.close()

        // Dock 表示を反映
        NSApp.setActivationPolicy(.regular)

        // UI を再読み込み
        loadSettings()
    }

    @objc private func testSpeakJapanese(_ sender: NSButton) {
        testSpeak(language: .japanese, text: "これはテスト読み上げです。", button: testJaButton)
    }

    @objc private func testSpeakEnglish(_ sender: NSButton) {
        testSpeak(language: .english, text: "This is a test of the text-to-speech voice.", button: testEnButton)
    }

    private func testSpeak(language: SpeechLanguage, text: String, button: NSButton) {
        saveSettings()

        statusLabel.stringValue = "Testing...".localized
        button.isEnabled = false

        if KeychainHelper.getAPIKey() != nil {
            Task {
                do {
                    let audioData = try await ttsService.synthesize(text: text, language: language)
                    await audioPlayer.playAndWait(data: audioData)

                    await MainActor.run {
                        statusLabel.stringValue = ""
                        button.isEnabled = true
                    }
                } catch {
                    await MainActor.run {
                        statusLabel.stringValue = "Error: \(error.localizedDescription)"
                        button.isEnabled = true
                    }
                }
            }
        } else {
            appleTTSService.speak(texts: [(text, language)]) { [weak self] in
                self?.statusLabel.stringValue = ""
                button.isEnabled = true
            }
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        saveSettings()
    }
}

// MARK: - リンク部分でポインターカーソルになる NSTextField

class ClickableLinkLabel: NSTextField {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if linkAt(point) != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    /// 指定座標にリンク属性があればその URL を返す
    func linkAt(_ point: NSPoint) -> URL? {
        guard let attrString = attributedStringValue as NSAttributedString?,
              !attrString.string.isEmpty else { return nil }
        let textStorage = NSTextStorage(attributedString: attrString)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: bounds.size)
        textContainer.lineFragmentPadding = 2
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        let index = layoutManager.characterIndex(for: point, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        guard index < attrString.length else { return nil }
        return attrString.attribute(.link, at: index, effectiveRange: nil) as? URL
    }
}

// MARK: - バージョンラベル 5回クリックで秘密の設定を開く

class VersionClickLabel: NSTextField {
    var onSecretTap: (() -> Void)?
    private var clickCount = 0
    private var lastClickTime: Date?

    override func mouseDown(with event: NSEvent) {
        let now = Date()
        if let last = lastClickTime, now.timeIntervalSince(last) > 2.0 {
            clickCount = 0
        }
        clickCount += 1
        lastClickTime = now

        if clickCount >= 5 {
            clickCount = 0
            onSecretTap?()
        }
    }
}
