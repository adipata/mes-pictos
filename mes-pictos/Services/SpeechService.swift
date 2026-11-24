import AVFoundation
import UIKit
import PictoCore

/// Speaks pictograms in French: the recorded voice when there is one, otherwise the iPad's voice.
/// Also reads whole sentences from the sentence bar, telling the caller which card is being spoken.
@MainActor
final class SpeechService {
    static let shared = SpeechService()

    /// Kept until it is replaced by `resetSynthesizer`: a deallocated synthesizer stops speaking.
    private var synthesizer = AVSpeechSynthesizer()
    /// Audio session and recordings, handled off the main thread.
    private let audio: AudioOutput
    private let relay = SpeechRelay()
    /// Bumped by `stop()`: callbacks from a recording started before it are ignored.
    private var playbackID = 0
    private var isPlayingRecording = false

    /// The utterance of the sequence being read. Callbacks for any other utterance are ignored.
    private var currentUtterance: AVSpeechUtterance?
    private var sequence: Sequence?

    /// Voice identifier the synthesizer has already been warmed up with since the app became active.
    private var prewarmedVoiceID: String?

    // Start watchdog. A synthesizer can get stuck: it accepts utterances but never starts any of them,
    // and only a new synthesizer speaks again. If nothing has started this long after an utterance
    // was handed over, the synthesizer is replaced and the last utterance is spoken once more.
    private static let startTimeout: TimeInterval = 3
    /// When the oldest utterance still waiting for `didStart` was handed over. Cleared by any start.
    private var awaitingStartSince: Date?
    /// The last utterance handed to the synthesizer, until it finishes or is cancelled.
    private var lastUtterance: AVSpeechUtterance?
    private var lastUtteranceIsRetry = false
    private var watchdog: Task<Void, Never>?

    private struct Sequence {
        let segments: [SpeechSegment]
        var index = 0
        let onItem: (Int) -> Void
        let onEnd: (_ completed: Bool) -> Void
    }

    private init() {
        audio = AudioOutput(onMediaServicesReset: { SpeechService.shared.mediaServicesWereReset() })
        relay.service = self
        synthesizer.delegate = relay
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        AudioLog.log("=== launch: app \(version) (\(build)), \(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)")
    }

    /// Sets the session up for speaking and starts the silent keep-alive. Returns at once:
    /// the session work runs on the audio queue (see `AudioOutput`).
    func configureSession(reason: String = "configure") {
        audio.configureForPlayback(reason: reason)
    }

    // MARK: Foreground and background

    /// Called when the app comes to the foreground: takes the audio session back and warms the voice up.
    func appDidBecomeActive() {
        configureSession(reason: "app active")
        prewarmedVoiceID = nil
        prewarm()
    }

    func appDidEnterBackground() {
        audio.enterBackground()
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
        send(utterance, note: "prewarm")
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
        send(makeUtterance(text), note: "text")
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
            send(utterance, note: "sentence \(current.index + 1)/\(current.segments.count)")
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
        lastUtterance = nil
        // Not guarded by `isSpeaking`: a paused synthesizer may not report itself as speaking, and
        // utterances queued behind a paused one would never be heard. Stopping an idle one is harmless.
        synthesizer.stopSpeaking(at: .immediate)
        playbackID &+= 1
        isPlayingRecording = false
        audio.stopPlayback()
        interrupted?.onEnd(false)
    }

    var isSpeaking: Bool { sequence != nil || synthesizer.isSpeaking || isPlayingRecording }

    // MARK: Handing utterances to the synthesizer

    /// Every utterance goes through here, so it is logged and covered by the start watchdog.
    private func send(_ utterance: AVSpeechUtterance, note: String, isRetry: Bool = false) {
        if let since = awaitingStartSince, Date().timeIntervalSince(since) > Self.startTimeout {
            resetSynthesizer(reason: String(format: "nothing started for %.1f s", Date().timeIntervalSince(since)))
        }
        if synthesizer.isPaused {
            AudioLog.log("speech: synthesizer was PAUSED, stopping it before speaking")
            synthesizer.stopSpeaking(at: .immediate)
        }
        AudioLog.log("speech: speak [\(note)\(isRetry ? ", retry" : "")] \"\(utterance.speechString)\""
            + " voice=\(utterance.voice?.identifier ?? "default") volume=\(utterance.volume)"
            + " synthSpeaking=\(synthesizer.isSpeaking)")
        // Queued behind speech that did start: it may legitimately wait longer than the timeout.
        let queuedBehindSpeech = synthesizer.isSpeaking && awaitingStartSince == nil
        lastUtterance = utterance
        lastUtteranceIsRetry = isRetry
        synthesizer.speak(utterance)
        guard !queuedBehindSpeech else { return }
        if awaitingStartSince == nil { awaitingStartSince = Date() }
        armWatchdog()
    }

