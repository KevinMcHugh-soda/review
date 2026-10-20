# GitHub

All GitHub access goes through `gh`, run with the login-shell environment.
`gh` holds the reviewer's credentials, handles SSO for org repositories, and
pages results with `--paginate`. The app never sees a token.

## Reading

| What | Call |
|---|---|
| PR metadata (title, body, author, base/head SHAs, state) | `gh api repos/{o}/{r}/pulls/{n}` |
| Changed files (names and status only — diffs are computed locally, see checkout-and-diff.md) | `gh api --paginate repos/{o}/{r}/pulls/{n}/files` |
| Existing review threads, with resolved/outdated state | `gh api graphql` — `pullRequest.reviewThreads`, since REST has no resolved flag |
| The reviewer's pending review, if one exists | `gh api repos/{o}/{r}/pulls/{n}/reviews`, filtered to `state == PENDING` for the viewer |
| Review-requested inbox (M6) | `gh search prs --review-requested=@me --state=open --json …` |

## Posting — as built

All drafts go in **one** `POST …/pulls/{n}/reviews`: line comments in
`comments[]`, everything else as sections of `body`. One request means the
review lands whole or not at all — GitHub rejects the entire review (422) if a
single line comment is on a line its diff does not show. `event` is
`COMMENT`, `APPROVE` or `REQUEST_CHANGES`; leaving it out creates a pending
review, finished on GitHub. `commit_id` is the head the plan was made
against.

File-level comments (`subject_type: "file"`) were planned for drafts outside
the hunks, but they exist only on the single-comment endpoint, which posts
immediately as its own review — that would break the one-request rule. Those
drafts go into the summary instead.

### Where each draft goes (`ReviewPlanner`)

| Draft | Goes to |
|---|---|
| Head-side lines in a hunk (added or context) | Line comment, `side: RIGHT` |
| Base-side lines in a hunk (removed or context) | Line comment, `side: LEFT` |
| A range inside one hunk | `start_line`/`start_side` + `line`/`side` |
| A range across two hunks | Its last line only (GitHub refuses a range across hunks), flagged |
| Lines outside the hunks | Summary: path and lines, a permalink at the exact commit, the code quoted, the note |
| A file the PR does not change | Summary, the same way; no link for paths outside the repository |
| Written against an older head | Re-anchored by its quoted lines if they occur **exactly once** in the new head; otherwise the summary, marked "on an earlier commit". Never silently moved. |
| Empty, "Keep private", or already posted | Not sent |

The Post sheet lists every draft with its destination and why, before
anything is sent.

### Preflight

- `gh api user` — who is posting. GitHub refuses approving or requesting
  changes on your own PR, so the sheet offers only Comment there.
- Any `PENDING` review by the viewer — GitHub allows one per PR, and creating
  a second fails. The sheet links to it and disables Post.

### After posting

Posted drafts are kept, marked with the date and the review's URL, and move
to a collapsed "Posted" section. Threads are reloaded.

## Reading threads

`gh api graphql --paginate --slurp` with the cursor variable named
`$endCursor` (gh's convention for GraphQL pagination); `--slurp` cannot be
combined with `--jq`, so the pages are decoded in Swift. A deleted author
comes back as `author: null` and shows as "ghost". Outdated threads keep
`originalLine` and lose `line`; they are listed but not marked in the gutter.

## Not verified against GitHub

The request has been checked by `review post --dry-run` and the sheet, but
**no review has been posted by this app yet**: posting is outward-facing, and
the only PRs used in development belong to other people. Do the first real
post on a throwaway PR in a repository you own.
