import Dispatch

/// Serializes an offline-input stop/restart transition onto the capture-session queue.
///
/// Camera Kit may invoke its stop completion on its own session processor queue. Restarting
/// Camera Kit from that callback can synchronously re-enter the same queue and trap in libdispatch.
final class OfflineInputTransitionCoordinator {
    private let queue: DispatchQueue

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func perform(
        stop: @escaping (@escaping () -> Void) -> Void,
        restart: @escaping () -> Void
    ) {
        queue.async { [queue] in
            stop {
                queue.async(execute: restart)
            }
        }
    }
}
