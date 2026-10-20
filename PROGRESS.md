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

## Milestone 3 — navigate ✅

⌘-click to a definition, find references, implementations and callers,
back and forward, for Go and TypeScript, against a checkout of the PR's head.
Whole-file mode now shows the real after-merge text when the base has moved.

**Verified in the app** (scripted with `--navigate`, rendered with
`REVIEW_SNAPSHOT`):

- spf13/cobra#2397: Jump to Definition on `cmd.CommandPath()` in an added
  line → `command.go:1465`, a file the PR does not change, centred and
  selected, header "Not changed in this PR", Back enabled.
- spf13/cobra#2397: Find Callers on the new `NoDuplicateArgs` → its four new
  tests, each expandable.
- sindresorhus/ky#881: Find References on `previousChunk` → 5 results in
  `body.ts` with their lines, through TypeScript 7's native server.

**What exists:**

- `ReviewLSP`: `LSPConnection`, `LanguageServer`, `ServerCommand`,
  `JSONValue`, framing — see plans/lsp.md
- `ReviewGit`: `ensureWorktree` (made after the PR opens, moved when it gains
  commits), `mergeTree`, path-limited diffs
- `ReviewKit`: `Navigator`; `CodeDocument` sources (`pullRequest`,
  `afterMerge`, `other`) and plain-file documents; `LocationSnippets`
- `review doctor` reports which TypeScript server will run
  ("TypeScript 7.0.2 (native)")
- App: ⌘-click, context menu, Navigate menu with Xcode's shortcuts, results
  panel with a draggable divider, lazily expanding callers tree, Back/Forward
  in the toolbar, a file header, an after-merge banner, a status line showing
  each server's state and navigation's last message

**Tests: 65**, stable across three runs: 9 framing/decoding, 6 against real
gopls, 3 against the real TypeScript server, and 3 end-to-end in ReviewKit
(worktree follows head; definition from a diff row through `Navigator`;
after-merge text and marks).

**Not yet:** hover (implemented in `Navigator`, no UI), a ⌘-hover underline,
navigation on removed lines (needs a base checkout), the
typescript-language-server fallback is untested here, and the session's
navigation logic has no unit tests — it was exercised through the app.

## Milestone 4 — draft and ask ✅

Select lines, Add Comment (⌘⇧M or the context menu), write what you think;
ask Claude about it (⌘↩) or about every draft at once (⌥⌘↩), and follow up.
Drafts live in a trailing inspector (⌥⌘0), are marked in the gutter, and are
saved per PR.

**The safety boundary was verified before any code was written**, against
the real CLI — see the table in plans/claude-integration.md. In short:
`--tools "Read,Grep,Glob"` (without it `--restricted` still offers Edit and
Write), `--restricted` (file tools refused outside the directories by the tool
layer, not just declined by the model), a neutral working directory with the
checkout attached by `--add-dir` (a PR's `CLAUDE.md` canary never fires; the
control run shows the canary does work), and `--strict-mcp-config`.

**Verified in the app** on spf13/cobra#2397: a draft on lines 70–75 —
"what the hell is this map of empty structs? why not a map[string]bool?" —
answered in about six seconds for $0.05. Claude explained the set idiom,
offered the `map[string]bool` version, and checked cobra's own precedent by
reading `flag_groups.go`. The draft and conversation survive a relaunch, and
the inspector reopens with them.

**What exists:**

- `ReviewCore`: `DraftComment`, `CommentAnchor` (path, side, lines, the
  commit they refer to, the quoted lines), `ConversationTurn`, `ReviewNotes`
- `ReviewClaude`: `ClaudeClient` (one turn per process, streamed, cancellable,
  ten-minute timeout), `ClaudeStreamParser`
- `ReviewKit`: `ReviewAssistant`, `ReviewPrompts` (system prompt, first
  question with excerpt and diff, follow-ups through `--resume`, the
  all-drafts overview), `NotesStore` (JSON per PR — SQLite dropped as
  unnecessary)
- App: Review menu, gutter bubbles (click to select the draft), draft cards
  with the quoted code, a note editor, streaming answers rendered as Markdown
  with code blocks, the tool Claude is using shown while it reads, per-turn
  cost, Stop, stale-anchor and not-in-PR tags

**Tests: 76** (+1 opt-in live test, which passed): the parser on sanitised
real streams, the argument list, prompts, the notes store.

**Not yet:** follow-ups and Ask About All were not exercised in the app,
only through the CLI (`--resume` keeps context; the session id is stable).
No re-anchoring when the PR moves (drafts are tagged "older commit"). The
session's draft logic has no unit tests.

## Milestone 5 — post ✅ (not yet posted for real)

