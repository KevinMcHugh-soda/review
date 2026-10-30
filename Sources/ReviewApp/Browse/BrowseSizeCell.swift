import ReviewCore
import SwiftUI

/// The lines worth reading: implementation only, without generated or
/// vendored files, tests or documentation. Until they are counted, GitHub's
/// totals, faded. The tooltip has every category.
struct BrowseSizeCell: View {
    let listing: PullRequestListing
    let size: ReviewSize?

    var body: some View {
        let lines = size.map { $0[.implementation] }
        HStack(spacing: Theme.tightSpacing) {
            Text("+\(lines?.additions ?? listing.additions)").foregroundStyle(.green)
            Text("−\(lines?.deletions ?? listing.deletions)").foregroundStyle(.red)
        }
        .font(Theme.Fonts.counts)
        .opacity(size == nil ? 0.4 : 1)
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var help: String {
        guard let size else { return "Counting implementation lines… GitHub's total is \(Self.describe(additions: listing.additions, deletions: listing.deletions))." }
        let rows = ReviewSize.Category.allCases.map { category in
            let tally = size[category]
            return "\(category.title): \(Self.describe(additions: tally.additions, deletions: tally.deletions)) in \(tally.files) files"
        }
        let total = size.total
        return (rows + ["Total: \(Self.describe(additions: total.additions, deletions: total.deletions)) in \(total.files) files"])
            .joined(separator: "\n")
    }

    private var accessibilityLabel: String {
        guard let size else { return "\(listing.additions) added, \(listing.deletions) removed in total, counting implementation" }
        let lines = size[.implementation]
        return "\(lines.additions) implementation lines added, \(lines.deletions) removed"
    }

    private static func describe(additions: Int, deletions: Int) -> String {
        "+\(additions.formatted()) −\(deletions.formatted())"
    }
}
