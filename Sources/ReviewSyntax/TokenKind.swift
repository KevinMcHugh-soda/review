/// What a highlighted span is, reduced from tree-sitter's open-ended capture
/// names (`function.method`, `variable.parameter`, …) to the handful of kinds
/// the theme colours. The app's `Theme` owns the colours.
public enum TokenKind: String, Hashable, Sendable, CaseIterable {
    case keyword
    case string
    case escape
    case comment
    case number
    case constant
    case type
    case function
    case property
    case parameter
    case `operator`
    case tag

    /// Maps a capture name such as `function.method.builtin`. Nil for the
    /// captures drawn in the default text colour: plain variables and
    /// punctuation.
    public init?(captureName: String) {
        let parts = captureName.split(separator: ".")
        guard let head = parts.first else { return nil }
        let second = parts.dropFirst().first

        switch head {
        case "keyword", "conditional", "repeat", "include", "exception": self = .keyword
        case "string":
            self = second == "escape" ? .escape : .string
        case "escape": self = .escape
        case "comment": self = .comment
        case "number", "float": self = .number
        case "boolean": self = .constant
        case "constant":
            self = second == "numeric" ? .number : .constant
        case "type", "constructor", "namespace", "module": self = .type
        case "function", "method": self = .function
        case "property", "field", "attribute": self = .property
        case "variable":
            switch second {
            case "parameter": self = .parameter
            case "builtin": self = .keyword
            case "member": self = .property
            default: return nil
            }
        case "operator": self = .operator
        case "tag": self = .tag
        case "label": self = .constant
        default: return nil
        }
    }
}
