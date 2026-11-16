//  Copyright Snap Inc. All rights reserved.

import CoreMedia
import Foundation
import SCSDKCameraKit

/// Hands live microphone audio straight to recording and streaming outputs.
///
/// Camera Kit passes every microphone buffer through its Lens engine, where the buffer waits for the frame
/// being rendered. A capture callback that waits too long loses audio, so live microphone audio is
/// delivered here instead and never enters Camera Kit.
final class MicrophoneAudioRouter {
    private final class WeakOutput {
        weak var output: Output?

        init(_ output: Output) {
            self.output = output
        }
    }

    private let lock = NSLock()
    private var outputs: [WeakOutput] = []
    private weak var cameraKit: CameraKitProtocol?

    init(cameraKit: CameraKitProtocol) {
        self.cameraKit = cameraKit
    }

    func add(_ output: Output) {
        lock.lock()
        defer { lock.unlock() }
        outputs.removeAll { $0.output == nil }
        guard !outputs.contains(where: { $0.output === output }) else { return }
        outputs.append(WeakOutput(output))
    }

    func remove(_ output: Output) {
        lock.lock()
        defer { lock.unlock() }
        outputs.removeAll { $0.output == nil || $0.output === output }
    }

    /// Runs on the microphone capture queue, so outputs must return without waiting on video work.
    func deliver(_ sampleBuffer: CMSampleBuffer) {
        guard let cameraKit else { return }
        lock.lock()
        let currentOutputs = outputs.compactMap(\.output)
        lock.unlock()
        for output in currentOutputs {
            output.cameraKit(cameraKit, didOutputAudioSampleBuffer: sampleBuffer)
        }
    }
}
