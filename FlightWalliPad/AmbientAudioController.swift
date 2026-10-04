import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AmbientAudioController {
    private var player: AVAudioPlayer?
    private var muted = true
    private var shouldPlay = false

    init() {
        player = try? AVAudioPlayer(data: Self.makeRainWave())
        player?.numberOfLoops = -1
        player?.volume = 0.055
        player?.prepareToPlay()
    }

    func update(condition: String) {
        let value = condition.uppercased()
        shouldPlay = value.contains("RA") || value.contains("SH") || value.contains("TS") || value.contains("DZ")
        applyState()
    }

    func setMuted(_ value: Bool) {
        muted = value
        applyState()
    }

    private func applyState() {
        if shouldPlay && !muted {
            player?.play()
        } else {
            player?.pause()
        }
    }

    private static func makeRainWave() -> Data {
        let sampleRate = 22_050
        let seconds = 5
        let sampleCount = sampleRate * seconds
        var samples = Data(capacity: sampleCount * 2)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        var smoothed = 0.0
        for _ in 0..<sampleCount {
            seed = seed &* 2862933555777941757 &+ 3037000493
            let noise = Double(Int32(truncatingIfNeeded: seed >> 32)) / Double(Int32.max)
            smoothed = smoothed * 0.82 + noise * 0.18
            var sample = Int16(max(-1, min(1, smoothed)) * 4_500).littleEndian
            withUnsafeBytes(of: &sample) { samples.append(contentsOf: $0) }
        }

        var result = Data()
        func append(_ string: String) { result.append(contentsOf: string.utf8) }
        func append16(_ value: UInt16) { var v = value.littleEndian; withUnsafeBytes(of: &v) { result.append(contentsOf: $0) } }
        func append32(_ value: UInt32) { var v = value.littleEndian; withUnsafeBytes(of: &v) { result.append(contentsOf: $0) } }
        append("RIFF"); append32(UInt32(36 + samples.count)); append("WAVEfmt ")
        append32(16); append16(1); append16(1); append32(UInt32(sampleRate)); append32(UInt32(sampleRate * 2)); append16(2); append16(16)
        append("data"); append32(UInt32(samples.count)); result.append(samples)
        return result
    }
}
