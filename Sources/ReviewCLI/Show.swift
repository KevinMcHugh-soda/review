import ArgumentParser
import Foundation
import ReviewCore
import ReviewDiff
import ReviewKit

/// Loads a pull request exactly as the app does and prints it: the summary
/// and file list, or one file's rows as the viewer would draw them.
struct Show: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Fetch a pull request and list its files, or print one file's diff.",
        discussion: "The first run for a repository clones it into ~/Library/Application Support/Review."
    )

    @Argument(help: "A pull request URL or owner/repo#123.")
    var pullRequest: String

    @Argument(help: "A changed file to print.")
    var path: String?

    @Flag(help: "Print the whole file at head instead of the diff.")
    var file = false

    @Flag(help: "Print each row's highlight spans.")
    var spans = false

    @Flag(help: "Print every file in one document, as the all-files view shows it.")
    var all = false

    func run() async throws {
        let reference = try PullRequestReference(parsing: pullRequest)
        let services = await AppServices.start()
        guard let loader = services.loader else {
            throw ValidationError("git or gh is missing — run `review doctor`.")
        }

        let started = ContinuousClock.now
        let review = try await loader.load(reference) { step in
            FileHandle.standardError.write(Data("→ \(step.rawValue)…\n".utf8))
        }
        .ordered(by: services.fileOrders.order(for: reference.repositorySlug))
        let elapsed = ContinuousClock.now - started

        if all {
            let document = try await review.allFilesDocument(mode: file ? .file : .diff, collapsed: review.generatedPaths)
            printDocument(document)
            return
        }
        guard let path else {
            printSummary(review, elapsed: elapsed)
            return
        }
        guard let diff = review.files.first(where: { $0.path == path || $0.oldPath == path }) else {
            throw ValidationError("\(path) is not changed in \(reference).")
        }
        let document = try await review.document(for: diff, mode: file ? .file : .diff)
        printDocument(document)
    }

    private func printSummary(_ review: LoadedReview, elapsed: Duration) {
        let pr = review.pullRequest
        print("\(pr.reference)  \(pr.title)")
        print("by \(pr.author) · \(pr.state.rawValue)\(pr.isDraft ? " · draft" : "") · \(pr.head.name) → \(pr.base.name)")
        print("merge base \(review.mergeBase.prefix(12)) · head \(pr.head.sha.prefix(12)) · loaded in \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds])))")
        let merge = switch review.merge {
        case nil: "head is the merged state"
        case .clean: "merges cleanly"
        case .conflicted: "conflicts"
        }
        print("base tip \(review.baseTip.prefix(12)) · \(merge)")
        print()
        for file in review.files {
            let status =
                switch file.status {
                case .added: "A"
                case .deleted: "D"
                case .renamed: "R"
                case .modified: "M"
                }
            let counts = file.isBinary ? "binary" : "+\(file.additions) −\(file.deletions)"
            let name = file.status == .renamed ? "\(file.oldPath ?? "") → \(file.path)" : file.path
            let generated = review.generatedPaths.contains(file.path) ? "  (generated)" : ""
            print("\(status)  \(counts.padding(toLength: 12, withPad: " ", startingAt: 0)) \(name)\(generated)")
        }
    }

    private func printDocument(_ document: CodeDocument) {
        guard !document.isBinary else {
            print("(binary file)")
            return
        }
        let width = String(document.maxLineNumber).count
        for row in document.rows {
            let old = row.oldLine.map(String.init) ?? ""
            let new = row.newLine.map(String.init) ?? ""
            let mark =
                switch row.kind {
                case .hunkHeader: "@"
                case .context: " "
                case .added: "+"
                case .removed: "-"
                case .gap: "⋯"
                case .filler: "."
                case .fileHeader: "#"
                }
            print("\(old.leftPad(width)) \(new.leftPad(width)) \(mark) \(row.text)")
            if spans, !row.spans.isEmpty {
                let text = row.text as NSString
                let described = row.spans.map { span in
                    let clipped = NSIntersectionRange(span.range, NSRange(location: 0, length: text.length))
                    return "\(span.kind.rawValue)「\(text.substring(with: clipped))」"
                }
                print("\(String(repeating: " ", count: width * 2 + 4))\(described.joined(separator: " "))")
            }
        }
    }
}

extension String {
    fileprivate func leftPad(_ width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
