import Foundation

/// 言語設定
enum SpeechLanguage: String {
    case japanese = "ja-JP"
    case english = "en-US"
}

/// 音声の種類
struct VoiceOption {
    let name: String        // API に送る名前 (例: "ja-JP-Neural2-B")
    let displayName: String // UI に表示する名前
    let language: SpeechLanguage

    static let allVoices: [VoiceOption] = [
        // Japanese - Neural2
        VoiceOption(name: "ja-JP-Neural2-B", displayName: "Japanese B (Female)", language: .japanese),
        VoiceOption(name: "ja-JP-Neural2-C", displayName: "Japanese C (Male)",   language: .japanese),
        VoiceOption(name: "ja-JP-Neural2-D", displayName: "Japanese D (Male)",   language: .japanese),
        // English - Neural2
        VoiceOption(name: "en-US-Neural2-C", displayName: "English C (Female)",  language: .english),
        VoiceOption(name: "en-US-Neural2-D", displayName: "English D (Male)",    language: .english),
        VoiceOption(name: "en-US-Neural2-F", displayName: "English F (Female)",  language: .english),
        VoiceOption(name: "en-US-Neural2-J", displayName: "English J (Male)",    language: .english),
    ]

    /// 指定の言語に合う音声を返す
    static func voices(for language: SpeechLanguage) -> [VoiceOption] {
        allVoices.filter { $0.language == language }
    }
}

class TTSService {

    private let session = URLSession.shared
    private let endpoint = "https://texttospeech.googleapis.com/v1/text:synthesize"

    /// テキストを音声合成して音声データ（Linear16 PCM）を返す
    func synthesize(text: String, language: SpeechLanguage) async throws -> Data {
        guard let apiKey = KeychainHelper.getAPIKey() else {
            throw TTSError.noAPIKey
        }

        let speakingRate = UserDefaults.standard.double(forKey: "speakingRate")
        let rate = speakingRate > 0 ? speakingRate : 1.0

        let voiceName = voiceName(for: language)

        let requestBody: [String: Any] = [
            "input": ["text": text],
            "voice": [
                "languageCode": language.rawValue,
                "name": voiceName
            ],
            "audioConfig": [
                "audioEncoding": "LINEAR16",
                "speakingRate": rate,
                "sampleRateHertz": 24000
            ]
        ]

        guard let url = URL(string: "\(endpoint)?key=\(apiKey)") else {
            throw TTSError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TTSError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TTSError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let audioContent = json["audioContent"] as? String,
              let audioData = Data(base64Encoded: audioContent) else {
            throw TTSError.invalidAudioData
        }

        return audioData
    }

    /// 言語に応じた音声名を返す（設定から取得）
    private func voiceName(for language: SpeechLanguage) -> String {
        let key: String
        switch language {
        case .japanese: key = "japaneseVoice"
        case .english:  key = "englishVoice"
        }

        if let saved = UserDefaults.standard.string(forKey: key) {
            let voices = VoiceOption.voices(for: language)
            if voices.contains(where: { $0.name == saved }) {
                return saved
            }
        }

        return VoiceOption.voices(for: language).first?.name ?? "ja-JP-Neural2-B"
    }
}

// MARK: - Errors

enum TTSError: LocalizedError {
    case noAPIKey
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)
    case invalidAudioData

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "API key is not configured."
        case .invalidURL:
            return "Invalid API URL."
        case .invalidResponse:
            return "Invalid response from server."
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        case .invalidAudioData:
            return "Failed to decode audio data."
        }
    }
}
