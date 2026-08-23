# Plan 004: Give the user control over image metadata

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 5c5f8b8..HEAD -- Sources/Compressyx/Services/ImageCompressor.swift Sources/Compressyx/Models/CompressionSettings.swift Sources/Compressyx/Models/CompressionQueue.swift`
> If any of those changed since this plan was written, compare the "Current
> state" excerpts against the live code before proceeding; on a mismatch, treat
> it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `5c5f8b8`, 2026-08-23

## Why this matters

Compressyx silently destroys EXIF on every image it writes. This was measured,
not inferred: an input tagged with `DateTimeOriginal`, `Make`, `Model` and GPS
coordinates came out the other side with all four gone, on both the JPEG and
the PNG path. ICC colour profiles *do* survive, so the loss is specifically the
metadata block, not colour.

That is destructive in one direction and valuable in the other, and right now
the user controls neither:

- **Destructive**: capture date is how Photos, Lightroom and the Finder sort
  images. A compressed shoot loses its timeline and collapses to import date.
  Paired with the existing **Remove input file** toggle
  (`CompressionSettings.swift:157`), the original is deleted and the loss is
  permanent.
- **Valuable**: stripping GPS before posting a photo is a real, common reason
  to reach for a compressor. Compressyx already does it — it just does it by
  accident, doesn't say so, and can't be asked to stop.

This plan turns an invisible side effect into a deliberate, documented choice.

## Current state

**All three image encoders drop metadata for the same underlying reason**: they
decode through `NSImage` → `tiffRepresentation` → `NSBitmapImageRep`, and that
chain carries pixels and colour profile but not the EXIF/IPTC/XMP dictionaries.

`ImageCompressor.swift:206-232` — the JPEG path:

```swift
    private static func compress_jpeg(input: URL, output: URL, quality: Double) throws {
        guard let image = NSImage(contentsOf: input),
              let tiff_data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff_data)
        else {
            throw ImageCompressorError.image_load_failed
        }

        guard let jpeg_data = bitmap.representation(
            using: .jpeg,
            properties: [.compressionFactor: quality]
        ) else {
            throw ImageCompressorError.compression_failed("JPEG encoding failed")
        }

        try jpeg_data.write(to: output)
    }
```

`ImageCompressor.swift:224+` — the HEIC path has the same decode chain, then
hands a `CIImage` to `CIContext.writeHEIFRepresentation`.

`ImageCompressor.swift:122+` — the PNG path shells out to `pngquant`, which
preserves nothing but the pixels by default, and
`png_source(for:)` at `ImageCompressor.swift:104-120` re-encodes non-PNG input
through the same lossy-for-metadata `NSBitmapImageRep` chain first.

**The settings object** you will extend — `CompressionSettings.swift:110-190`.
Every stored property follows one pattern: a `didSet` that writes to
`UserDefaults` under a `Key` constant, plus a restore line in `private init()`.
Here is the existing exemplar to copy exactly:

```swift
    private enum Key {
        static let video_codec = "settings.video_codec"
        ...
        static let remove_input_file = "settings.remove_input_file"
    }

    var remove_input_file: Bool = false {
        didSet { UserDefaults.standard.set(remove_input_file, forKey: Key.remove_input_file) }
    }
```

and in `private init()`:

```swift
        remove_input_file = defaults.bool(forKey: Key.remove_input_file)
```

**The params struct and its only call site** —
`ImageCompressor.swift:25-30` and `CompressionQueue.swift:201-206`:

```swift
struct ImageCompressionParams: Sendable {
    let quality: Double
    let pngquant_range: String
    let output_url: URL
    let target_format: ImageOutputFormat
}
```

```swift
                let params = ImageCompressionParams(
                    quality: settings.quality_preset.image_quality,
                    pngquant_range: settings.quality_preset.pngquant_range,
                    output_url: output_url,
                    target_format: settings.image_output_format
                )
