import Observation

/// Runs jobs one after another, in the order they were added. A job starts only when the previous one
/// has finished, so overlapping requests (two folders dropped in a row, Save pressed twice) never see
/// each other's half-done work.
@MainActor
@Observable
final class SerialTaskQueue {
    private(set) var pending = 0
    @ObservationIgnored private var last: Task<Void, Never>?

    var isBusy: Bool { pending > 0 }

    /// Queues `job`. The returned task finishes when the job has run.
    @discardableResult
    func enqueue(_ job: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = last
        pending += 1
        let task = Task {
            await previous?.value
            await job()
            pending -= 1
        }
        last = task
        return task
    }
}
