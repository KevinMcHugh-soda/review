import Foundation
import Testing
@testable import ReviewProcess

@Suite
struct ToolEnvironmentTests {
    @Test("Parses env output that follows the marker and ignores a banner")
    func parsesEnvOutputThatFollowsTheMarkerAndIgnoresABanner() throws {
        let raw = "Welcome to zsh!\nlast login: today\0__REVIEW_ENV_BEGIN__\0PATH=/a:/b\0GOFLAGS=-mod=mod\0EMPTY=\0"
        let variables = try #require(ToolEnvironment.parse(Data(raw.utf8)))
        #expect(variables == ["PATH": "/a:/b", "GOFLAGS": "-mod=mod", "EMPTY": ""])
    }

    /// Banners and the marker share a field when the banner has no trailing NUL.
    @Test("Finds the marker glued to the end of a banner")
    func findsTheMarkerGluedToTheEndOfABanner() throws {
        let raw = "banner text__REVIEW_ENV_BEGIN__\0PATH=/a\0"
        #expect(try #require(ToolEnvironment.parse(Data(raw.utf8))) == ["PATH": "/a"])
    }

    @Test("Keeps an equals sign inside a value")
    func keepsAnEqualsSignInsideAValue() throws {
        let raw = "__REVIEW_ENV_BEGIN__\0LS_COLORS=di=34:ln=35\0"
        #expect(try #require(ToolEnvironment.parse(Data(raw.utf8)))["LS_COLORS"] == "di=34:ln=35")
    }

    @Test("Returns nothing when the marker never printed")
    func returnsNothingWhenTheMarkerNeverPrinted() {
        #expect(ToolEnvironment.parse(Data("PATH=/a\0".utf8)) == nil)
    }

    @Test("Falls back to the usual tool directories")
    func fallsBackToTheUsualToolDirectories() throws {
        let environment = ToolEnvironment.fallback(["PATH": "/usr/bin:/bin"], reason: "test")
        let path = try #require(environment.variables["PATH"])
        #expect(path.hasPrefix("/usr/bin:/bin:"))
        #expect(path.contains("/opt/homebrew/bin"))
        #expect(path.contains("/go/bin"))
        #expect(!path.contains("~"))
    }

    @Test("Locates the first matching executable on PATH")
    func locatesTheFirstMatchingExecutableOnPATH() {
        let environment = ToolEnvironment(variables: ["PATH": "/nonexistent:/bin:/usr/bin"], source: .fallback(reason: "test"))
        #expect(environment.locate("sh")?.path == "/bin/sh")
        #expect(environment.locate("definitely-not-a-tool") == nil)
    }

    /// The real login shell, on this machine. Proves the marker survives
    /// whatever the user's `.zshrc` prints and that PATH comes back richer than
    /// launchd's.
    @Test("Reads the real login shell's environment")
    func readsTheRealLoginShellsEnvironment() async throws {
        let environment = await ToolEnvironment.loginShell()
        if case .fallback(let reason) = environment.source {
            Issue.record("fell back: \(reason)")
        }
        let path = try #require(environment.variables["PATH"])
        #expect(path.split(separator: ":").count > 4)
    }
}
