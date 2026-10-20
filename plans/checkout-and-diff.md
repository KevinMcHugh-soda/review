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
  no worktree is needed to read a PR, only to navigate one.
- **Worktree** of head, made in the background after the PR opens, with
  `worktree add --detach --force`; moved with `checkout --force --detach`
  when the PR gains commits. `worktree prune` first, because a worktree
  deleted by hand leaves a registration that blocks re-adding the path. For a
  blobless clone this is when every file at head is fetched, so it is the
  slow step on a large repository; navigation says "Checking out…" until
  then.
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
`--no-textconv`, `--full-index` (against `core.abbrev`; viewed-file tracking
compares blob ids across loads), and `core.quotePath=false`. The end-to-end test runs under
a global config that sets all of them; dropping the prefix pin fails it.

## "After merge"

The second viewing mode shows each file whole, as it will be on the base
branch once this PR merges — the code you are actually approving, with full
context, rather than hunks.

When the base branch has not moved since the PR branched, that is simply the
head. When it has, the head is stale: it lacks whatever landed on main since.
`git merge-tree --write-tree <base> <head>` (git ≥ 2.38; Apple's git is 2.39)
computes the real merge result without touching any working tree, and its
tree id reads like a commit: `cat-file blob <tree>:<path>`. No commit is made,
so no committer identity is needed, and no second checkout either.

**As built:** whole-file mode uses the merge tree only for files where the
merged text differs from head — i.e. the base changed them too. Their marks
come from diffing the base tip against the merge tree, which is exactly what
merging adds, numbered as the merged file. A banner says so. Navigation is
off in that view because its line numbers no longer match the head checkout
the servers run on; Diff view (⌘1) navigates. A conflicted merge falls back to
head.

**Decided:** the diff is the default mode; after-merge is one click away.



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
