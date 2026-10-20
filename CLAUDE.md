# Review — agent instructions

Review is a native macOS app for reviewing GitHub pull requests: a code
viewer with diff and after-merge modes, language-server navigation for Go and
TypeScript, private draft comments that can be sent to `claude -p`, and
posting the result as a GitHub review.

## Documentation conventions

* Keep a master PLAN.md as an index to the documentation you make for this codebase.

* Store specific in-depth documentation in plans/whatever.md.

* Record progress in PROGRESS.md. I should be able to tell a future agent "read PLAN.md and
  PROGRESS.md" and trust it's up to speed with this codebase.

* Never name a doc `claude.md` in any casing. The filesystem is case-insensitive, so Claude
  Code loads it as that directory's `CLAUDE.md` instructions.

## Skills

Three skills belong in `.claude/skills/` — use them, they are not optional. They are **not**
committed: two of the three carry no licence, so redistributing them from here is not ours to
do. `README.md` has the commands to fetch them.

* Before and after deciding on code, use the **swiftui-pro** skill to ensure we're following
  modern SwiftUI best practices.

* Use the **macos-design** skill to make sure the UI we come up with makes sense as a modern
  macOS app, with modern professional macOS idioms. Keep things simple. It also covers type
  scale and visual hierarchy — pay attention to type weight and emphasis.

* Use the **swift** skill (Airbnb Swift Style Guide) when creating or editing any `.swift` file,
  in every target — not just views. The toolchain here is Swift 6.1, which does not support
  raw-identifier test names: write `@Test("Sentence") func sentence()` instead.

* SwiftUI's macros (`@Entry`, `#Preview`) do not expand here — their plugins ship with Xcode, not
  the Command Line Tools. Write `EnvironmentKey`/`FocusedValueKey` conformances by hand.

`SWIFTUI-RULES.md` in the repo root is the house style and takes precedence where it conflicts.

Ask before adding a third-party dependency.

## Build

No Xcode IDE, no `xcodebuild`. **This machine has Command Line Tools only** — `xcodebuild` does
not exist here, so never reach for it. `swift build` compiles; `build.sh` bundles and signs.

* `make check` — compile only; the fast gate to run after every change
* `make test` — `swift test`; covers the logic targets without launching a GUI
* `make run` — build, bundle, sign, launch
* `make cli && ./.build/debug/review doctor` — confirms every external tool is found
* `./.build/debug/review show <pr> [path]` — loads a PR exactly as the app does, headless
* **Look at UI changes.** `screencapture` from an agent shell sees only the desktop (no Screen
  Recording permission), so the app renders its own window instead:
  `open -n --env REVIEW_SNAPSHOT=/path/out.png build/Review.app --args --open <pr> --file <path> [--mode diff|split|file]`
  writes a PNG (plus `-sheet.png` / `-popover.png` when one is up) once loading settles and quits.
  Launch through `open`, not by running the binary: run directly from an agent shell, the app
  can come up with no window at all. Every option must be a `--flag value` pair — AppKit treats
  a value without a flag as a file to open, and a launch that opens a file creates no window.
  Options: `--navigate definition|references|callers|… --line <head line> --column <utf-16 column>`,
  `--comment 70-75 --note "…" --ask` (asks Claude; costs a few cents), `--hover <line>:<column>`,
  `--expand <gap>`, `--post-sheet`. See `LaunchOptions.swift`.
* `review post <pr> --dry-run` prints where every saved draft lands and the exact request.
  **Never run `review post … --yes`, or press Post in a scripted app run, on someone else's PR** —
  it is public and cannot be unsent. `--post-sheet` opens the sheet without posting.
* `REVIEW_LIVE_CLAUDE=1 swift test --filter Live` re-checks the Claude safety boundary against the
  real `claude`. Opt-in because it costs money; run it after touching `ClaudeClient`'s flags.
* `SIGN_IDENTITY` defaults to `review-dev`, a self-signed cert created by
  `scripts/make-signing-cert.sh`. Optional: ad-hoc signing works, but changes the cdhash every
  build, so macOS treats each build as a different program and re-asks for any permission it
  was granted.

## Architecture

Everything except SwiftUI views (and the NSTextView wrapper) lives in library targets so both
the app and the CLI consume it, and so the hard parts are testable without a GUI. Every external
program runs as a child process with the login-shell environment — never with the app's own.
See plans/architecture.md.

## Untrusted input

The code under review is someone else's. Never run a PR's package scripts, build, or tests
automatically, and keep Claude's tools read-only. See plans/checkout-and-diff.md and
plans/claude-integration.md.

## Git

* Never commit directly to `main` — always a feature branch.
* You may push PRs, but you MUST NOT ever merge them yourself to main.
