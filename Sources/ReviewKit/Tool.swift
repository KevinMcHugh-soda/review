import Foundation

/// The external programs the app drives. None are bundled: each is what the
/// reviewer already has installed, found through their login-shell PATH.
public enum Tool: String, CaseIterable, Sendable {
    case git
    case gh
    case gopls
    case typescriptLanguageServer = "typescript-language-server"
    case claude

    public var executableName: String { rawValue }

    /// What the app uses it for, in the reviewer's terms.
    public var purpose: String {
        switch self {
        case .git: "Checking out the base and head of a pull request"
        case .gh: "Reading pull requests and posting reviews"
        case .gopls: "Go definitions, references and callers"
        case .typescriptLanguageServer: "TypeScript definitions, references and callers"
        case .claude: "Answering questions about your draft comments"
        }
    }

    public var installHint: String {
        switch self {
        case .git: "xcode-select --install"
        case .gh: "brew install gh && gh auth login"
        case .gopls: "go install golang.org/x/tools/gopls@latest"
        case .typescriptLanguageServer: "npm install -g typescript-language-server typescript"
        case .claude: "https://docs.claude.com/en/docs/claude-code/setup"
        }
    }

    /// Without git or gh there is no pull request to look at; the others only
    /// switch off one feature.
    public var isRequired: Bool {
        switch self {
        case .git, .gh: true
        case .gopls, .typescriptLanguageServer, .claude: false
        }
    }

    var versionArguments: [String] {
        switch self {
        case .gopls: ["version"]
        case .git, .gh, .typescriptLanguageServer, .claude: ["--version"]
        }
    }
}
