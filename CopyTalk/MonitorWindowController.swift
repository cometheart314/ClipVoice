import Cocoa
import NaturalLanguage

/// 読み上げ内容を表示し、読み上げ中の部分をハイライトするモニターウィンドウ
class MonitorWindowController: NSWindowController {

    static let shared: MonitorWindowController = {
        let wc = MonitorWindowController()
        return wc
    }()

    static let defaultsKey = "showMonitorWindow"
    static let volumeKey = "speakingVolume"
    static let opacityKey = "monitorOpacity"

    /// 設定されているウィンドウの不透明度（0.3〜1.0）
    static var opacity: Double {
        min(max(UserDefaults.standard.double(forKey: opacityKey), 0.3), 1.0)
    }

    /// 中止ボタンが押されたときに呼ばれる
    var onStop: (() -> Void)?

    /// 設定でモニターウィンドウの表示が有効になっているか
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    private var textView: NSTextView!
    private var rateSlider: NSSlider!
    private var rateLabel: NSTextField!
    private var volumeSlider: NSSlider!
    private var stopButton: NSButton!

    /// 各セグメント（段落またはチャンク）の表示テキスト内での範囲
    private var segmentRanges: [NSRange] = []

    // 再生時間からの推定ハイライト用（Google TTS）
    private var timer: Timer?
    private var timedSegment = 0
    private var timedSentences: [NSRange] = []
    private var timedLength = 0
    private var timedDuration: TimeInterval = 0
    private var timedStart = Date()
    private var timedCurrent = -1

    private let segmentColor = NSColor.systemYellow.withAlphaComponent(0.25)
    private let currentColor = NSColor.systemYellow.withAlphaComponent(0.85)

    convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 280),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.title = "ClipVoice"
        panel.isReleasedWhenClosed = false
        // 他のアプリで作業中でも前面に表示し、フォーカスは奪わない
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 400, height: 140)

        self.init(window: panel)
        setupUI()

        panel.center()
        windowFrameAutosaveName = "ClipVoiceMonitorWindow"
    }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSTextView.scrollableTextView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        textView = scrollView.documentView as? NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.textContainerInset = NSSize(width: 10, height: 10)

        contentView.addSubview(scrollView)

        // 下部コントロールバー（速度・音量・中止）
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)

        let speedTitle = NSTextField(labelWithString: "Speed:".localized)
        speedTitle.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

        rateSlider = NSSlider(value: 1.0, minValue: 0.5, maxValue: 2.0, target: self, action: #selector(rateChanged))
        rateSlider.controlSize = .small
        rateSlider.isContinuous = true
        rateSlider.toolTip = "Speed:".localized

        rateLabel = NSTextField(labelWithString: "1.0x")
        rateLabel.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        rateLabel.textColor = .secondaryLabelColor

        let volumeIcon = NSImageView()
        volumeIcon.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Volume".localized)
        volumeIcon.contentTintColor = .secondaryLabelColor
        volumeIcon.toolTip = "Volume".localized

        volumeSlider = NSSlider(value: 1.0, minValue: 0.0, maxValue: 1.0, target: self, action: #selector(volumeChanged))
        volumeSlider.controlSize = .small
        volumeSlider.isContinuous = true
        volumeSlider.toolTip = "Volume".localized

        stopButton = NSButton(title: "Stop".localized, target: self, action: #selector(stopClicked))
        stopButton.bezelStyle = .rounded
        stopButton.controlSize = .small
        stopButton.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        stopButton.isEnabled = false

        let bar = NSStackView(views: [speedTitle, rateSlider, rateLabel, volumeIcon, volumeSlider, stopButton])
        bar.orientation = .horizontal
        bar.alignment = .centerY
        bar.spacing = 6
        bar.setCustomSpacing(16, after: rateLabel)
        bar.setCustomSpacing(16, after: volumeSlider)
        bar.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        bar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bar)

        // ウィンドウ幅に応じて伸縮するのはスライダーのみ
        for view in [speedTitle, rateLabel, volumeIcon, stopButton] as [NSView] {
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: separator.topAnchor),

            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bar.topAnchor),

            bar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: 34),

            rateSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            volumeSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),
            rateSlider.widthAnchor.constraint(equalTo: volumeSlider.widthAnchor, multiplier: 1.3),
            rateLabel.widthAnchor.constraint(equalToConstant: 30)
        ])

        syncControls()
        // 設定パネル側で速度が変更されたらスライダーに反映する
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncControls()
        }
    }

    /// UserDefaults の値をスライダーとウィンドウの透明度に反映する
    private func syncControls() {
        let alpha = CGFloat(Self.opacity)
        if let window = window, abs(window.alphaValue - alpha) > 0.001 {
            window.alphaValue = alpha
        }

        let saved = UserDefaults.standard.double(forKey: "speakingRate")
        let rate = saved > 0 ? saved : 1.0
        if abs(rateSlider.doubleValue - rate) > 0.001 {
            rateSlider.doubleValue = rate
        }
        rateLabel.stringValue = String(format: "%.1fx", rate)

        let volume = UserDefaults.standard.double(forKey: Self.volumeKey)
        if abs(volumeSlider.doubleValue - volume) > 0.001 {
            volumeSlider.doubleValue = volume
        }
    }

    // MARK: - Control Actions

    @objc private func rateChanged(_ sender: NSSlider) {
        // 0.1 刻みに丸める（設定パネルの表示と揃える）
        let rate = (sender.doubleValue * 10).rounded() / 10
        rateLabel.stringValue = String(format: "%.1fx", rate)
        UserDefaults.standard.set(rate, forKey: "speakingRate")
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        UserDefaults.standard.set(sender.doubleValue, forKey: Self.volumeKey)
    }

    @objc private func stopClicked(_ sender: NSButton) {
        onStop?()
    }

    /// 読み上げ状態を反映する（中止ボタンの有効化、終了時のハイライト消去）
    func setSpeaking(_ speaking: Bool) {
        stopButton.isEnabled = speaking
        if !speaking {
            clearHighlight()
        }
    }

    // MARK: - Public

    /// 読み上げるテキストを表示する
    /// segments: 読み上げ単位（段落またはチャンク）
    /// paragraphBreaks: 段落の最後にあたるセグメントのインデックス
    func show(segments: [String], paragraphBreaks: Set<Int>) {
        stopTimer()

        var text = ""
        segmentRanges = []
        for (index, segment) in segments.enumerated() {
            let start = (text as NSString).length
            text += segment
            segmentRanges.append(NSRange(location: start, length: (segment as NSString).length))

            guard index < segments.count - 1 else { continue }
            if paragraphBreaks.contains(index) {
                text += "\n"
            } else if let last = segment.unicodeScalars.last, last.isASCII,
                      !CharacterSet.whitespacesAndNewlines.contains(last) {
                // 英文などで文と文がくっつかないようにスペースを補う
                text += " "
            }
        }

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        style.paragraphSpacing = 10
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style
        ])
        textView.textStorage?.setAttributedString(attributed)
        textView.scrollRangeToVisible(NSRange(location: 0, length: 0))

        if window?.isVisible != true {
            window?.orderFrontRegardless()
        }
    }

    /// 指定セグメントをハイライトする
    /// inner: セグメント内で現在読み上げ中の範囲（単語など）。nil ならセグメント全体を強調
    func highlight(segment index: Int, inner: NSRange? = nil) {
        stopTimer()
        applyHighlight(segment: index, inner: inner)
    }

    /// 指定セグメントをハイライトし、再生時間から読み上げ中の文を推定して強調する
    /// （読み上げ位置の通知がない Google TTS 用）
    func highlight(segment index: Int, estimatedDuration: TimeInterval) {
        stopTimer()
        guard segmentRanges.indices.contains(index), let storage = textView.textStorage else { return }

        let text = storage.attributedSubstring(from: segmentRanges[index]).string
        let sentences = Self.sentenceRanges(in: text)
        guard sentences.count > 1, estimatedDuration > 0 else {
            applyHighlight(segment: index, inner: nil)
            return
        }

        timedSegment = index
        timedSentences = sentences
        timedLength = (text as NSString).length
        timedDuration = estimatedDuration
        timedStart = Date()
        timedCurrent = -1
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    /// ハイライトを消す（読み上げ終了・停止時）
    func clearHighlight() {
        stopTimer()
        removeHighlight()
    }

    // MARK: - Private

    private func tick() {
        let progress = min(Date().timeIntervalSince(timedStart) / timedDuration, 1.0)
        let offset = Int(progress * Double(timedLength))
        let current = timedSentences.lastIndex(where: { $0.location <= offset }) ?? 0
        guard current != timedCurrent else { return }
        timedCurrent = current
        applyHighlight(segment: timedSegment, inner: timedSentences[current])
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func removeHighlight() {
        guard let layoutManager = textView.layoutManager, let storage = textView.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: full)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
    }

    private func applyHighlight(segment index: Int, inner: NSRange?) {
        guard let layoutManager = textView.layoutManager, segmentRanges.indices.contains(index) else { return }
        removeHighlight()

        let segment = segmentRanges[index]
        var current = segment
        if let inner = inner, inner.length > 0 {
            let range = NSRange(location: segment.location + inner.location, length: inner.length)
            if NSMaxRange(range) <= NSMaxRange(segment) {
                current = range
                layoutManager.addTemporaryAttribute(.backgroundColor, value: segmentColor, forCharacterRange: segment)
            }
        }
        layoutManager.addTemporaryAttributes(
            [.backgroundColor: currentColor, .foregroundColor: NSColor.black],
            forCharacterRange: current
        )
        textView.scrollRangeToVisible(current)
    }

    /// テキストを文単位に分割した範囲（UTF-16 単位）を返す
    private static func sentenceRanges(in text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ranges.append(NSRange(range, in: text))
            return true
        }
        return ranges
    }
}
