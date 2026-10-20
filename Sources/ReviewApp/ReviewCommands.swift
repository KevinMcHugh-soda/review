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
            Button("Show Whole File") { session?.mode = .file }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(session?.selectedFile == nil)
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
            Button("Add Comment") { session?.addDraft() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
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
