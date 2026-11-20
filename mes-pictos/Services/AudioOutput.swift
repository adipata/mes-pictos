import AVFoundation
import PictoCore

/// Owns the audio session and the audio players, and does all their work on one serial queue.
///
/// Activating the session, changing its category and preparing a player can block for a while
/// (the system may have to wake the audio hardware), so none of it runs on the main thread.
/// Every call returns at once; the work runs in the order the calls were made, so a `stopPlayback()`
/// always lands before the `play` that follows it. Results come back on the main actor.
nonisolated final class AudioOutput: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    typealias Callback = @MainActor @Sendable () -> Void

    private let queue = DispatchQueue(label: "mespictos.audio-output", qos: .userInitiated)

    // Everything below is only touched on `queue`.

    /// Looping silence that keeps the speaker route awake while the app is in the foreground.
    /// Without it, the output powers down between taps and the first syllable of the next word is cut.
    private var keepAlive: AVAudioPlayer?
    private var player: AVAudioPlayer?
    private var onPlayerFinished: Callback?

    // MARK: Session

    /// `.playback` so the app speaks even when the silent switch is on. No ducking: the silent
    /// keep-alive runs all the time, ducking would lower other apps' audio permanently.
    func configureForPlayback() {
        queue.async {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .spokenAudio, options: [])
            try? session.setActive(true)
            self.startKeepAliveOnQueue()
        }
    }

    /// Stops any playback and switches the session to recording. Returns once the session is ready.
    func configureForRecording() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.stopPlaybackOnQueue()
                self.keepAlive?.pause()
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                    try session.setActive(true)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: Keep-alive

    func startKeepAlive() {
        queue.async { self.startKeepAliveOnQueue() }
    }

    func stopKeepAlive() {
        queue.async { self.keepAlive?.pause() }
    }

    private func startKeepAliveOnQueue() {
        if keepAlive == nil, let silence = try? AVAudioPlayer(data: SilentAudio.wavData(seconds: 2)) {
            silence.numberOfLoops = -1
            silence.volume = 0
            silence.prepareToPlay()
            keepAlive = silence
        }
        guard let keepAlive, !keepAlive.isPlaying else { return }
        keepAlive.play()
    }

    // MARK: Recordings

    /// Plays a recording, replacing the one playing. `onFailed` runs if it cannot be decoded or
    /// started, `onFinished` when it reaches its end. Neither runs once `stopPlayback()` stopped it.
    func play(_ data: Data, onFailed: @escaping Callback, onFinished: @escaping Callback) {
        queue.async {
            self.stopPlaybackOnQueue()
            guard let player = try? AVAudioPlayer(data: data) else {
                Self.onMain(onFailed)
                return
            }
            player.delegate = self
            self.player = player
            self.onPlayerFinished = onFinished
            player.prepareToPlay()
            if !player.play() {
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
        queue.async {
            // A player that was stopped or replaced in the meantime reports nothing.
            guard finished === self.player, let callback = self.onPlayerFinished else { return }
            self.player = nil
            self.onPlayerFinished = nil
            Self.onMain(callback)
        }
    }

    private static func onMain(_ body: @escaping Callback) {
        DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
    }
}
