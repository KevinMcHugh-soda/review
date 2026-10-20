# Architecture

## Layering rule

Everything except SwiftUI views lives in library targets. The app and the CLI
are both thin frontends over the same core, and the hard parts are testable
with `swift test` without launching a GUI.

SwiftUI is a system framework, so nothing structurally prevents `import SwiftUI`
appearing in `ReviewLSP`. `make lint-layers` greps for it and fails the build —
it runs as part of `make check`, and covers every directory under `Sources/`
except the two frontends, so a new target is covered the moment it exists.

The code viewer is the one place this bends: it has to be an `NSTextView`
(see code-viewer.md), and that wrapper lives in `ReviewApp` with the views.
What it *displays* — lines, diff marks, highlight spans, comment anchors — is
computed in logic targets and handed over as plain values.

## Target graph

Targets are added by the milestone that needs them; an empty placeholder
target is noise.

```
ReviewCore       PullRequestReference, PullRequest, Side, CodeLocation,
                 DraftComment/CommentAnchor/ReviewNotes, ReviewThread,
                 ReviewEvent. No I/O.
ReviewProcess    Subprocess, ToolEnvironment. The only target that spawns.
  ReviewDiff     FileDiff/Hunk/DiffLine and UnifiedDiffParser.             ✅ M2
  ReviewGit      GitClient (pinned diff options), CheckoutStore clones.    ✅ M2
  ReviewGitHub   gh api: PR metadata, review threads (GraphQL), posting.  ✅ M2, M5
  ReviewSyntax   tree-sitter highlighting, vendored queries.               ✅ M2
  ReviewLSP      JSON-RPC over stdio; LanguageServer; ServerCommand picks
                 gopls or a TypeScript server.                             ✅ M3
  ReviewClaude   claude -p, read-only, stream-json; ClaudeStreamParser.   ✅ M4
    ReviewKit    ReviewLoader, LoadedReview, CodeDocument (the viewer's
                 rows), Navigator, ReviewAssistant + ReviewPrompts,
                 NotesStore, ReviewPlanner + ReviewPublisher, Doctor.
      ReviewApp  SwiftUI views, @Observable models, the NSTextView wrapper.
      ReviewCLI  ArgumentParser commands. Product name: `review`.
```

`ReviewKitTests` is the end-to-end suite: a fixture repository standing in
for GitHub, cloned, fetched and diffed for real, under a global git config
built to break every step.

## Naming: why the app binary is `ReviewApp`

Same reason as uncurl. macOS filesystems are case-insensitive by default, so
binaries named `Review` and `review` are the same file in the build directory
and inside `Contents/MacOS/`. The bundle is `Review.app` with display name
Review; only `CFBundleExecutable` differs. That leaves `review` free for the
CLI.

## Everything is a child process

The app talks to five programs, none bundled: git, gh, gopls,
typescript-language-server and claude. That is deliberate — each is what the
reviewer already has installed and authenticated, so the app holds no GitHub
token, no Anthropic key and no copy of a language server.

Two consequences shape the core:

**The environment comes from the login shell.** A Finder-launched app gets
launchd's PATH (`/usr/bin:/bin:/usr/sbin:/sbin`), which finds none of
`~/go/bin/gopls`, `~/.local/bin/claude` or Homebrew's `gh`. GOPRIVATE,
GOFLAGS and GOPATH go missing with it, which breaks gopls on private modules
even when gopls is found. `ToolEnvironment.loginShell()` runs
`$SHELL -l -i -c env` once at launch and every child gets that environment.
Interactive as well as login, because most people set PATH in `.zshrc`.

**No App Sandbox.** A sandboxed app cannot exec tools from the user's home
directory or let them read arbitrary repositories. This is a local developer
tool, never an App Store app, so the sandbox stays off and there is no
entitlements file.

Two kinds of child:

- **Run to completion** — git, gh, one `claude -p` turn. `Subprocess.run`
  drains stdout and stderr concurrently (sequential draining deadlocks once a
  child fills the 64 KiB pipe buffer on the other stream) and enforces a
  timeout.
- **Long-lived conversations** — language servers. Owned by an actor in
  `ReviewLSP` that frames JSON-RPC over the child's stdio; see lsp.md.

## Where state lives

```
~/Library/Application Support/Review/
  repos/<owner>/<repo>.git           managed clone, shared by every PR in that repo
  worktrees/<owner>/<repo>/<n>/head  the PR head, detached, for the servers
  reviews/<owner>/<repo>/<n>.json    drafts and Claude conversations
  claude/<owner>/<repo>/<n>/         the empty directory claude -p runs in
```

Nothing is written into the reviewer's own clones. See checkout-and-diff.md.
