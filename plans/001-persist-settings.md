# Plan 001: Persist compression settings across app launches

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 4a27277..HEAD -- Sources/Compressyx/Models/CompressionSettings.swift`
> If that file changed since this plan was written, compare the "Current state"
> excerpt against the live code before proceeding; on a mismatch, treat it as a
> STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `4a27277`, 2026-08-23

## Why this matters

`CompressionSettings` holds every user-facing preference — codec, quality
preset, output formats, output directory, whether to delete the input, and how
many files compress concurrently — and none of it survives quitting the app.
There is no `UserDefaults`, `@AppStorage`, or `Codable` anywhere in the
codebase (`grep -rn "AppStorage\|UserDefaults\|Codable" Sources/` returns
nothing). Compressyx is a batch utility people open repeatedly for the same
job, so re-picking "H.265 / Medium / output to ~/Desktop" on every launch is
the most repetitive friction in the product. This plan makes the settings
sticky without changing any compression behavior.

## Current state

Files involved:

- `Sources/Compressyx/Models/CompressionSettings.swift` — the single settings
  object; `@Observable`, `@MainActor`, exposed as `CompressionSettings.shared`.
  Views bind directly to its properties.

The type as it exists today (`CompressionSettings.swift:110-134`):

```swift
@Observable
@MainActor
final class CompressionSettings {
    static let shared = CompressionSettings()

    var video_codec: VideoCodec = .h265
    var quality_preset: QualityPreset = .high
    var video_output_format: VideoOutputFormat = .same_as_input
    var image_output_format: ImageOutputFormat = .same_as_input
    var output_directory: URL?
    var remove_input_file: Bool = false
    var max_concurrent: Int = 3

