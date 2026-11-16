import Foundation

/// A few seconds of silence as a WAV file, played in a loop to keep the audio output awake while the
/// app is in the foreground. Otherwise the speaker route powers down between taps and the first
/// syllable of the next word is lost while it starts again.
public enum SilentAudio {
    public static let headerSize = 44

    /// 16-bit mono PCM silence with a standard RIFF/WAVE header.
    public static func wavData(seconds: Double = 1, sampleRate: Int = 44_100) -> Data {
        let sampleCount = max(1, Int(Double(sampleRate) * seconds))
        let dataSize = sampleCount * 2
        var data = Data(capacity: headerSize + dataSize)

        func append(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func append32(_ value: Int) {
            var little = UInt32(value).littleEndian
            data.append(Data(bytes: &little, count: 4))
        }
        func append16(_ value: Int) {
            var little = UInt16(value).littleEndian
            data.append(Data(bytes: &little, count: 2))
        }

        append("RIFF")
        append32(36 + dataSize)
        append("WAVE")
        append("fmt ")
        append32(16)            // PCM chunk size
        append16(1)             // PCM format
        append16(1)             // mono
        append32(sampleRate)
        append32(sampleRate * 2) // byte rate
        append16(2)             // block align
        append16(16)            // bits per sample
        append("data")
        append32(dataSize)
        data.append(Data(count: dataSize))
        return data
    }
}
