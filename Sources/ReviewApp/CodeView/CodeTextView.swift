import AppKit
import ReviewKit

/// A read-only NSTextView that draws full-width diff bands behind its rows.
///
/// TextKit 1, deliberately: the gutter and the bands need each row's line
/// fragment rect, which `NSLayoutManager` hands over directly, and a read-only
/// viewer gains nothing from TextKit 2's editing model. Non-contiguous layout
/// keeps large files fast.
final class CodeTextView: NSTextView {
    /// One kind per row, and the UTF-16 offset where each row starts.
    private(set) var rowKinds: [CodeDocument.Row.Kind] = []
    private(set) var rowStarts: [Int] = []
    private(set) var rows: [CodeDocument.Row] = []

    /// ⌘-click and the context menu's navigation items. The character index
    /// is in the text view's string.
    var onNavigate: ((NavigationAction, Int) -> Void)?
    var onAddComment: (() -> Void)? {
        didSet { refreshCommentButton() }
    }
    /// Clicking a collapsed gap between hunks, by row.
    var onExpandGap: ((Int) -> Void)?
    /// Clicking a file's header in the all-files view, by row.
    var onHeaderClick: ((Int) -> Void)?
    /// Asks what to show when the pointer rests on a symbol; nil for nothing.
    /// Nil itself on a pane that has no navigation (the base side of a split).
    var onHover: ((Int) async -> String?)?

    private var hoverTask: Task<Void, Never>?
    private var hoverPopover: NSPopover?
    private var hoveredWord: NSRange?
    private var underlinedWord: NSRange?
    private var pointerTracking: NSTrackingArea?
    /// The first code row of a highlighted selection. The gutter draws an
    /// add-comment button there. Nil for a caret, or a pane that cannot comment.
    var commentButtonRow: Int? {
        didSet { updateCommentButtonChrome() }
    }

    /// Rows covered by a draft, which the gutter marks.
    var draftRows: [Int: UUID] = [:] {
        didSet { enclosingScrollView?.verticalRulerView?.needsDisplay = true }
    }
    /// Rows with a thread already on GitHub.
    var threadRows: [Int: String] = [:] {
        didSet { enclosingScrollView?.verticalRulerView?.needsDisplay = true }
    }

    static func make() -> CodeTextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.allowsNonContiguousLayout = true
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
        // Code does not wrap: one row is one line fragment, which the bands
        // and the gutter both rely on.
        container.widthTracksTextView = false
        layoutManager.addTextContainer(container)

