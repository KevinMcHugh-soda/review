import Foundation
import ReviewCore

/// The source line at each location, for result lists: "where is it called"
/// is answered by reading the calls, not their file names.
public enum LocationSnippets {
    /// Each file is read once, off the caller's actor. Lines are trimmed of
    /// leading whitespace; locations whose file cannot be read are left out.
    public static func load(_ locations: [CodeLocation]) async -> [CodeLocation: String] {
        await Task.detached(priority: .userInitiated) {
            let byFile = Dictionary(grouping: locations, by: \.file)
            var snippets: [CodeLocation: String] = [:]
            for (file, locations) in byFile {
                guard let data = try? Data(contentsOf: file) else { continue }
                let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
                for location in locations where lines.indices.contains(location.line - 1) {
                    snippets[location] = lines[location.line - 1].trimmingCharacters(in: .whitespaces)
                }
            }
            return snippets
        }.value
    }
}
