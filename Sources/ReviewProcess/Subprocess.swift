import Foundation
import Synchronization

/// What a finished child process left behind.
public struct ProcessOutput: Sendable {
    public let status: Int32
    public let stdout: Data
    public let stderr: Data

    public var succeeded: Bool { status == 0 }
    public var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

public enum SubprocessError: Error, Sendable, Equatable {
    case launchFailed(executable: String, reason: String)
    case timedOut(executable: String, after: Duration)
}

/// Runs a command to completion and collects its output.
///
/// Everything this app talks to — git, gh, claude — is a child process, so
/// this is the one place that knows how to run one. Long-lived processes with
/// a conversation over stdio (the language servers) use `Process` directly;
/// see plans/lsp.md.
public enum Subprocess {
    /// - Parameters:
    ///   - environment: the child's whole environment. Pass
    ///     `ToolEnvironment.variables` — a GUI app's own environment lacks the
    ///     user's PATH, so tools in `~/go/bin` or `~/.local/bin` vanish.
    ///   - timeout: the child is terminated if it runs longer than this.
    public static func run(
        _ executable: URL,
        _ arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        input: Data? = nil,
        timeout: Duration? = nil
    ) async throws(SubprocessError) -> ProcessOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let stdin = input.map { _ in Pipe() }
        process.standardInput = stdin ?? FileHandle.nullDevice

        // Both pipes are drained concurrently while the child runs. Reading
        // them one after the other, or only after exit, deadlocks as soon as
        // the child fills the 64 KiB pipe buffer on the stream not being read.
        let exited = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { exited.continuation.yield($0.terminationStatus) }

        do {
            try process.run()
        } catch {
            throw .launchFailed(executable: executable.path, reason: error.localizedDescription)
        }

        let outHandle = stdout.fileHandleForReading
        let errHandle = stderr.fileHandleForReading
        let outTask = Task.detached { await outHandle.readAll() }
        let errTask = Task.detached { await errHandle.readAll() }
        if let input, let inHandle = stdin?.fileHandleForWriting {
            Task.detached {
                inHandle.write(input)
                try? inHandle.close()
            }
        }

        // The watchdog signals by pid rather than holding the Process, which
        // is not Sendable, and records that it fired so a timeout is never
        // confused with a child that died of some other signal.
        let pid = process.processIdentifier
        let fired = Flag()
        let watchdog = timeout.map { limit in
            Task.detached {
                try await Task.sleep(for: limit)
                fired.set()
                kill(pid, SIGTERM)
            }
        }

        var status: Int32 = -1
        for await code in exited.stream {
            status = code
            break
        }
        watchdog?.cancel()

        let output = ProcessOutput(status: status, stdout: await outTask.value, stderr: await errTask.value)
        if let timeout, fired.isSet {
            throw .timedOut(executable: executable.lastPathComponent, after: timeout)
        }
        return output
    }
}

/// A one-way latch the watchdog can set from another task. `Mutex` is
/// non-copyable and cannot be captured by an escaping closure on its own.
private final class Flag: Sendable {
    private let state = Mutex(false)

    var isSet: Bool { state.withLock { $0 } }

    func set() {
        state.withLock { $0 = true }
    }
}
