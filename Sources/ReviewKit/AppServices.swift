import Foundation
import ReviewClaude
import ReviewGit
import ReviewGitHub
import ReviewProcess

/// The facade both frontends consume. Holds what every feature needs: the
/// environment child processes run in, and the clients built on it.
public struct AppServices: Sendable {
    public static let version = "0.1.0"

    public let environment: ToolEnvironment

    public init(environment: ToolEnvironment) {
        self.environment = environment
    }

    /// Asks the login shell for the environment. Takes about half a second
    /// with a typical `.zshrc`, so it is not done in `init`.
    public static func start() async -> Self {
        Self(environment: await ToolEnvironment.loginShell())
    }

    public var doctor: Doctor { Doctor(environment: environment) }

    /// Nil when git or gh is missing; `doctor` says which and how to fix it.
    public var loader: ReviewLoader? {
        guard
            let gitPath = environment.locate(Tool.git.executableName),
            let ghPath = environment.locate(Tool.gh.executableName)
        else { return nil }
        let git = GitClient(git: gitPath, gh: ghPath, environment: environment.variables)
        return ReviewLoader(
            github: GitHubClient(gh: ghPath, environment: environment.variables),
            checkouts: CheckoutStore(root: CheckoutStore.defaultRoot, git: git),
            git: git
        )
    }

    /// Nil when claude is not installed.
    public var assistant: ReviewAssistant? {
        guard let claude = environment.locate(Tool.claude.executableName) else { return nil }
        return ReviewAssistant(
            client: ClaudeClient(executable: claude, environment: environment.variables),
            scratchRoot: CheckoutStore.defaultRoot.appendingPathComponent("claude", isDirectory: true)
        )
    }

    public var notes: NotesStore { NotesStore(root: CheckoutStore.defaultRoot) }

    /// Nil when gh is missing.
    public var publisher: ReviewPublisher? {
        guard let gh = environment.locate(Tool.gh.executableName) else { return nil }
        return ReviewPublisher(github: GitHubClient(gh: gh, environment: environment.variables))
    }
}
