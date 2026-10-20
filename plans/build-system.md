# Build system

No Xcode project, no `xcodebuild`, no XcodeGen. `swift build` compiles; a shell
script bundles and signs; `make` orchestrates. Xcode is only a toolchain
provider (`swift`, `codesign`, `notarytool`, `stapler`).

## The pieces

- **`Package.swift`** — library targets for the logic, two executable
  targets (`ReviewApp`, `review`), one test target per library. Swift 6
  language mode. See architecture.md for the graph.
- **`build.sh`** — `swift build` → assemble `build/Review.app` (Info.plist
  with `__SHORT_VERSION__`/`__BUILD_VERSION__` substituted, `PkgInfo`, any
  dependency `*.bundle`s copied into `Contents/Resources`, the icon) → codesign.
  Falls back to ad-hoc signing (`-`) when no real identity is available, so
  `make run` always works on a bare machine.
- **`Makefile`** — the front door. `make help` lists everything.
- **`Resources/Info.plist`** — bundle metadata. Version strings are
  placeholders filled at build time.
- **No entitlements file, no App Sandbox.** The app runs git, gh, gopls,
  typescript-language-server and claude from the user's own install and reads
  arbitrary repositories; the sandbox forbids both. See architecture.md.
  `build.sh` still signs with entitlements if `Review/Review.entitlements`
  ever appears.

## Permissions & capabilities

OS capabilities work in this no-Xcode, ad-hoc-signed bundle — you just have to
add the keys by hand, because there's no Xcode "Signing & Capabilities" tab
doing it for you:

- **Usage prompts** need the matching `NS…UsageDescription` string in
  `Resources/Info.plist`. CoreLocation, for example, prompts and returns a fix
  with `NSLocationUsageDescription` (+ `NSLocationWhenInUseUsageDescription`)
  present — ad-hoc signing and the hand-assembled `.app` are not a barrier.
- **The sandbox decides the entitlement.** With the App Sandbox **off**, a
  usage-description string is enough. With it **on**, also add the matching
  `com.apple.security.*` entitlement (e.g.
  `com.apple.security.personal-information.location`).
- **Always design the denied path.** A permission the user declines should
  route to a sensible default, not a dead feature — e.g. a one-shot location
  request that yields `nil` falls back to a configured location.

## Everyday targets

| Target        | What it does                                              |
|---------------|----------------------------------------------------------|
| `make check`  | `swift build` only — fast compile gate for CI/agents      |
| `make test`   | `swift test` (swift-testing)                              |
| `make cli`    | build and sign the `review` command-line tool             |
| `make run`    | build the `.app`, ad-hoc sign, `open` it                 |
| `make` / build| `build/Review.app` (debug)                              |
| `make icon`   | regenerate `build/AppIcon.icns`                          |
| `make clean`  | remove `build/ .build/ dist/`                            |

## Versioning

`make` resolves the version in this order: a `VERSION=` override → an exact
`vX.Y.Z` git tag at HEAD → the `VERSION` file. `make print-version` shows what
resolved and from where.

## Release pipeline (`make dist`)

Requires an exact `vX.Y.Z` tag at HEAD and a Developer ID signing identity.
The chain is deliberately ordered:

```
clean → release → sign → zip-notary → notarize → staple → zip-release → checksum → verify-release
```

The two-zip dance is intentional: Apple's notary service takes a zip; stapling
writes the ticket back into the `.app`; the zip you actually ship must be made
**after** stapling. One-time credential setup:

```sh
make notary-setup TEAM_ID=XXXXXXXXXX APPLE_ID=you@example.com
```

`make github-release` uploads the release zip + `.sha256` to a GitHub release.

## CI gate

The minimum a change must pass: `make check && make test`. The minimum a *UI*
change must pass: also `make run` and look at it — see `SWIFTUI-RULES.md` §9.