    var output_folder_option: OutputFolderOption {
        get { output_directory == nil ? .same_as_input : .custom }
        set {
            if newValue == .same_as_input {
                output_directory = nil
            }
        }
    }
```

All four enums (`VideoCodec`, `QualityPreset`, `VideoOutputFormat`,
`ImageOutputFormat`) are already `String`-backed and `CaseIterable`, declared at
the top of the same file. Their raw values are display strings such as
`"H.265 (HEVC)"` and `"Same as input"`.

Repo conventions you must match — these are enforced by the project's
`CLAUDE.md` and are visible throughout `Sources/`:

- `snake_case` for variables, properties, and functions
  (`video_output_format`, `output_url(for:file_type:)`).
- `PascalCase` for types.
- Arrow-function style does not apply (this is Swift), but **do not** introduce
  Objective-C-style naming or camelCase properties.
- Comment policy is near-zero: only write a comment when the *why* is
  non-obvious. Do not narrate what the code does. See how sparse the comments
  are in `CompressionQueue.swift` for the bar.
- No force-unwrapping in new code; the file currently uses `??` defaults.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Regenerate project | `xcodegen generate` | exit 0, prints `Created project at .../Compressyx.xcodeproj` |
| Build | `xcodebuild -project Compressyx.xcodeproj -scheme Compressyx -configuration Release -derivedDataPath .build/xcode CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build` | exit 0, `** BUILD SUCCEEDED **` |

There is no test suite and no linter in this repo. `xcodebuild` is the only
verification gate — run it after every step.

`xcodegen` is required because `Compressyx.xcodeproj` is gitignored and
generated from `project.yml`. If `xcodegen` is missing, install it with
`brew install xcodegen`.

## Scope

**In scope** (the only files you should modify):
- `Sources/Compressyx/Models/CompressionSettings.swift`

**Out of scope** (do NOT touch, even though they look related):
- `Sources/Compressyx/Views/SettingsView.swift` and
  `Sources/Compressyx/Views/ContentView.swift` — they bind to
  `CompressionSettings.shared` properties by name. If your change keeps the
  property names and types identical, these files need no edits. Needing to
  edit them means you changed the public shape, which is a STOP condition.
- `Sources/Compressyx/Models/CompressionQueue.swift` — reads settings, never
  writes them.
- The four enum declarations' `rawValue` strings. They are persisted keys after
  this change; renaming one silently discards a user's saved preference.

## Git workflow

- Branch: `advisor/001-persist-settings`
- One commit for the whole plan is fine; this is a single cohesive change.
- Commit message style from `git log`: a short imperative subject line, then a
  blank line, then prose explaining *why*. Example from this repo:
  `Replace the placeholder app icon and release 1.0.1`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add a persistence key namespace and load/store helpers

In `CompressionSettings.swift`, add a private `enum` inside the
`CompressionSettings` class holding the `UserDefaults` keys. Prefix every key so
it cannot collide with Sparkle's own defaults (Sparkle stores `SU*` keys in the
same domain):

```swift
private enum Key {
    static let video_codec = "settings.video_codec"
    static let quality_preset = "settings.quality_preset"
    static let video_output_format = "settings.video_output_format"
    static let image_output_format = "settings.image_output_format"
    static let output_directory = "settings.output_directory"
    static let remove_input_file = "settings.remove_input_file"
    static let max_concurrent = "settings.max_concurrent"
}
```

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`

### Step 2: Persist on write via `didSet`

Change each stored property to write through to `UserDefaults.standard` in a
`didSet` observer. Enums persist as `rawValue`. Example for two of them —
follow the same shape for the rest:

```swift
var video_codec: VideoCodec = .h265 {
    didSet { UserDefaults.standard.set(video_codec.rawValue, forKey: Key.video_codec) }
}

var max_concurrent: Int = 3 {
    didSet { UserDefaults.standard.set(max_concurrent, forKey: Key.max_concurrent) }
}
```

`output_directory` is a `URL?` and must be handled differently — persist
`output_directory?.path` as a `String?`, and delete the key when the value is
`nil`:

```swift
var output_directory: URL? {
    didSet {
        if let path = output_directory?.path {
            UserDefaults.standard.set(path, forKey: Key.output_directory)
        } else {
            UserDefaults.standard.removeObject(forKey: Key.output_directory)
        }
    }
}
```

Leave `output_folder_option` alone — it is a computed property derived from
`output_directory`, so it persists for free.

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`

### Step 3: Restore in `init`

`CompressionSettings` currently has no explicit initializer — it relies on the
implicit one. Add a `private init()` that reads each key back, falling back to
the existing default when the key is absent or the stored raw value no longer
maps to a case.

Critical detail: under the `@Observable` macro, assigning to a property inside
`init` **does** trigger `didSet` — the macro rewrites stored properties into
computed ones backed by `_name`, so init assignments go through the setter.
This is the opposite of plain-Swift property-observer semantics. It is harmless
here (the restore writes back the value it just read, and defaults for absent
keys), so do not work around it — but do not rely on init assignments being
observer-free either.

Shape to produce:

```swift
private init() {
    let defaults = UserDefaults.standard

    if let raw = defaults.string(forKey: Key.video_codec),
       let value = VideoCodec(rawValue: raw) {
        video_codec = value
    }
    // ... same pattern for quality_preset, video_output_format, image_output_format

    if let path = defaults.string(forKey: Key.output_directory) {
        output_directory = URL(fileURLWithPath: path)
    }

    remove_input_file = defaults.bool(forKey: Key.remove_input_file)

    let stored_concurrent = defaults.integer(forKey: Key.max_concurrent)
    if stored_concurrent > 0 {
        max_concurrent = stored_concurrent
    }
}
```

Note the two guarded cases and why they are guarded:

- `defaults.integer(forKey:)` returns `0` for a missing key, and `0` concurrent
  compressions would hang `CompressionQueue.compress_all`. The `> 0` check
  preserves the default of `3`.
- `defaults.bool(forKey:)` returns `false` for a missing key, which happens to
  equal the intended default for `remove_input_file`, so it needs no guard.

Adding `private init()` also correctly prevents anyone constructing a second
settings instance that would fight the singleton over the same keys.

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`

### Step 4: Confirm the round trip at runtime

Build, launch the app, change **every** setting away from its default, quit,
and relaunch.

```
open .build/xcode/Build/Products/Release/Compressyx.app
```

Read the persisted values back directly:

```
defaults read com.compressyx.app | grep settings
```

**Verify**: the command prints a `settings.*` entry for each setting you
changed, and the relaunched app's Settings window shows your chosen values
rather than the defaults.

## Test plan

This repo has no test target, so there is nothing to model new tests on and
adding one is explicitly out of scope for this plan (it is tracked separately
in `plans/README.md` under "Establish a test baseline"). Verification for this
plan is the manual round trip in Step 4 plus the `defaults read` output.

If you want a regression guard cheaply, note in your report that
`CompressionSettings` is now the natural first unit-test target, since it has no
UI or filesystem dependencies beyond `UserDefaults`.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `xcodegen generate` exits 0
- [ ] `xcodebuild ... build` exits 0 and prints `** BUILD SUCCEEDED **`
- [ ] `grep -c "didSet" Sources/Compressyx/Models/CompressionSettings.swift` returns `7`
- [ ] `grep -n "private init()" Sources/Compressyx/Models/CompressionSettings.swift` returns a match
- [ ] `defaults read com.compressyx.app | grep -c settings` returns ≥ 1 after changing settings in a running build
- [ ] `git status --porcelain` lists only `Sources/Compressyx/Models/CompressionSettings.swift` and `plans/README.md`
- [ ] `plans/README.md` status row for 001 updated

## STOP conditions

Stop and report back (do not improvise) if:

- The `CompressionSettings` class in the live code does not match the "Current
  state" excerpt (the file drifted since this plan was written).
- You find you need to edit `SettingsView.swift` or `ContentView.swift` to make
  it compile — that means the property shape changed, which this plan forbids.
- `xcodebuild` fails twice after a reasonable fix attempt.
- You discover settings are already persisted somewhere you did not expect
  (the assumption "no persistence exists today" is false).
- Adding `private init()` breaks a call site that constructs
  `CompressionSettings()` directly rather than using `.shared`.

## Maintenance notes

- Every new setting added to this class from now on needs three edits: a `Key`
  entry, a `didSet`, and an `init` restore line. A reviewer should check all
  three are present.
- The enum `rawValue` strings are now persisted data. Renaming a case's raw
  value — e.g. `"H.265 (HEVC)"` — silently resets that preference for every
  existing user. If a display string must change, decouple it from `rawValue`
  by giving the enum a separate `display_name` property.
- `output_directory` is persisted as a plain path, not a security-scoped
  bookmark. That is fine today because the app is not sandboxed
  (`ENABLE_APP_SANDBOX: false` in `project.yml`). **If sandboxing is ever
  enabled, this breaks** — the restored path will not be accessible and must
  become a bookmark. Flag this in any future sandboxing work.
