# Code viewer

## NSTextView with TextKit 2, wrapped

The viewer is an `NSTextView` in an `NSViewRepresentable`, read-only but
selectable. The alternatives and why not:

- **SwiftUI `Text` in a `ScrollView`** — no character-level hit testing (which
  ⌘-click needs), no viewport-only layout, and a 5,000-line file lays out every
  line up front.
- **A WebView running Monaco** — the fastest way to a VS Code look, and the
  opposite of a native app: its own scrolling, selection, find, keybindings
  and fonts, none of them the system's.
- **STTextView** (a TextKit 2 editor component) — a good fit, but it is a
  third-party dependency; ask before adding it. Start with `NSTextView` and
  reach for it only if gutter or line-decoration work gets painful.

TextKit 2 lays out only the viewport, so large files scroll smoothly, and it
gives native find (⌘F), selection, copy, and accessibility for free.

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

- **Diff** — unified to start. One text view, removed and added lines
  interleaved, a two-column old/new line-number gutter. Split (side-by-side)
  is a second pair of text views with synchronised scrolling; add it once
  unified is solid.
- **After merge** — the whole file (see checkout-and-diff.md), with changed
  lines marked in the gutter and removed lines available on hover.

## Positions

LSP positions are `(line, character)` where character counts **UTF-16 code
units** by default. That is exactly `NSString`'s indexing, so a click's
character index converts to an LSP position without re-encoding — provided the
client does not negotiate `positionEncoding` to UTF-8. Keep UTF-16.

Positions in diff mode refer to the diff text, not the file; the viewer keeps a
table from diff-text line to `(side, file line)` so a ⌘-click on a removed line
can go to the base worktree and one on an added line to head.

## Highlighting

Two candidates, decided in M2:

- **tree-sitter** (SwiftTreeSitter plus the Go and TypeScript grammars) —
  fast, incremental, works on any text including the base side of a diff and
  deleted files, no server warm-up. Third-party C dependencies: needs your
  OK, and needs proving that the grammars build under SwiftPM with Command
  Line Tools only.
- **LSP semantic tokens** — no new dependency and semantically richer
  (distinguishes a type from a variable), but only for files a running server
  has open, so the base side needs its own server, and nothing is coloured
  until the server is warm.

Leaning tree-sitter for the base colouring, with semantic tokens layered on
top once a server is ready.
