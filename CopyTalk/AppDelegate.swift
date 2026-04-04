import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock アイコン表示設定を反映
        let showInDock = UserDefaults.standard.bool(forKey: "showInDock")
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)

        statusBarController = StatusBarController()

        // サービスメニューのプロバイダーを登録
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
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
