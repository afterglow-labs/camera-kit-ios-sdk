import AVFoundation
import CoreMedia
import SCSDKCameraKit
import XCTest
@testable import SCSDKCameraKitReferenceUI

/// Live microphone audio must reach recorders and streams without entering Camera Kit. Inside Camera Kit
/// every microphone buffer waits for the Lens engine, and the capture system drops audio that waits too long.
final class MicrophoneAudioRoutingTests: XCTestCase {
    // MARK: Adapter

    func testAdapterHandsMicrophoneAudioToItsHandlerInsteadOfCameraKit() throws {
        let source = RoutingTestInput()
        let cameraKitSide = InputDestinationSpy()
        var handled: [CMSampleBuffer] = []
        let adapter = ExternalInputCompatibilityAdapter(source: source) { handled.append($0) }
        adapter.destination = cameraKitSide
        let audio = try MediaSamples.audio()

        adapter.input(source, receivedAudioSampleBuffer: audio)

        XCTAssertEqual(handled.count, 1)
        XCTAssertTrue(handled.first === audio)
        XCTAssertTrue(cameraKitSide.audioSampleBuffers.isEmpty, "Microphone audio must not enter Camera Kit")
    }

    func testAdapterStillPassesVideoFramesToCameraKit() throws {
        let source = RoutingTestInput()
        let cameraKitSide = InputDestinationSpy()
        let adapter = ExternalInputCompatibilityAdapter(source: source) { _ in }
        adapter.destination = cameraKitSide
        let video = try MediaSamples.video()

        adapter.input(source, receivedVideoSampleBuffer: video)

        XCTAssertEqual(cameraKitSide.videoSampleBuffers.count, 1)
    }

    // MARK: Router

    func testRouterDeliversMicrophoneAudioToEveryAddedOutput() throws {
        let cameraKit = SharedControllers.withBuiltInCamera.cameraKit
        let router = MicrophoneAudioRouter(cameraKit: cameraKit)
        let recorder = AudioOutputSpy()
        let stream = AudioOutputSpy()
        router.add(recorder)
        router.add(stream)
        let audio = try MediaSamples.audio()

        router.deliver(audio)

        XCTAssertTrue(recorder.audioSampleBuffers.first === audio)
        XCTAssertTrue(stream.audioSampleBuffers.first === audio)
        XCTAssertTrue(recorder.cameraKits.first === cameraKit)
    }

    func testRouterStopsDeliveringToARemovedOutput() throws {
        let router = MicrophoneAudioRouter(cameraKit: SharedControllers.withBuiltInCamera.cameraKit)
        let output = AudioOutputSpy()
        router.add(output)
        router.remove(output)

        router.deliver(try MediaSamples.audio())

        XCTAssertTrue(output.audioSampleBuffers.isEmpty)
    }

    func testRouterDeliversOnceToAnOutputAddedTwice() throws {
        let router = MicrophoneAudioRouter(cameraKit: SharedControllers.withBuiltInCamera.cameraKit)
        let output = AudioOutputSpy()
        router.add(output)
        router.add(output)

        router.deliver(try MediaSamples.audio())

        XCTAssertEqual(output.audioSampleBuffers.count, 1)
    }

    func testRouterDoesNotKeepOutputsAlive() throws {
        let router = MicrophoneAudioRouter(cameraKit: SharedControllers.withBuiltInCamera.cameraKit)
        var output: AudioOutputSpy? = AudioOutputSpy()
        weak var releasedOutput = output
        router.add(try XCTUnwrap(output))

        output = nil
        router.deliver(try MediaSamples.audio())

        XCTAssertNil(releasedOutput)
    }

    // MARK: Controller

    func testExternalInputMicrophoneAudioReachesOutputsAddedThroughTheController() throws {
        let input = SharedControllers.externalInput
        let controller = SharedControllers.withExternalInput
        let output = AudioOutputSpy()
        controller.add(output: output)
        let audio = try MediaSamples.audio()

        input.destination?.input(input, receivedAudioSampleBuffer: audio)

        XCTAssertEqual(output.audioSampleBuffers.count, 1)
        XCTAssertTrue(output.audioSampleBuffers.first === audio)
    }

