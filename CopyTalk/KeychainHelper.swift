import Foundation

struct KeychainHelper {

    private static let userDefaultsKey = "googleCloudTTSAPIKey"

    /// API キーを保存する
    @discardableResult
    static func saveAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        } else {
            UserDefaults.standard.set(trimmed, forKey: userDefaultsKey)
        }
        return true
    }

    /// API キーを取得する
    static func getAPIKey() -> String? {
        guard let key = UserDefaults.standard.string(forKey: userDefaultsKey),
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return key
    }

    /// API キーを削除する
    @discardableResult
    static func deleteAPIKey() -> Bool {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        return true
    }
}
