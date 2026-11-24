import AVFoundation
import PictoCore

/// Owns the audio session and the audio players, and does all their work on one serial queue.
///
/// Activating the session, changing its category and preparing a player can block for a while
/// (the system may have to wake the audio hardware), so none of it runs on the main thread.
/// Every call returns at once; the work runs in the order the calls were made, so a `stopPlayback()`
/// always lands before the `play` that follows it. Results come back on the main actor.
///
/// It also watches the session: after an interruption (Siri, a call, an alarm, another app) the
/// session is taken back, and after the system resets its media services the players are rebuilt
/// and the speech service is told to rebuild its synthesizer. Everything is written to `AudioLog`.
nonisolated final class AudioOutput: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    typealias Callback = @MainActor @Sendable () -> Void

    private enum Mode: String {
        case playback, recording, background
    }

    private let queue = DispatchQueue(label: "mespictos.audio-output", qos: .userInitiated)
    private let onMediaServicesReset: Callback

    // Everything below is only touched on `queue`.

    private var mode = Mode.playback
    /// Looping silence that keeps the speaker route awake while the app is in the foreground.
    /// Without it, the output powers down between taps and the first syllable of the next word is cut.
    private var keepAlive: AVAudioPlayer?
    private var player: AVAudioPlayer?
    private var onPlayerFinished: Callback?
    /// Session notification observers, kept for the app's lifetime.
    private var observers: [NSObjectProtocol] = []

    /// `onMediaServicesReset` runs on the main actor once the session and players were rebuilt.
    init(onMediaServicesReset: @escaping Callback) {
        self.onMediaServicesReset = onMediaServicesReset
        super.init()
        observeSession()
    }

    // MARK: Session

    /// `.playback` so the app speaks even when the silent switch is on. No ducking: the silent
    /// keep-alive runs all the time, ducking would lower other apps' audio permanently.
    func configureForPlayback(reason: String) {
        queue.async {
            self.mode = .playback
            self.activatePlaybackOnQueue(reason: reason)
        }
    }

    private func activatePlaybackOnQueue(reason: String) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
        } catch {
            AudioLog.log("session: setCategory(playback) FAILED (\(reason)): \(Self.describeError(error))")
        }
        do {
            try session.setActive(true)
        } catch {
            AudioLog.log("session: setActive(true) FAILED (\(reason)): \(Self.describeError(error))")
        }
        startKeepAliveOnQueue()
        AudioLog.log("session: playback activated (\(reason)) | \(stateOnQueue())")
    }

    /// Stops any playback and switches the session to recording. Returns once the session is ready.
    func configureForRecording() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.mode = .recording
                self.stopPlaybackOnQueue()
                self.keepAlive?.pause()
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                    try session.setActive(true)
                    AudioLog.log("session: recording activated | \(self.stateOnQueue())")
                    continuation.resume()
                } catch {
                    AudioLog.log("session: recording activation FAILED: \(Self.describeError(error))")
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Writes the current session state to the journal, after any work already queued.
    func logState(_ reason: String) {
        queue.async { AudioLog.log("\(reason) | \(self.stateOnQueue())") }
    }

    // MARK: Keep-alive

    /// The app went to the background: stops the silent keep-alive.
    func enterBackground() {
        queue.async {
            self.mode = .background
            self.keepAlive?.pause()
            AudioLog.log("session: keep-alive paused (background)")
        }
    }

    private func startKeepAliveOnQueue() {
        if keepAlive == nil {
            do {
                let silence = try AVAudioPlayer(data: SilentAudio.wavData(seconds: 2))
                silence.numberOfLoops = -1
                silence.volume = 0
                silence.prepareToPlay()
                keepAlive = silence
            } catch {
                AudioLog.log("keep-alive: could not be created: \(Self.describeError(error))")
            }
        }
        guard let keepAlive, !keepAlive.isPlaying else { return }
        if !keepAlive.play() {
            AudioLog.log("keep-alive: play() returned false")
        }
    }

    // MARK: Recordings

    /// Plays a recording, replacing the one playing. `onFailed` runs if it cannot be decoded or
    /// started, `onFinished` when it reaches its end. Neither runs once `stopPlayback()` stopped it.
    func play(_ data: Data, onFailed: @escaping Callback, onFinished: @escaping Callback) {
        queue.async {
            self.stopPlaybackOnQueue()
            let player: AVAudioPlayer
            do {
                player = try AVAudioPlayer(data: data)
            } catch {
                AudioLog.log("recording: could not be decoded (\(data.count) bytes): \(Self.describeError(error))")
                Self.onMain(onFailed)
                return
            }
            player.delegate = self
            self.player = player
            self.onPlayerFinished = onFinished
            player.prepareToPlay()
            if player.play() {
                AudioLog.log("recording: playing \(String(format: "%.1f", player.duration)) s | \(self.stateOnQueue())")
            } else {
                AudioLog.log("recording: play() returned false, falling back | \(self.stateOnQueue())")
                self.stopPlaybackOnQueue()
                Self.onMain(onFailed)
            }
        }
    }

    func stopPlayback() {
        queue.async { self.stopPlaybackOnQueue() }
    }

    private func stopPlaybackOnQueue() {
        player?.delegate = nil
        player?.stop()
        player = nil
        onPlayerFinished = nil
    }

    func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        // Players are not Sendable: only their identity crosses to the queue.
        let finishedID = ObjectIdentifier(finished)
        queue.async {
            // A player that was stopped or replaced in the meantime reports nothing.
            guard let player = self.player, ObjectIdentifier(player) == finishedID,
                  let callback = self.onPlayerFinished else { return }
            AudioLog.log("recording: finished (successfully: \(flag))")
            self.player = nil
            self.onPlayerFinished = nil
            Self.onMain(callback)
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ failed: AVAudioPlayer, error: Error?) {
        let message = error.map(Self.describeError) ?? "no error"
        AudioLog.log("recording: decode error: \(message)")
    }

    // MARK: Session notifications

    private func observeSession() {
        let center = NotificationCenter.default

        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { note in
            let info = note.userInfo ?? [:]
            let type = info[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let reason = info[AVAudioSessionInterruptionReasonKey] as? UInt
            self.queue.async { self.handleInterruption(type: type, options: options, reason: reason) }
        })

        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { note in
            let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let previous = (note.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription)
                .map(Self.describeRoute) ?? "?"
            self.queue.async {
                AudioLog.log("route change: \(Self.routeChangeName(reason)), previous: \(previous) | \(self.stateOnQueue())")
            }
        })

        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereLostNotification, object: nil, queue: nil) { _ in
            AudioLog.log("MEDIA SERVICES LOST")
        })

        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { _ in
            self.queue.async { self.handleMediaServicesReset() }
        })

        observers.append(center.addObserver(forName: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil, queue: nil) { note in
            let type = note.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt
            AudioLog.log("silence secondary audio hint: \(type == 1 ? "begin" : type == 0 ? "end" : "?")")
        })
    }

    private func handleInterruption(type: UInt?, options: UInt, reason: UInt?) {
        let reasonText = reason.map(String.init) ?? "none"
        switch type.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) {
        case .began:
            AudioLog.log("INTERRUPTION began (reason \(reasonText), mode \(mode.rawValue)) | \(stateOnQueue())")
        case .ended:
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume)
            AudioLog.log("INTERRUPTION ended (shouldResume: \(shouldResume), mode \(mode.rawValue))")
            // The system deactivated the session; take it back so the next tap is heard.
            switch mode {
            case .playback:
                activatePlaybackOnQueue(reason: "interruption ended")
            case .recording:
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                } catch {
                    AudioLog.log("session: reactivation for recording FAILED: \(Self.describeError(error))")
                }
            case .background:
                break
            }
        default:
            AudioLog.log("INTERRUPTION of unknown type \(type.map(String.init) ?? "nil")")
        }
    }

    /// Apple: after a media services reset every audio object is invalid and must be recreated.
    private func handleMediaServicesReset() {
        AudioLog.log("MEDIA SERVICES RESET: rebuilding session and players (mode \(mode.rawValue))")
        stopPlaybackOnQueue()
        keepAlive?.stop()
        keepAlive = nil
        if mode != .background {
            mode = .playback
            activatePlaybackOnQueue(reason: "media services reset")
        }
        Self.onMain(onMediaServicesReset)
    }

    // MARK: Descriptions

    private func stateOnQueue() -> String {
        let session = AVAudioSession.sharedInstance()
        return "category=\(session.category.rawValue) mode=\(session.mode.rawValue)"
            + " out=\(Self.describeRoute(session.currentRoute))"
            + " volume=\(String(format: "%.2f", session.outputVolume))"
            + " otherAudio=\(session.isOtherAudioPlaying)"
            + " silenceHint=\(session.secondaryAudioShouldBeSilencedHint)"
            + " keepAlive=\(keepAlive.map { $0.isPlaying ? "playing" : "paused" } ?? "none")"
    }

    private static func describeRoute(_ route: AVAudioSessionRouteDescription) -> String {
        let outputs = route.outputs.map { "\($0.portType.rawValue)(\($0.portName))" }
        return outputs.isEmpty ? "[none]" : "[" + outputs.joined(separator: ",") + "]"
    }

    private static func describeError(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code) \(nsError.localizedDescription)"
    }

    private static func routeChangeName(_ raw: UInt?) -> String {
        guard let raw, let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return "unknown" }
        switch reason {
        case .newDeviceAvailable: return "newDeviceAvailable"
        case .oldDeviceUnavailable: return "oldDeviceUnavailable"
        case .categoryChange: return "categoryChange"
        case .override: return "override"
        case .wakeFromSleep: return "wakeFromSleep"
        case .noSuitableRouteForCategory: return "noSuitableRouteForCategory"
        case .routeConfigurationChange: return "routeConfigurationChange"
        default: return "reason \(raw)"
        }
    }

    private static func onMain(_ body: @escaping Callback) {
        DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
    }
}
