import Foundation

/// Moving items within an ordered list — the sidebar's open PRs.
public enum ListReordering {
    /// SwiftUI's `onMove` contract: take the items at `offsets` and put them,
    /// in their existing order, before the item that was at `destination` —
    /// a position counted in the list *before* they were removed, so dragging
    /// one row down past another names an offset one higher than it lands at.
    public static func moving<T>(_ list: [T], fromOffsets offsets: IndexSet, toOffset destination: Int) -> [T] {
        let moved = offsets.filter(list.indices.contains).map { list[$0] }
        var remaining = list.indices.filter { !offsets.contains($0) }.map { list[$0] }
        let removedBefore = offsets.count { $0 < destination }
        let insertion = min(max(destination - removedBefore, 0), remaining.count)
        remaining.insert(contentsOf: moved, at: insertion)
        return remaining
    }

    /// One item moved up (`-1`) or down (`+1`) a place, or as far as the list
    /// allows; unchanged when it is not in the list.
    public static func moving<T: Equatable>(_ item: T, by offset: Int, in list: [T]) -> [T] {
        guard let index = list.firstIndex(of: item) else { return list }
        let target = min(max(index + offset, 0), list.count - 1)
        guard target != index else { return list }
        var result = list
        result.remove(at: index)
        result.insert(item, at: target)
        return result
    }
}