```

Repo conventions you must match:

- `snake_case` for variables, properties and functions; `PascalCase` for types.
- Settings enums are `String`-backed and `CaseIterable` so they can drive a
  SwiftUI `Picker` via `ForEach(X.allCases, id: \.self)` — see
  `ImageOutputFormat` at `CompressionSettings.swift:44-63` and its picker at
  `ContentView.swift:96`.
- **Enum `rawValue` strings are persisted data.** They are the display strings
  *and* the UserDefaults values. Choose them once and do not rename them later.
- Errors are cases on `ImageCompressorError` with an `errorDescription` switch
  (`ImageCompressor.swift:5-30`). Add cases there, never `NSError`.
- Near-zero comments; only a non-obvious *why*.
- No force-unwrapping in new code.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Regenerate project | `xcodegen generate` | exit 0 |
| Build | `xcodebuild -project Compressyx.xcodeproj -scheme Compressyx -configuration Release -derivedDataPath .build/xcode CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build` | exit 0, `** BUILD SUCCEEDED **` |
| Inspect metadata | `exiftool -s -DateTimeOriginal -Make -Model -GPSLatitude <file>` | prints tags, or nothing when stripped |

`exiftool` is the verification instrument for this entire plan. If it is
missing, `brew install exiftool`. There is no test suite and no linter.

## Scope

**In scope** (the only files you should modify):
- `Sources/Compressyx/Services/ImageCompressor.swift`
- `Sources/Compressyx/Models/CompressionSettings.swift`
- `Sources/Compressyx/Models/CompressionQueue.swift` (the `ImageCompressionParams` construction only)
- `Sources/Compressyx/Views/SettingsView.swift` (add one picker to the General tab)
- `README.md` (document the behavior)

**Out of scope** (do NOT touch, even though they look related):
- `Sources/Compressyx/Services/VideoCompressor.swift` — video metadata is a
  separate problem with a separate mechanism (`-map_metadata`). Not this plan.
- The `remove_input_file` setting and its semantics.
- `Sources/Compressyx/Views/ContentView.swift` sidebar. The sidebar is the
  quick-access surface for per-job settings; metadata policy is a
  set-once preference and belongs in Settings only. Adding it to both doubles
  the maintenance for no gain.
- Colour-profile handling. ICC already survives; do not "improve" it.
- Any change to `pngquant`/`cwebp` invocation flags beyond what Step 4 specifies.

## Git workflow

- Branch: `advisor/004-metadata-policy`
- Commit per step or per logical unit.
- Commit message style from `git log`: short imperative subject, blank line,
  prose explaining why. Example: `Add WebP output, persist settings, and fix image format conversion`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add the setting

In `CompressionSettings.swift`, add the enum next to the other output enums
(near `ImageOutputFormat`, around line 63):

```swift
enum MetadataPolicy: String, CaseIterable, Sendable {
    case preserve = "Preserve"
    case strip_location = "Remove location"
    case strip_all = "Remove all"

    var explanation: String {
        switch self {
        case .preserve: return "Keeps capture date, camera info, and location."
        case .strip_location: return "Keeps capture date and camera info, removes GPS."
        case .strip_all: return "Removes every metadata tag."
        }
    }
}
```

Three options rather than a two-way toggle, because "share this photo but keep
its date" is the common case and a boolean cannot express it.

Then wire it into `CompressionSettings` following the exemplar above: a `Key`
entry (`"settings.metadata_policy"`), the stored property with `didSet`, and a
restore line in `private init()`.

**Default to `.preserve`.** Today's behavior is `.strip_all`, so this is a
deliberate behavior change: the tool stops destroying data unless asked. Call
this out in your report.

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`

### Step 2: Thread it through to the compressor

Add `let metadata_policy: MetadataPolicy` to `ImageCompressionParams`
(`ImageCompressor.swift:25-30`) and pass
`metadata_policy: settings.metadata_policy` at the single call site in
`CompressionQueue.swift:201-206`.

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`

### Step 3: Replace the JPEG encoder with a metadata-carrying one

`NSBitmapImageRep` cannot carry EXIF. Use ImageIO, which can: read the source
properties with `CGImageSourceCopyPropertiesAtIndex`, then hand them to
`CGImageDestinationAddImage` as the properties dictionary alongside the
compression quality.

The shape to produce (not necessarily line-for-line):

```swift
    private static func compress_jpeg(input: URL, output: URL, quality: Double, policy: MetadataPolicy) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let cg_image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw ImageCompressorError.image_load_failed
        }

        var properties = source_properties(source, policy: policy)
        properties[kCGImageDestinationLossyCompressionQuality] = quality

        guard let destination = CGImageDestinationCreateWithURL(
            output as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw ImageCompressorError.compression_failed("Could not create JPEG destination")
        }

        CGImageDestinationAddImage(destination, cg_image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageCompressorError.compression_failed("JPEG encoding failed")
        }
    }