Existing review threads show in the gutter and the inspector; drafts become
one GitHub review. The Post sheet (⇧⌘P) shows where every draft will land and
why before anything is sent. See plans/github.md for the rules.

**Verified:**

- `review threads spf13/cobra#2356` lists its two resolved, outdated threads
  with every comment — the GraphQL path against real data.
- `review post spf13/cobra#2397 --dry-run` with five drafts, one of each kind:
  a range in the diff → RIGHT 70–75 with `start_line`; a draft from an older
  commit → re-anchored from line 3 to 73 by its quoted line; an empty draft →
  skipped; lines outside the diff and a file outside the PR → summary sections
  with permalinks at the exact commit and the code quoted.
- The Post sheet, rendered: the same five placements, and Post enabled
  because preflight (viewer login, own-PR check, pending-review check) ran
  against GitHub and passed.

**Not verified: an actual post.** No review has been sent — the PRs used in
development are other people's, and posting is public. The first real one
should be on a throwaway PR in a repository you own.

**What exists:**

- `ReviewCore`: `ReviewThread`, `ThreadComment`, `ReviewEvent`; drafts gain
  `isExcludedFromReview` and `posted`, decoded so older notes files still load
- `ReviewGitHub`: `viewerLogin`, `reviewThreads` (GraphQL, paginated),
  `pendingReviewURL`, `createReview`
- `ReviewKit`: `ReviewPlanner` (placements, re-anchoring, the summary, the
  payload), `ReviewPublisher` (preflight, plan, post, threads)
- CLI: `review threads <pr>`, `review post <pr> [--dry-run] [--event …]
  [--summary …] [--yes]`
- App: Post sheet, Keep private, a collapsed Posted section, an "On GitHub"
  section of thread cards, thread marks in the gutter; snapshots now capture
  an attached sheet as `<name>-sheet.png`

**Tests: 89** (+1 opt-in live): 12 for placement rules, thread decoding
across pages and deleted authors.

**Not yet:** replying to or resolving existing threads; adding drafts to an
existing pending review (GitHub's REST API cannot, GraphQL's
`addPullRequestReviewThread` could).

## Milestone 6 — daily driver ✅

**What exists:**

- **Open PRs survive a relaunch.** `open-pull-requests.json` keeps the
  sidebar's list in order; sessions are recreated but load only when first
  selected.
- **Review Requested inbox**, a second sidebar section from
  `gh search prs --review-requested=@me --state=open`, newest activity first,
  drafts tagged. Selecting one opens it. Refresh with ⌘R or the header button.
- **Viewed files.** A checkbox per file, ⌥⌘V to mark viewed and jump to the
  next unviewed file, "n of m files viewed" in the footer. Pinned to the
  file's head blob id, like GitHub: a push that changes the file unmarks it,
  one that does not leaves it marked. The diff is now `--full-index` so the
  ids are full whatever `core.abbrev` says. Local only — GitHub's own viewed
  state is not synced.
- **Change navigation**: ⌃⌘↓ / ⌃⌘↑ to the next/previous hunk in Diff view,
  the next/previous run of added lines in File view. Reveals can now target a
  row, for hunks of removed lines only.
- **`review open <pr>`** → `review://open?pr=…`, registered in Info.plist and
  routed to the existing window. Needs the app registered (`make register`
  for ./build, `make install` for /Applications).

**Verified:** with the app quit, `review open spf13/cobra#2397` launched it;
`review open https://github.com/sindresorhus/ky/pull/881/files` then went to
the same process (one process, both PRs in the saved list). A plain relaunch
rendered the restored sidebar, the inbox with the reviewer's real review
requests, viewed checkboxes and "0 of 5 files viewed".

**Tests: 96** (+1 opt-in live): blob ids from the `index` line, viewed state
across pushes, renames and deletes, inbox decoding, the open-PR store, and
full ids under a hostile `core.abbrev`.

**Not yet:** change navigation was not exercised visually; the restored
sidebar shows `#2397` for a PR until it loads (titles are not cached); inbox
titles render in a quieter colour than open PRs, which may want a look.

## After the plan

**Built and verified:**

- **Gaps between hunks** — "⋯ N unchanged lines" rows that expand on click,
  keeping the scroll position. Rendered on sindresorhus/ky#881; tests check
  every expanded line's numbers against both sides' files.
- **Split view** (⌘2; File moved to ⌘3) — base left, head right, synchronised
  vertical scrolling, filler rows so changes sit level, a one-column gutter per
  side. Rendered on ky#881.
- **Hover** — 0.6 s rest on a symbol shows the server's hover in a popover;
  rendered on cobra#2397 (`CommandPath`'s signature and doc comment from
  gopls). **⌘ underline** for jumpable symbols (not seen in a render — it needs
  a real pointer).
