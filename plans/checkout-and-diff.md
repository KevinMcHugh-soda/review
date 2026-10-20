# Checkouts and diffs

## Why check the PR out at all

GitHub's API can give a diff and file contents, which would be enough for a
diff viewer. It is not enough for navigation: a language server needs a real
directory tree with `go.mod`/`tsconfig.json` and every file the changed code
refers to. So each PR gets a worktree on disk.

## Managed clones, not the reviewer's own

One clone per repository under `Application Support/Review/repos/`, with a
worktree per PR. Reusing the reviewer's working copy was rejected: adding
worktrees and fetching PR refs into someone's day-to-day clone is a surprise,
and a dirty or mid-rebase clone would break checkouts in ways the app cannot
explain.

- **Clone** with `gh repo clone <slug> -- --filter=blob:none --no-checkout`.
  `gh` supplies the credentials; the blobless partial clone keeps the first
  open of a large monorepo to history only, with blobs fetched as worktrees
  need them.
- **Fetch** `refs/pull/<n>/head` and the base branch on every open, so a PR
  that gained commits since last time is current.
- **Worktree** with `git worktree add --detach <path> <head-sha>`. Detached,
  so no branch names collide across PRs. Removed when the PR is closed in the
  app; `git worktree prune` on launch tidies up after a crash.

A later option, if first clones prove slow: `--reference` an existing local
clone of the same repository to borrow its objects without touching its
working tree.

## What "the diff" is

GitHub's PR diff is the **three-dot** diff: merge-base(base, head) → head. It
shows what the PR changes, not what has happened on main since it branched.
`git diff <merge-base> <head>` reproduces it exactly, so the app computes
diffs locally rather than trusting the API's `patch` field — which GitHub
omits for large files and truncates for large PRs.

Diff options that match GitHub's view: `--find-renames`, `--no-color`,
`--no-ext-diff`, `-U<n>` with a context the viewer can expand from the full
file it already has.

## "After merge"

The second viewing mode shows each file whole, as it will be on the base
branch once this PR merges — the code you are actually approving, with full
context, rather than hunks.

When the base branch has not moved since the PR branched, that is simply the
head. When it has, the head is stale: it lacks whatever landed on main since.
`git merge-tree --write-tree <base> <head>` (git ≥ 2.38; Apple's git is 2.39)
computes the real merge result without touching any working tree. The app
checks out that tree as the `merge` worktree so navigation works on it too,
and shows a banner when the merge would conflict — in which case it falls back
to head and says so.

**Open question for M2:** should the default mode be the diff, or after-merge
with changed lines marked in the gutter? The second is closer to reviewing in
an editor; the first is what GitHub trains everyone to expect.

## Untrusted code on disk

A PR branch is code from someone else. Checking it out is safe; running it is
not. Rules:

- **Never run `npm install`/`go generate`/`make` automatically.** Package
  scripts run arbitrary code. TypeScript navigation without `node_modules`
  still resolves everything inside the repo; types from dependencies degrade
  to `any`. An explicit, per-PR "Install dependencies" action may come later,
  with the risk stated on the button.
- **gopls is acceptable.** It runs `go list` and reads the module cache;
  it does not execute package code. It may download modules, which is the same
  thing `go build` would do.
- **tsserver plugins** listed in a PR's `tsconfig.json` load only from
  `node_modules`, which is absent unless installed — another reason not to.
- Claude's boundary is in claude-integration.md.
