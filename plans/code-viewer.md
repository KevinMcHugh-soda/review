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

## Three modes

The diff is the default. ⌘1 Diff, ⌘2 Split, ⌘3 File.

- **Diff** — unified to start. One text view, removed and added lines
  interleaved, a two-column old/new line-number gutter. Split (side-by-side)
  is a second pair of text views with synchronised scrolling; add it once
  unified is solid.
- **Split** — side by side, base left and head right, one `CodePane` each,
  scrolling together vertically and independently sideways. Within a hunk a
  run of removed lines pairs row for row with the run of added lines after
  it; the shorter side gets filler rows, so a line and its replacement sit
  level. The right pane is the full document (navigation, comments, hover);
  the left is for reading — navigation runs on head, and base-side comments
  are made in the unified diff.
- **After merge** — the whole file (see checkout-and-diff.md), with changed
  lines marked in the gutter.

### All files in one scroll

The default, as on GitHub's "Files changed" page: every file one after
another, each under a header row (`path · Modified · +12 −3`). ⌘4 or the
toolbar's All Files button switches to one file at a time. Works in Diff,
Split and File modes.

- **One document.** `LoadedReview.allFilesDocument` builds each file's
  document (eight at a time — each needs two `git cat-file`s) and
  `CodeDocument(combining:)` joins them; every row carries its file's index.
  Everything that used to ask "the selected file" asks the row instead:
  navigation, drafts, gutter marks, gaps, hover.
- **The file list follows the scroll.** The pane reports the row just below
  the top edge; its file becomes the selection. Picking a file scrolls its
  header to the top (not the middle — centred, the previous file's tail sat at
  the top and the list jumped back to it). ⌥⌘↓/↑ go file to file.
- **Collapsed files.** Viewed files and generated files show as their
  header only ("… · viewed · click to show"); clicking a header folds or
  unfolds that file.
- **Jumps into hidden code** open what hides it — the file's fold, then the
  gap holding the line — instead of leaving the view.
- File mode across all files may mix head and after-merge text; the
  document records which files are after-merge, and navigation and comments
  are off on those rows only.

### Generated files

Files marked `linguist-generated` (set or `true`) in `.gitattributes` at the
PR's head — GitHub's rule — or at the base branch's current tip go to the end of the file list and the scroll,
tagged "generated", collapsed until clicked. Found with
`git check-attr --cached` against a throwaway index read from head's tree:
the clone is bare, and Apple's git 2.39 predates `check-attr --source`.
`-diff` and `binary` attributes are not treated as generated.

The base tip counts because a PR cut before the base added a rule would
otherwise miss it: harmony#13296 branched before `internal/*api/client.go`
was marked generated, and showed 449 removed generated lines as hand-written.
The tip is `refs/review/base/<branch>` from the fetch, not the API's
`base.sha`, which GitHub moves only when the PR itself changes — for that PR
it was still the merge base.

### Gaps between hunks

The unchanged runs a diff leaves out show as one row, "⋯ 67 unchanged
lines" — before the first hunk, between hunks, and after the last. Clicking
one expands it into numbered context lines (both sides' numbers, and
navigable). Expansion is per file and per session; re-showing the same file
and mode keeps the scroll position, so the code above an expanded gap does
not move. Added and deleted files have no gaps — and the first version crashed
on them, caught by a test.

### Hover and the ⌘ underline

Resting the pointer on a symbol for 0.6 s asks the language server for its
hover and shows it in a popover, rendered as Markdown (code fences, rules).
Holding ⌘ underlines the symbol under the pointer and shows a pointing hand —
what ⌘-click would jump to.

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

**JSON and YAML** too, from `tree-sitter-json` 0.24.8 and
`tree-sitter-yaml` 0.7.0 (tree-sitter-grammars). Keys take the property
colour so they read apart from values; JSON's `string.special.key` capture is
mapped to it. Precedence again differs: JSON names keys before strings (first
wins), YAML strings before keys (last wins), and a test fails if either is
flipped. `.json`, `.jsonc`, `.json5`, `.yaml`, `.yml`.

`tree-sitter-yaml` is pinned to exactly 0.7.0: from 0.7.1 its manifest adds
`scanner.c` only if `FileManager.fileExists(atPath: "src/scanner.c")` — a
relative path, which SwiftPM does not evaluate from the package's directory,
so the scanner is silently dropped and linking fails on
`tree_sitter_yaml_external_scanner_*`.

**SQL** from DerekStride's `tree-sitter-sql`, pinned to a commit on its
`gh-pages` branch (e038788e): its release tags ship `scanner.c` without the
generated `parser.c`, so a tag does not build. Its highlight query is written
for Neovim, whose `#match?` takes Lua patterns, so `scripts/vendor-queries.swift`
rewrites `%d` to `[0-9]` (stated in the generated file); without that, numbers
colour as strings, which a test catches. `.sql`, `.psql`, `.pgsql`.

LSP semantic tokens may be layered on top later, once a server is warm.
