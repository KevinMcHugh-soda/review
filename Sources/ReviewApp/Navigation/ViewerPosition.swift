import Foundation
import ReviewKit

/// Where the viewer is, for back and forward.
struct ViewerPosition: Equatable {
    let selectedFilePath: String?
    let externalFile: URL?
    let mode: CodeDocument.Mode
    /// The head-side line the cursor was on, if any.
    let line: Int?
}

/// A request to scroll to and select a place once its document is showing.
/// `id` makes each request distinct, so asking for the same line twice still
/// scrolls the second time.
struct Reveal: Equatable {
    /// A head-side line, or — for next/previous change — a row directly,
    /// since a hunk of only removed lines has no head line to aim at.
    let line: Int?
    let row: Int?
    let column: Int
    let length: Int
    let id = UUID()

    init(line: Int, column: Int, length: Int) {
        self.line = line
        row = nil
        self.column = column
        self.length = length
    }

    init(row: Int) {
        line = nil
        self.row = row
        column = 0
        length = 0
    }

    func row(in document: CodeDocument) -> Int? {
        row ?? line.flatMap(document.row(forNewLine:))
    }
}

/// The cursor in the current document: a row and a UTF-16 column in it.
struct Cursor: Equatable {
    let row: Int
    let column: Int
}
