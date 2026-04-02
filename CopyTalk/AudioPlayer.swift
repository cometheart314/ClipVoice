import AVFoundation

class AudioPlayer {

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let sampleRate: Double = 24000
    private let channels: AVAudioChannelCount = 1

    init() {
        engine.attach(playerNode)
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: channels, interleaved: true)!
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    }

    /// エンジンを起動し、短い無音を再生してオーディオパイプラインを暖める
    func warmUp() async {
        ensureEngineRunning()
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: channels, interleaved: true)!
        // 極短い無音（0.05秒）でパイプラインをプライミング
        let frameCount = AVAudioFrameCount(sampleRate * 0.05)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            playerNode.scheduleBuffer(buffer) {
                continuation.resume()
            }
            playerNode.play()
        }
    }

    /// 音声データ（Linear16 PCM）を再生し、再生完了まで待機する
    func playAndWait(data: Data) async {
        guard let buffer = pcmBuffer(from: data) else { return }
        ensureEngineRunning()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            playerNode.scheduleBuffer(buffer) {
                continuation.resume()
            }
            playerNode.play()
        }
    }

    /// 指定した秒数の無音を再生し、完了まで待機する
    func playSilence(duration: Double) async {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: channels, interleaved: true)!
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        ensureEngineRunning()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            playerNode.scheduleBuffer(buffer) {
                continuation.resume()
            }
            playerNode.play()
        }
    }

    private func ensureEngineRunning() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            print("AudioEngine start error: \(error)")
        }
    }

    /// 再生を停止する
    func stop() {
        playerNode.stop()
        if engine.isRunning {
            engine.stop()
        }
    }

    /// Linear16 PCM データを AVAudioPCMBuffer に変換する
    private func pcmBuffer(from data: Data) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: channels, interleaved: true)!
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)

        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        data.withUnsafeBytes { rawBuffer in
            if let src = rawBuffer.baseAddress {
                buffer.int16ChannelData?[0].update(from: src.assumingMemoryBound(to: Int16.self), count: Int(frameCount))
            }
        }

        return buffer
    }
}