```

And the shared policy helper, which every format path will use:

```swift
    private static func source_properties(_ source: CGImageSource, policy: MetadataPolicy) -> [CFString: Any] {
        guard policy != .strip_all,
              let raw = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return [:]
        }

        var properties = raw
        if policy == .strip_location {
            properties.removeValue(forKey: kCGImagePropertyGPSDictionary)
        }
        return properties
    }
```

Two things to get right:

- **Orientation.** `CGImageSourceCreateImageAtIndex` returns the *unrotated*
  pixel buffer, and the orientation tag travels in the properties dictionary.
  Under `.preserve` and `.strip_location` the tag is copied through, so the
  image displays correctly. Under `.strip_all` the tag is dropped, and a photo
  shot in portrait will display sideways. Handle this explicitly: under
  `.strip_all`, carry `kCGImagePropertyOrientation` forward even though
  everything else is dropped, **or** bake the rotation into the pixels. Pick
  one, and state which in your report. Step 6 tests it.
- **Do not copy `kCGImagePropertyDPIWidth`/`DPIHeight` blindly if you resize.**
  This plan does not resize, so copying them is correct here.

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`, then:

```
exiftool -s -DateTimeOriginal -Make -GPSLatitude <a-compressed-jpeg>
```
→ tags present when the policy is `.preserve`.

### Step 4: Apply the policy to the HEIC, PNG and WebP paths

- **HEIC** (`ImageCompressor.swift:224+`): `CIContext.writeHEIFRepresentation`
  takes an options dictionary. Pass the source properties the same way, or
  switch this path to `CGImageDestination` with `UTType.heic` for consistency
  with Step 3. Prefer the `CGImageDestination` route — one mechanism is easier
  to reason about than two.
- **PNG** (`compress_png`, `ImageCompressor.swift:122+`): `pngquant` discards
  ancillary chunks. Under `.preserve`, add `--strip` *only* when the policy is
  `.strip_all`; note that pngquant's default already drops most metadata, so
  full preservation on this path may not be achievable. **If it is not, do not
  fake it** — report the limitation and document it in Step 7 rather than
  claiming preservation the tool cannot deliver.
- **WebP** (`compress_webp`, `ImageCompressor.swift:160+`): `cwebp` takes
  `-metadata all` / `-metadata none` / `-metadata exif,icc`. Map the three
  policies onto those. This is the easiest of the three.

**Verify**: `xcodebuild ... build` succeeds, and for each of JPEG/HEIC/PNG/WebP
the `exiftool` output matches the selected policy — or the limitation is
recorded.

### Step 5: Surface it in Settings

Add a picker to the **General** tab of `SettingsView.swift`, near the existing
output-format controls (see the `Picker("Output format", selection: $settings.image_output_format)`
at `SettingsView.swift:47` for the exact idiom to copy):

```swift
Picker("Metadata", selection: $settings.metadata_policy) {
    ForEach(MetadataPolicy.allCases, id: \.self) { policy in
        Text(policy.rawValue).tag(policy)
    }
}
Text(settings.metadata_policy.explanation)
    .font(.caption)
    .foregroundStyle(.secondary)
```

The explanation line matters: "Remove all" sounds harmless until you learn it
takes the capture date with it.

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`, and the picker
appears in Settings → General with the caption updating as you switch.

### Step 6: Verify the policy matrix end to end

Build the fixture:

```
cp <a-photo.jpg> /tmp/meta/in.jpg
exiftool -overwrite_original \
  -DateTimeOriginal="2026:01:15 10:30:00" -Make="TestCam" -Model="X1" \
  -GPSLatitude=37.7749 -GPSLatitudeRef=N -GPSLongitude=-122.4194 -GPSLongitudeRef=W \
  -Orientation#=6 /tmp/meta/in.jpg
```

`Orientation#=6` is 90° rotation — that is the orientation trap from Step 3.

For each policy, compress and inspect:

