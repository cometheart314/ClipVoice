import Cocoa
import ServiceManagement

class PreferencesWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {

    static let shared: PreferencesWindowController = {
        let wc = PreferencesWindowController()
        return wc
    }()

    private var apiKeyField: NSTextField!
    private var japaneseVoicePopup: NSPopUpButton!
    private var englishVoicePopup: NSPopUpButton!
    private var speakingRateSlider: NSSlider!
    private var speakingRateLabel: NSTextField!
    private var testJaButton: NSButton!
    private var testEnButton: NSButton!
    private var engineStatusLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var doubleCopySpeakCheckbox: NSButton!
    private var launchAtLoginCheckbox: NSButton!

    private let ttsService = TTSService()
    private let appleTTSService = AppleTTSService()
    private let audioPlayer = AudioPlayer()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 416),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CopyTalk Settings".localized
        window.isReleasedWhenClosed = false

        self.init(window: window)
        window.delegate = self
        setupUI()
        loadSettings()
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
        var y: CGFloat = 366

        // API Key
        contentView.addSubview(makeLabel("API Key:", frame: NSRect(x: margin, y: y, width: labelWidth, height: 22), alignment: .right))
        apiKeyField = NSSecureTextField(frame: NSRect(x: fieldX, y: y, width: fieldWidth, height: 24))
        apiKeyField.placeholderString = "Enter Google Cloud API Key"
        apiKeyField.delegate = self
        apiKeyField.target = self
        apiKeyField.action = #selector(apiKeyChanged)
        contentView.addSubview(apiKeyField)

        // Engine Status
        y -= 18
        engineStatusLabel = NSTextField(labelWithString: "")
        engineStatusLabel.frame = NSRect(x: fieldX, y: y, width: fieldWidth, height: 16)
        engineStatusLabel.font = NSFont.systemFont(ofSize: 10)
        engineStatusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(engineStatusLabel)

        // Japanese Voice
        y -= 26
        contentView.addSubview(makeLabel("Japanese Voice:", frame: NSRect(x: margin, y: y + 2, width: labelWidth, height: 22), alignment: .right))
        japaneseVoicePopup = NSPopUpButton(frame: NSRect(x: fieldX, y: y, width: 200, height: 26))
        japaneseVoicePopup.target = self
        japaneseVoicePopup.action = #selector(voiceChanged)
        contentView.addSubview(japaneseVoicePopup)

        testJaButton = NSButton(title: "Test", target: self, action: #selector(testSpeakJapanese))
        testJaButton.bezelStyle = .rounded
        testJaButton.controlSize = .small
        testJaButton.font = NSFont.systemFont(ofSize: 11)
        testJaButton.frame = NSRect(x: fieldX + 208, y: y, width: 60, height: 26)
        contentView.addSubview(testJaButton)

        // English Voice
        y -= 36
        contentView.addSubview(makeLabel("English Voice:", frame: NSRect(x: margin, y: y + 2, width: labelWidth, height: 22), alignment: .right))
        englishVoicePopup = NSPopUpButton(frame: NSRect(x: fieldX, y: y, width: 200, height: 26))
        englishVoicePopup.target = self
        englishVoicePopup.action = #selector(voiceChanged)
        contentView.addSubview(englishVoicePopup)

        testEnButton = NSButton(title: "Test", target: self, action: #selector(testSpeakEnglish))
        testEnButton.bezelStyle = .rounded
        testEnButton.controlSize = .small
        testEnButton.font = NSFont.systemFont(ofSize: 11)
        testEnButton.frame = NSRect(x: fieldX + 208, y: y, width: 60, height: 26)
        contentView.addSubview(testEnButton)

        // Speaking Rate
        y -= 36
        contentView.addSubview(makeLabel("Speed:", frame: NSRect(x: margin, y: y + 2, width: labelWidth, height: 22), alignment: .right))
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
        y -= 30
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: fieldX, y: y, width: 280, height: 22)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(statusLabel)

        // Separator
        y -= 20
        let separator = NSBox(frame: NSRect(x: margin, y: y, width: 410, height: 1))
        separator.boxType = .separator
        contentView.addSubview(separator)

        // Speak on Double Copy
        y -= 30
        doubleCopySpeakCheckbox = NSButton(checkboxWithTitle: "Speak on Double Copy (⌘C ⌘C)".localized, target: self, action: #selector(doubleCopySpeakChanged))
        doubleCopySpeakCheckbox.frame = NSRect(x: fieldX, y: y, width: fieldWidth, height: 22)
        contentView.addSubview(doubleCopySpeakCheckbox)

        // Launch at Login
        y -= 26
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at Login".localized, target: self, action: #selector(launchAtLoginChanged))
        launchAtLoginCheckbox.frame = NSRect(x: fieldX, y: y, width: fieldWidth, height: 22)
        contentView.addSubview(launchAtLoginCheckbox)

        // Info
        y -= 50
        let infoLabel = NSTextField(wrappingLabelWithString: "CopyTalk reads clipboard text aloud using Apple's built-in voices. For higher quality, set a Google Cloud API key above.".localized)
        infoLabel.frame = NSRect(x: margin, y: y, width: 410, height: 44)
        infoLabel.font = NSFont.systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor
        contentView.addSubview(infoLabel)
    }

    private func makeLabel(_ title: String, frame: NSRect, alignment: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.frame = frame
        label.alignment = alignment
        return label
    }

    // MARK: - Voice Popup Management

    private func updateVoicePopups() {
        // Japanese voices
        let jaVoices = VoiceOption.voices(for: .japanese)
        japaneseVoicePopup.removeAllItems()
        for voice in jaVoices {
            japaneseVoicePopup.addItem(withTitle: voice.displayName)
            japaneseVoicePopup.lastItem?.representedObject = voice.name
        }

        // English voices
        let enVoices = VoiceOption.voices(for: .english)
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
        }

        updateVoicePopups()

        let rate = UserDefaults.standard.double(forKey: "speakingRate")
        let effectiveRate = rate > 0 ? rate : 1.0
        speakingRateSlider.doubleValue = effectiveRate
        updateRateLabel(effectiveRate)

        statusLabel.stringValue = ""
        updateEngineState()

        doubleCopySpeakCheckbox.state = UserDefaults.standard.bool(forKey: "doubleCopySpeak") ? .on : .off
        launchAtLoginCheckbox.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
    }

    private func saveSettings() {
        let key = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            KeychainHelper.saveAPIKey(key)
        } else {
            KeychainHelper.deleteAPIKey()
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

    // MARK: - Actions

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

        japaneseVoicePopup.isEnabled = hasAPIKey
        englishVoicePopup.isEnabled = hasAPIKey

        if hasAPIKey {
            engineStatusLabel.stringValue = "Using Google Cloud Text-to-Speech".localized
        } else {
            engineStatusLabel.stringValue = "Using Apple built-in voices".localized
        }
    }

    @objc private func doubleCopySpeakChanged(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: "doubleCopySpeak")
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
            Task {
                await appleTTSService.speakAndWait(text: text, language: language)

                await MainActor.run {
                    statusLabel.stringValue = ""
                    button.isEnabled = true
                }
            }
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        saveSettings()
    }
}
