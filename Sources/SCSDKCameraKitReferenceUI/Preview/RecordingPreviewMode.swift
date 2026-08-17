//  Copyright Snap Inc. All rights reserved.

/// Selects which video, if any, is presented on screen while Camera Kit records.
public enum RecordingPreviewMode: String, CaseIterable {
    /// Keep Camera Kit's processed Lens output visible.
    case lens

    /// Show the direct capture-session preview while Camera Kit renders the recording offscreen.
    case rawCamera

    /// Render the Camera Kit recording without presenting video on screen.
    case hidden
}

public struct RecordingPreviewPresentation: Equatable {
    public let attachesLensOutput: Bool
    public let showsRawCamera: Bool

    public init(attachesLensOutput: Bool, showsRawCamera: Bool) {
        self.attachesLensOutput = attachesLensOutput
        self.showsRawCamera = showsRawCamera
    }

    public static func resolve(mode: RecordingPreviewMode, isRecording: Bool) -> RecordingPreviewPresentation {
        guard isRecording else {
            return RecordingPreviewPresentation(attachesLensOutput: true, showsRawCamera: false)
        }

        switch mode {
        case .lens:
            return RecordingPreviewPresentation(attachesLensOutput: true, showsRawCamera: false)
        case .rawCamera:
            return RecordingPreviewPresentation(attachesLensOutput: false, showsRawCamera: true)
        case .hidden:
            return RecordingPreviewPresentation(attachesLensOutput: false, showsRawCamera: false)
        }
    }
}