```
exiftool -s -DateTimeOriginal -Make -GPSLatitude -Orientation <output>
```

**Verify** against this table:

| Policy | DateTimeOriginal | Make | GPSLatitude | Renders upright |
|---|---|---|---|---|
| Preserve | present | present | present | yes |
| Remove location | present | present | **absent** | yes |
| Remove all | absent | absent | absent | **yes** |

The last cell is the one that catches a broken Step 3. Open the output in
Preview and confirm it is not sideways.

Repeat for at least JPEG and WebP output. Record which formats you covered.

### Step 7: Document it

Update `README.md`:

- Add metadata control to the feature list near the other bullets (line ~12-22).
- State the default (`Preserve`) and what each option removes.
- If PNG cannot fully preserve metadata (Step 4), say so plainly in the
  implementation notes section around line 139.

Add a `## [Unreleased]` entry to `CHANGELOG.md` following the existing format
(see the 1.0.2 section for the house style: what changed and why it matters,
not a commit list). This is both a feature *and* a behavior change — previous
versions stripped everything — so it belongs under both **Added** and
**Changed**.

**Verify**: `grep -n -i metadata README.md CHANGELOG.md` returns matches in both.

## Test plan

No test target exists, so verification is the Step 6 matrix run through the real
app. Record in your report:

- which output formats you exercised for each of the three policies,
- the exact `exiftool` output for the `.strip_all` + orientation case,
- any format where the policy could not be honored, and why.

`source_properties(_:policy:)` is pure and takes only a `CGImageSource`, making
it the natural first unit test if a test target is ever added.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `xcodegen generate` exits 0
- [ ] `xcodebuild ... build` exits 0 and prints `** BUILD SUCCEEDED **`
- [ ] `grep -n "MetadataPolicy" Sources/Compressyx/Models/CompressionSettings.swift Sources/Compressyx/Services/ImageCompressor.swift Sources/Compressyx/Views/SettingsView.swift` returns matches in all three
- [ ] `grep -c "tiffRepresentation" Sources/Compressyx/Services/ImageCompressor.swift` is strictly lower than 4 (the JPEG path no longer uses it)
- [ ] `grep -n "settings.metadata_policy" Sources/Compressyx/Models/CompressionQueue.swift` returns a match
- [ ] `defaults read com.compressyx.app | grep metadata_policy` returns a value after changing the setting in a running build
- [ ] Every row of the Step 6 table holds for JPEG output
- [ ] `git status --porcelain` lists only the five in-scope files plus `plans/README.md`
- [ ] `plans/README.md` status row for 004 updated

## STOP conditions

Stop and report back (do not improvise) if:

- The code at the cited locations doesn't match the "Current state" excerpts.
- Switching the JPEG path to `CGImageDestination` changes output **size** by
  more than ~10% at the same quality value. `kCGImageDestinationLossyCompressionQuality`
  and `NSBitmapImageRep`'s `.compressionFactor` are both 0–1 but are not
  guaranteed to be the same curve. If they diverge, the quality presets need
  recalibrating — report the measurements rather than silently changing what
  "High" means.
- Preserving metadata on the PNG path proves impossible. Report it; do not
  present `.preserve` as working when it does not.
- A `.strip_all` output renders sideways and you cannot fix it within
  `ImageCompressor.swift`.
- `xcodebuild` fails twice after a reasonable fix attempt.

## Maintenance notes

- The default changes from "strip everything" to "preserve everything". Anyone
  relying on the old accidental privacy behavior loses it silently on upgrade.
  This is the right default, but it must be in the release notes — the appcast
  now surfaces `CHANGELOG.md` in the Sparkle update dialog, so Step 7's entry is
  what users will actually read.
- Every new image format added later needs a metadata decision. A reviewer
  should reject any new encoder path that ignores `params.metadata_policy`.
- `source_properties` is the single policy chokepoint. Keep it that way; policy
  logic duplicated per format is how the three paths drifted apart originally.
- Deferred deliberately: video metadata (`-map_metadata`), and stripping XMP/IPTC
  independently of EXIF. Both are real, neither is this plan.
- Interaction with plan 006: if resolution scaling lands, the DPI and
  `PixelWidth`/`PixelHeight` properties copied here become stale and must be
  recomputed rather than passed through.
