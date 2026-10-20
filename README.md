# Review

A native macOS app for reviewing GitHub pull requests, built for Go and
TypeScript:

1. **Code viewer** — the diff, or each whole file as it will be after the merge
2. **Navigation** — ⌘-click to definitions and types, find references, find
   all callers, through gopls and typescript-language-server
3. **Draft comments** — private notes on any line, in your own words
4. **Ask Claude** — send a draft to `claude -p`, with read-only access to the
   checked-out PR, and get an answer before you say anything in public
5. **Post** — the drafts you keep become a GitHub review

Everything it talks to is a tool you already have: git, `gh` for GitHub,
the language servers, and Claude Code. It holds no tokens of its own.

SwiftUI, SwiftPM and a Makefile. No Xcode project — this builds on a machine
with Command Line Tools only.

## Building

```sh
make check      # compile + layering gate
make test       # swift test, no GUI needed
make run        # build, bundle, sign, launch
make cli        # the companion `review` command-line tool
```

```sh
review open <pr>                 # open it in Review.app (after make install or make register)
review show <pr>                 # fetch a PR and list its files
review show <pr> <path> [--file] [--spans]
review threads <pr>              # the review threads already on it
review post <pr> --dry-run       # where your drafts would land, and the request
review doctor                    # are git, gh, the servers and claude found?
```

`review doctor` checks that every tool is installed and reachable:

```sh
go install golang.org/x/tools/gopls@latest
npm install -g typescript-language-server typescript
brew install gh && gh auth login
```

Optionally, `./scripts/make-signing-cert.sh` creates a self-signed identity so
macOS stops treating each build as a different program.

## Credits

The project structure — `Makefile`, `build.sh`, `Resources/Info.plist`,
`SWIFTUI-RULES.md` and the `PLAN.md`/`PROGRESS.md` convention — is copied from
uncurl, which began as a copy of
[tqbf/swiftui-app](https://github.com/tqbf/swiftui-app).

Development leans on three agent skills, which are **not** redistributed in this
repository. Install them into `.claude/skills/` yourself:

```sh
mkdir -p .claude/skills
git clone --depth 1 https://github.com/ceorkm/macos-design-skill /tmp/mds \
  && mkdir -p .claude/skills/macos-design \
  && cp -R /tmp/mds/SKILL.md /tmp/mds/references .claude/skills/macos-design/
git clone --depth 1 https://github.com/twostraws/swiftui-agent-skill /tmp/sas \
  && mkdir -p .claude/skills/swiftui-pro \
  && cp -R /tmp/sas/swiftui-pro/SKILL.md /tmp/sas/swiftui-pro/references .claude/skills/swiftui-pro/
mkdir -p .claude/skills/swift \
  && curl -sSL https://swift.airbnb.tech/SKILL.md -o .claude/skills/swift/SKILL.md
```

Dependencies: [swift-argument-parser](https://github.com/apple/swift-argument-parser),
[SwiftTreeSitter](https://github.com/ChimeHQ/SwiftTreeSitter),
[tree-sitter-go](https://github.com/tree-sitter/tree-sitter-go) and
[tree-sitter-typescript](https://github.com/tree-sitter/tree-sitter-typescript).
The highlight queries are vendored from the grammar repositories (and
tree-sitter-javascript); their MIT licences are in `ThirdPartyLicenses/`.