- **Posting, replying and resolving, for real** — on KevinMcHugh-soda/review#1
  (this work's own PR): a review with a single-line comment, a range comment and
  a summary section for a draft outside the diff; then a reply on one thread,
  and resolving it. Done through the CLI; the app's Post sheet and thread-card
  buttons call the same code but were not pressed.
- **Notification when Claude answers**, with click-through to the draft.
- **One window, always.** A single `Window` scene: one window at launch,
  `review://` links land in it, including one that launches the app.

**Not verified:**

- **The notification on screen.** It needs the one-time permission prompt
  answered by someone at the machine.

**Tests: 100** (+1 opt-in live), including gap rows, expansion, the split
layout, and added files.

## What next

1. The two review comments on review#1: remove `SplitCodeView`'s observers in
   `deinit`; flush pending note saves on quit.
2. Navigation on removed lines (a base worktree) and in the after-merge view.
3. Sync viewed state with GitHub (`markFileAsViewed`).
4. Cache PR titles for the sidebar; the inbox's quieter title colour.

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

**TypeScript 7 has no tsserver.** The global `typescript@7` is the native
rewrite; typescript-language-server failed `initialize` with "Could not find
a valid TypeScript installation". TS 7's `tsc --lsp --stdio` is a real LSP
server and is now preferred.

**SIGPIPE from a dead language server would kill the app.** Ignored
process-wide when a connection starts.

**An actor's `let` properties are isolated outside their module.** Mark them
`nonisolated let` when another module reads them synchronously.

**Centring a jump target before the lines above it are laid out misses.**
Non-contiguous layout estimates their heights; lay out up to the target first.

**`textViewDidChangeSelection` fires during `updateNSView`.** Writing the
cursor into observed state from there is a mutation mid-update; it is
deferred to the next turn of the run loop.

**`--restricted` alone is not read-only.** It drops the code-running tools but
still offers Edit, Write and NotebookEdit, confined to the working
directories — which include the checkout. `--tools "Read,Grep,Glob"` is what
makes it read-only.

**A model declining is not a guard.** The first probe asked Claude to write
outside its directories and it refused on its own; that proves nothing about
the tool layer. The second asked innocently and the Read tool itself refused,
which shows up in `permission_denials`.

**`--bare` is the wrong mode here.** Its help says `--add-dir` there *is* a
source of CLAUDE.md files, and it drops OAuth.

**Captured CLI output carries personal data.** The `system/init` line lists
plugins, paths and account details, and `input_json_delta` fragments spell
out paths piecewise. The fixtures were cut down before they were committed.

**GitHub rejects a whole review for one bad line.** A line comment on a line
outside the diff fails the entire `POST …/reviews` with 422. Everything is
placed by `ReviewPlanner` against the diff before sending, and what cannot be
a line comment goes into the summary.

**File-level comments cannot join a review.** `subject_type: "file"` exists
only on the single-comment endpoint, which posts at once as its own review.

**`gh api --slurp` and `--jq` are mutually exclusive.** Decode the slurped
pages yourself.

**A sheet is its own window.** Snapshotting the main window shows it dimmed
with nothing on top; `writeSnapshot` now also writes the attached sheet.

**Swift `"""` inside a Python `"""` edit ends the Python string.** Write the
Swift snippet to a file and splice it in.

**A URL-scheme launch cannot take `REVIEW_SNAPSHOT`.** `open review://…`
starts the app without the shell's environment; verify by the saved open-PR
list and the process count instead.

**Running the app binary directly from an agent shell can give it no window.**
Mid-session, every direct launch came up with a menu bar and nothing else,
while `open build/Review.app` worked. Snapshot runs use
`open -n --env REVIEW_SNAPSHOT=… build/Review.app --args …` now.

**A launch argument without a flag is a file to open.** AppKit reads
`-key value` pairs as defaults and treats a stray value as a document; a launch
that opens a document creates no window. `--hover 73 62` did that; it is
`--hover 73:62` now.

**`WindowGroup` and `review://` links do not mix.** Without
`handlesExternalEvents` every link opened a new window; on the scene,
`handlesExternalEvents(matching:)` made plain launches open none; on the view,
`preferring: ["*"]` made launches open two. A single `Window` scene with
`onOpenURL` behaves: one window at launch, links land in it, a link that
launches the app is handled once the model exists. Verified by counting the
process's windows through `CGWindowListCopyWindowInfo`, which needs no
permission.

**Added files crashed the unified diff once gaps existed.** They have no gaps,
and the gap list was indexed unguarded. A test on the fixture's added file
caught it.

**gopls separates a hover's signature and doc with `---`.** Rendered as text
until MarkdownText learned horizontal rules.
