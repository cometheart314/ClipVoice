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
    func splitText(_ text: String, model: TTSModel = .neural2) -> (chunks: [String], paragraphBreaks: Set<Int>) {
        // Chirp 3: HD はセンテンス長制限が厳しい → 1文=1チャンクで送る
        if model == .chirp3HD {
            return splitTextForChirp3HD(text)
        }

        let maxBytes = 4500

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

    /// Chirp 3: HD 用のテキスト分割（1文=1チャンク、長い文は句読点で分割）
    /// 分割された断片には句点を付与してセンテンス終端を明示する
    private func splitTextForChirp3HD(_ text: String) -> (chunks: [String], paragraphBreaks: Set<Int>) {
        let paragraphs = splitIntoParagraphs(text)
        guard !paragraphs.isEmpty else { return ([text], []) }

        var chunks: [String] = []
        var paragraphBreaks: Set<Int> = []

        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            let startIndex = chunks.count
            let sentences = splitIntoSentences(paragraph)

            for sentence in sentences {
                let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                chunks.append(trimmed)
            }

            // 段落の最後のチャンクをマーク
            if paragraphIndex < paragraphs.count - 1 && chunks.count > startIndex {
                paragraphBreaks.insert(chunks.count - 1)
            }
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

    /// URL文字列を「URL」に置換する
    private func replaceURLs(_ text: String) -> String {
        let urlPattern = #"https?://[^\s\p{Zs}、。！？）」』】〉》"']+"#
        return text.replacingOccurrences(
            of: urlPattern,
            with: " URL ",
            options: .regularExpression
        )
    }

    /// 記号が連続している部分を除去する（装飾線や区切り線など）
    /// 同じ記号が3回以上連続、または記号のみで構成された部分を除去
    private func removeSymbolRuns(_ text: String) -> String {
        var result = text
        // 同じ記号が3回以上連続するパターンを除去（例: ===, ---, ***, ・・・, ■■■, ━━━）
        result = result.replacingOccurrences(
            of: #"(.)\1{2,}"#,
            with: "",
            options: .regularExpression
        )
        // 異なる記号が3文字以上連続するパターンを除去（例: ◆◇◆, =-=, ★☆★）
        // ただし通常の句読点（。、！？…）の組み合わせは除外
        let symbolPattern = #"[^\p{L}\p{N}\p{Zs}\n。、！？!?,，.．:：;；()（）「」『』\[\]【】〈〉《》""''…]{3,}"#
        result = result.replacingOccurrences(
            of: symbolPattern,
            with: "",
            options: .regularExpression
        )
        return result
    }

    /// テキストを段落で分割する（空行で区切る）
    private func splitIntoParagraphs(_ text: String) -> [String] {
        let cleaned = removeSymbolRuns(replaceURLs(text))
        let paragraphs = cleaned.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return paragraphs.isEmpty ? [cleaned] : paragraphs
    }

    /// テキストを文単位で分割する
    /// NLTokenizer で分割後、長すぎる文は句読点で追加分割する
    private func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]))
            return true
        }
        if sentences.isEmpty { sentences = [text] }

        // 長すぎる文を句読点・読点で追加分割（Chirp 3: HD のセンテンス制限対策）
        let maxSentenceChars = 60
        var result: [String] = []
        for sentence in sentences {
            if sentence.count <= maxSentenceChars {
                result.append(sentence)
            } else {
                result.append(contentsOf: splitLongSentence(sentence, maxChars: maxSentenceChars))
            }
        }
        return result
    }

    /// 長い文を句読点・読点・カンマ等で分割する
    private func splitLongSentence(_ text: String, maxChars: Int) -> [String] {
        // 分割ポイント: 読点、カンマ、セミコロン、括弧閉じ等
        let delimiters: [Character] = ["、", "，", ",", ";", "；", "：", ":", "）", ")", "」", "】"]
        var chunks: [String] = []
        var current = ""

        for char in text {
            current.append(char)
            if current.count >= 20 && delimiters.contains(char) {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            // 残りが短すぎる場合（句点のみ等）は前のチャンクに結合
            if current.count <= 5 && !chunks.isEmpty {
                chunks[chunks.count - 1].append(current)
            } else {
                chunks.append(current)
            }
        }

        // まだ長すぎる断片を強制分割
        var result: [String] = []
        for chunk in chunks {
            if chunk.count > maxChars {
                result.append(contentsOf: splitByCharCount(chunk, maxChars: maxChars))
            } else {
                result.append(chunk)
            }
        }

        return mergeShortTail(result)
    }

    /// 文字数で強制分割
    private func splitByCharCount(_ text: String, maxChars: Int) -> [String] {
        var chunks: [String] = []
        var current = ""
        for char in text {
            current.append(char)
            if current.count >= maxChars {
                chunks.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return mergeShortTail(chunks)
    }

    /// 末尾の短い断片（5文字以下）を前のチャンクに結合する
    /// 「。」だけが独立チャンクになるのを防止
    private func mergeShortTail(_ chunks: [String]) -> [String] {
        guard chunks.count >= 2 else { return chunks }
        var result = chunks
        if let last = result.last, last.count <= 5 {
            result.removeLast()
            result[result.count - 1].append(last)
        }
        return result
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
