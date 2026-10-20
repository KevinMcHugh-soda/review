import Foundation
import ReviewProcess

/// The facade both frontends consume. Holds what every feature needs: the
/// environment child processes run in. Grows a service per milestone —
/// checkouts, GitHub, language servers, Claude, the store.
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
}
