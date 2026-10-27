import Foundation
import ReviewCore
import ReviewDiff
import ReviewGit
import ReviewKit
import ReviewLSP
import ReviewProcess

extension ReviewSession {
    /// Checks out head and starts the servers for the PR's languages, so they
    /// index while the reviewer reads.
    func prepareNavigation(_ review: LoadedReview, checkouts: CheckoutStore, environment: ToolEnvironment) async {
        navigationState = .preparing
        do {
            let worktree = try await review.checkOut(using: checkouts)
            let navigator = Navigator(root: worktree, environment: environment)
            self.worktree = worktree
            self.navigator = navigator
            await navigator.warmUp(paths: review.files.compactMap(\.newPath))
            navigationState = .ready
            for kind in await navigator.startedKinds {
                Task { await follow(kind, on: navigator) }
            }
        } catch {
            navigationState = .unavailable("The checkout failed: \(error)")
        }
    }

    private func follow(_ kind: ServerKind, on navigator: Navigator) async {
        guard let updates = await navigator.statusUpdates(for: kind) else {
            serverStatus[kind] = .failed("did not start")
            return
        }
        for await status in updates {
            serverStatus[kind] = status
        }
    }

    // MARK: Cursor and position

    /// The path and position the servers should be asked about, or why not.
    func navigationTarget(at cursor: Cursor) -> Result<(path: String, line: Int, column: Int), NavigationProblem> {
        guard navigationState == .ready else { return .failure(.notReady) }
        guard let document, document.rows.indices.contains(cursor.row) else { return .failure(.nothingThere) }
        guard document.isNavigable(atRow: cursor.row) else { return .failure(.afterMerge) }
        let row = document.rows[cursor.row]
        guard row.isCode else { return .failure(.nothingThere) }
        guard let line = row.newLine else { return .failure(.removedLine) }
        let path: String
        if let externalFile {
            path = worktree.flatMap { CodeLocation(file: externalFile, line: 1, column: 0).path(relativeTo: $0) } ?? externalFile.path
        } else if let newPath = file(atRow: cursor.row)?.newPath {
            path = newPath
        } else {
            return .failure(.nothingThere)
        }
        return .success((path, line, cursor.column))
    }

    enum NavigationProblem: Error {
        case notReady, nothingThere, removedLine, afterMerge

        var message: String {
            switch self {
            case .notReady: "Navigation is still getting ready."
            case .nothingThere: "Put the cursor on a symbol first."
            case .removedLine: "This line only exists in the base. Navigation runs on the PR's head."
            case .afterMerge: "This is the after-merge view. Switch to Diff (⌘1) to navigate."
            }
        }
    }

    var currentPosition: ViewerPosition {
        let line = cursor.flatMap { document?.rows.indices.contains($0.row) == true ? document?.rows[$0.row].newLine : nil }
        return ViewerPosition(selectedFilePath: selectedFilePath, externalFile: externalFile, mode: mode, line: line)
    }

    /// The language server's description of the symbol at a position, for
    /// the hover popover. Nil whenever there is nothing to say.
    func hover(at cursor: Cursor) async -> String? {
        guard case .success(let target) = navigationTarget(at: cursor), let navigator else { return nil }
        return try? await navigator.hover(path: target.path, line: target.line, column: target.column)
    }

    // MARK: Actions

    func perform(_ action: NavigationAction, at cursor: Cursor? = nil) async {
        if let cursor { self.cursor = cursor }
        guard let cursor = self.cursor ?? cursor else {
            navigationMessage = NavigationProblem.nothingThere.message
            return
        }
        let target: (path: String, line: Int, column: Int)
        switch navigationTarget(at: cursor) {
        case .success(let found): target = found
        case .failure(let problem):
            navigationMessage = problem.message
            return
        }
        guard let navigator else { return }
        navigationMessage = nil

        do {
            switch action {
            case .definition, .typeDefinition:
                let found = action == .definition
                    ? try await navigator.definition(path: target.path, line: target.line, column: target.column)
                    : try await navigator.typeDefinition(path: target.path, line: target.line, column: target.column)
                if found.count == 1, let only = found.first {
                    open(only)
                } else if found.isEmpty {
                    navigationMessage = action == .definition ? "No definition found." : "No type definition found."
                } else {
                    await showLocations(found, title: action.title)
                }
            case .references:
                results = .loading(title: action.title)
                let found = try await navigator.references(path: target.path, line: target.line, column: target.column)
                await showLocations(found, title: "References")
            case .implementations:
                results = .loading(title: action.title)
                let found = try await navigator.implementations(path: target.path, line: target.line, column: target.column)
                await showLocations(found, title: "Implementations")
            case .callers:
                results = .loading(title: action.title)
                guard let root = try await navigator.callHierarchy(path: target.path, line: target.line, column: target.column) else {
                    results = .failed(title: "Callers", message: "That is not something that can be called.")
                    return
                }
                let node = CallerTreeNode(caller: root)
                node.isExpanded = true
                results = .callers(title: "Callers of \(root.name)", root: node)
                await node.loadChildren(using: navigator)
            }
        } catch {
            if case .loading = results {
                results = .failed(title: action.title, message: "\(error)")
            } else {
                navigationMessage = "\(error)"
            }
        }
    }

