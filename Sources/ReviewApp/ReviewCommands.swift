import ReviewKit
import SwiftUI

// Written out by hand: `@Entry` is a macro whose plugin ships with Xcode, not
// the Command Line Tools, so it does not expand on this machine.
private struct ReviewSessionKey: FocusedValueKey {
    typealias Value = ReviewSession
}

extension FocusedValues {
    /// The pull request in the key window, for menu commands.
    var reviewSession: ReviewSession? {
        get { self[ReviewSessionKey.self] }
        set { self[ReviewSessionKey.self] = newValue }
    }
}

/// The View menu's review commands. Each acts on the key window's session.
struct ReviewCommands: Commands {
    @FocusedValue(\.reviewSession) private var session

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Show Diff") { session?.mode = .diff }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(session?.selectedFile == nil)
            Button("Show Side by Side") { session?.mode = .split }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(session?.selectedFile == nil)
            Button("Show Whole File") { session?.mode = .file }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(session?.selectedFile == nil)
            Button(session?.isContinuous == true ? "Show One File at a Time" : "Show All Files in One Scroll") {
                session?.isContinuous.toggle()
            }
            .keyboardShortcut("4", modifiers: .command)
            .disabled(session?.review == nil)
            Divider()
            Button("Next Change") { session?.revealChange(offset: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.control, .command])
                .disabled(session?.document == nil)
            Button("Previous Change") { session?.revealChange(offset: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.control, .command])
                .disabled(session?.document == nil)
            Divider()
            Button("Next File") { session?.selectFile(offset: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(session?.review == nil)
            Button("Previous File") { session?.selectFile(offset: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(session?.review == nil)
            Divider()
        }
        CommandMenu("Review") {
            Button(session?.selectedFile.map { session?.isViewed($0) == true } == true ? "Mark as Not Viewed" : "Mark as Viewed and Go to Next") {
                session?.toggleViewedAndAdvance()
            }
            .keyboardShortcut("v", modifiers: [.command, .option])
            .disabled(session?.selectedFile == nil)
            Divider()
            Button("Add Comment") { session?.addDraft() }
                .keyboardShortcut(.addComment)
                .disabled(session?.document == nil)
            Button("Ask Claude About This Draft") {
                guard let session, let id = session.selectedDraftID else { return }
                session.ask(about: id)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(session?.selectedDraftID == nil || session?.canAsk != true)
            Button("Ask Claude About All Drafts") { session?.askAboutAll() }
                .keyboardShortcut(.return, modifiers: [.command, .option])
                .disabled(session?.notes.drafts.isEmpty != false || session?.canAsk != true)
            Button("Post Review…") { session?.isPostSheetShown = true }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(session?.review == nil || session?.publisher == nil)
            Divider()
            Button(session?.isInspectorShown == true ? "Hide Drafts" : "Show Drafts") {
                session?.isInspectorShown.toggle()
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
            .disabled(session == nil)
        }
        CommandMenu("Navigate") {
            ForEach(NavigationAction.allCases) { action in
                Button(action.title) {
                    guard let session else { return }
                    Task { await session.perform(action) }
                }
                .keyboardShortcut(action.shortcut)
                .disabled(session?.navigationState != .ready)
            }
            Divider()
            Button("Back") { session?.goBack() }
                .keyboardShortcut(.leftArrow, modifiers: [.control, .command])
                .disabled(session?.canGoBack != true)
            Button("Forward") { session?.goForward() }
                .keyboardShortcut(.rightArrow, modifiers: [.control, .command])
                .disabled(session?.canGoForward != true)
        }
    }
}
