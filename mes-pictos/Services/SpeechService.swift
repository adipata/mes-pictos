import AVFoundation
import PictoCore

/// Speaks pictograms in French: the recorded voice when there is one, otherwise the iPad's voice.
/// Also reads whole sentences from the sentence bar, telling the caller which card is being spoken.
@MainActor
final class SpeechService {
    static let shared = SpeechService()

    /// Kept for the app's lifetime: a deallocated synthesizer stops speaking.
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private let relay = SpeechRelay()

    /// The utterance of the sequence being read. Callbacks for any other utterance are ignored.
    private var currentUtterance: AVSpeechUtterance?
    private var sequence: Sequence?

    /// Looping silence that keeps the speaker route awake while the app is in the foreground.
    /// Without it, the output powers down between taps and the first syllable of the next word is cut.
    private lazy var keepAlive: AVAudioPlayer? = {
        guard let player = try? AVAudioPlayer(data: SilentAudio.wavData(seconds: 2)) else { return nil }
        player.numberOfLoops = -1
        player.volume = 0
        player.prepareToPlay()
        return player
    }()
    /// Voice identifier the synthesizer has already been warmed up with since the app became active.
    private var prewarmedVoiceID: String?

    private struct Sequence {
        let segments: [SpeechSegment]
        var index = 0
        let onItem: (Int) -> Void
        let onEnd: (_ completed: Bool) -> Void
    }

    private init() {
        relay.service = self
        synthesizer.delegate = relay
    }

