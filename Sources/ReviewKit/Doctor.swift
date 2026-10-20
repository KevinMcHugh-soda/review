import Foundation
import ReviewLSP
import ReviewProcess

/// Whether one tool is installed and usable.
public struct ToolStatus: Sendable, Identifiable {
    public let tool: Tool
    public let location: URL?
    /// The first line of `--version`, when it ran.
    public let version: String?
    /// Why a found tool still is not usable — e.g. gh installed but signed out.
    public let problem: String?

    public var id: Tool { tool }
    public var isUsable: Bool { location != nil && problem == nil }
}

/// Finds each tool and asks it for its version. Shared by `review doctor`
/// and the app's status footer, so both always agree.
public struct Doctor: Sendable {
    public let environment: ToolEnvironment

    public init(environment: ToolEnvironment) {
        self.environment = environment
    }

    public func check() async -> [ToolStatus] {
        await withTaskGroup(of: ToolStatus.self) { group in
            for tool in Tool.allCases {
                group.addTask { await status(of: tool) }
            }
            let found = await group.reduce(into: [Tool: ToolStatus]()) { $0[$1.tool] = $1 }
            return Tool.allCases.compactMap { found[$0] }
        }
    }

    func status(of tool: Tool) async -> ToolStatus {
        if tool == .typeScriptServer {
            // Which program serves TypeScript is a decision, not a lookup.
            let command = await ServerCommand.resolve(.typeScript, environment: environment)
            return ToolStatus(tool: tool, location: command?.executable, version: command?.summary, problem: nil)
        }
        guard let location = environment.locate(tool.executableName) else {
            return ToolStatus(tool: tool, location: nil, version: nil, problem: nil)
        }
        let version = try? await Subprocess.run(
            location, tool.versionArguments, environment: environment.variables, timeout: .seconds(10)
        )
        let firstLine = version.flatMap { output in
            output.stdoutText.split(whereSeparator: \.isNewline).first.map(String.init)
        }
        let problem: String? = if tool == .gh { await ghAuthProblem(location) } else { nil }
        return ToolStatus(tool: tool, location: location, version: firstLine, problem: problem)
    }

    /// `gh auth status` exits non-zero when no account is signed in.
    private func ghAuthProblem(_ gh: URL) async -> String? {
        let output = try? await Subprocess.run(
            gh, ["auth", "status", "--hostname", "github.com"],
            environment: environment.variables, timeout: .seconds(10)
        )
        guard let output else { return "gh auth status did not run" }
        return output.succeeded ? nil : "Not signed in — run gh auth login"
    }
}
