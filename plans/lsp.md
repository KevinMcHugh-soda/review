# Language servers

## Which servers

| Language | Server | Notes |
|---|---|---|
| Go | `gopls` | Already installed (`~/go/bin`). Call hierarchy, references, implementations all supported. |
| TypeScript / TSX / JS | `typescript-language-server --stdio` | Wraps tsserver. Needs `typescript` resolvable — from the worktree's `node_modules`, or the global install alongside it. Not yet installed here: `npm install -g typescript-language-server typescript`. |

One server process per **(worktree, language)**. A PR that touches Go and
TypeScript in a monorepo gets two; the after-merge worktree gets its own.
Servers start lazily, the first time a file in that language is opened, and
stop when the PR is closed.

## A hand-written client, not a dependency

The protocol surface needed is small, so `ReviewLSP` implements it directly:
Content-Length framing over stdio, JSON-RPC request/response matching by id,
notifications both ways, and server-to-client requests answered (gopls sends
`workspace/configuration` and `window/workDoneProgress/create` and stalls if
ignored). ChimeHQ's `LanguageServerProtocol`/`LanguageClient` packages were
considered; they would be a third-party dependency, and a small actor fits
Swift 6 strict concurrency more cleanly than adapting one.

Requests used:

| Feature | Method |
|---|---|
| ⌘-click | `textDocument/definition` |
| Go to type | `textDocument/typeDefinition` |
| Find references | `textDocument/references` (`includeDeclaration: false`) |
| Find all callers | `textDocument/prepareCallHierarchy` → `callHierarchy/incomingCalls`, expanded on demand into a tree |
| Implementations | `textDocument/implementation` (interfaces in Go are where this earns its keep) |
| Hover | `textDocument/hover` |
| Ready state | `$/progress` — show "indexing…" until the initial load ends |

Files are opened with `textDocument/didOpen` using the on-disk text. The
viewer is read-only, so there is never a `didChange`.

## Results outside the PR

A definition often lands in a file the PR does not touch, or in the module
cache / `node_modules` / the Go standard library. The viewer opens any file
read-only, marking files outside the PR's change set and outside the worktree
(e.g. `$GOROOT/src/...`) so it is clear what is under review and what is
context.

## Gotchas to expect

- **gopls needs the login-shell environment** — GOPRIVATE and GOFLAGS for
  private modules, GOPATH for the module cache. `ToolEnvironment` provides it.
- **Initial indexing takes time on a large module.** Requests made before it
  finishes return partial results rather than errors; the UI must say
  "indexing" rather than show an empty references list as the truth.
- **Positions are UTF-16** — see code-viewer.md.
- **Call hierarchy in typescript-language-server** is supported but less
  complete than gopls (e.g. calls through object-literal methods); show what it
  returns and fall back to references.
