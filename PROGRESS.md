# Progress

Read this with [PLAN.md](PLAN.md) to get up to speed.

## Milestone 1 — walking skeleton ✅

The target graph builds, tests pass, both executables run, and the app
launches as a signed bundle.

**Verified on this machine (macOS 15.8.1, Swift 6.1.2, Command Line Tools only):**

- `make check` — compiles with no warnings; `lint-layers` clean
- `make test` — 17 tests pass, including one against the real login shell
- `make run` — `build/Review.app` builds, signs ad-hoc (no `review-dev`
  identity yet) and launches with its menu bar. **The window itself has not
  been visually checked:** `screencapture` from the agent's terminal has no
  Screen Recording permission and captured only the desktop.
- `review doctor`, run under `env -i` with launchd's bare PATH to imitate a
  Finder launch, still finds everything via the login shell:

```
environment: from /bin/zsh -l -i
✓ git      /usr/bin/git                       git version 2.39.5
✓ gh       /opt/homebrew/bin/gh               gh version 2.99.0
✓ gopls    ~/go/bin/gopls                     gopls v0.24.0
– typescript-language-server   not found — npm install -g typescript-language-server typescript
✓ claude   ~/.local/bin/claude                2.1.304 (Claude Code)
```

**What exists:**

- `ReviewCore.PullRequestReference` — parses PR URLs (with `/files`, query,
  fragment, no scheme) and `owner/repo#n`
- `ReviewProcess.Subprocess` — runs a child to completion, draining both
  streams concurrently, with stdin and a timeout that is never confused with
  the child dying of some other signal
- `ReviewProcess.ToolEnvironment` — the login shell's environment, with a
  fallback to well-known tool directories
- `ReviewKit.Doctor` — finds each tool, its version, and whether gh is signed in
- App shell: paste a PR to add it to the sidebar; a footer shows tool status
  with a popover of details
- CLI: `review doctor`, `review version`

## Milestone 2 — read a pull request ✅

Paste a PR; the app asks GitHub about it, clones or updates a blobless bare
clone, diffs merge base → head, and shows the changed files and a
highlighted code viewer with Diff (default) and File modes.

**Verified against real PRs**, in the app (rendered with `REVIEW_SNAPSHOT`)
and headless with `review show`:

```
spf13/cobra#2397  Go   3 files   cold 1.8 s (clone 804K), warm 1.3 s
sindresorhus/ky#881  TypeScript   5 files   1.7 s
```

Go and TypeScript highlight correctly, including method calls, JSDoc blocks
and multi-hunk files; bands, gutter numbers and +/− marks line up. Checked in
dark mode only.

**What exists:**

- `ReviewGitHub.GitHubClient` — PR metadata through `gh api`
- `ReviewGit.GitClient` — git with credentials from gh, no prompts, and
  every diff-format option pinned; `CheckoutStore` — clones staged then
  renamed into place, fetches into `refs/review/…` from `origin`
- `ReviewDiff.UnifiedDiffParser` — renames, binary, mode-only, added/deleted,
  quoted and spaced paths, CRLF, missing newlines, header lookalikes in
  content
- `ReviewSyntax` — tree-sitter for Go, TypeScript, TSX/JS; vendored queries
  (`scripts/vendor-queries.swift`), per-query precedence, spans cut per line
- `ReviewKit.CodeDocument` — the viewer's rows; each side highlighted whole,
  then sliced onto diff rows; whole-file mode maps every unchanged head line
  to its merge-base line
- App: three columns (PRs, files, code); TextKit 1 `CodeTextView` with
  full-width bands; `LineNumberGutter` with base/head numbers and +/− marks;
  View menu: ⌘1 Diff, ⌘2 Whole File, ⌥⌘↓/↑ next/previous file
- CLI: `review show <pr> [path] [--file] [--spans]`
- Dev: `--open`, `--file`, `--mode file` launch options and `REVIEW_SNAPSHOT`

**Tests: 45**, including an end-to-end suite against a fixture repository
whose global git config sets `diff.noprefix`, `diff.mnemonicPrefix`,
`diff.renames=false`, `diff.context=10`, `diff.external`, `color.diff=always`
and `core.quotePath`. It asserts every diff line's number names that exact
line in its side's file. Proven non-vacuous: removing the prefix pins fails
it.

**Not yet:** expanding context between hunks, split (side-by-side) diff, a
file tree for large PRs, light-mode visual check, after-merge via
`git merge-tree` (M3, with worktrees).

## Next: milestone 3 — navigate

Worktrees for head (and merge, when the base has moved), then `ReviewLSP`:
the JSON-RPC client, gopls and typescript-language-server per worktree,
⌘-click to definition, find references and incoming calls in a panel below
the code. See plans/lsp.md.

## Things that bit us

**A doc named `claude.md` is a `CLAUDE.md`.** `plans/claude.md` was loaded by
Claude Code as instructions for `plans/`, because macOS filesystems are
case-insensitive. Renamed to `claude-integration.md`; CLAUDE.md now forbids
the name. Same root cause as the `ReviewApp`/`review` binary naming.

**Swift 6.1 has no raw identifiers.** The swift skill asks for
`` func `Sentence names`() `` test names; that is Swift 6.2. On 6.1 use
`@Test("Sentence names") func sentenceNames()`.

**`Mutex` cannot be captured by an escaping closure.** It is non-copyable.
The subprocess watchdog wraps it in a small `final class … : Sendable`.

**tree-sitter queries disagree about precedence.** Go's lists specific
patterns first and expects the first match to win; JavaScript's opens with
`(identifier) @variable` and expects the last to win. Applying one rule to
both coloured `cmd.CommandPath()` as a property. Caught from `review show
--spans` on a real PR; each query is now tagged with its convention.

**The JSX query does not compile against the TypeScript grammar.** Its node
types exist only in TSX. Verified, which is why `.ts` and `.tsx` compile
different query concatenations.

**SwiftUI macros do not expand with Command Line Tools.** `@Entry` fails
with "plugin for module 'SwiftUIMacros' not found". Hand-written keys work.

**A partial clone only filters fetches from its promisor remote.** Fetching
by URL instead of `origin` would download every blob in the new history.

**`git add -A` re-reads the file mode from disk.** The fixture's
`update-index --chmod=+x` was silently undone by the `add` after it; the
mode-change assertion caught it.

**A navigation title set in the detail column never reached the window.**
Set it on the `NavigationSplitView`.

**Creating sessions inside a view body mutates observed state mid-update.**
Sessions are made when a PR is opened; lookups are read-only.
