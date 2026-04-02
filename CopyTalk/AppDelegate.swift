import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusBarController: StatusBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()

        // サービスメニューのプロバイダーを登録
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
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
