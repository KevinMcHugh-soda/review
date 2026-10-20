import Foundation
import ReviewCore
import ReviewDiff

/// Where each draft will go when the review is posted, and the request that
/// posts it. Built before anything is sent, so the reviewer sees every
/// placement first; see plans/github.md.
public struct ReviewPlan: Sendable {
    public struct Item: Sendable, Identifiable, Hashable {
        public let draftID: UUID
        public let destination: Destination
        public var id: UUID { draftID }
    }

    public enum Destination: Sendable, Hashable {
        /// A line comment. `startLine` is set for a range.
        case line(path: String, side: Side, startLine: Int?, line: Int, note: LineNote?)
        /// A section of the review summary, with the code quoted.
        case summary(SummaryReason)
        case skipped(SkipReason)
    }

    public enum LineNote: Sendable, Hashable {
        /// Written before the PR's latest push; found again by its quoted lines.
        case reanchored(fromLine: Int)
        /// The range crosses two hunks, which GitHub rejects; anchored on its
        /// last line.
        case narrowedToLastLine
    }

    public enum SummaryReason: Sendable, Hashable {
        /// The lines are not in the diff, and GitHub only takes line comments
        /// on lines it shows.
        case outsideDiff
        case notInPullRequest
        /// Written before the PR's latest push, and its lines are no longer
        /// there exactly once.
        case couldNotReanchor
    }

    public enum SkipReason: Sendable, Hashable {
        case empty
        case excluded
        case alreadyPosted
    }

    public let items: [Item]
    public let payload: ReviewPayload

    public var lineCommentCount: Int { payload.comments.count }
    public var postedDraftIDs: [UUID] {
        items.compactMap { item in
            if case .skipped = item.destination { nil } else { item.draftID }
        }
    }
}

/// `POST /repos/{owner}/{repo}/pulls/{number}/reviews`.
public struct ReviewPayload: Encodable, Sendable, Hashable {
    public struct Comment: Encodable, Sendable, Hashable {
        public let path: String
        public let body: String
        public let line: Int
        public let side: String
        public let startLine: Int?
        public let startSide: String?

        enum CodingKeys: String, CodingKey {
            case path, body, line, side
            case startLine = "start_line"
            case startSide = "start_side"
        }
    }

    public let commitID: String
    public let body: String
    /// Nil leaves the review pending on GitHub.
    public let event: String?
    public let comments: [Comment]

    enum CodingKeys: String, CodingKey {
        case commitID = "commit_id"
        case body, event, comments
    }
}

public enum ReviewPlanner {
    /// - Parameters:
    ///   - headLines: the current head text of files whose drafts were written
    ///     against an older head, for re-anchoring by their quoted lines.
    public static func plan(
        drafts: [DraftComment],
        summary: String,
        event: ReviewEvent,
        pullRequest: PullRequest,
        mergeBase: String,
        files: [FileDiff],
        headLines: [String: [String]] = [:]
    ) -> ReviewPlan {
        let lines = DiffLines(files)
        var items: [ReviewPlan.Item] = []
        var comments: [ReviewPayload.Comment] = []
        var sections: [String] = []

        for draft in drafts.sorted(by: { ($0.anchor.path, $0.anchor.startLine) < ($1.anchor.path, $1.anchor.startLine) }) {
            let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let destination: ReviewPlan.Destination =
                if draft.posted != nil { .skipped(.alreadyPosted) }
                else if draft.isExcludedFromReview { .skipped(.excluded) }
                else if body.isEmpty { .skipped(.empty) }
                else { place(draft, pullRequest: pullRequest, mergeBase: mergeBase, lines: lines, headLines: headLines) }
            items.append(ReviewPlan.Item(draftID: draft.id, destination: destination))

            switch destination {
            case let .line(path, side, startLine, line, _):
                comments.append(ReviewPayload.Comment(
                    path: path, body: body, line: line, side: side.gitHubName,
                    startLine: startLine, startSide: startLine == nil ? nil : side.gitHubName
                ))
            case .summary(let reason):
                sections.append(section(for: draft, body: body, reason: reason, pullRequest: pullRequest, mergeBase: mergeBase))
            case .skipped:
                break
            }
        }

        var fullSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sections.isEmpty {
            let notes = sections.joined(separator: "\n\n")
            fullSummary = fullSummary.isEmpty ? notes : "\(fullSummary)\n\n---\n\n\(notes)"
        }
        let payload = ReviewPayload(
            commitID: pullRequest.head.sha,
            body: fullSummary,
            event: event == .pending ? nil : event.rawValue,
            comments: comments
        )
        return ReviewPlan(items: items, payload: payload)
    }

