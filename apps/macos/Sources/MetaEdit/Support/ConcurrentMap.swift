import Foundation

/// Applies `transform` to `items` on background threads, up to `width` at a time, and hands each result
/// to `receive` on the main actor in the order of `items`, as soon as every result before it is in.
@MainActor
func mapConcurrently<Item: Sendable, Output: Sendable>(
    _ items: [Item],
    width: Int = ProcessInfo.processInfo.activeProcessorCount,
    transform: @escaping @Sendable (Item) -> Output,
    receive: (Item, Output) -> Void
) async {
    await withTaskGroup(of: (index: Int, output: Output).self) { group in
        var submitted = 0
        func submitNext() {
            guard submitted < items.count else { return }
            let index = submitted
            let item = items[index]
            group.addTask { (index, transform(item)) }
            submitted += 1
        }
        for _ in 0..<max(width, 1) { submitNext() }

        var finished: [Int: Output] = [:]
        var delivered = 0
        while let result = await group.next() {
            finished[result.index] = result.output
            submitNext()
            while let output = finished.removeValue(forKey: delivered) {
                receive(items[delivered], output)
                delivered += 1
            }
        }
    }
}
