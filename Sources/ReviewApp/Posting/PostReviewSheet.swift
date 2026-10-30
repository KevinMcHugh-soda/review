import ReviewCore
import ReviewKit
import SwiftUI

/// Everything about the review before it goes: the summary, how to submit it,
/// and where each draft will land. Nothing is sent until Post.
struct PostReviewSheet: View {
    @Bindable var session: ReviewSession
    @Environment(\.dismiss) private var dismiss
    @State private var summary = ""
    @State private var event = ReviewEvent.comment
    @State private var plan: ReviewPlan?
    @State private var preflight: ReviewPublisher.Preflight?
    @State private var preflightError: String?
    @State private var isPosting = false
    @State private var postError: String?
    @State private var postedURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let postedURL {
                posted(postedURL)
            } else {
                form
            }
        }
        .frame(width: Theme.postSheetWidth, height: Theme.postSheetHeight)
        .task { await checkPreflight() }
        .task(id: PlanInput(summary: summary, event: event, drafts: session.notes.drafts)) {
            // Debounced: the summary is typed into.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let publisher = session.publisher, let review = session.pullRequestReview else { return }
            plan = await publisher.plan(session.notes.drafts, summary: summary, event: event, for: review)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text("Post Review")
                .font(Theme.Fonts.pageTitle)
            Text("Summary")
                .font(Theme.Fonts.panelTitle)
            TextEditor(text: $summary)
                .font(Theme.Fonts.note)
                .frame(height: Theme.summaryHeight)
                .scrollContentBackground(.hidden)
                .padding(Theme.tightSpacing)
                .background(.background, in: .rect(cornerRadius: Theme.codeBlockCornerRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.codeBlockCornerRadius).strokeBorder(.separator))

            Picker("Submit as", selection: $event) {
                ForEach(ReviewEvent.allCases, id: \.self) { event in
                    Text(event.title)
                        .tag(event)
                        .disabled(preflight?.isOwnPullRequest == true && !event.isAllowedOnOwnPullRequest)
                }
            }
            .pickerStyle(.radioGroup)
            if preflight?.isOwnPullRequest == true {
                Text("This is your pull request, so GitHub only accepts comments.")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
            }

            Divider()
            Text("Where your drafts will go")
                .font(Theme.Fonts.panelTitle)
            if let plan {
                PlanList(plan: plan, session: session)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let pending = preflight?.existingPendingReview {
                Link("Open the pending review on GitHub", destination: pending)
                    .font(Theme.Fonts.meta)
            }

            HStack {
                if let plan {
                    Text(countSummary(plan))
                        .font(Theme.Fonts.meta)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isPosting ? "Posting…" : "Post") { Task { await post() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canPost)
            }
        }
        .padding(Theme.sheetPadding)
    }

    private func posted(_ url: URL) -> some View {
        VStack(spacing: Theme.spacing) {
            ContentUnavailableView {
                Label("Review Posted", systemImage: "checkmark.circle")
            } description: {
                Text(event == .pending ? "It is waiting on GitHub for you to submit." : "It is on GitHub now.")
            } actions: {
                Link("Open on GitHub", destination: url)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: State

    private struct PlanInput: Equatable {
        let summary: String
        let event: ReviewEvent
        let drafts: [DraftComment]
    }

    /// Why Post is off, or a caution about posting.
    private var warning: String? {
        if let preflightError { return "Could not check GitHub first: \(preflightError)" }
        if preflight?.existingPendingReview != nil {
            return "You already have a pending review on this PR. GitHub allows one — submit or discard it there first."
        }
        if let postError { return postError }
        if let plan, plan.postedDraftIDs.isEmpty, plan.payload.body.isEmpty, event != .approve {
            return "Nothing to post: write a summary or a draft."
        }
        if event == .requestChanges, summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Requesting changes needs a summary."
        }
        return nil
    }

    private var canPost: Bool {
        guard let plan, let preflight, !isPosting, preflight.existingPendingReview == nil else { return false }
        if preflight.isOwnPullRequest, !event.isAllowedOnOwnPullRequest { return false }
        if event == .requestChanges, summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return !plan.postedDraftIDs.isEmpty || !plan.payload.body.isEmpty || event == .approve
    }

    private func countSummary(_ plan: ReviewPlan) -> String {
        let summaryCount = plan.items.count { if case .summary = $0.destination { true } else { false } }
        return "\(plan.lineCommentCount) line \(plan.lineCommentCount == 1 ? "comment" : "comments") · \(summaryCount) in the summary"
    }

    private func checkPreflight() async {
        guard let publisher = session.publisher, let review = session.pullRequestReview else {
            preflightError = "gh is not available."
            return
        }
        do {
            preflight = try await publisher.preflight(for: review)
            if preflight?.isOwnPullRequest == true { event = .comment }
        } catch {
            preflightError = "\(error)"
        }
    }

    private func post() async {
        guard let plan, let publisher = session.publisher, let review = session.pullRequestReview else { return }
        isPosting = true
        postError = nil
        defer { isPosting = false }
        do {
            let url = try await publisher.post(plan, for: review)
            session.didPost(plan, url: url)
            postedURL = url ?? review.pullRequest.reference.webURL
        } catch {
            postError = "GitHub refused the review: \(error)"
        }
    }
}
