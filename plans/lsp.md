# Language servers

## Which servers

| Language | Server | Notes |
|---|---|---|
| Go | `gopls` | Call hierarchy, references, implementations all supported. |
| TypeScript / TSX / JS | **TypeScript 7's own server** (`tsgo`, or `tsc` from `typescript@7`, run as `--lsp --stdio`), else `typescript-language-server --stdio` | Chosen by `ServerCommand.resolve`; see below. |

**Why TypeScript 7 first.** TypeScript 7 is the native (Go) rewrite. It ships
no `tsserver.js`, which is what typescript-language-server wraps, so once
`typescript@7` is the global install, typescript-language-server cannot run at
all — found on this machine, where it failed `initialize` with "Could not find
a valid TypeScript installation". TS 7 has an LSP server built in, and it is
the faster of the two.

**The fallback** is typescript-language-server, which looks for TypeScript in
the workspace's `node_modules` first. A PR checkout never has one (the app
does not install a PR's dependencies), so it is given
`initializationOptions.tsserver.fallbackPath` pointing at a global TypeScript
5 `lib/` when one is found beside the `tsc` on PATH. **Not exercised on this
machine**, where TS 7 always wins.

One server process per **(worktree, language)**. A PR that touches Go and
TypeScript in a monorepo gets two; the after-merge worktree gets its own.
Servers start lazily, the first time a file in that language is opened, and
stop when the PR is closed.

## A hand-written client, not a dependency ✅

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

## As built

- `LSPConnection` (actor): Content-Length framing, ids, server→client
  requests answered (`workspace/configuration` with one `{}` per item,
  everything else `null`), `$/cancelRequest` on task cancellation, a timeout
  per request, and every pending request failed when the server exits.
- `LanguageServer` (actor): the initialize handshake, `didOpen` once per file
  with its on-disk text, typed requests, and a status stream from `$/progress`
  (starting → indexing "Loading packages" → ready).
- `Navigator` (ReviewKit, actor): one server per language for a checkout,
  started on first use or by `warmUp` when the PR opens; answers are
  `CodeLocation`s with 1-based lines.
- Tests run against the real gopls and TypeScript server on small fixture
  projects, and skip when a server is not installed.

## Gotchas found

- **SIGPIPE.** Writing to a server that has died raises it, and its default
  action kills the app. `LSPConnection.start` ignores it so the write fails
  with EPIPE instead.
- **An actor's `let` is isolated across modules.** `LanguageServer.kind` had
  to be `nonisolated let` for ReviewKit to read it synchronously.
- **TypeScript 7 does not count an import as a reference** under
  `includeDeclaration: false` (it is the declaration of a local alias);
  tsserver does. Tests assert the call, not the count.
- **gopls qualifies hover signatures** from other packages
  (`func shapes.Total(shapes []shapes.Shape)`).

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
