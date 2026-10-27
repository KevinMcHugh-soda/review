import Foundation
import Testing
@testable import ReviewProcess

@Suite
struct FileHandleChunksTests {
    @Test("Yields what is written and ends at end of file")
    func yieldsWhatIsWrittenAndEndsAtEndOfFile() async throws {
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(Data("hello".utf8))
        try pipe.fileHandleForWriting.close()
        #expect(String(decoding: await pipe.fileHandleForReading.readAll(), as: UTF8.self) == "hello")
    }

    /// Far more open, silent pipes than the cooperative pool has threads — what
    /// a few language servers left running amount to. With a blocking read per
    /// pipe, every thread is taken and the subprocess below never finishes.
    @Test("Open pipes do not starve other async work", .timeLimit(.minutes(1)))
    func openPipesDoNotStarveOtherAsyncWork() async throws {
        let pipes = (0..<64).map { _ in Pipe() }
        let readers = pipes.map { pipe in
            Task.detached { await pipe.fileHandleForReading.readAll().count }
        }

        let output = try await Subprocess.run(URL(fileURLWithPath: "/bin/echo"), ["still running"], timeout: .seconds(20))
        #expect(output.stdoutText == "still running\n")

        for pipe in pipes {
            try pipe.fileHandleForWriting.close()
        }
        for reader in readers {
            #expect(await reader.value == 0)
        }
    }
}
