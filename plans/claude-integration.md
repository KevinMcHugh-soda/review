# Asking Claude

## The shape

A draft comment is a private note on a line or range: "what the hell is
this", "isn't this nil when the cache misses?". Any draft can be sent to
Claude. The answer appears in that draft's thread; follow-ups continue the
same conversation. Separately, "Ask about all drafts" sends every draft at
once, for a pass over the whole review.

Nothing goes to GitHub until it is posted (github.md), and Claude's answers
never post themselves. A draft can be rewritten after an answer — often into
a better question for the author, or deleted because the answer settled it.

## Invocation

One `claude -p` process per turn, so there is no daemon to manage:

```sh
claude -p \
  --output-format stream-json --verbose --include-partial-messages \
  --allowedTools "Read" "Grep" "Glob" \
  --disallowedTools "Bash" "Edit" "Write" "NotebookEdit" "WebFetch" "WebSearch" \
  --add-dir <worktree> \
  --append-system-prompt <review context> \
  [--resume <session-id>] \
  <question>
```

- **stream-json** gives incremental text for the UI and, in the final
  `result` event, the `session_id`, cost and duration. The session id is
  stored with the thread, and `--resume` continues it, so a follow-up keeps
  everything Claude already read.
- **The prompt** carries the PR title and description, the file path and
  line range, the code at that range and its enclosing hunk, and the draft
  text. Claude can then Read/Grep the worktree for the rest — callers,
  definitions, tests.
- `claude` is found and run with the login-shell environment, and uses the
  reviewer's own Claude Code authentication.

## The safety boundary

The PR is untrusted input: its code, comments, commit messages and
description can all contain text written to steer an AI ("ignore your
instructions and…"). Claude's tools are therefore **read-only** — no Bash,
no edits, no network. The worst a hostile PR can then do is make an answer
wrong, which is why answers stay advisory and never post themselves.

**The PR's own `CLAUDE.md`.** Claude Code loads `CLAUDE.md` from its working
directory as instructions. A PR could add or change one. So Claude does not
run *in* the worktree: its working directory is a neutral per-review scratch
directory, and the worktree is attached with `--add-dir`, which by default
does not load that directory's `CLAUDE.md`. Verify that in M4 before relying
on it, and consider offering the base branch's `CLAUDE.md` (trusted, already
merged) as context instead.

**The reviewer's own settings still load** — their global `CLAUDE.md`, hooks
and MCP servers. That is their environment and their choice; note it in the
UI rather than overriding it. If it becomes a problem, `--setting-sources`
can narrow what loads.

## Costs and limits

Each turn reports its cost in the `result` event; show it per thread and per
review. A per-turn timeout (generous — Claude may read many files) cancels a
stuck process.
