import Foundation
import ReviewDiff
import Testing
@testable import ReviewKit

/// Gaps between hunks and the side-by-side layout, on the fixture's main.go:
/// 40 lines at base; the PR changes line 3, inserts a line after 20 and
/// removes the old line 35, which gives three hunks.
@Suite
struct GapsAndSplitTests {
    private func mainGo() async throws -> (LoadedReview, FileDiff, FixtureRepository) {
        let fixture = try await FixtureRepository.make()
        let review = try await CheckoutAndDiffTests.load(fixture)
        let file = try #require(review.files.first { $0.path == "main.go" })
        return (review, file, fixture)
    }

    @Test("Collapses the unchanged runs between and after hunks into gap rows")
    func gapRows() async throws {
        let (review, file, fixture) = try await mainGo()
        defer { fixture.remove() }
        let document = try await review.document(for: file, mode: .diff)
        let gaps = document.rows.filter { $0.kind == .gap }
        // Line 3's hunk starts at line 1, so there is no leading gap; then
        // two gaps between hunks and one after the last.
        #expect(gaps.count == 3)
        #expect(gaps.allSatisfy { $0.text.hasPrefix("⋯ ") && $0.text.contains("unchanged lines") })
        // Every head line appears exactly once, as a row or inside a gap.
        let shown = Set(document.rows.compactMap(\.newLine))
        let hidden = gaps.compactMap { row -> Int? in Int(row.text.split(separator: " ")[1]) }.reduce(0, +)
        #expect(shown.count + hidden == 40)
    }

    @Test("Expands a gap into numbered context lines that match both sides' files")
    func expandedGap() async throws {
        let (review, file, fixture) = try await mainGo()
        defer { fixture.remove() }
        let collapsed = try await review.document(for: file, mode: .diff)
        let first = try #require(collapsed.rows.first { $0.kind == .gap }?.gapLines)
        let expanded = try await review.document(for: file, mode: .diff, revealed: IndexSet(integersIn: first))
        #expect(!expanded.rows.contains { $0.gapLines == first })
        #expect(expanded.rows.count > collapsed.rows.count)

        let old = try #require(try await review.text(of: file, on: .base).map(CodeDocument.lines))
        let new = try #require(try await review.text(of: file, on: .head).map(CodeDocument.lines))
        for row in expanded.rows where row.kind == .context {
            let oldLine = try #require(row.oldLine)
            let newLine = try #require(row.newLine)
            #expect(old[oldLine - 1] == row.text)
            #expect(new[newLine - 1] == row.text)
        }
    }

    @Test("Shows part of a gap, leaving the rest collapsed on either side")
    func partlyRevealedGap() async throws {
        let (review, file, fixture) = try await mainGo()
        defer { fixture.remove() }
        let collapsed = try await review.document(for: file, mode: .diff)
        let gap = try #require(collapsed.rows.first { $0.kind == .gap })
        let lines = try #require(gap.gapLines)
        let middle = lines.lowerBound + 3
        let document = try await review.document(for: file, mode: .diff, revealed: [middle])

        let shown = try #require(document.row(forNewLine: middle))
        #expect(document.rows[shown].kind == .context)
        #expect(document.rows[shown - 1].gapLines == lines.lowerBound...(middle - 1))
        #expect(document.rows[shown + 1].gapLines == (middle + 1)...lines.upperBound)
    }

    @Test("Offers five lines at each end of a gap, and only the end that has code beside it")
    func stepExpansions() async throws {
        let (review, file, fixture) = try await mainGo()
        defer { fixture.remove() }
        let document = try await review.document(for: file, mode: .diff)
        let gaps = document.rows.filter { $0.kind == .gap }
        let between = try #require(gaps.first)
        let lines = try #require(between.gapLines)
        #expect(between.expansions.map(\.label) == ["↓ 5 lines", "↑ 5 lines"])
        #expect(between.expansions.map(\.lines) == [
            lines.lowerBound...(lines.lowerBound + 4), (lines.upperBound - 4)...lines.upperBound,
        ])
        // Each label sits in the row's text where its columns say.
        for expansion in between.expansions {
            let text = between.text as NSString
            let range = NSRange(location: expansion.columns.lowerBound, length: expansion.columns.count)
            #expect(text.substring(with: range) == expansion.label)
        }
        // After the last hunk there is nothing below to continue upwards.
        let trailing = try #require(gaps.last)
        #expect(!trailing.expansions.contains { $0.label.hasPrefix("↑") })
    }

    @Test("Lines a change up side by side, padding the shorter side")
    func split() async throws {
        let (review, file, fixture) = try await mainGo()
        defer { fixture.remove() }
        let document = try await review.document(for: file, mode: .split)
        let left = try #require(document.leftRows)
        #expect(left.count == document.rows.count)

        for (base, head) in zip(left, document.rows) {
            switch (base.kind, head.kind) {
            case (.context, .context):
                #expect(base.text == head.text)
                #expect(base.newLine == nil && head.oldLine == nil)
            case (.removed, .added), (.removed, .filler), (.filler, .added),
                 (.hunkHeader, .hunkHeader), (.gap, .gap):
                break
            default:
                Issue.record("unexpected pair \(base.kind) | \(head.kind)")
            }
        }
        // Line 3 changed: its old and new versions sit level.
        let changed = try #require(document.rows.firstIndex { $0.text == "line 3 changed" })
        #expect(left[changed].text == "line 3")
        // The inserted line has nothing beside it.
        let inserted = try #require(document.rows.firstIndex { $0.text == "inserted after 20" })
        #expect(left[inserted].kind == .filler)
        // The removed line has nothing beside it either.
        let removed = try #require(left.firstIndex { $0.kind == .removed && $0.text == "line 35" })
        #expect(document.rows[removed].kind == .filler)
    }

    @Test("Has no gaps for an added file, which is one hunk end to end")
    func addedFileHasNoGaps() async throws {
        let fixture = try await FixtureRepository.make()
        defer { fixture.remove() }
        let review = try await CheckoutAndDiffTests.load(fixture)
        let added = try #require(review.files.first { $0.path == "new.ts" })
        #expect(try await review.document(for: added, mode: .diff).rows.allSatisfy { $0.kind != .gap })
    }
}
