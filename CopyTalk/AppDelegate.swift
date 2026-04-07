import Cocoa

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 出荷初期のデフォルト値を登録（未設定のキーにのみ適用される）
        UserDefaults.standard.register(defaults: [
            "doubleCopySpeak": true,
            "showInDock": true
        ])

        // Dock アイコン表示設定を反映
        let showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)

        statusBarController = StatusBarController()

        // サービスメニューのプロバイダーを登録
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        // 初回起動時のみダイアログと設定パネルを表示
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            showFirstLaunchAlert()
        }
    }

    private func showFirstLaunchAlert() {
        let alert = NSAlert()
        alert.messageText = "Welcome to ClipVoice!".localized
        alert.informativeText = "ClipVoice is ready in the menu bar with a speaker icon. Press ⌘C twice quickly to read selected text aloud.".localized
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings".localized)
        alert.runModal()

        PreferencesWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        return statusBarController.menu
    }

    @objc func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showPreferences() {
        PreferencesWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}

// MARK: - Services Menu

extension AppDelegate {
    /// サービスメニューから呼ばれるテキスト読み上げハンドラ
    @objc func readText(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "No text provided" as NSString
            return
        }
        statusBarController.speakText(text)
    }
}
