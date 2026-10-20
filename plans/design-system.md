# Design system

The UI is governed by three skills (mandated by `CLAUDE.md`) and one source of
truth in code (`Theme`).

## The skills

- **macos-design** — layout, composition, native idioms, type scale and
  hierarchy. Use before deciding a design and when reviewing one.
- **swiftui-pro** — modern-API/correctness review of the code.
- **swift** — the Airbnb style guide, for every `.swift` file.

Run them before *and* after writing UI.

## `Theme` — one place for type and metrics

Every font and layout constant lives in `Sources/ReviewApp/Theme.swift`. Two
rules keep it honest (`SWIFTUI-RULES.md` §2.4, §5.1):

1. **Scale is semantic.** Fonts come from SwiftUI text styles, never
   hardcoded point sizes, so Dynamic Type and OS metric updates keep working.
   The code viewer is the one exception that will need care: an `NSTextView`
   takes an `NSFont`, so derive it from the monospaced body style's size rather
   than picking a number.
2. **Emphasis is weight; de-emphasis is color.** Headings get `.semibold`;
   quieter text gets `.secondary`, never a lighter weight.

## The intended shape

A three-column `NavigationSplitView`, the Mail/Xcode shape:

| Column | Holds |
|---|---|
| Sidebar | Open pull requests (later: the review-requested inbox) |
| Content | The selected PR's changed files, as a tree, with viewed/commented marks |
| Detail | The code viewer, with drafts and threads in an inspector on the trailing edge |

Navigation results (references, callers) appear in a panel below the code,
like Xcode's find navigator, so the file under review stays in view. Claude's
answers appear in the draft's thread in the inspector, not in a separate chat
window — the answer belongs next to the code it is about.

Light and dark come from system colors and materials. The one palette the app
owns is syntax and diff coloring, and it lives in `Theme` with both
appearances defined together.
