import Foundation
import ReviewCore
import ReviewDiff
import ReviewGitHub

/// Reads a PR's existing threads, and turns drafts into a posted review.
public struct ReviewPublisher: Sendable {
    let github: GitHubClient

    public init(github: GitHubClient) {
        self.github = github
    }

    /// What has to be known before posting: who is posting, whether the PR is
    /// theirs (GitHub refuses approving your own), and whether a pending review
    /// is already waiting (GitHub allows only one).
    public struct Preflight: Sendable, Equatable {
        public let viewer: String
        public let isOwnPullRequest: Bool
        public let existingPendingReview: URL?
    }

    public func preflight(for review: LoadedReview) async throws -> Preflight {
        let viewer = try await github.viewerLogin()
        let pending = try await github.pendingReviewURL(review.pullRequest.reference, viewer: viewer)
        return Preflight(
            viewer: viewer,
            isOwnPullRequest: viewer.caseInsensitiveCompare(review.pullRequest.author) == .orderedSame,
            existingPendingReview: pending
        )
    }

    /// The plan, with drafts written against an older head re-anchored where
    /// their quoted lines can be found again.
    public func plan(
        _ drafts: [DraftComment],
        summary: String,
        event: ReviewEvent,
        for review: LoadedReview
    ) async -> ReviewPlan {
        let head = review.pullRequest.head.sha
        let stalePaths = Set(drafts.filter { $0.anchor.side == .head && $0.anchor.commit != head }.map(\.anchor.path))
        var headLines: [String: [String]] = [:]
        for path in stalePaths {
            if let data = try? await review.git.contents(of: path, at: head, in: review.repository) {
                headLines[path] = CodeDocument.lines(of: String(decoding: data, as: UTF8.self))
            }
        }
        return ReviewPlanner.plan(
            drafts: drafts, summary: summary, event: event, pullRequest: review.pullRequest,
            mergeBase: review.mergeBase, files: review.files, headLines: headLines
        )
    }

    /// Sends the review. Returns its page on GitHub.
    public func post(_ plan: ReviewPlan, for review: LoadedReview) async throws -> URL? {
        try await github.createReview(review.pullRequest.reference, payload: plan.payload)
    }

    public func threads(for review: LoadedReview) async throws -> [ReviewThread] {
        try await github.reviewThreads(review.pullRequest.reference)
    }
}
