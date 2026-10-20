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

- **Clone** with `git clone --bare --filter=blob:none`. Bare, because
  nothing ever checks out the clone itself; blobless, so the first open of a
  large monorepo downloads history only and file contents arrive as a diff
  or a checkout needs them. cobra's clone is 804K.
- **Credentials** come from `gh` on every git call
  (`-c credential.helper= -c credential.helper='!gh auth git-credential'`),
  whatever the user configured. A blobless clone can need the network even
  for `cat-file`, so it is not only fetches that need them.
- **Fetch** `refs/pull/<n>/head` and the base branch on every open, into
  `refs/review/…`, so a PR that gained commits since last time is current.
  Fetches name `origin`, never the URL: a partial clone applies its blob
  filter only when fetching from its promisor remote.
- **Contents** for the viewer come from `git cat-file blob <sha>:<path>` —
  no worktree is needed to read a PR, only to navigate one (M3).
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

Every option that changes the output format is pinned, because user config
can change each of them: `--src-prefix=a/ --dst-prefix=b/` (against
`diff.noprefix`/`diff.mnemonicPrefix`), `--find-renames` (`diff.renames`),
`--unified=3` (`diff.context`), `--no-color`, `--no-ext-diff`,
`--no-textconv`, and `core.quotePath=false`. The end-to-end test runs under
a global config that sets all of them; dropping the prefix pin fails it.

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

**Decided:** the diff is the default mode; after-merge is one click away.

**As built in M2,** the File mode shows the file at head. The merge-tree
result arrives with worktrees in M3; until then File is exactly right
whenever the base has not touched the same file.

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