    private func showLocations(_ locations: [CodeLocation], title: String) async {
        let snippets = await LocationSnippets.load(locations)
        let groups = Dictionary(grouping: locations) { displayPath(for: $0.file) }
            .map { path, locations in
                LocationGroup(
                    displayPath: path,
                    items: locations.sorted { ($0.line, $0.column) < ($1.line, $1.column) }
                        .map { LocationItem(location: $0, snippet: snippets[$0] ?? "") }
                )
            }
            .sorted { $0.displayPath < $1.displayPath }
        let count = locations.count
        results = .locations(title: "\(title) · \(count == 1 ? "1 result" : "\(count) results")", groups: groups)
    }

    func displayPath(for file: URL) -> String {
        worktree.flatMap { CodeLocation(file: file, line: 1, column: 0).path(relativeTo: $0) } ?? file.path
    }

    /// For launch options: waits for the document and the servers, then acts
    /// at a head-side line. Gives up after a minute.
    func performWhenReady(_ action: NavigationAction, line: Int, column: Int, onlyWait: Bool = false) async {
        let deadline = ContinuousClock.now + .seconds(60)
        // Taken now: in the all-files view, scrolling reselects whichever
        // file is at the top while the servers start.
        let file = selectedFileIndex
        while ContinuousClock.now < deadline {
            let serversReady = !serverStatus.isEmpty && serverStatus.values.allSatisfy { $0 == .ready }
            if onlyWait, navigationState == .ready, serversReady, document != nil { return }
            if navigationState == .ready, serversReady, let row = document?.row(forNewLine: line, file: file) {
                await perform(action, at: Cursor(row: row, column: column))
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        navigationMessage = "Timed out waiting for navigation."
    }

    // MARK: Moving around

    /// Shows a location: in the changed file when the PR changes it, otherwise
    /// as a plain file. Records where the viewer was, for Back.
    func open(_ location: CodeLocation) {
        backStack.append(currentPosition)
        forwardStack.removeAll()
        show(location)
    }

    private func show(_ location: CodeLocation) {
        let shownKey = documentKey
        defer {
            // A jump within the document on screen loads nothing, so only
            // this call can open the gap or fold that hides the line.
            if documentKey == shownKey, let document { didShow(document) }
        }
        let relative = worktree.flatMap { location.path(relativeTo: $0) }
        let length = location.endLine == location.line ? max(location.endColumn - location.column, 0) : 0
        if let relative, let index = files.firstIndex(where: { $0.newPath == relative }) {
            // Selected as if by scrolling, so the selection itself does not
            // replace this reveal with one for the file's header.
            isFollowingScroll = true
            selectedFilePath = files[index].path
            isFollowingScroll = false
            externalFile = nil
            pendingReveal = Reveal(
                line: location.line, column: location.column, length: length, file: isContinuous ? index : nil
            )
        } else {
            selectedFilePath = nil
            externalFile = location.file
            pendingReveal = Reveal(line: location.line, column: location.column, length: length)
        }
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(currentPosition)
        restore(previous)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentPosition)
        restore(next)
    }

    private func restore(_ position: ViewerPosition) {
        mode = position.mode
        if let file = position.externalFile {
            selectedFilePath = nil
            externalFile = file
            pendingReveal = position.line.map { Reveal(line: $0, column: 0, length: 0) }
        } else {
            isFollowingScroll = true
            selectedFilePath = position.selectedFilePath
            isFollowingScroll = false
            externalFile = nil
            let index = isContinuous ? files.firstIndex { $0.path == position.selectedFilePath } : nil
            pendingReveal = position.line.map { Reveal(line: $0, column: 0, length: 0, file: index) }
        }
    }

    /// Called when a document appears. A jump to a line the diff does not
    /// show switches to the whole file, where every line is.
    func didShow(_ document: CodeDocument) {
        guard let reveal = pendingReveal, reveal.row(in: document) == nil else { return }
        if isContinuous, externalFile == nil, let line = reveal.line, let file = reveal.file {
            // In the all-files view, open whatever hides the line rather than
            // leaving the view: the file's fold, then the gap holding it.
            if document.headerRow(forFile: file) != nil, !document.rows.contains(where: { $0.file == file && $0.kind != .fileHeader }) {
                toggledFiles.formSymmetricDifference([files[file].path])
            } else if let gapRow = document.gapRow(containing: line, file: file) {
                expandGap(atRow: gapRow)
            } else {
                pendingReveal = nil
            }
        } else if mode == .diff, externalFile == nil {
            mode = .file
        } else {
            pendingReveal = nil
        }
    }
}
