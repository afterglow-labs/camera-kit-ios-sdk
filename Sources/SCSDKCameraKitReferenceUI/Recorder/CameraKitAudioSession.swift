//  Copyright Snap Inc. All rights reserved.

import AVFoundation

/// Audio-session policy for Camera Kit capture and recording.
public enum CameraKitAudioSession {
    public static let category: AVAudioSession.Category = .playAndRecord
    public static let mode: AVAudioSession.Mode = .videoRecording
    public static let preferredSampleRate: Double = 48_000
    public static let options: AVAudioSession.CategoryOptions = [
        .allowBluetoothA2DP,
        .defaultToSpeaker,
    ]

    public static func activateForCameraRecording(
        _ audioSession: AVAudioSession = .sharedInstance()
    ) throws {
        try audioSession.setCategory(category, mode: mode, options: options)
        try audioSession.setPreferredSampleRate(preferredSampleRate)
        try audioSession.setActive(true)
    }
}