        let view = CodeTextView(frame: .zero, textContainer: container)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.isHorizontallyResizable = true
        view.isVerticallyResizable = true
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.autoresizingMask = [.width, .height]
        view.textContainerInset = Theme.Code.textInset
        view.backgroundColor = Theme.Code.background
        view.drawsBackground = true
        return view
    }

    /// Replaces the text. With `keepingScroll`, the scroll position stays —
    /// for the same file re-shown with a gap expanded, where everything above
    /// the gap is where it was.
    func show(_ rows: [CodeDocument.Row], text: NSAttributedString, keepingScroll: Bool = false) {
        let origin = enclosingScrollView?.contentView.bounds.origin
        dismissHover()
        self.rows = rows
        rowKinds = rows.map(\.kind)
        var starts: [Int] = []
        starts.reserveCapacity(rows.count)
        var offset = 0
        for row in rows {
            starts.append(offset)
            offset += (row.text as NSString).length + 1
        }
        rowStarts = starts
        textStorage?.setAttributedString(text)
        if keepingScroll, let origin, let clip = enclosingScrollView?.contentView {
            // Lay out down to the old position first: with non-contiguous
            // layout, unlaid lines have estimated heights, and the position
            // would drift.
            if let layoutManager, let textContainer {
                let above = NSRect(x: 0, y: 0, width: clip.bounds.width, height: origin.y + clip.bounds.height)
                layoutManager.ensureLayout(forBoundingRect: above, in: textContainer)
            }
            clip.scroll(to: origin)
            enclosingScrollView?.reflectScrolledClipView(clip)
        } else {
            setSelectedRange(NSRange(location: 0, length: 0))
            scroll(.zero)
        }
        needsDisplay = true
    }

    /// The row whose text contains a UTF-16 offset.
    func row(containing offset: Int) -> Int {
        var low = 0
        var high = rowStarts.count - 1
        guard high >= 0 else { return 0 }
        while low < high {
            let middle = (low + high + 1) / 2
            if rowStarts[middle] <= offset { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// A character index as a row and a column within it.
    func cursor(at index: Int) -> Cursor? {
        guard !rowStarts.isEmpty else { return nil }
        let row = row(containing: index)
        return Cursor(row: row, column: index - rowStarts[row])
    }

    /// The rows a selection touches. A selection ending at the very start of
    /// a row (a triple-click, or a drag to the line below) does not include it.
    func rows(in range: NSRange) -> ClosedRange<Int>? {
        guard !rowStarts.isEmpty else { return nil }
        let first = row(containing: range.location)
        let end = range.length > 0 ? range.location + range.length - 1 : range.location
        return first...max(first, row(containing: end))
    }

    /// Scrolls a row to the middle of the view, selects the range and flashes
    /// it, so the eye finds where a jump landed.
    /// `atTop` puts the row at the top of the view instead — for a file's
    /// header, so the file being read is the one the header names.
    func reveal(row: Int, column: Int, length: Int, atTop: Bool = false) {
        guard rowStarts.indices.contains(row) else { return }
        let rowLength = (rows[row].text as NSString).length
        let start = rowStarts[row] + min(column, rowLength)
        let range = NSRange(location: start, length: min(length, rowLength - min(column, rowLength)))
        if let layoutManager, let textContainer {
            // Everything up to the target, not just the target: with
            // non-contiguous layout the lines above are only estimated until
            // laid out, and the real heights would push the target off screen
            // after it was centred.
            layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: rowStarts[row] + rowLength))
            let glyphs = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: rowStarts[row], length: max(rowLength, 1)), actualCharacterRange: nil
            )
            var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            rect.origin.y += textContainerOrigin.y
            let visible = enclosingScrollView?.contentView.bounds.height ?? rect.height
            if !atTop { rect.origin.y -= (visible - rect.height) / 2 }
            rect.size.height = visible
            rect.origin.x = 0
            scrollToVisible(rect)
        }
        setSelectedRange(range)
        if range.length > 0 { showFindIndicator(for: range) }
        window?.makeFirstResponder(self)
    }

    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        // Wait until the drag ends, so the button appears once the highlight is chosen.
        if !stillSelectingFlag { refreshCommentButton() }
    }

    /// Shows the gutter's add-comment button on the first code row of a real
    /// selection. A caret is not a highlight, and the base side of a split has
    /// no `onAddComment`.
    func refreshCommentButton() {
        let range = selectedRange()
        let row: Int? =
            if onAddComment == nil || range.length == 0 {
                nil
            } else if let rows = rows(in: range) {
                rows.first { self.rows.indices.contains($0) && self.rows[$0].isCode }
            } else {
                nil
            }
        if commentButtonRow != row { commentButtonRow = row }
    }

    private func updateCommentButtonChrome() {
        guard let gutter = enclosingScrollView?.verticalRulerView else { return }
        gutter.needsDisplay = true
        gutter.window?.invalidateCursorRects(for: gutter)
    }

    override func mouseDown(with event: NSEvent) {
        dismissHover()
        let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        // ⌘-click jumps to the definition, as in every editor.
        if event.modifierFlags.contains(.command), onNavigate != nil {
            setSelectedRange(NSRange(location: index, length: 0))
            onNavigate?(.definition, index)
            return
        }
        // A click on a collapsed gap opens it; on a file header, folds the file.
        if !rowStarts.isEmpty {
            let clicked = row(containing: index)
            switch rows[clicked].kind {
            case .gap:
                onExpandGap?(clicked)
                return
            case .fileHeader:
                onHeaderClick?(clicked)
                return
            case .context, .added, .removed, .hunkHeader, .filler:
                break
            }
        }
        super.mouseDown(with: event)
    }

    // MARK: Pointer: hover and the ⌘ underline

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTracking { removeTrackingArea(pointerTracking) }
        let area = NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(area)
        pointerTracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        pointerMoved(to: event.locationInWindow, commandDown: event.modifierFlags.contains(.command))
    }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        guard let window else { return }
        pointerMoved(to: window.mouseLocationOutsideOfEventStream, commandDown: event.modifierFlags.contains(.command))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setUnderline(nil)
        hoverTask?.cancel()
    }

    override func keyDown(with event: NSEvent) {
        dismissHover()
        super.keyDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        dismissHover()
        super.scrollWheel(with: event)
    }

    /// The identifier under a point, if any: a word made of letters, digits
    /// and underscores, on a row of code.
    private func symbol(at point: NSPoint) -> NSRange? {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: local, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        // Past the end of a line, the nearest glyph is the last one; ignore it.
        guard glyphRect.contains(local) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        guard !rowStarts.isEmpty, rows[row(containing: index)].isCode else { return nil }
        let range = selectionRange(forProposedRange: NSRange(location: index, length: 0), granularity: .selectByWord)
        guard range.length > 0 else { return nil }
        let word = (textStorage.string as NSString).substring(with: range)
        let identifier = word.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "_" }
        return identifier ? range : nil
    }

    private func pointerMoved(to windowPoint: NSPoint, commandDown: Bool) {
        let word = symbol(at: convert(windowPoint, from: nil))
        // ⌘ held over a symbol: underline it and show it can be clicked.
        let jumpable = commandDown && onNavigate != nil ? word : nil
        setUnderline(jumpable)
        if jumpable != nil { NSCursor.pointingHand.set() } else { NSCursor.iBeam.set() }

        guard word != hoveredWord else { return }
        hoveredWord = word
        hoverTask?.cancel()
        hoverPopover?.performClose(nil)
        guard let word, let onHover else { return }
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: Theme.Code.hoverDelay)
            guard !Task.isCancelled, let markdown = await onHover(word.location), !Task.isCancelled else { return }
            self?.showHover(markdown, for: word)
        }
    }

    /// For launch options: hovers over the symbol at a character index as if
    /// the pointer had rested there.
    func triggerHover(at index: Int) async {
        guard let onHover, let textStorage, index < textStorage.length else { return }
        let word = selectionRange(forProposedRange: NSRange(location: index, length: 0), granularity: .selectByWord)
        guard let markdown = await onHover(index) else { return }
        showHover(markdown, for: word)
    }

    private func setUnderline(_ range: NSRange?) {
        guard range != underlinedWord, let layoutManager else { return }
        if let old = underlinedWord {
            layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: old)
        }
        if let range {
            layoutManager.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, forCharacterRange: range)
        }
        underlinedWord = range
    }

    private func showHover(_ markdown: String, for word: NSRange) {
        guard let layoutManager, let textContainer, window != nil else { return }
        let glyphs = layoutManager.glyphRange(forCharacterRange: word, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        let popover = NSPopover()
        popover.behavior = .semitransient
        popover.animates = false
        popover.contentViewController = HoverContent.controller(markdown: markdown)
        popover.show(relativeTo: rect, of: self, preferredEdge: .maxY)
        hoverPopover = popover
    }

    private func dismissHover() {
        hoverTask?.cancel()
        hoveredWord = nil
        hoverPopover?.performClose(nil)
        hoverPopover = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        dismissHover()
        let menu = super.menu(for: event) ?? NSMenu()
        // A pane without navigation (the base side of a split) gets the
        // standard menu only.
        guard onNavigate != nil else { return menu }
        let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
        // Right-clicking outside the selection moves the cursor there, so
        // the menu acts on what was clicked.
        if !NSLocationInRange(index, selectedRange()) || selectedRange().length == 0 {
            setSelectedRange(NSRange(location: index, length: 0))
        }
        let items = NavigationAction.allCases.map { action in
            let item = NSMenuItem(title: action.title, action: #selector(navigate(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            item.showShortcut(action.shortcut)
            return item
        }
        let comment = NSMenuItem(title: "Add Comment", action: #selector(addComment(_:)), keyEquivalent: "")
        comment.target = self
        comment.showShortcut(.addComment)
        for (offset, item) in ([comment, .separator()] + items).enumerated() {
            menu.insertItem(item, at: offset)
        }
        menu.insertItem(.separator(), at: items.count + 2)
        return menu
    }

    @objc private func addComment(_ sender: NSMenuItem) {
        onAddComment?()
    }

    @objc private func navigate(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = NavigationAction(rawValue: raw) else { return }
        onNavigate?(action, selectedRange().location)
    }

    /// Visible rows and their line rects, in this view's coordinates.
    func visibleRows(in rect: NSRect) -> [(row: Int, rect: NSRect)] {
        guard let layoutManager, let textContainer, !rowStarts.isEmpty else { return [] }
        let containerRect = rect.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
        let glyphs = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let length = textStorage?.length ?? 0

        var result: [(row: Int, rect: NSRect)] = []
        var row = self.row(containing: characters.location)
        while row < rowStarts.count, rowStarts[row] <= NSMaxRange(characters) {
            let start = rowStarts[row]
            var lineRect =
                if start < length {
                    layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: start), effectiveRange: nil)
                } else {
                    // An empty final row has no glyph; it lives in the extra fragment.
                    layoutManager.extraLineFragmentRect
                }
            lineRect.origin.y += textContainerOrigin.y
            result.append((row, lineRect))
            row += 1
        }
        return result
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        for (row, lineRect) in visibleRows(in: rect) {
            guard let band = Theme.Code.band(for: rowKinds[row]) else { continue }
            band.setFill()
            NSRect(x: rect.minX, y: lineRect.minY, width: rect.width, height: lineRect.height).fill()
        }
    }
}
