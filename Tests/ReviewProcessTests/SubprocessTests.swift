import Foundation
import Testing
@testable import ReviewProcess

@Suite
struct SubprocessTests {
    private let sh = URL(fileURLWithPath: "/bin/sh")

    @Test("Collects stdout, stderr and the exit status separately")
    func collectsStdoutStderrAndTheExitStatusSeparately() async throws {
        let output = try await Subprocess.run(sh, ["-c", "echo out; echo err >&2; exit 3"])
        #expect(output.status == 3)
        #expect(output.stdoutText == "out\n")
        #expect(output.stderrText == "err\n")
    }

    /// Both streams well past the 64 KiB pipe buffer at once. Draining them one
    /// after the other deadlocks here, which is the bug this guards.
    @Test("Does not deadlock when both streams overflow the pipe buffer")
    func doesNotDeadlockWhenBothStreamsOverflowThePipeBuffer() async throws {
        let script = "head -c 1000000 /dev/zero | tr '\\0' a; head -c 1000000 /dev/zero | tr '\\0' b >&2"
        let output = try await Subprocess.run(sh, ["-c", script], timeout: .seconds(20))
        #expect(output.stdout.count == 1_000_000)
        #expect(output.stderr.count == 1_000_000)
    }

    @Test("Feeds input to stdin")
    func feedsInputToStdin() async throws {
        let output = try await Subprocess.run(URL(fileURLWithPath: "/usr/bin/wc"), ["-c"], input: Data("hello".utf8))
        #expect(output.stdoutText.trimmingCharacters(in: .whitespaces) == "5\n")
    }

    @Test("Uses the given environment and working directory")
    func usesTheGivenEnvironmentAndWorkingDirectory() async throws {
        let output = try await Subprocess.run(
            sh, ["-c", "echo $GREETING; pwd"],
            environment: ["GREETING": "hi"],
            currentDirectory: URL(fileURLWithPath: "/private/tmp")
        )
        #expect(output.stdoutText == "hi\n/private/tmp\n")
    }

    @Test("Terminates a child that outlives its timeout")
    func terminatesAChildThatOutlivesItsTimeout() async {
        let started = ContinuousClock.now
        await #expect(throws: SubprocessError.timedOut(executable: "sh", after: .milliseconds(300))) {
            try await Subprocess.run(sh, ["-c", "exec sleep 30"], timeout: .milliseconds(300))
        }
        #expect(ContinuousClock.now - started < .seconds(5))
    }

    /// A child killed by a signal it did not get from the watchdog is a normal
    /// exit, not a timeout.
    @Test("Does not report a timeout for a child that dies of its own signal")
    func doesNotReportATimeoutForAChildThatDiesOfItsOwnSignal() async throws {
        let output = try await Subprocess.run(sh, ["-c", "kill -TERM $$"], timeout: .seconds(10))
        #expect(!output.succeeded)
    }

    @Test("Reports a missing executable as a launch failure")
    func reportsAMissingExecutableAsALaunchFailure() async {
        await #expect {
            try await Subprocess.run(URL(fileURLWithPath: "/nonexistent/tool"))
        } throws: { error in
            if case .launchFailed = error as? SubprocessError { true } else { false }
        }
    }
}