    /// `.playback` so the app speaks even when the silent switch is on. No ducking: the silent
    /// keep-alive runs all the time, ducking would lower other apps' audio permanently.
    func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
        startKeepAlive()
    }

    // MARK: Foreground and background

    /// Called when the app comes to the foreground: takes the audio session back and warms the voice up.
    func appDidBecomeActive() {
        configureSession()
        prewarmedVoiceID = nil
        prewarm()
    }

    func appDidEnterBackground() {
        stopKeepAlive()
    }

    /// The recorder is about to switch the session to recording.
    func prepareForRecording() {
        stop()
        stopKeepAlive()
    }

    private func startKeepAlive() {
        guard let keepAlive, !keepAlive.isPlaying else { return }
        keepAlive.play()
    }

    private func stopKeepAlive() {
        keepAlive?.pause()
    }

    /// Loads the voice before the first real tap: speaks a short word at volume 0.
    /// Once per foreground activation and per voice, never while something is being said.
    func prewarm() {
        guard !isSpeaking else { return }
        let voice = currentVoice()
        let voiceID = voice?.identifier ?? ""
        guard prewarmedVoiceID != voiceID else { return }
        prewarmedVoiceID = voiceID
        let utterance = AVSpeechUtterance(string: "Bonjour")
        utterance.volume = 0
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    // MARK: One card

    func speak(_ pictogram: Pictogram) {
        speak(label: pictogram.label, spokenText: pictogram.spokenText, recording: pictogram.recordingData)
    }

    func speak(label: String, spokenText: String?, recording: Data?) {
        stop()
        switch SpeechResolver.resolve(label: label, spokenText: spokenText, recording: recording) {
        case .recording(let data):
            if !play(data) {
                speakText(spokenText ?? label)
            }
        case .text(let text):
            speakText(text)
        case .none:
            break
        }
    }

    @discardableResult
    func play(_ recording: Data) -> Bool {
        stop()
        guard let player = try? AVAudioPlayer(data: recording) else { return false }
        self.player = player
        player.prepareToPlay()
        return player.play()
    }

    func speakText(_ text: String) {
        synthesizer.speak(makeUtterance(text))
    }

    // MARK: A sentence

    /// Reads several cards as one sentence. Consecutive text cards are read in one utterance, so
    /// "Je veux" + "une pomme" sounds like "Je veux une pomme". Recordings are played in between.
    /// `onItem` receives the index of the card being spoken; `onEnd` tells whether the reading
    /// finished or was interrupted by `stop()`.
    func speakSequence(_ contents: [SpeechContent], onItem: @escaping (Int) -> Void, onEnd: @escaping (Bool) -> Void) {
        stop()
        let segments = SpeechPlanner.segments(from: contents)
        guard !segments.isEmpty else {
            onEnd(true)
            return
        }
        sequence = Sequence(segments: segments, onItem: onItem, onEnd: onEnd)
        playCurrentSegment()
    }

    private func playCurrentSegment() {
        guard let current = sequence else { return }
        guard current.index < current.segments.count else {
            sequence = nil
            current.onEnd(true)
            return
        }
        switch current.segments[current.index] {
        case .utterance(let text, let pieces):
            let utterance = makeUtterance(text)
            currentUtterance = utterance
            // Highlight the first card at once; some voices report no ranges at all.
            if let first = pieces.first { current.onItem(first.index) }
            synthesizer.speak(utterance)
        case .recording(let data, let index):
            current.onItem(index)
            guard let player = try? AVAudioPlayer(data: data) else {
                advance()
                return
            }
            player.delegate = relay
            self.player = player
            player.prepareToPlay()
            if !player.play() { advance() }
        }
    }

    private func advance() {
        sequence?.index += 1
        playCurrentSegment()
    }

    /// Interrupts anything being said. A sequence in progress ends with `completed == false`.
    func stop() {
        let interrupted = sequence
        sequence = nil
        currentUtterance = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        player?.stop()
        player = nil
        interrupted?.onEnd(false)
    }

    var isSpeaking: Bool { sequence != nil || synthesizer.isSpeaking || (player?.isPlaying ?? false) }

    // MARK: Relay callbacks (main actor)

    fileprivate func willSpeak(_ range: NSRange, of utterance: AVSpeechUtterance) {
        guard utterance === currentUtterance, let current = sequence,
              current.index < current.segments.count,
              case .utterance(_, let pieces) = current.segments[current.index],
              let piece = pieces.last(where: { $0.utf16Range.lowerBound <= range.location })
        else { return }
        current.onItem(piece.index)
    }

    fileprivate func didFinish(_ utterance: AVSpeechUtterance) {
        guard utterance === currentUtterance else { return }
        currentUtterance = nil
        advance()
    }

    fileprivate func didCancel(_ utterance: AVSpeechUtterance) {
        if utterance === currentUtterance { currentUtterance = nil }
    }

    fileprivate func playerDidFinish() {
        guard sequence != nil else { return }
        player = nil
        advance()
    }

    // MARK: Voice

    private func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let defaults = UserDefaults.standard
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = currentVoice()
        utterance.rate = Float(defaults.double(forKey: SettingsKey.speechRate, default: SettingsDefault.speechRate))
        utterance.pitchMultiplier = Float(defaults.double(forKey: SettingsKey.speechPitch, default: SettingsDefault.speechPitch))
        // Small margins so the output has started before the first sound and drains after the last one.
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.15
        return utterance
    }

    func currentVoice() -> AVSpeechSynthesisVoice? {
        let identifier = UserDefaults.standard.string(forKey: SettingsKey.voiceIdentifier) ?? ""
        if !identifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        return Self.frenchVoices().first ?? AVSpeechSynthesisVoice(language: "fr-FR")
    }

    /// French voices, best first: fr-FR before other French locales, then premium, enhanced, default.
    nonisolated static func frenchVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("fr") && !$0.voiceTraits.contains(.isNoveltyVoice) }
            .sorted { a, b in
                let aFrance = a.language == "fr-FR"
                let bFrance = b.language == "fr-FR"
                if aFrance != bFrance { return aFrance }
                if a.quality.rawValue != b.quality.rawValue { return a.quality.rawValue > b.quality.rawValue }
                return a.name < b.name
            }
    }

    nonisolated static func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality {
        case .premium: return "premium"
        case .enhanced: return "améliorée"
        default: return "standard"
        }
    }
}

/// AVFoundation delegate proxy: forwards the callbacks to the service on the main actor.
/// They arrive on the main thread in practice, but this does not rely on it.
private final class SpeechRelay: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    weak var service: SpeechService?

    private func onMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            DispatchQueue.main.async(execute: body)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        onMain { self.service?.willSpeak(characterRange, of: utterance) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onMain { self.service?.didFinish(utterance) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onMain { self.service?.didCancel(utterance) }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        onMain { self.service?.playerDidFinish() }
    }
}
