import XCTest
@testable import SCSDKCameraKitReferenceUI

/// The recorder's capture callbacks pass through this gate. The microphone callback must never wait
/// behind video work, because a capture callback that waits too long loses audio.
final class RecordingMediaGateTests: XCTestCase {
    func testNothingIsAdmittedBeforeRecordingStarts() {
        let gate = RecordingMediaGate()
        var admitted: [String] = []

        gate.admitVideo { admitted.append("video") }
        gate.admitAudio { admitted.append("audio") }

        XCTAssertEqual(admitted, [])
    }

    func testNothingIsAdmittedOnceRecordingStops() {
        let gate = RecordingMediaGate()
        var admitted: [String] = []
        gate.open()
        gate.close()

        gate.admitVideo { admitted.append("video") }
        gate.admitAudio { admitted.append("audio") }

        XCTAssertEqual(admitted, [])
    }

    func testMicrophoneAudioIsAdmittedWhileAVideoFrameIsStillBeingWritten() {
        let gate = RecordingMediaGate()
        gate.open()
        let videoIsBeingWritten = DispatchSemaphore(value: 0)
        let finishVideo = DispatchSemaphore(value: 0)
        let videoReturned = expectation(description: "video frame written")
        DispatchQueue.global().async {
            gate.admitVideo {
                videoIsBeingWritten.signal()
                finishVideo.wait()
            }
            videoReturned.fulfill()
        }
        XCTAssertEqual(videoIsBeingWritten.wait(timeout: .now() + 2), .success)

        let audioAdmitted = expectation(description: "audio admitted without waiting for video")
        DispatchQueue.global().async {
            gate.admitAudio { audioAdmitted.fulfill() }
        }
        wait(for: [audioAdmitted], timeout: 2)

        finishVideo.signal()
        wait(for: [videoReturned], timeout: 2)
    }

    func testStoppingWaitsForAVideoFrameThatIsStillBeingWritten() {
        let gate = RecordingMediaGate()
        gate.open()
        let videoIsBeingWritten = DispatchSemaphore(value: 0)
        let finishVideo = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            gate.admitVideo {
                videoIsBeingWritten.signal()
                finishVideo.wait()
            }
        }
        XCTAssertEqual(videoIsBeingWritten.wait(timeout: .now() + 2), .success)

        let stopped = expectation(description: "gate closed")
        let stopReturned = Flag()
        DispatchQueue.global().async {
            gate.close()
            stopReturned.set()
            stopped.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertFalse(stopReturned.isSet, "Stopping must wait for the frame that is still being written")

        finishVideo.signal()
        wait(for: [stopped], timeout: 2)
    }

    func testStoppingWaitsForMicrophoneAudioThatIsStillBeingAdmitted() {
        let gate = RecordingMediaGate()
        gate.open()
        let audioIsBeingAdmitted = DispatchSemaphore(value: 0)
        let finishAudio = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            gate.admitAudio {
                audioIsBeingAdmitted.signal()
                finishAudio.wait()
            }
        }
        XCTAssertEqual(audioIsBeingAdmitted.wait(timeout: .now() + 2), .success)

        let stopped = expectation(description: "gate closed")
        let stopReturned = Flag()
        DispatchQueue.global().async {
            gate.close()
            stopReturned.set()
            stopped.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertFalse(stopReturned.isSet, "Stopping must wait for audio that is still being admitted")

        finishAudio.signal()
        wait(for: [stopped], timeout: 2)
    }
}

private final class Flag {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}
