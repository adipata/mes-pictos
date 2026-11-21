import AVFoundation
import PictoCore

/// Speaks pictograms in French: the recorded voice when there is one, otherwise the iPad's voice.
/// Also reads whole sentences from the sentence bar, telling the caller which card is being spoken.
@MainActor
final class SpeechService {
    static let shared = SpeechService()

    /// Kept for the app's lifetime: a deallocated synthesizer stops speaking.
    private let synthesizer = AVSpeechSynthesizer()
    /// Audio session and recordings, handled off the main thread.
    private let audio = AudioOutput()
    private let relay = SpeechRelay()
    /// Bumped by `stop()`: callbacks from a recording started before it are ignored.
    private var playbackID = 0
    private var isPlayingRecording = false

    /// The utterance of the sequence being read. Callbacks for any other utterance are ignored.
    private var currentUtterance: AVSpeechUtterance?
    private var sequence: Sequence?

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

    /// Sets the session up for speaking and starts the silent keep-alive. Returns at once:
    /// the session work runs on the audio queue (see `AudioOutput`).
    func configureSession() {
        audio.configureForPlayback()
    }

    // MARK: Foreground and background

    /// Called when the app comes to the foreground: takes the audio session back and warms the voice up.
    func appDidBecomeActive() {
        configureSession()
        prewarmedVoiceID = nil
        prewarm()
    }

    func appDidEnterBackground() {
        audio.stopKeepAlive()
    }

    /// Stops speaking and switches the session to recording. Returns once the session is ready.
    func prepareForRecording() async throws {
        stop()
        try await audio.configureForRecording()
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
            play(data) { [weak self] in
                self?.speakText(spokenText ?? label)
            }
        case .text(let text):
            speakText(text)
        case .none:
            break
        }
    }

    /// Plays a recording. `onFailed` runs if it cannot be played, unless `stop()` was called since.
    func play(_ recording: Data, onFailed: (@MainActor @Sendable () -> Void)? = nil) {
        stop()
        startRecording(recording, onFailed: { onFailed?() }, onFinished: {})
    }

    /// Starts a recording on the audio queue. The callbacks run only if nothing stopped it meanwhile.
    private func startRecording(
        _ data: Data,
        onFailed: @escaping @MainActor @Sendable () -> Void,
        onFinished: @escaping @MainActor @Sendable () -> Void
    ) {
        let id = playbackID
        isPlayingRecording = true
        audio.play(
            data,
            onFailed: { [weak self] in
                guard let self, self.playbackID == id else { return }
                self.isPlayingRecording = false
                onFailed()
            },
            onFinished: { [weak self] in
                guard let self, self.playbackID == id else { return }
                self.isPlayingRecording = false
                onFinished()
            }
        )
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
            startRecording(data, onFailed: { [weak self] in self?.advance() },
                           onFinished: { [weak self] in self?.advance() })
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
        playbackID &+= 1
        isPlayingRecording = false
        audio.stopPlayback()
        interrupted?.onEnd(false)
    }

    var isSpeaking: Bool { sequence != nil || synthesizer.isSpeaking || isPlayingRecording }

    // MARK: Relay callbacks (main actor)

    /// Utterances are not Sendable, so the relay hands over only their identity. That is enough:
    /// `currentUtterance` keeps its utterance alive, so its identifier cannot be reused meanwhile.
    private func isCurrent(_ utterance: ObjectIdentifier) -> Bool {
        currentUtterance.map(ObjectIdentifier.init) == utterance
    }

    fileprivate func willSpeak(_ range: NSRange, of utterance: ObjectIdentifier) {
        guard isCurrent(utterance), let current = sequence,
              current.index < current.segments.count,
              case .utterance(_, let pieces) = current.segments[current.index],
              let piece = pieces.last(where: { $0.utf16Range.lowerBound <= range.location })
        else { return }
        current.onItem(piece.index)
    }

    fileprivate func didFinish(_ utterance: ObjectIdentifier) {
        guard isCurrent(utterance) else { return }
        currentUtterance = nil
        advance()
    }

    fileprivate func didCancel(_ utterance: ObjectIdentifier) {
        if isCurrent(utterance) { currentUtterance = nil }
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

/// Synthesizer delegate proxy: forwards the callbacks to the service on the main actor.
/// They arrive on the main thread in practice, but this does not rely on it.
private final class SpeechRelay: NSObject, AVSpeechSynthesizerDelegate {
    weak var service: SpeechService?

    private func onMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            DispatchQueue.main.async(execute: body)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        onMain { self.service?.willSpeak(characterRange, of: id) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        onMain { self.service?.didFinish(id) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        onMain { self.service?.didCancel(id) }
    }
}
