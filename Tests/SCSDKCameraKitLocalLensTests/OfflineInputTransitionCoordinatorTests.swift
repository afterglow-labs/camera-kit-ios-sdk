import Dispatch
import XCTest
@testable import SCSDKCameraKitReferenceUI

final class OfflineInputTransitionCoordinatorTests: XCTestCase {
    func testRestartLeavesStopCallbackQueueBeforeRunning() {
        let transitionQueue = DispatchQueue(label: "test.offline-input.transition")
        let stopCallbackQueue = DispatchQueue(label: "test.camerakit.session.processor")
        let transitionKey = DispatchSpecificKey<String>()
        let stopCallbackKey = DispatchSpecificKey<String>()
        transitionQueue.setSpecific(key: transitionKey, value: "transition")
        stopCallbackQueue.setSpecific(key: stopCallbackKey, value: "processor")

        let restarted = expectation(description: "offline input restarted")
        let coordinator = OfflineInputTransitionCoordinator(queue: transitionQueue)

        coordinator.perform(
            stop: { completion in
                stopCallbackQueue.async(execute: completion)
            },
            restart: {
                XCTAssertEqual(DispatchQueue.getSpecific(key: transitionKey), "transition")
                XCTAssertNil(DispatchQueue.getSpecific(key: stopCallbackKey))
                restarted.fulfill()
            }
        )

        wait(for: [restarted], timeout: 2)
    }
}