    static func place(
        _ draft: DraftComment,
        pullRequest: PullRequest,
        mergeBase: String,
        lines: DiffLines,
        headLines: [String: [String]]
    ) -> ReviewPlan.Destination {
        var anchor = draft.anchor
        guard anchor.isInPullRequest else { return .summary(.notInPullRequest) }

        var note: ReviewPlan.LineNote?
        let current = anchor.side == .head ? pullRequest.head.sha : mergeBase
        if anchor.commit != current {
            guard anchor.side == .head,
                  let text = headLines[anchor.path],
                  let found = reanchor(anchor.quotedLines, in: text)
            else { return .summary(.couldNotReanchor) }
            note = .reanchored(fromLine: anchor.startLine)
            anchor = CommentAnchor(
                path: anchor.path, side: anchor.side, startLine: found.lowerBound, endLine: found.upperBound,
                commit: current, quotedLines: anchor.quotedLines, isInPullRequest: true
            )
        }

        guard let endHunk = lines.hunk(path: anchor.path, side: anchor.side, line: anchor.endLine) else {
            return .summary(.outsideDiff)
        }
        guard anchor.startLine != anchor.endLine else {
            return .line(path: anchor.path, side: anchor.side, startLine: nil, line: anchor.endLine, note: note)
        }
        let startHunk = lines.hunk(path: anchor.path, side: anchor.side, line: anchor.startLine)
        if startHunk == endHunk {
            return .line(path: anchor.path, side: anchor.side, startLine: anchor.startLine, line: anchor.endLine, note: note)
        }
        return .line(path: anchor.path, side: anchor.side, startLine: nil, line: anchor.endLine, note: note ?? .narrowedToLastLine)
    }

    /// Where a draft's quoted lines are now, if they appear exactly once.
    static func reanchor(_ quoted: [String], in lines: [String]) -> ClosedRange<Int>? {
        guard !quoted.isEmpty, quoted.count <= lines.count else { return nil }
        let matches = (0...(lines.count - quoted.count)).filter { start in
            zip(lines[start..<(start + quoted.count)], quoted).allSatisfy(==)
        }
        guard matches.count == 1, let start = matches.first else { return nil }
        return (start + 1)...(start + quoted.count)
    }

    /// A draft as a section of the summary: where it is, a link, the code, and
    /// the note.
    static func section(
        for draft: DraftComment,
        body: String,
        reason: ReviewPlan.SummaryReason,
        pullRequest: PullRequest,
        mergeBase: String
    ) -> String {
        let anchor = draft.anchor
        let lines = anchor.startLine == anchor.endLine ? "line \(anchor.startLine)" : "lines \(anchor.startLine)–\(anchor.endLine)"
        var heading = "**`\(anchor.path)`** · \(lines)"
        if !anchor.path.hasPrefix("/") {
            let reference = pullRequest.reference
            let range = anchor.startLine == anchor.endLine ? "L\(anchor.startLine)" : "L\(anchor.startLine)-L\(anchor.endLine)"
            heading += " ([view](https://github.com/\(reference.repositorySlug)/blob/\(anchor.commit)/\(anchor.path)#\(range)))"
        }
        if reason == .couldNotReanchor { heading += " — on an earlier commit" }
        let language = codeFenceLanguage(for: anchor.path)
        let quoted = anchor.quotedLines.joined(separator: "\n")
        return "\(heading)\n\n```\(language)\n\(quoted)\n```\n\n\(body)"
    }

    static func codeFenceLanguage(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "go": "go"
        case "ts", "mts", "cts": "ts"
        case "tsx": "tsx"
        case "js", "mjs", "cjs": "js"
        case "jsx": "jsx"
        default: ""
        }
    }
}

/// Which lines GitHub will take a comment on: those its diff shows. Right
/// side, the head numbers of added and context lines; left side, the base
/// numbers of removed and context lines. Each line remembers its hunk, because
/// a range must stay within one.
struct DiffLines {
    private var hunks: [String: [Side: [Int: Int]]] = [:]

    init(_ files: [FileDiff]) {
        for file in files {
            for (index, hunk) in file.hunks.enumerated() {
                for line in hunk.lines {
                    if let new = line.newLine, let path = file.newPath {
                        hunks[path, default: [:]][.head, default: [:]][new] = index
                    }
                    if let old = line.oldLine, let path = file.oldPath {
                        hunks[path, default: [:]][.base, default: [:]][old] = index
                    }
                }
            }
        }
    }

    func hunk(path: String, side: Side, line: Int) -> Int? {
        hunks[path]?[side]?[line]
    }
}

extension Side {
    /// GitHub's names: `RIGHT` is the PR's version.
    var gitHubName: String {
        switch self {
        case .head: "RIGHT"
        case .base: "LEFT"
        }
    }
}