    private func armWatchdog() {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.startTimeout))
            guard !Task.isCancelled else { return }
            self?.watchdogFired()
        }
    }

    private func watchdogFired() {
        guard let since = awaitingStartSince else { return }
        let waited = Date().timeIntervalSince(since)
        guard waited >= Self.startTimeout - 0.1 else { return }
        audio.logState("speech: WATCHDOG nothing started for \(String(format: "%.1f", waited)) s")
        let stuck = lastUtterance
        let wasRetry = lastUtteranceIsRetry
        resetSynthesizer(reason: "watchdog")
        // Say the last word again on the new synthesizer, once.
        guard let stuck, !wasRetry, let copy = stuck.copy() as? AVSpeechUtterance else {
            // Giving up on this utterance: end a sentence in progress so its highlight goes away.
            if sequence != nil { stop() }
            return
        }
        if let currentUtterance, currentUtterance === stuck {
            self.currentUtterance = copy
        }
        send(copy, note: "after watchdog", isRetry: true)
    }

    /// Replaces the synthesizer with a new one and takes the audio session back.
    private func resetSynthesizer(reason: String) {
        AudioLog.log("speech: REPLACING synthesizer (\(reason)); old one speaking=\(synthesizer.isSpeaking) paused=\(synthesizer.isPaused)")
        let old = synthesizer
        old.delegate = nil
        old.stopSpeaking(at: .immediate)
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = relay
        awaitingStartSince = nil
        lastUtterance = nil
        watchdog?.cancel()
        watchdog = nil
        prewarmedVoiceID = nil
        configureSession(reason: "synthesizer replaced")
    }

    /// The system reset its media services: every audio object, the synthesizer included, is dead.
    fileprivate func mediaServicesWereReset() {
        stop()
        resetSynthesizer(reason: "media services reset")
    }

    /// Manual recovery from Settings: what a restart of the app would do for the voice.
    func resetAudio() {
        AudioLog.log("speech: manual audio reset from Settings")
        stop()
        resetSynthesizer(reason: "manual")
        prewarm()
    }

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

    fileprivate func didStart(_ utterance: ObjectIdentifier, text: String) {
        if let since = awaitingStartSince {
            AudioLog.log("speech: didStart \"\(text)\" after \(String(format: "%.2f", Date().timeIntervalSince(since))) s")
        } else {
            AudioLog.log("speech: didStart \"\(text)\"")
        }
        awaitingStartSince = nil
        watchdog?.cancel()
        watchdog = nil
    }

    fileprivate func didPause(_ utterance: ObjectIdentifier, text: String) {
        AudioLog.log("speech: didPause \"\(text)\"")
    }

    fileprivate func didContinue(_ utterance: ObjectIdentifier, text: String) {
        AudioLog.log("speech: didContinue \"\(text)\"")
    }

    fileprivate func didFinish(_ utterance: ObjectIdentifier, text: String) {
        AudioLog.log("speech: didFinish \"\(text)\"")
        if lastUtterance.map(ObjectIdentifier.init) == utterance { lastUtterance = nil }
        guard isCurrent(utterance) else { return }
        currentUtterance = nil
        advance()
    }

    fileprivate func didCancel(_ utterance: ObjectIdentifier, text: String) {
        AudioLog.log("speech: didCancel \"\(text)\"")
        if lastUtterance.map(ObjectIdentifier.init) == utterance { lastUtterance = nil }
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

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let text = utterance.speechString
        onMain { self.service?.didStart(id, text: text) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let text = utterance.speechString
        onMain { self.service?.didPause(id, text: text) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let text = utterance.speechString
        onMain { self.service?.didContinue(id, text: text) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let text = utterance.speechString
        onMain { self.service?.didFinish(id, text: text) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        let text = utterance.speechString
        onMain { self.service?.didCancel(id, text: text) }
    }
}
