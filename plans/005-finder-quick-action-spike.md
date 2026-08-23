# Plan 005: Design spike — compress from the Finder

> **Executor instructions**: This is a **design spike, not a build plan**. Its
> deliverable is a written recommendation plus a throwaway proof-of-concept, not
> a shippable feature. Do not implement the production extension. If you find
> yourself writing polished UI, you have overshot — stop and write up what you
> learned. When done, update the status row for this plan in `plans/README.md`
> and attach your findings document.
>
> **Drift check (run first)**: `git diff --stat 5c5f8b8..HEAD -- project.yml Sources/Compressyx/Services Sources/Compressyx/Models`
> If those changed substantially, re-read them before trusting the excerpts below.

## Status

- **Priority**: P2
- **Effort**: M (spike) / L (the feature it scopes)
- **Risk**: MED
- **Depends on**: plans/003-folder-ingest.md (see "Why the dependency")
- **Category**: direction
- **Planned at**: commit `5c5f8b8`, 2026-08-23

## Why this matters

Compressyx is a batch utility whose only entry point is "launch the app, then
drag files into it". The gesture people actually reach for is right-click in
Finder → compress. Every competitor in this category ships that. It is the
single highest-leverage new surface for adoption, and it is also the one that
most constrains the app's architecture, which is why it gets a spike before it
gets a plan.

The constraint that makes this non-trivial: compression currently lives in
`Sources/Compressyx/Services/`, compiled directly into the app target. An app
extension is a **separate process with its own bundle**. It cannot call into the
host app's code unless that code moves into a shared framework, and it cannot
shell out to Homebrew binaries as freely as the main app does.

## Why the dependency

Plan 003 makes `FileUtils.expand(urls:)` the single ingest funnel. A Quick
Action receives an arbitrary Finder selection — files *and* folders, mixed. If
this spike runs first, it will re-derive its own filtering and the two will
drift. Land 003 first, then this spike inherits the funnel.

## Current state

**There is exactly one target.** `project.yml:24-32`:

```yaml
targets:
  Compressyx:
    type: application
    platform: macOS
    sources:
      - path: Sources/Compressyx
    dependencies:
      - package: DockProgress
      - package: KeyboardShortcuts
      - package: SettingsAccess
      - package: Sparkle
```

**The app is not sandboxed** — `project.yml:62`: `ENABLE_APP_SANDBOX: false`.
This is load-bearing for the current design, because compression shells out to
`/opt/homebrew/bin/{ffmpeg,pngquant,cwebp}`. See
`VideoCompressor.find_ffmpeg()` (`VideoCompressor.swift:30-42`) and
`ImageCompressor.find_tool(_:)` (`ImageCompressor.swift:32-49`), both of which
probe hardcoded Homebrew paths.

**The compression entry points** the extension would need:

- `ImageCompressor.compress(input_url:params:on_process:)` — `ImageCompressor.swift:76`
- `VideoCompressor.compress(input_url:params:on_progress:on_process:)` — `VideoCompressor.swift:44`
- `CompressionSettings.shared` — `CompressionSettings.swift:113`, a `@MainActor`
  singleton backed by `UserDefaults.standard`

**Distribution context** (this shapes what is acceptable): the app ships as a
Developer ID–signed, notarized DMG via GitHub Releases, updated by Sparkle. Team
ID `DRKB4AV7KC`. It is *not* on the Mac App Store. Signing and notarization run
in `.github/workflows/release.yml`, which signs nested components inside-out
before the outer bundle — an added extension target must be folded into that
signing order or notarization will fail.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Regenerate project | `xcodegen generate` | exit 0 |
| Build | `xcodebuild -project Compressyx.xcodeproj -scheme Compressyx -configuration Release -derivedDataPath .build/xcode CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build` | exit 0, `** BUILD SUCCEEDED **` |
| List registered extensions | `pluginkit -m -v -p com.apple.services` | your extension appears after a build+launch |
| Inspect signing of nested code | `codesign -d --verbose=2 <path>` | shows the identity and flags |

## Scope

**In scope**:
- A scratch branch containing a throwaway proof-of-concept.
- A written findings document at `plans/005-findings.md`.
- Edits to `plans/README.md`.

**Out of scope** (this is a spike — do NOT do these):
- Any production-quality extension UI.
- Changing `ENABLE_APP_SANDBOX` on the main app.
- Modifying `.github/workflows/release.yml`. Record what *would* need to change;
  do not change it. A broken release workflow is worse than a missing feature.
- Refactoring `Services/` into a framework "while you're there". The spike may
  *prototype* that move on a scratch branch to measure the cost, but the
  recommendation, not the refactor, is the deliverable.
- Committing the proof-of-concept to `main`.

## Questions the spike must answer

Answer each with evidence — a build that worked, a `codesign` output, a
measured number. "Probably fine" is not an answer.

### Q1: Which extension point?

macOS offers at least three routes. Determine which fits and say why the others
do not:

