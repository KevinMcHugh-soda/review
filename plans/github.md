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

## Posting

Drafts become one review, created as **pending** so nothing is visible until
the reviewer submits:

```
POST repos/{o}/{r}/pulls/{n}/reviews
{ "commit_id": <head sha the drafts were written against>,
  "comments": [ { "path", "body", "line", "side", "start_line", "start_side" } ] }
```

then `POST …/reviews/{id}/events` with `COMMENT`, `APPROVE` or
`REQUEST_CHANGES` and the summary body.

### Line mapping is the hard part

GitHub addresses review comments by `(path, line, side)`: `side` is `LEFT`
(base) or `RIGHT` (head), `line` is the file line on that side, and a range
adds `start_line`/`start_side`. `ReviewDiff` owns this mapping and it gets
the heaviest testing in the codebase.

**A line comment must fall inside a diff hunk.** GitHub rejects (422) a
comment on a line the diff does not show. Since this app shows whole files and
lets you comment anywhere, drafts outside hunks need a fallback:

- a **file-level** comment (`subject_type: "file"`) on a changed file, quoting
  the line and linking to it, or
- a line in the **review summary** with a permalink, for files the PR does not
  touch at all.

The posting sheet shows which drafts will land where before anything is sent.

### Drafts written against an older head

If the author pushes while you are reviewing, the drafts' lines refer to the
old head. Post with the `commit_id` they were written against — GitHub then
shows them as outdated, which is honest — or re-anchor them first. Never
silently move a comment to a different line.
