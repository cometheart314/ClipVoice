import Foundation
import NaturalLanguage

class TextProcessor {

    /// テキストの言語を判別する（日本語 or 英語）
    func detectLanguage(_ text: String) -> SpeechLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        if let language = recognizer.dominantLanguage {
            switch language {
            case .japanese:
                return .japanese
            default:
                return .english
            }
        }
        return .japanese
    }

    /// テキストを段落→文単位で分割する
    /// 最初のチャンクを小さくして読み上げ開始を速くする
    /// paragraphBreaks: 段落の最後にあたるチャンクのインデックス（このチャンクの後にポーズを入れる）
    func splitText(_ text: String) -> (chunks: [String], paragraphBreaks: Set<Int>) {
        let maxBytes = 4500 // Google Cloud TTS の制限（5000バイト）に余裕を持たせる

        // まず段落で分割し、各段落を文単位で分割
        let paragraphs = splitIntoParagraphs(text)

        guard !paragraphs.isEmpty else { return ([text], []) }

        // 文をチャンクにまとめる
        // 最初のチャンクは短めに（50〜100文字程度）して読み上げ開始を速くする
        // ただし短すぎると再生が一瞬で終わり次のチャンクの取得が間に合わない
        // 段落の境界ではチャンクを区切り、読み上げ時に自然な間を作る
        let firstChunkMinChars = 50
        var chunks: [String] = []
        var paragraphBreaks: Set<Int> = []
        var currentChunk = ""
        var isFirstChunk = true

        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            // 段落が変わったら現在のチャンクを確定する
            if !currentChunk.isEmpty {
                chunks.append(currentChunk)
                // 前の段落の末尾なので段落区切りとしてマーク
                if paragraphIndex > 0 {
                    paragraphBreaks.insert(chunks.count - 1)
                }
                currentChunk = ""
                isFirstChunk = false
            }

            let sentences = splitIntoSentences(paragraph)

            for sentence in sentences {
                let combined = currentChunk.isEmpty ? sentence : currentChunk + sentence

                if combined.utf8.count > maxBytes {
                    if !currentChunk.isEmpty {
                        chunks.append(currentChunk)
                        currentChunk = ""
                        isFirstChunk = false
                    }
                    if sentence.utf8.count > maxBytes {
                        chunks.append(contentsOf: splitByBytes(sentence, maxBytes: maxBytes))
                        isFirstChunk = false
                    } else {
                        currentChunk = sentence
                    }
                } else if isFirstChunk && combined.count >= firstChunkMinChars {
                    // 最初のチャンクが十分な長さに達したら区切る
                    chunks.append(combined)
                    currentChunk = ""
                    isFirstChunk = false
                } else {
                    currentChunk = combined
                }
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return (chunks, paragraphBreaks)
    }

    /// テキストを段落のみで分割する（Apple TTS 用、バイト制限チャンキングなし）
    func splitIntoParagraphsOnly(_ text: String) -> (chunks: [String], paragraphBreaks: Set<Int>) {
        let paragraphs = splitIntoParagraphs(text)
        guard paragraphs.count > 1 else { return (paragraphs, []) }
        // 最後の段落以外すべてを段落区切りとしてマーク
        let breaks = Set(0..<(paragraphs.count - 1))
        return (paragraphs, breaks)
    }

    /// テキストを段落で分割する（空行で区切る）
    private func splitIntoParagraphs(_ text: String) -> [String] {
        let paragraphs = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return paragraphs.isEmpty ? [text] : paragraphs
    }

    /// テキストを文単位で分割する
    private func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]))
            return true
        }
        return sentences.isEmpty ? [text] : sentences
    }

    /// バイト制限に収まるよう文字列を強制分割
    private func splitByBytes(_ text: String, maxBytes: Int) -> [String] {
        var chunks: [String] = []
        var current = ""

        for char in text {
            let next = current + String(char)
            if next.utf8.count > maxBytes {
                chunks.append(current)
                current = String(char)
            } else {
                current = next
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }
}
