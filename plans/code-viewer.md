# Code viewer

## NSTextView with TextKit 2, wrapped

The viewer is an `NSTextView` in an `NSViewRepresentable`, read-only but
selectable — on **TextKit 1**, chosen while building it: the gutter and the
full-width bands need each row's line-fragment rect, which `NSLayoutManager`
gives directly, and a read-only view gains nothing from TextKit 2's editing
model. Non-contiguous layout keeps large files fast; lines never wrap, so one
row is one fragment. The alternatives and why not:

- **SwiftUI `Text` in a `ScrollView`** — no character-level hit testing (which
  ⌘-click needs), no viewport-only layout, and a 5,000-line file lays out every
  line up front.
- **A WebView running Monaco** — the fastest way to a VS Code look, and the
  opposite of a native app: its own scrolling, selection, find, keybindings
  and fonts, none of them the system's.
- **STTextView** (a TextKit 2 editor component) — a good fit, but it is a
  third-party dependency; ask before adding it. Start with `NSTextView` and
  reach for it only if gutter or line-decoration work gets painful.

Either TextKit gives native find (⌘F), selection, copy, and accessibility
for free.

Highlighting a 3,700-line Go file takes 37 ms in a release build (0.16 s in
debug); 18,000 lines take 0.14 s.

## What the view is given

The wrapper is dumb. `ReviewDiff` and `ReviewSyntax` produce plain values and
the view renders them:

- the text
- per-line marks: added, removed, context, hunk header, collapsed gap
- highlight spans: `(range, tokenKind)`; colors come from `Theme`
- comment anchors: line ranges with a draft or an existing thread

Diff backgrounds are drawn per line fragment, not as attributed-string
backgrounds, so they span the full width rather than ending at the last
character.

## Two modes

The diff is the default.

- **Diff** — unified to start. One text view, removed and added lines
  interleaved, a two-column old/new line-number gutter. Split (side-by-side)
  is a second pair of text views with synchronised scrolling; add it once
  unified is solid.
- **After merge** — the whole file (see checkout-and-diff.md), with changed
  lines marked in the gutter and removed lines available on hover.

## Navigation in the view

⌘-click is Jump to Definition; the context menu and the Navigate menu offer
the rest, with Xcode's shortcuts (⌃⌘J, ⌃⇧⌘J, ⌃⌘R, ⌃⌘I, ⌃⇧⌘H; back/forward
⌃⌘← / ⌃⌘→). Results — references, implementations, callers — open in a
resizable panel below the code. A jump into a changed file stays in Diff if
the line is in a hunk and switches to the whole file if not; anywhere else
opens as a plain file, labelled "Not changed in this PR" or "Outside the
repository".

**Revealing a line lays out everything above it first.** With
non-contiguous layout, lines not yet laid out have estimated heights; centring
on the target and then letting real layout happen pushed it ten lines off
screen.

## Positions

LSP positions are `(line, character)` where character counts **UTF-16 code
units** by default. That is exactly `NSString`'s indexing, so a click's
character index converts to an LSP position without re-encoding — provided the
client does not negotiate `positionEncoding` to UTF-8. Keep UTF-16.

Positions in diff mode refer to the diff text, not the file; the viewer keeps a
table from diff-text line to `(side, file line)` so a ⌘-click on a removed line
can go to the base worktree and one on an added line to head.

## Highlighting

**Decided: tree-sitter**, via ChimeHQ's SwiftTreeSitter and the official
`tree-sitter-go` and `tree-sitter-typescript` packages. Proven to resolve and
build under SwiftPM with Command Line Tools only before it was adopted.

- Each side of a diff is highlighted as a **whole file** (old at the merge
  base, new at head), then the spans are cut per line onto the diff rows. A
  hunk on its own does not parse — it starts mid-string or mid-comment as often
  as not.
- Capture ranges come back in UTF-16 units, so they are `NSRange`s into the
  text view's string as-is.
- The highlight queries are **vendored as Swift string literals** in
  `ReviewSyntax`, not loaded from the grammar packages' resource bundles: the
  TypeScript query only adds to JavaScript's (which is in a third package), the
  JSX patterns must stay out of the plain-TypeScript query or it fails to
  compile, and it keeps `Bundle.module` lookups out of a hand-assembled `.app`.
  Licences are in `ThirdPartyLicenses/`.
- **Precedence is per query.** Longer spans paint first so nested nodes
  win. For several patterns on one node, the upstream queries disagree: Go's
  lists specific patterns first and expects the first to win; JavaScript's
  opens with `(identifier) @variable` and expects the last to win. Each
  vendored query is tagged with its convention (`Precedence`), and a test pins
  each — a Go method call once came out as a property.

LSP semantic tokens may be layered on top in M3, once a server is warm.
