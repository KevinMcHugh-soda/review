import Foundation

extension FileHandle {
    /// The handle's data as it arrives, ending at end of file.
    ///
    /// Read through `readabilityHandler`, on a dispatch queue, never with a
    /// blocking `availableData` or `readDataToEndOfFile` in a task. A blocking
    /// read holds one of Swift concurrency's cooperative threads — about one
    /// per core — for as long as the pipe stays open, and each language server
    /// keeps two open for the life of the PR. A handful of them used to take
    /// every thread, and every other `async` call in the app waited.
    ///
    /// The stream is unbounded, so the pipe is drained however slowly the
    /// consumer reads. Ending the iteration stops reading.
    public var chunks: AsyncStream<Data> {
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
            } else {
                continuation.yield(data)
            }
        }
        continuation.onTermination = { [weak self] _ in self?.readabilityHandler = nil }
        return stream
    }

    /// Everything up to end of file, read without blocking a thread.
    public func readAll() async -> Data {
        var all = Data()
        for await chunk in chunks {
            all.append(chunk)
        }
        return all
    }
}
