import ArgumentParser
import Foundation
import ReviewCore
import ReviewKit

/// The review threads already on a PR.
struct Threads: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the review threads already on a pull request.")

    @Argument(help: "A pull request URL or owner/repo#123.")
    var pullRequest: String

    func run() async throws {
        let reference = try PullRequestReference(parsing: pullRequest)
        let services = await AppServices.start()
        guard let loader = services.loader, let publisher = services.publisher else {
            throw ValidationError("git or gh is missing — run `review doctor`.")
        }
        let review = try await loader.load(reference)
        for thread in try await publisher.threads(for: review) {
            let where_ = thread.lines.map { "\(thread.path):\($0.lowerBound == $0.upperBound ? "\($0.upperBound)" : "\($0.lowerBound)–\($0.upperBound)")" }
                ?? "\(thread.path) (outdated, was line \(thread.originalLine ?? 0))"
            let state = [thread.isResolved ? "resolved" : nil, thread.side == .base ? "base" : nil].compactMap(\.self)
            print("\(where_)\(state.isEmpty ? "" : "  [\(state.joined(separator: ", "))]")")
            for comment in thread.comments {
                let firstLine = comment.body.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
                print("    \(comment.author): \(firstLine.prefix(100))")
            }
        }
    }
}

/// Posts the drafts saved for a PR as one review.
struct Post: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Post your drafts on a pull request as a GitHub review.",
        discussion: "Shows where every draft will land first. Nothing is sent without --yes; --dry-run also prints the request."
    )

    @Argument(help: "A pull request URL or owner/repo#123.")
    var pullRequest: String

    @Option(help: "comment, approve, request-changes or pending.")
    var event = "comment"

    @Option(help: "The review's summary.")
    var summary = ""

    @Flag(help: "Print the plan and the request; send nothing.")
    var dryRun = false

    @Flag(help: "Send it. Required for anything to be posted.")
    var yes = false

    func run() async throws {
        let reference = try PullRequestReference(parsing: pullRequest)
        let event: ReviewEvent =
            switch self.event {
            case "comment": .comment
            case "approve": .approve
            case "request-changes": .requestChanges
            case "pending": .pending
            default: throw ValidationError("--event must be comment, approve, request-changes or pending.")
            }
        let services = await AppServices.start()
        guard let loader = services.loader, let publisher = services.publisher else {
            throw ValidationError("git or gh is missing — run `review doctor`.")
        }
        let review = try await loader.load(reference)
        var notes = try services.notes.load(reference)
        let plan = await publisher.plan(notes.drafts, summary: summary, event: event, for: review)

        for item in plan.items {
            guard let draft = notes.drafts.first(where: { $0.id == item.draftID }) else { continue }
            print("\(draft.anchor.description)  →  \(Self.describe(item.destination))")
        }
        print("\n\(plan.lineCommentCount) line comments; summary \(plan.payload.body.isEmpty ? "empty" : "\(plan.payload.body.count) characters"); \(event.title)")

        if dryRun {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(plan.payload), as: UTF8.self))
        }
        guard !dryRun, yes else {
            if !dryRun { print("\nNothing sent. Add --yes to post.") }
            return
        }
        guard !plan.postedDraftIDs.isEmpty || !plan.payload.body.isEmpty else {
            throw ValidationError("Nothing to post.")
        }

        let preflight = try await publisher.preflight(for: review)
        if let pending = preflight.existingPendingReview {
            throw ValidationError("You already have a pending review on this PR: \(pending.absoluteString). Submit or discard it first.")
        }
        if preflight.isOwnPullRequest, !event.isAllowedOnOwnPullRequest {
            throw ValidationError("GitHub does not let you \(event.title.lowercased()) your own pull request.")
        }
        let url = try await publisher.post(plan, for: review)
        let posted = DraftComment.Posted(date: .now, reviewURL: url)
        for id in plan.postedDraftIDs {
            if let index = notes.drafts.firstIndex(where: { $0.id == id }) { notes.drafts[index].posted = posted }
        }
        try services.notes.save(notes, for: reference)
        print("Posted: \(url?.absoluteString ?? "(no link returned)")")
    }

    static func describe(_ destination: ReviewPlan.Destination) -> String {
        switch destination {
        case let .line(_, side, startLine, line, note):
            let lines = startLine.map { "\($0)–\(line)" } ?? "\(line)"
            let noteText: String =
                switch note {
                case .reanchored(let from): " (moved from line \(from))"
                case .narrowedToLastLine: " (last line only: the range crosses hunks)"
                case nil: ""
                }
            return "line comment, \(side == .head ? "RIGHT" : "LEFT") \(lines)\(noteText)"
        case .summary(let reason):
            let why =
                switch reason {
                case .outsideDiff: "outside the diff"
                case .notInPullRequest: "file not in this PR"
                case .couldNotReanchor: "written on an earlier commit and not found again"
                }
            return "summary (\(why))"
        case .skipped(let reason):
            return switch reason {
            case .empty: "skipped (empty)"
            case .excluded: "skipped (kept private)"
            case .alreadyPosted: "skipped (already posted)"
            }
        }
    }
}
