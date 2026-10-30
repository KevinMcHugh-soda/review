# File order

GitHub, and git, list a PR's changed files alphabetically. That order is
happenstance: in Harmony, `cmd/` sorts before `db/`, though the schema is where
a reviewer wants to start. The reviewer can say what order they want, once per
repository.

## Rules

`FileOrder` (ReviewKit) is an ordered list of directories (or single files),
plus at most one `*` — everything else.

* A file takes the position of the **longest** listed directory that holds
  it, matched on whole path components (`db` holds `db/x.sql`, not
  `dbtools/x.go`). So `pkg/admin` can be listed before a broader `pkg`.
* A file under none of them goes where `*` is, or last without one.
* Ties keep git's order — alphabetical.
* Generated files stay last whatever the rules say, as on GitHub.

Rules are tidied on the way in: surrounding `/`, leading `./`, blanks and
repeats are dropped.

## Where it applies

`LoadedReview.ordered(by:)` returns the review with `files` rearranged from
`diffOrder`, git's list. Everything downstream reads `files`, so the file list,
the all-files document, next/previous file and the CLI's `review show` all
agree. `ReviewSession.fileOrder` is set by `AppModel` before a load and
whenever Settings changes it; the all-files `scrollKey` includes the rules so
the combined document is rebuilt, and the view returns to the selected file's
header.

## Storage

`FileOrderStore` writes `file-order.json` in Application Support/Review:
`{"owner/repo": ["db", "pkg/sponsor", "*", "cmd"]}`, keyed by lowercased
`owner/repo`. Empty orders are not written. It is the reviewer's, not the
repository's — nothing is read from the checkout.

## Editing

Settings › File Order: pick a repository (tracked, open, or already ordered),
drag rows, add with the text field, remove with − or Delete. Everything Else is
always shown so a directory can be dragged below it. A changed file's context
menu offers Show First / Show Last for each of its directories, and Edit File
Order…, which opens Settings on that tab.

## Not done: an automatic order

A language server can't say that `db` is beneath `pkg/sponsor`, but the import
graph can: Go imports name packages, and TypeScript relative imports name
files. Sorting the changed files so dependencies come before their importers
would give much of this order with no rules. A candidate for later; rules
would still override it.
