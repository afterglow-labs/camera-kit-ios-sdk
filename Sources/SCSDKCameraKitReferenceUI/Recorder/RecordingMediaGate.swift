//  Copyright Snap Inc. All rights reserved.

import Foundation

/// Decides whether capture callbacks may hand media to the recorder.
///
/// Video and microphone audio are admitted under separate locks. A video frame is written while its lock
/// is held, which can take a while under encoder backpressure; the microphone callback must not wait for
/// that, because a capture callback that waits too long loses audio.
final class RecordingMediaGate {
    private let videoLock = NSLock()
    private let audioLock = NSLock()
    private var admitsVideo = false
    private var admitsAudio = false

    func open() {
        videoLock.lock()
        admitsVideo = true
        videoLock.unlock()

        audioLock.lock()
        admitsAudio = true
        audioLock.unlock()
    }

    /// Returns once nothing more can be admitted and no admission is still running.
    func close() {
        videoLock.lock()
        admitsVideo = false
        videoLock.unlock()

        audioLock.lock()
        admitsAudio = false
        audioLock.unlock()
    }

    /// Runs `body` if recording is underway. `close()` waits for a body that is still running.
    func admitVideo(_ body: () -> Void) {
        videoLock.lock()
        defer { videoLock.unlock() }
        guard admitsVideo else { return }
        body()
    }

    /// Runs `body` if recording is underway, without waiting for video. Keep `body` short.
    func admitAudio(_ body: () -> Void) {
        audioLock.lock()
        defer { audioLock.unlock() }
        guard admitsAudio else { return }
        body()
    }
}
