# Browsing pull requests

The sidebar's **Browse** row (⇧⌘B, View › Browse Pull Requests) replaces the
files and code columns with a pull request browser, so finding something to
review never means a trip to github.com. Choosing a pull request in it (double-click,
Return, or Open in its menu) opens it in the sidebar as usual and leaves the
browser.

## Shape

| Column | Holds |
|---|---|
| Sidebar | Unchanged, with Browse as its first row |
| Content | Where to search: Involving You, Tracked Repositories, the tracked repositories one by one, then every other repository the reviewer can see, most recently pushed first, with a filter field |
| Detail | A filter bar, a table of matches, and a status bar with the count and Load More |

The window title is the scope; the toolbar's search field (`.searchable`)
searches titles.

## The query

Everything becomes one GitHub search query, built by
`PullRequestFilter.searchQuery(scope:)` in ReviewCore and tested there:

```
is:pr <scope> <state> <draft> <review> <people> <sort> [in:title <words>]
```

- **Scope** (`BrowseScope`): `repo:` per tracked repository, `repo:` for one,
  or `involves:@me`. Tracked with nothing tracked falls back to
  `involves:@me` — a search of all of GitHub is never what anyone wants.
- **State**: `is:open`, `is:merged`, `is:closed is:unmerged` (plain
  `is:closed` includes merged), or nothing.
- **Drafts**: `draft:true` / `draft:false`.
- **Review**: `review:none|required|approved|changes_requested`.
- **People** (`PersonCondition`): author, reviewed by, review requested
  from, assignee, involves — each one negatable (`-author:@me`). Logins are
  checked: `@me`, a login (a leading `@` is dropped), `app/name`, or
  `org/team`. Anything else — half-typed, two words, `x repo:y` — is left out
  of the query and the token is outlined in red, because a stray word would
  change the meaning of the whole search.
- **Words** go last after `in:title`, verbatim, so a typed qualifier such
  as `label:bug` still works.

The query travels to GitHub as a GraphQL variable (`-f q=…`), never spliced
into the request, so what is typed changes the search but not the request.

## Fetching

`GitHubClient.searchPullRequests` uses GraphQL `search(type: ISSUE)` rather
than `gh search prs`: one request returns the review decision, the latest
opinionated reviews, additions and deletions, the total count and a cursor.
50 per page; the last row appearing, or Load More, fetches the next. GitHub
stops paging after 1,000 matches.

**Review state** is `reviewDecision` when the repository requires reviews.
Where it does not, `reviewDecision` is null, and any reviewer asking for
changes outweighs approvals.

**Repositories** come from REST `user/repos` with
`affiliation=owner,collaborator,organization_member`, archived ones dropped.
GraphQL's `viewer.repositories` was tried first and returned 9 of the
reviewer's 128: it misses repositories reached through organization teams.

## Implementation lines

The table's **Implementation** column is not GitHub's `additions`/`deletions`:
those count generated output, which for one OpenAPI or sqlc change is most of
the diff. It is harmony's PR Line Count (`.github/workflows/pr-line-count.yml`,
`scripts/pr-line-count.sh`) ported to Swift: every changed file goes in one
category, first match wins —

1. **Generated / Vendored** — `.gitattributes` sets `linguist-generated` or
   `linguist-vendored` (set, or `=true`).
2. **Tests** — `*_test.go`, `*_test.sh`, `*.test.*` / `*.spec.*` (js, ts, jsx,
   tsx), or under a `test`, `tests`, `testdata`, `__tests__`, `__mocks__`,
   `fixtures` or `testutil` directory.
3. **Documentation** — `.md`, `.mdx`, `.mdc`, `.rst`, `.adoc`, under `doc/`
   or `docs/`, or under a root `decisions/`.
4. **Implementation** — the rest. This is the column; the tooltip has all four
   and the total.

The script runs `git check-attr` in a checkout. The browser has no checkout of
most of what it lists, so `GitAttributes` (ReviewCore) reads the root
`.gitattributes` text itself, gitattributes(5) rules: no slash matches the
name at any depth, a slash anchors, `**` spans directories, a trailing-slash
pattern matches no file, the last line that mentions an attribute wins. Not
read: nested `.gitattributes`, macros, quoted patterns. The file comes from
the repository's default branch, once per repository per session (Refresh
reads it again) — the script reads the PR's own copy, so a PR that adds a
rule is counted by the old rules until it merges.

Files come from GraphQL `files(first: 100)`, 25 pull requests per request
with an alias each, after the search, not in it: put in the search, every
keystroke's search would cost ~50 rate-limit points. Larger PRs page through
REST `pulls/{n}/files` (GitHub stops at 3,000 files). Counts are cached by
head commit, so a push recounts and a re-search does not. Until counted, a row
shows GitHub's totals, faded.

**Verified** against the script's own output: all 55 harmony PRs with the
`line-count` label — whose descriptions carry its table — counted the same
implementation lines, file for file.

## Searching as you type

`BrowseView` runs the search from `.task(id: query)`. Any change to the
words, a filter or the scope changes the query, which cancels the running
search and starts another after a 350 ms pause (none for the first search
when the browser is shown). Results for the previous query stay on screen
while the next one runs, so the table does not flash empty; a late,
cancelled search cannot clear the spinner of the one that replaced it.

## Persistence

`BrowseStore` keeps the scope and filter in `browse.json` beside the other
stores, so a relaunch comes back to the same search. Results are not cached.

## Tracking from the browser

A repository's context menu has Track Repository / Stop Tracking — the same
list as Settings › Repositories, which also feeds the sidebar's inbox.

## Headless

`review search [words…] [--repo owner/repo | --involving-me] [--state …]
[--drafts any|draft|ready] [--review …] [--author L] [--not-author L]
[--reviewed-by L] [--review-requested L] [--more]` prints the query it sent
and the results — implementation lines beside GitHub's totals — through the
same code.

`--browse on|tracked|me|owner/repo` and `--search <words>` open the browser
in a scripted launch. These save to `browse.json` like any other change.
