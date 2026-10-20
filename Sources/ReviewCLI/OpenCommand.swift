import ArgumentParser
import Foundation
import ReviewCore

/// Opens a pull request in the app, which is started if it is not running.
struct Open: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Open a pull request in Review.app.",
        discussion: "Goes through the review:// URL scheme, so a running app opens it in its window. Needs Review.app registered: make install, or make register for the build in ./build."
    )

    @Argument(help: "A pull request URL or owner/repo#123.")
    var pullRequest: String

    func run() throws {
        let reference = try PullRequestReference(parsing: pullRequest)
        var components = URLComponents()
        components.scheme = "review"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "pr", value: reference.description)]
        guard let url = components.url else { throw ExitCode.failure }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ValidationError("macOS has no app for review:// links yet. Run `make install` (or `make register`) first.")
        }
    }
}