    func testOutputRemovedThroughTheControllerStopsReceivingMicrophoneAudio() throws {
        let input = SharedControllers.externalInput
        let controller = SharedControllers.withExternalInput
        let output = AudioOutputSpy()
        controller.add(output: output)
        controller.remove(output: output)

        input.destination?.input(input, receivedAudioSampleBuffer: try MediaSamples.audio())

        XCTAssertTrue(output.audioSampleBuffers.isEmpty)
    }

    func testBuiltInCameraMicrophoneAudioReachesOutputsAddedThroughTheController() throws {
        let controller = SharedControllers.withBuiltInCamera
        let output = AudioOutputSpy()
        controller.add(output: output)
        let cameraInput = controller.makeCameraInput()
        let microphoneSide = try XCTUnwrap(cameraInput as? InputDestination)
        let audio = try MediaSamples.audio()

        microphoneSide.input(cameraInput, receivedAudioSampleBuffer: audio)

        XCTAssertEqual(output.audioSampleBuffers.count, 1)
        XCTAssertTrue(output.audioSampleBuffers.first === audio)
    }

    func testControllerWithAnExternalInputGivesCameraKitTheAdapterThatRoutesItsAudio() {
        let cameraInput = SharedControllers.withExternalInput.makeCameraInput()

        XCTAssertTrue(cameraInput === SharedControllers.externalInput.destination)
    }

    func testControllersRecorderRecordsMicrophoneAudioArrivingFromTheLiveInput() async throws {
        let input = SharedControllers.externalInput
        let controller = SharedControllers.withExternalInput
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let recorder = try Recorder(
            url: url,
            orientation: .portrait,
            configuration: RecordingConfiguration(
                outputSize: CGSize(width: 320, height: 240),
                framesPerSecond: 30,
                videoCodec: .h264
            )
        )
        controller.replaceRecorder(with: recorder)
        recorder.startRecording()

        // One second of media: Camera Kit hands the recorder video, the live input supplies the microphone.
        let start = CMTime(value: 1_000, timescale: 1)
        for frame in 0 ..< 30 {
            let time = CMTimeAdd(start, CMTime(value: CMTimeValue(frame), timescale: 30))
            recorder.output.cameraKit(
                controller.cameraKit,
                didOutputVideoSampleBuffer: try MediaSamples.video(width: 320, height: 240, presentationTime: time)
            )
        }
        for buffer in 0 ..< 46 {
            let firstFrame = buffer * 1_024
            let time = CMTimeAdd(start, CMTime(value: CMTimeValue(firstFrame), timescale: 48_000))
            input.destination?.input(
                input,
                receivedAudioSampleBuffer: try MediaSamples.audio(
                    presentationTime: time,
                    firstFrameIndex: firstFrame,
                    tone: 440
                )
            )
        }

        let recordedURL: URL? = await withCheckedContinuation { continuation in
            controller.finishRecording { url, _ in continuation.resume(returning: url) }
        }

        let audioSeconds = try await MediaSamples.trackSeconds(.audio, in: try XCTUnwrap(recordedURL))
        XCTAssertEqual(try XCTUnwrap(audioSeconds, "The recording has no audio track"), 0.98, accuracy: 0.06)
    }
}

private final class InputDestinationSpy: NSObject, InputDestination {
    private(set) var audioSampleBuffers: [CMSampleBuffer] = []
    private(set) var videoSampleBuffers: [CMSampleBuffer] = []

    func input(_ input: Input, receivedVideoSampleBuffer sampleBuffer: CMSampleBuffer) {
        videoSampleBuffers.append(sampleBuffer)
    }

    func input(_ input: Input, receivedAudioSampleBuffer sampleBuffer: CMSampleBuffer) {
        audioSampleBuffers.append(sampleBuffer)
    }

    func inputChangedAttributes(_ input: Input) {}
}

private final class AudioOutputSpy: NSObject, Output {
    private(set) var audioSampleBuffers: [CMSampleBuffer] = []
    private(set) var cameraKits: [CameraKitProtocol] = []

    func cameraKit(_ cameraKit: CameraKitProtocol, didOutputTexture texture: Texture) {}

    func cameraKit(_ cameraKit: CameraKitProtocol, didOutputVideoSampleBuffer sampleBuffer: CMSampleBuffer) {}

    func cameraKit(_ cameraKit: CameraKitProtocol, didOutputAudioSampleBuffer sampleBuffer: CMSampleBuffer) {
        audioSampleBuffers.append(sampleBuffer)
        cameraKits.append(cameraKit)
    }
}
