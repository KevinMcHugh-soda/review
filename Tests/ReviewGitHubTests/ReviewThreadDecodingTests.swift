import Foundation
import ReviewCore
import Testing
@testable import ReviewGitHub

@Suite
struct ReviewThreadDecodingTests {
    /// The shape `gh api graphql --paginate --slurp` prints: an array of
    /// pages. Modelled on spf13/cobra#2356's threads.
    @Test("Decodes threads across pages, including outdated ones and deleted authors")
    func decodes() throws {
        let page = { (nodes: String) in
            #"{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[\#(nodes)]}}}}}"#
        }
        let first = #"{"id":"T1","isResolved":true,"isOutdated":true,"path":"completions.go","line":null,"startLine":null,"originalLine":369,"diffSide":"RIGHT","comments":{"nodes":[{"author":{"login":"ccoVeille"},"body":"About that","createdAt":"2026-03-01T10:00:00Z","url":"https://github.com/spf13/cobra/pull/2356#discussion_r1"}]}}"#
        let second = #"{"id":"T2","isResolved":false,"isOutdated":false,"path":"args.go","line":12,"startLine":10,"originalLine":12,"diffSide":"LEFT","comments":{"nodes":[{"author":null,"body":"Gone","createdAt":"2026-03-02T10:00:00Z","url":null}]}}"#
        let data = Data("[\(page(first)),\(page(second))]".utf8)

        let threads = try GitHubClient.decodeThreads(data)
        #expect(threads.map(\.id) == ["T1", "T2"])
        #expect(threads[0].lines == nil)
        #expect(threads[0].isOutdated && threads[0].isResolved)
        #expect(threads[0].comments.first?.author == "ccoVeille")
        #expect(threads[1].side == .base)
        #expect(threads[1].lines == 10...12)
        #expect(threads[1].comments.first?.author == "ghost")
    }
}
