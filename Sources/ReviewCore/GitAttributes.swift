import Foundation

/// A repository's root `.gitattributes`, read without a checkout, for when
/// `git check-attr` is not an option: the browser sizes pull requests in
/// repositories it has never cloned.
///
/// Patterns follow gitattributes(5): one with no slash matches a file's name
/// at any depth; one with a slash is anchored at the root, `*` and `?` stay
/// within a component, and `**` spans any number of them. A pattern ending
/// in `/` names directories, which never carry attributes for the files
/// inside, so it matches nothing here. The last line that mentions an
/// attribute wins. Quoted patterns, macros and nested `.gitattributes`
/// files are not read.
public struct GitAttributes: Hashable, Sendable {
    public enum Value: Hashable, Sendable {
        case set
        case unset
        case string(String)
    }

    struct Rule: Hashable, Sendable {
        let pattern: [String]
        let isBasename: Bool
        /// Nil removes the attribute (`!name`): back to unspecified.
        let attributes: [String: Value?]
    }

    let rules: [Rule]

    public init(parsing text: String) {
        rules = text.split(whereSeparator: \.isNewline).compactMap(Self.rule)
    }

    /// The attribute's value for `path`, nil when no line says.
    public func value(of attribute: String, for path: String) -> Value? {
        let components = path.split(separator: "/").map(String.init)
        for rule in rules.reversed() {
            guard let value = rule.attributes[attribute], Self.matches(rule, components) else { continue }
            return value
        }
        return nil
    }

    /// Generated or vendored as GitHub's linguist reads it, and as harmony's
    /// `scripts/pr-line-count.sh` does: set, or `=true`.
    public func isGenerated(_ path: String) -> Bool {
        ["linguist-generated", "linguist-vendored"].contains { attribute in
            switch value(of: attribute, for: path) {
            case .set, .string("true"): true
            case .unset, .string, nil: false
            }
        }
    }

    private static func rule(_ line: Substring) -> Rule? {
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let first = fields.first, !first.hasPrefix("#"), !first.hasPrefix("\""), !first.hasPrefix("[attr]"),
              !first.hasSuffix("/")
        else { return nil }
        var pattern = String(first)
        if pattern.hasPrefix("/") { pattern.removeFirst() }
        let attributes = fields.dropFirst().reduce(into: [String: Value?]()) { attributes, field in
            if field.hasPrefix("-") {
                attributes[String(field.dropFirst())] = .some(.unset)
            } else if field.hasPrefix("!") {
                attributes[String(field.dropFirst())] = .some(nil)
            } else if let equals = field.firstIndex(of: "=") {
                attributes[String(field[..<equals])] = .some(.string(String(field[field.index(after: equals)...])))
            } else {
                attributes[String(field)] = .some(.set)
            }
        }
        guard !pattern.isEmpty, !attributes.isEmpty else { return nil }
        return Rule(
            pattern: pattern.split(separator: "/").map(String.init),
            // A slash anywhere anchors it; a trailing one was refused above.
            isBasename: !first.contains("/"),
            attributes: attributes
        )
    }

    private static func matches(_ rule: Rule, _ path: [String]) -> Bool {
        if rule.isBasename {
            guard let name = path.last, let pattern = rule.pattern.first else { return false }
            return fnmatch(pattern, name, 0) == 0
        }
        return matches(rule.pattern[...], path[...])
    }

    /// Every component of `path` consumed by `pattern`.
    private static func matches(_ pattern: ArraySlice<String>, _ path: ArraySlice<String>) -> Bool {
        guard let first = pattern.first else { return path.isEmpty }
        if first == "**" {
            // `a/**` holds everything under `a`, but not `a` itself.
            if pattern.count == 1 { return !path.isEmpty }
            return (path.startIndex...path.endIndex).contains { matches(pattern.dropFirst(), path[$0...]) }
        }
        guard let component = path.first, fnmatch(first, component, 0) == 0 else { return false }
        return matches(pattern.dropFirst(), path.dropFirst())
    }
}
