import Foundation
import Testing
import ReviewKit

@Suite
struct ListReorderingTests {
    private let list = ["a", "b", "c", "d"]

    /// SwiftUI reports a drag of row 0 to just below row 2 as offset 3.
    @Test("Moves a dragged row down, counting the destination before removal")
    func dragDown() {
        #expect(ListReordering.moving(list, fromOffsets: [0], toOffset: 3) == ["b", "c", "a", "d"])
        #expect(ListReordering.moving(list, fromOffsets: [0], toOffset: 4) == ["b", "c", "d", "a"])
    }

    @Test("Moves a dragged row up")
    func dragUp() {
        #expect(ListReordering.moving(list, fromOffsets: [3], toOffset: 0) == ["d", "a", "b", "c"])
        #expect(ListReordering.moving(list, fromOffsets: [2], toOffset: 1) == ["a", "c", "b", "d"])
    }

    @Test("Moves several rows together, keeping their order")
    func dragSeveral() {
        #expect(ListReordering.moving(list, fromOffsets: [0, 2], toOffset: 4) == ["b", "d", "a", "c"])
    }

    @Test("Leaves the list alone for a drop where the row already is")
    func dropInPlace() {
        #expect(ListReordering.moving(list, fromOffsets: [1], toOffset: 1) == list)
        #expect(ListReordering.moving(list, fromOffsets: [1], toOffset: 2) == list)
    }

    @Test("Moves one item up, down, or to the top, stopping at the ends")
    func stepwise() {
        #expect(ListReordering.moving("c", by: -1, in: list) == ["a", "c", "b", "d"])
        #expect(ListReordering.moving("b", by: 1, in: list) == ["a", "c", "b", "d"])
        #expect(ListReordering.moving("a", by: -1, in: list) == list)
        #expect(ListReordering.moving("d", by: 1, in: list) == list)
        #expect(ListReordering.moving("d", by: -list.count, in: list) == ["d", "a", "b", "c"])
        #expect(ListReordering.moving("z", by: 1, in: list) == list)
    }

    /// The sidebar groups open PRs by status; a drag in one group names
    /// offsets within it. Upper-case letters are one group here.
    @Test("Moves within a group, leaving the other groups' rows where they were")
    func dragWithinGroup() {
        let mixed = ["A", "x", "B", "y", "C"]
        let isUpper = { (item: String) in item == item.uppercased() }
        #expect(ListReordering.moving(mixed, where: isUpper, fromOffsets: [2], toOffset: 0) == ["C", "x", "A", "y", "B"])
        #expect(ListReordering.moving("A", by: 1, in: mixed, where: isUpper) == ["B", "x", "A", "y", "C"])
        #expect(ListReordering.moving("x", by: 1, in: mixed, where: { !isUpper($0) }) == ["A", "y", "B", "x", "C"])
    }
}