| Route | Notes to verify |
|---|---|
| **Services menu** (`NSServices` in Info.plist) | Simplest — no separate target, the app declares a service and receives an `NSPasteboard`. Does it appear in the right-click menu for a multi-file selection? Does it launch the app if not running? |
| **Finder Sync / Action extension** | A real extension target. Richer menu placement. Requires the framework split. |
| **Quick Action / Automator workflow** | Ships as a `.workflow`, appears under Quick Actions. Installed where, and how does an app-bundled one get registered? |

The Services route may make the whole framework question moot. **Check it
first** — if a plain `NSServices` declaration in the existing single target
delivers the gesture, the rest of this spike collapses to a small plan and that
is the finding.

### Q2: Does the compression code need to move?

Only if Q1 lands on a real extension target. If so, measure:

- What has to move into a shared framework: `Services/`, `Models/`, `Utils/`?
- Does `CompressionSettings` (a `@MainActor @Observable` singleton on
  `UserDefaults.standard`) work across two processes? **Suspect no** — two
  processes each hold their own in-memory copy with no change notification, and
  `didSet` writes from one are invisible to the other. Determine whether an App
  Group + `UserDefaults(suiteName:)` is required, and what that means for
  already-persisted `settings.*` keys (migration, or accept a reset).
- How much does xcodegen's `project.yml` grow? Paste the diff in the findings.

### Q3: Can an extension shell out to Homebrew binaries?

This is the highest-risk unknown and the most likely thing to kill the design.

- Can a non-sandboxed app extension `Process.run()` `/opt/homebrew/bin/ffmpeg`?
- Does the answer change once notarized and run on a machine other than the
  build machine?
- What happens when the tool is missing — how does an extension with no window
  tell the user to install it?

**Test this early.** If extensions cannot spawn Homebrew binaries, the entire
feature depends on bundling the tools first — which is already a separate open
direction finding in `plans/README.md`, and this spike would become blocked on
it. Finding that out is a successful spike outcome.

### Q4: What happens after the click?

Design question, answer with a recommendation:

- Does the extension compress silently in the background, or hand off to the app
  with the selection pre-queued?
- Which settings apply — the last-used ones from `CompressionSettings`, or a
  fixed default? Silent compression using settings the user cannot see, on files
  they may not be able to recover (**Remove input file** is a persisted setting),
  is a genuine hazard. Say how you would prevent it.
- How does a background compression report progress and failure with no window?

Recommendation: handing off to the app with the queue pre-populated is the safer
default and far cheaper to build. Argue for or against it with what you learn.

### Q5: What does the release workflow need?

`.github/workflows/release.yml` has a "Sign app bundle" step that signs Sparkle's
nested helpers inside-out, then the frameworks, then the app. An extension is
another nested signable at `Contents/PlugIns/`. Document — **do not implement**:

- where in the signing order it belongs,
- whether `--options runtime` and the existing notarization submission cover it,
- whether `codesign --verify --deep --strict` still passes.

## Deliverable

Write `plans/005-findings.md` containing:

1. **Recommendation**, first and in one paragraph: which route, and whether to
   build it now, later, or not at all.
2. **Answers to Q1–Q5**, each with the evidence that supports it.
3. **A follow-up plan sketch** — enough that plan 006+ can be written from it
   without redoing this investigation: files to create, targets to add, the
   signing-order change, and an effort estimate you now believe.
4. **Blockers**, explicitly. If Q3 says extensions cannot reach Homebrew, say so
   in the recommendation paragraph, not buried in Q3.
5. **What you did not test** and why.

A spike that concludes "don't build this yet, here's what has to happen first"
is a successful spike. Do not manufacture a positive recommendation.

## Done criteria

- [ ] `plans/005-findings.md` exists and answers Q1 through Q5, each with evidence
- [ ] The recommendation paragraph names a route and a go/no-go
- [ ] Q3 is answered by an actual executed test, not by reasoning alone
- [ ] The follow-up sketch is concrete enough to write a plan from
- [ ] No changes to `.github/workflows/release.yml`
- [ ] No proof-of-concept code committed to `main` (`git status` on `main` is clean apart from `plans/`)
- [ ] `plans/README.md` status row for 005 updated

## STOP conditions

Stop and report back (do not improvise) if:

- Q3 shows extensions cannot spawn Homebrew binaries. Write the findings with
  that as the headline and stop — do not start bundling ffmpeg, which is a
  separate direction finding with an unresolved LGPL/GPL-vs-MIT licensing
  question recorded in `plans/README.md`.
- The framework split turns out to require touching more than ~half the files in
  `Sources/`. That is a rewrite, not a refactor; report the file count.
- You find yourself editing `.github/workflows/release.yml` to make a build work.
- The spike exceeds roughly a day of work. Write up what you have. A partial
  findings document beats a perfect one that never arrives.

## Maintenance notes

- Whatever route is chosen, it must ingest through `FileUtils.expand(urls:)`
  from plan 003, or folder support silently regresses on the new surface.
- If an App Group becomes necessary, the persisted `settings.*` keys in
  `UserDefaults.standard` need a migration story. Users have real saved
  preferences as of 1.0.2.
- The Services route, if viable, has a hidden cost worth stating: `NSServices`
  entries are cached by macOS and can be stubborn to update during development.
  Note the reset incantation you end up using.
