# Plan 003: Accept dropped folders and expand them recursively

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 5c5f8b8..HEAD -- Sources/Compressyx/Utils/FileUtils.swift Sources/Compressyx/Views/DropZoneView.swift Sources/Compressyx/Views/ContentView.swift Sources/Compressyx/Models/CompressionQueue.swift`
> If any of those changed since this plan was written, compare the "Current
> state" excerpts against the live code before proceeding; on a mismatch, treat
> it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S–M
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `5c5f8b8`, 2026-08-23

## Why this matters

`README.md:14` advertises "**Drag and drop** files or folders directly into the
app". Folders do not work. Dropping one is silently ignored — no error, no
item added, nothing in the UI to explain why. The file picker refuses them too.

This is the core batch workflow for a batch compression tool: point it at a
shoot, a screenshots folder, a directory of screen recordings. Right now every
user has to select files individually, and the one who tries the documented
gesture concludes the app is broken.

## Current state

The rejection happens in three independent places, all of which must change.

**1. The drop handler filters by extension** — `DropZoneView.swift:47-59`:

```swift
    private func handle_drop(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadTransferable(type: URL.self) { result in
                guard case .success(let url) = result,
                      FileUtils.is_supported(url: url)
                else { return }

                Task { @MainActor in
                    queue.add_files([url])
                }
            }
        }
    }
```

A directory URL has no path extension, so `is_supported` returns `false` and the
`guard` drops it silently.

**2. The file picker refuses directories** — `ContentView.swift:256-267`:

```swift
    private func open_file_panel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .video, .image, .png, .jpeg, .heic, .tiff, .bmp]

        if panel.runModal() == .OK {
            let urls = panel.urls.filter { FileUtils.is_supported(url: $0) }
            queue.add_files(urls)
        }
    }
```

**3. The queue filters again** — `CompressionQueue.swift:45-59`:

```swift
    func add_files(_ urls: [URL]) {
        let existing_paths = Set(items.map { $0.url.path })

        for url in urls {
            guard FileUtils.is_supported(url: url) else { continue }
            guard !existing_paths.contains(url.path) else { continue }

            let item = CompressionItem(url: url)
            items.append(item)

            Task {
                item.thumbnail = await ThumbnailGenerator.generate(for: url, type: item.file_type)
            }
        }
    }
```

Note a second, smaller defect here: `existing_paths` is computed once *before*
the loop, so two identical URLs inside a single call both get added. Expanding a
folder makes duplicates far more likely (a folder plus one of its own files
dropped together), so fix this as part of the work — see Step 3.

**The support predicate** — `FileUtils.swift:19-22`:

```swift
    static func is_supported(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supported_video_types.contains(ext) || supported_image_types.contains(ext)
    }
