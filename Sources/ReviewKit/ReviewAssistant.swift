import Foundation
import ReviewClaude
import ReviewCore
import ReviewDiff

/// Asks Claude about drafts: builds the prompt from the review and the
/// checkout, and runs it read-only. See plans/claude-integration.md.
public struct ReviewAssistant: Sendable {
    let client: ClaudeClient
    /// Parent of the empty per-review directories Claude runs in.
    let scratchRoot: URL

    public init(client: ClaudeClient, scratchRoot: URL) {
        self.client = client
        self.scratchRoot = scratchRoot
    }

    /// The first question about a draft, or — with a session to resume — a
    /// follow-up, which needs no context because Claude already has it.
    public func ask(
        about draft: DraftComment,
        followUp: String?,
        in review: LoadedReview,
        worktree: URL
    ) async throws -> AsyncThrowingStream<ClaudeEvent, any Error> {
        let prompt: String
        if let followUp, draft.claudeSessionID != nil {
            prompt = followUp
        } else {
            let context = try await context(for: draft, in: review, worktree: worktree)
            prompt = ReviewPrompts.question(about: draft, context: context)
                + (followUp.map { "\n\nTheir question: \($0)" } ?? "")
        }
        return client.ask(request(prompt, review: review, worktree: worktree, resume: draft.claudeSessionID))
    }

    /// Every draft at once; follow-ups resume the same conversation.
    public func askAboutAll(
        _ drafts: [DraftComment],
        followUp: String?,
        sessionID: String?,
        in review: LoadedReview,
        worktree: URL
    ) async throws -> AsyncThrowingStream<ClaudeEvent, any Error> {
        let prompt: String
        if let followUp, sessionID != nil {
            prompt = followUp
        } else {
            var items: [(DraftComment, DraftContext)] = []
            for draft in drafts {
                items.append((draft, try await context(for: draft, in: review, worktree: worktree)))
            }
            prompt = ReviewPrompts.overview(of: items)
        }
        return client.ask(request(prompt, review: review, worktree: worktree, resume: sessionID))
    }

    private func request(_ prompt: String, review: LoadedReview, worktree: URL, resume: String?) -> ClaudeRequest {
        let reference = review.pullRequest.reference
        let directory = scratchRoot
            .appendingPathComponent(reference.owner, isDirectory: true)
            .appendingPathComponent(reference.repository, isDirectory: true)
            .appendingPathComponent(String(reference.number), isDirectory: true)
        return ClaudeRequest(
            prompt: prompt,
            systemPrompt: ReviewPrompts.systemPrompt(for: review.pullRequest, mergeBase: review.mergeBase, worktree: worktree),
            workingDirectory: directory,
            readableDirectories: [worktree],
            resumeSessionID: resume
        )
    }

    /// The anchor's file on its side, cut around the anchor, and its diff.
    func context(for draft: DraftComment, in review: LoadedReview, worktree: URL) async throws -> DraftContext {
        let anchor = draft.anchor
        let file = review.files.first { anchor.side == .head ? $0.newPath == anchor.path : $0.oldPath == anchor.path }
        let text: String?
        if let file {
            text = try await review.text(of: file, on: anchor.side)
        } else {
            let url = anchor.path.hasPrefix("/") ? URL(fileURLWithPath: anchor.path) : worktree.appendingPathComponent(anchor.path)
            text = (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
        }
        let lines = text.map(CodeDocument.lines) ?? anchor.quotedLines
        let excerpt = text == nil
            ? ReviewPrompts.excerpt(lines: anchor.quotedLines, anchor: 1...anchor.quotedLines.count)
            : ReviewPrompts.excerpt(lines: lines, anchor: anchor.lines)
        let patch = try await file.asyncMap { try await review.patch(for: $0) }
        return DraftContext(excerpt: excerpt, patch: patch)
    }
}

extension LoadedReview {
    /// One file's diff in this PR, as git prints it.
    public func patch(for file: FileDiff) async throws -> String {
        let paths = Array(Set([file.oldPath, file.newPath].compactMap(\.self)))
        return try await git.diff(from: mergeBase, to: pullRequest.head.sha, paths: paths, in: repository)
    }
}

extension Optional {
    fileprivate func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let self else { return nil }
        return try await transform(self)
    }
}
