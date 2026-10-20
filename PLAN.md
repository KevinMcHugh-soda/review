# Review

A native macOS app for reviewing GitHub pull requests, built around five
capabilities:

1. **A real code viewer** — the diff, or the whole file as it will be after the
   merge, in a native text view that copes with large files
2. **Code navigation** — ⌘-click to a definition or type, find references,
   find all callers, through the same language servers VS Code and Zed use
   (gopls, typescript-language-server)
3. **Private draft comments** — mark up the code in your own words first
4. **Ask Claude** — "what the hell is this" on any draft, answered by
   `claude -p` with read-only access to the checked-out PR
5. **Post the review** — turn the drafts you keep into a GitHub review

The code under review is almost entirely Go and TypeScript, so those two get
first-class support and nothing else is planned.

Built on the same setup as [uncurl](../uncurl): SwiftUI, SwiftPM, a Makefile,
and no Xcode IDE — which itself came from
[tqbf/swiftui-app](https://github.com/tqbf/swiftui-app).

## Documentation index

| Document | Covers |
|---|---|
| [plans/architecture.md](plans/architecture.md) | Target graph, layering rule, the process model |
| [plans/build-system.md](plans/build-system.md) | Makefile, build.sh, bundling, code signing |
| [plans/checkout-and-diff.md](plans/checkout-and-diff.md) | Managed clones, worktrees, what "the diff" and "after merge" mean |
| [plans/code-viewer.md](plans/code-viewer.md) | Why NSTextView/TextKit 2, highlighting, the diff gutter |
| [plans/lsp.md](plans/lsp.md) | The language-server client, gopls and typescript-language-server |
| [plans/claude-integration.md](plans/claude-integration.md) | How drafts are sent to `claude -p`, and the safety boundary |
| [plans/github.md](plans/github.md) | Reading PRs and posting reviews through `gh` |
| [plans/design-system.md](plans/design-system.md) | Theme, type scale, UI shape |
| [SWIFTUI-RULES.md](SWIFTUI-RULES.md) | House SwiftUI style — takes precedence where it conflicts |
| [PROGRESS.md](PROGRESS.md) | What is built, what is next |

## Quick start

```sh
make check                       # compile + layering gate
make test                        # swift test, no GUI needed
make run                         # build, bundle, sign, launch
make cli && ./.build/debug/review doctor
./.build/debug/review show spf13/cobra#2397 args.go --spans
```

## Milestones

1. ✅ **Walking skeleton** — target graph, app shell, CLI, login-shell
   environment, tool doctor, signing
2. ✅ **Read a pull request** — fetch with `gh`, managed blobless clone,
   file list, code viewer, diff and whole-file modes, tree-sitter highlighting
3. ✅ **Navigate** — a worktree per PR and language servers on it; ⌘-click to
   definition and type definition, find references, implementations and
   callers; back/forward; after-merge via `git merge-tree`
4. ✅ **Draft and ask** — draft comments on lines and ranges, stored locally;
   ask Claude about one draft or all of them, read-only, with follow-ups
5. ✅ **Post** — existing review threads shown inline; drafts become one
   GitHub review — comment, approve, request changes, or left pending
6. **Daily driver** — review-requested inbox, viewed-file tracking,
   keyboard-driven file and hunk navigation, `review open <url>`
