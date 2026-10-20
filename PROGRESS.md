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

## Next: milestone 2 — read a pull request

Decisions to make first (see the plans):

1. Highlighting — tree-sitter (a third-party dependency, needs a yes) or LSP
   semantic tokens only. code-viewer.md.
2. Default mode — the diff, or after-merge with changes marked.
   checkout-and-diff.md.

Then, in order: `ReviewGitHub` PR metadata → `ReviewGit` managed clone, fetch
and worktree → `ReviewDiff` unified-diff parser and line mapping (heavily
tested) → the NSTextView viewer → the file list.

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