```

Repo conventions you must match:

- `snake_case` for variables, properties and functions; `PascalCase` for types.
- Near-zero comments. Only write one when the *why* is non-obvious — see how
  sparse `CompressionQueue.swift` is for the bar.
- No force-unwrapping.
- `FileUtils` is an `enum` used as a namespace of `static` functions. Put new
  file-system helpers there, matching that shape.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Regenerate project | `xcodegen generate` | exit 0, `Created project at .../Compressyx.xcodeproj` |
| Build | `xcodebuild -project Compressyx.xcodeproj -scheme Compressyx -configuration Release -derivedDataPath .build/xcode CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build` | exit 0, `** BUILD SUCCEEDED **` |

There is no test suite and no linter in this repo. `xcodebuild` is the only
automated gate; the rest is the manual matrix in Step 5. `Compressyx.xcodeproj`
is gitignored and generated from `project.yml`, so `xcodegen generate` must run
before the first build. Install it with `brew install xcodegen` if missing.

## Scope

**In scope** (the only files you should modify):
- `Sources/Compressyx/Utils/FileUtils.swift`
- `Sources/Compressyx/Views/DropZoneView.swift`
- `Sources/Compressyx/Views/ContentView.swift` (the `open_file_panel` function only)
- `Sources/Compressyx/Models/CompressionQueue.swift` (the `add_files` function only)

**Out of scope** (do NOT touch, even though they look related):
- `Sources/Compressyx/Services/*` — nothing about compression itself changes.
  This plan only changes which URLs reach the queue.
- `Sources/Compressyx/Models/CompressionItem.swift` — items are still one file
  each. Do not add a "folder" item type; folders expand to files at ingest time
  and are never represented in the queue.
- `Sources/Compressyx/Models/CompressionSettings.swift` — do not add a
  "recursive" setting. Recursion is unconditional; see Step 2 for why.
- Output-path handling. Expanded files keep today's behavior — output lands
  beside each source, or in the custom output folder, flat. Mirroring the input
  tree into the output folder is a deliberate non-goal here; note it in your
  report if you think it's needed.

## Git workflow

- Branch: `advisor/003-folder-ingest`
- Commit per step or per logical unit.
- Commit message style from `git log`: short imperative subject, blank line,
  then prose explaining *why*. Example subject from this repo:
  `Add WebP output, persist settings, and fix image format conversion`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add folder expansion to `FileUtils`

Add two `static` functions to the `FileUtils` enum in
`Sources/Compressyx/Utils/FileUtils.swift`.

```swift
static func is_directory(url: URL) -> Bool {
    var is_dir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &is_dir)
    return exists && is_dir.boolValue
}

static func expand(urls: [URL]) -> [URL] {
    var result: [URL] = []
    for url in urls {
        if is_directory(url: url) {
            result.append(contentsOf: supported_files(in: url))
        } else if is_supported(url: url) {
            result.append(url)
        }
    }
    return result
}
```

And the recursive walk, also on `FileUtils`:

```swift
private static func supported_files(in directory: URL) -> [URL] {
    let keys: [URLResourceKey] = [.isRegularFileKey]
    guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: keys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
        return []
    }

    var found: [URL] = []
    for case let url as URL in enumerator where is_supported(url: url) {
        found.append(url)
    }
    return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
}
```

Three details that are load-bearing — do not drop them:

- `.skipsHiddenFiles` keeps `.DS_Store` and dotfile noise out.
- `.skipsPackageDescendants` stops the walk from descending into bundles. A
  `.photoslibrary`, `.fcpbundle` or an `.app` is a directory on disk; without
  this flag, dropping one enqueues thousands of internal assets.
- The sort makes queue order match Finder order. `localizedStandardCompare`
  gives natural numeric ordering, so `img2` precedes `img10`.

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`

### Step 2: Expand at the drop handler

In `DropZoneView.swift`, replace the `is_supported` guard with expansion. A
directory reaching `add_files` must already have become a list of files.

```swift
    private func handle_drop(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadTransferable(type: URL.self) { result in
                guard case .success(let url) = result else { return }

                let expanded = FileUtils.expand(urls: [url])
                guard !expanded.isEmpty else { return }

                Task { @MainActor in
                    queue.add_files(expanded)
                }
            }
        }
    }
```

Recursion is unconditional and has no setting. A user dropping a folder means
"everything in here"; a depth control is a preference nobody will find, and
`.skipsPackageDescendants` already prevents the pathological case. If you
believe a depth limit is needed, report it rather than adding one.

Note `FileUtils.expand` runs on whatever thread `loadTransferable`'s completion
handler uses, which is deliberate — enumerating a large tree must not block the
main actor. `queue.add_files` is still hopped onto `@MainActor`.

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`

### Step 3: Expand at the queue, and fix the duplicate check

In `CompressionQueue.add_files`, expand defensively (so every caller benefits)
and move the seen-set update *inside* the loop so duplicates within a single
call are caught:

```swift
    func add_files(_ urls: [URL]) {
        var existing_paths = Set(items.map { $0.url.path })

        for url in FileUtils.expand(urls: urls) {
            guard existing_paths.insert(url.path).inserted else { continue }

            let item = CompressionItem(url: url)
            items.append(item)

            Task {
                item.thumbnail = await ThumbnailGenerator.generate(for: url, type: item.file_type)
            }
        }
    }
```

`Set.insert` returns `(inserted: Bool, memberAfterInsert: Element)`, so this
both tests and records in one step. The `is_supported` guard is gone because
`FileUtils.expand` already applies it.

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`

### Step 4: Let the file picker choose folders

In `ContentView.open_file_panel`, allow directories and route through the same
expansion:

```swift
        panel.canChooseDirectories = true
```

and replace the filter with:

```swift
        if panel.runModal() == .OK {
            queue.add_files(panel.urls)
        }
```

Leave `allowedContentTypes` as it is — `NSOpenPanel` permits directory
selection alongside a content-type filter, and removing the filter would let
users pick unsupported files that then silently vanish.

Also update the drop-zone hint text in `DropZoneView.swift:24` from
`"Drop videos or images here"` to mention folders, so the capability is
discoverable.

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`

### Step 5: Exercise the ingest matrix

Build and launch:

```
open .build/xcode/Build/Products/Release/Compressyx.app
```

Construct a test tree first:

```
mkdir -p /tmp/ingest/{nested/deep,empty}
cp <some.jpg> /tmp/ingest/a.jpg
cp <some.png> /tmp/ingest/nested/b.png
cp <some.jpg> /tmp/ingest/nested/deep/c.jpg
cp <some.txt> /tmp/ingest/ignore.txt
touch /tmp/ingest/.hidden.jpg
```

**Verify** each of these:

| Action | Expected |
|---|---|
| Drop `/tmp/ingest` | exactly 3 items: `a.jpg`, `b.png`, `c.jpg` |
| `.hidden.jpg` | never appears |
| `ignore.txt` | never appears |
| Drop `/tmp/ingest` twice | still 3 items, no duplicates |
| Drop `/tmp/ingest` **and** `/tmp/ingest/a.jpg` together | still 3 items |
| Drop `/tmp/ingest/empty` | nothing added, no crash, no error dialog |
| Add Files → select a folder | same 3 items |
| Drop any `.app` from `/Applications` | nothing added (package not descended) |
| Drop a single loose file | still works exactly as before |

The two-drops-in-one-gesture row is the specific case the old code got wrong.

## Test plan

This repo has no test target, so there is nothing to model new tests on, and
adding one is out of scope here (it is tracked in `plans/README.md` under
"Establish a test baseline"). Verification is the matrix in Step 5.

Record in your report which rows you actually exercised. `FileUtils.expand` is
pure and filesystem-only, so note in your report that it is the best unit-test
candidate in the codebase if a test target is ever added.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `xcodegen generate` exits 0
- [ ] `xcodebuild ... build` exits 0 and prints `** BUILD SUCCEEDED **`
- [ ] `grep -n "skipsPackageDescendants" Sources/Compressyx/Utils/FileUtils.swift` returns a match
- [ ] `grep -n "canChooseDirectories = true" Sources/Compressyx/Views/ContentView.swift` returns a match
- [ ] `grep -c "FileUtils.expand" Sources/Compressyx/` across the tree returns at least 2
- [ ] `grep -n "guard FileUtils.is_supported" Sources/Compressyx/Models/CompressionQueue.swift` returns **no** matches
- [ ] Every row of the Step 5 matrix behaves as tabulated
- [ ] `git status --porcelain` lists only the four in-scope files plus `plans/README.md`
- [ ] `plans/README.md` status row for 003 updated

## STOP conditions

Stop and report back (do not improvise) if:

- The code at the cited locations doesn't match the "Current state" excerpts.
- Dropping a large folder (>2000 files) freezes the UI for more than a couple of
  seconds. That means expansion is running on the main actor; report it rather
  than adding a progress indicator, which is a bigger design change.
- `loadTransferable` does not deliver directory URLs at all on this macOS
  version — the assumption "a dropped folder arrives as a `URL`" would then be
  false, and the fix is a different API (`NSFilePromiseReceiver` or a
  `.fileURL` `NSItemProvider` type), which is out of scope here.
- You conclude output paths need to mirror the input tree. That is a real design
  question; report it, do not decide it.
- `xcodebuild` fails twice after a reasonable fix attempt.

## Maintenance notes

- `FileUtils.expand` is now the single ingest funnel. Any future entry point —
  a Finder Quick Action (plan 005), a CLI, a Shortcuts action — must route
  through it rather than re-filtering, or folder support silently regresses for
  that surface.
- A reviewer should check that `.skipsPackageDescendants` survives. It is the
  one line standing between "drop your Photos library" and forty thousand queue
  items.
- Output paths stay flat: two files named `shot.jpg` in different subfolders
  both become `shot_compressed.jpg`. With a custom output folder they collide
  and the second overwrites the first. This is pre-existing behavior for
  multi-select, but folder ingest makes it far easier to hit. Deferred
  deliberately — worth its own plan.
- `README.md:14` already claims folder support, so no doc change is needed once
  this lands. Verify that claim is finally true rather than editing the README.
