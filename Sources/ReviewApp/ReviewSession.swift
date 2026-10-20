import Foundation
import Observation
import ReviewCore
import ReviewDiff
import ReviewKit

/// One open pull request: loading it, the file being looked at, and how.
@Observable
@MainActor
final class ReviewSession {
    enum Phase {
        case loading(ReviewLoader.Step?)
        case loaded(LoadedReview)
        case failed(String)
    }

    enum DocumentState {
        case idle
        case loading
        case loaded(CodeDocument, id: String)
        case failed(String)
    }

    let reference: PullRequestReference
    private(set) var phase: Phase = .loading(nil)
    private(set) var documentState: DocumentState = .idle

    /// Whether `load` has ever run, so re-selecting the PR does not refetch.
    private(set) var hasStarted = false
    var selectedFilePath: String?
    var mode: CodeDocument.Mode = .diff

    /// Documents already built this session, keyed like `documentKey`.
    private var documents: [String: CodeDocument] = [:]

    init(reference: PullRequestReference) {
        self.reference = reference
    }

    var review: LoadedReview? {
        if case .loaded(let review) = phase { review } else { nil }
    }

    var files: [FileDiff] { review?.files ?? [] }

    var selectedFile: FileDiff? {
        files.first { $0.path == selectedFilePath }
    }

    /// Changes whenever the viewer must show something else; drives the
    /// detail column's `.task(id:)`, which cancels a superseded load.
    var documentKey: String? {
        guard let review, let selectedFilePath else { return nil }
        return "\(review.pullRequest.head.sha):\(selectedFilePath):\(mode.rawValue)"
    }

    func load(with loader: ReviewLoader) async {
        hasStarted = true
        phase = .loading(nil)
        documents = [:]
        do {
            let review = try await loader.load(reference) { step in
                Task { @MainActor in self.didReach(step) }
            }
            phase = .loaded(review)
            if selectedFilePath == nil || selectedFile == nil {
                selectedFilePath = review.files.first?.path
            }
        } catch {
            phase = .failed("\(error)")
        }
    }

    func fail(_ message: String) {
        hasStarted = true
        phase = .failed(message)
    }

    private func didReach(_ step: ReviewLoader.Step) {
        if case .loading = phase { phase = .loading(step) }
    }

    func loadDocument() async {
        guard let review, let file = selectedFile, let key = documentKey else {
            documentState = .idle
            return
        }
        if let cached = documents[key] {
            documentState = .loaded(cached, id: key)
            return
        }
        documentState = .loading
        do {
            let document = try await review.document(for: file, mode: mode)
            guard !Task.isCancelled else { return }
            documents[key] = document
            documentState = .loaded(document, id: key)
        } catch {
            guard !Task.isCancelled else { return }
            documentState = .failed("\(error)")
        }
    }

    /// Moves the selection by `offset` files, stopping at either end.
    func selectFile(offset: Int) {
        guard let index = files.firstIndex(where: { $0.path == selectedFilePath }) else {
            selectedFilePath = files.first?.path
            return
        }
        let target = min(max(index + offset, 0), files.count - 1)
        selectedFilePath = files[target].path
    }
}
