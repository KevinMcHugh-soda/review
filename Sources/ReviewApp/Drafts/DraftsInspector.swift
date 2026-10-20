import ReviewCore
import SwiftUI

/// The trailing inspector: every draft on this PR, and the conversation about
/// all of them.
struct DraftsInspector: View {
    @Bindable var session: ReviewSession
    @FocusState private var focusedDraft: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.spacing) {
                    if session.unpostedDrafts.isEmpty {
                        ContentUnavailableView(
                            "No Drafts",
                            systemImage: "text.bubble",
                            description: Text("Select lines and choose Add Comment (⌘⇧M). Drafts stay private until you post them.")
                        )
                        .padding(.top, Theme.readingTopInset)
                    } else {
                        OverviewSection(session: session)
                        ForEach(session.unpostedDrafts) { draft in
                            DraftCard(draft: draft, session: session, focusedDraft: $focusedDraft)
                                .id(draft.id)
                        }
                    }
                    if !session.threads.isEmpty || session.threadsError != nil {
                        DisclosureGroup {
                            if let error = session.threadsError {
                                Text(error).font(Theme.Fonts.meta).foregroundStyle(.secondary)
                            }
                            ForEach(session.threads) { thread in
                                ThreadCard(thread: thread, session: session)
                                    .id(thread.id)
                            }
                        } label: {
                            Text("On GitHub · \(session.threads.count)")
                                .font(Theme.Fonts.panelTitle)
                        }
                        .padding(.top, Theme.spacing)
                    }
                    if !session.postedDrafts.isEmpty {
                        DisclosureGroup {
                            ForEach(session.postedDrafts) { draft in
                                PostedDraftRow(draft: draft, session: session)
                            }
                        } label: {
                            Text("Posted · \(session.postedDrafts.count)")
                                .font(Theme.Fonts.panelTitle)
                        }
                    }
                }
                .padding(Theme.gutter)
            }
            .onChange(of: session.selectedThreadID) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .top) }
            }
            .onChange(of: session.selectedDraftID) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .top) }
                // A new, empty draft wants typing straight away.
                if session.draft(id)?.body.isEmpty == true { focusedDraft = id }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let problem = session.askProblem {
                Text(problem)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.gutter)
                    .background(.bar)
            }
        }
    }
}

/// "Ask about all drafts", and that conversation.
private struct OverviewSection: View {
    @Bindable var session: ReviewSession

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            HStack {
                Text("^[\(session.unpostedDrafts.count) draft](inflect: true)")
                    .font(Theme.Fonts.panelTitle)
                Spacer()
                if session.notes.overview.isEmpty, session.asks[overviewID] == nil {
                    Button("Ask About All", systemImage: "sparkles") { session.askAboutAll() }
                        .help("Ask Claude about every draft at once (⌥⌘↩)")
                        .disabled(!session.canAsk)
                }
                Button("Post…", systemImage: "paperplane") { session.isPostSheetShown = true }
                    .help("Post your drafts as a GitHub review (⇧⌘P)")
                    .disabled(session.publisher == nil)
            }
            if !session.notes.overview.isEmpty || session.asks[overviewID] != nil {
                ConversationView(
                    turns: session.notes.overview,
                    progress: session.asks[overviewID],
                    followUp: Binding(
                        get: { session.followUps[overviewID] ?? "" },
                        set: { session.followUps[overviewID] = $0 }
                    ),
                    canFollowUp: session.canAsk && session.notes.overviewSessionID != nil,
                    isSelected: false,
                    ask: { session.askAboutAll() },
                    stop: { session.cancelAsk(overviewID) }
                )
                .padding(Theme.gutter)
                .background(.background.secondary, in: .rect(cornerRadius: Theme.cardCornerRadius))
            }
        }
    }
}
