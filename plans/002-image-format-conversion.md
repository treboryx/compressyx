# Plan 002: Make the image output format picker actually convert

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 4a27277..HEAD -- Sources/Compressyx/Services/ImageCompressor.swift Sources/Compressyx/Models/CompressionQueue.swift`
> If either file changed since this plan was written, compare the "Current
> state" excerpts against the live code before proceeding; on a mismatch, treat
> it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `4a27277`, 2026-08-23

## Why this matters

The app shows an "Image format" picker in two places — the Settings window and
the main window toolbar — offering JPEG, PNG, HEIC and WebP. The picker changes
the **file extension of the output path** and nothing else. The actual encoder
is chosen purely from the *input* file's extension, so selecting PNG → JPEG
writes pngquant's PNG bytes into a file named `.jpg`. The result is a file that
most tools will refuse to open, or will open only by sniffing content and
ignoring the name.

WebP is worse: `compress_webp` encodes JPEG data, writes it to a *sibling*
`.jpg` path, and then `compress` returns the `.webp` URL that was never
created. `CompressionQueue` then calls `FileUtils.file_size` on that
nonexistent path, which returns `0`, so the UI reports a successful compression
to 0 bytes. The README advertises WebP as a supported output format.

This is the largest gap between what Compressyx claims to do and what it does.

## Current state

Files involved:

- `Sources/Compressyx/Services/ImageCompressor.swift` — all image encoding;
  the faulty dispatch is at lines 45–69, the broken WebP path at 148–161.
- `Sources/Compressyx/Models/CompressionQueue.swift` — the only caller; builds
  `ImageCompressionParams` at lines 201–205.
- `Sources/Compressyx/Models/CompressionSettings.swift` — declares
  `ImageOutputFormat` (lines 44–63) and computes the output path from it in
  `output_url(for:file_type:)` (lines 133–145).

`ImageCompressionParams` carries no format — this is the root of the bug
(`ImageCompressor.swift:25-29`):

```swift
struct ImageCompressionParams: Sendable {
    let quality: Double
    let pngquant_range: String
    let output_url: URL
}
```

The dispatch switches on the **input** extension (`ImageCompressor.swift:45-69`):

```swift
    static func compress(
        input_url: URL,
        params: ImageCompressionParams,
        on_process: @escaping @Sendable (Process) -> Void = { _ in }
    ) async throws -> URL {
        let ext = input_url.pathExtension.lowercased()

        switch ext {
        case "png":
            try await compress_png(input: input_url, output: params.output_url, pngquant_range: params.pngquant_range, on_process: on_process)
        case "jpg", "jpeg":
            try compress_jpeg(input: input_url, output: params.output_url, quality: params.quality)
        case "heic", "heif":
            try compress_heif(input: input_url, output: params.output_url, quality: params.quality)
        case "webp":
            try compress_webp(input: input_url, output: params.output_url, quality: params.quality)
        case "tiff", "tif", "bmp":
            let jpg_output = params.output_url.deletingPathExtension().appendingPathExtension("jpg")
            try compress_jpeg(input: input_url, output: jpg_output, quality: params.quality)
        default:
            throw ImageCompressorError.unsupported_format(ext)
        }

        return params.output_url
    }
```

Note the `tiff/bmp` branch already has the same class of defect: it writes to
`jpg_output` but returns `params.output_url`.

The broken WebP encoder (`ImageCompressor.swift:148-161`):

```swift
    private static func compress_webp(input: URL, output: URL, quality: Double) throws {
        guard let image = NSImage(contentsOf: input),
              let tiff_data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff_data)
        else {
            throw ImageCompressorError.image_load_failed
        }

        let quality_factor = quality
        if let jpeg_data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality_factor]) {
            let jpeg_output = output.deletingPathExtension().appendingPathExtension("jpg")
            try jpeg_data.write(to: jpeg_output)
        }
    }
```

The call site (`CompressionQueue.swift:201-205`):

```swift
                let params = ImageCompressionParams(
                    quality: settings.quality_preset.image_quality,
                    pngquant_range: settings.quality_preset.pngquant_range,
                    output_url: output_url
                )
```

The enum you will dispatch on (`CompressionSettings.swift:44-63`):

```swift
enum ImageOutputFormat: String, CaseIterable, Sendable {
    case same_as_input = "Same as input"
    case jpeg = "JPEG"
    case png = "PNG"
    case heic = "HEIC"
    case webp = "WebP"

    var file_extension: String? {
        switch self {
        case .same_as_input: return nil
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .webp: return "webp"
        }
    }
}
```

Repo conventions you must match:

- `snake_case` for variables, properties and functions; `PascalCase` for types.
- Errors are modeled as a `LocalizedError` enum with an `errorDescription`
  switch — see `ImageCompressorError` at `ImageCompressor.swift:5-23`. Add new
  cases there rather than throwing `NSError`.
- Near-zero comments. Only explain a non-obvious *why*.
- No force-unwrapping. The one existing `CGColorSpace(name:)!` at
  `ImageCompressor.swift` is pre-existing; do not copy that style, and do not
  fix it here either (out of scope).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Regenerate project | `xcodegen generate` | exit 0 |
| Build | `xcodebuild -project Compressyx.xcodeproj -scheme Compressyx -configuration Release -derivedDataPath .build/xcode CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build` | exit 0, `** BUILD SUCCEEDED **` |
| Identify a produced file | `file <path>` | reports the format you expect |

There is no test suite and no linter. `xcodebuild` plus the `file(1)` checks in
Step 5 are the verification gates.

## Scope

**In scope** (the only files you should modify):
- `Sources/Compressyx/Services/ImageCompressor.swift`
- `Sources/Compressyx/Models/CompressionQueue.swift` (the
  `ImageCompressionParams` construction at lines 201–205 only)

**Out of scope** (do NOT touch, even though they look related):
- `Sources/Compressyx/Models/CompressionSettings.swift` — `ImageOutputFormat`
  and `output_url(for:file_type:)` are already correct. The output *path* is
  right; only the encoder selection is wrong. Changing the path logic will
  double-apply the fix.
- `Sources/Compressyx/Services/VideoCompressor.swift` — the video path has its
  own format handling and is not affected.
- `Sources/Compressyx/Views/SettingsView.swift`, `ContentView.swift` — the
  pickers are already wired correctly to `settings.image_output_format`.
- Adding a real WebP *encoder*. macOS has no built-in WebP encoder, and adding
  one means a new dependency (`cwebp` or libwebp). That decision is explicitly
  deferred — see Step 4 for what to do instead.

## Git workflow

- Branch: `advisor/002-image-format-conversion`
- Commit per step or per logical unit.
- Commit message style from `git log`: short imperative subject, blank line,
  prose explaining why. Example: `Replace the placeholder app icon and release 1.0.1`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Carry the target format into `ImageCompressionParams`

Add a `target_format` field. Use the existing `ImageOutputFormat` type rather
than inventing a parallel enum — it is already `Sendable`.

```swift
struct ImageCompressionParams: Sendable {
    let quality: Double
    let pngquant_range: String
    let output_url: URL
    let target_format: ImageOutputFormat
}
```

Update the single call site in `CompressionQueue.swift:201-205` to pass
`target_format: settings.image_output_format`.

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`

### Step 2: Resolve the effective format, then dispatch on it

In `ImageCompressor.compress`, replace the input-extension switch with a
two-stage resolution: decide the effective format first, then encode to it.

The resolution rule:

- If `params.target_format` is `.same_as_input`, the effective format is
  derived from the input extension (`png` → `.png`, `jpg`/`jpeg` → `.jpeg`,
  `heic`/`heif` → `.heic`, `webp` → `.webp`).
- `tiff`, `tif` and `bmp` have no matching `ImageOutputFormat` case. They keep
  today's behavior of falling back to JPEG when the target is `.same_as_input`.
- Otherwise the effective format is `params.target_format` directly.
- An input extension not in the supported list still throws
  `ImageCompressorError.unsupported_format(ext)`.

Then switch on the effective format, not the input extension:

```swift
switch effective_format {
case .png:
    try await compress_png(input: input_url, output: params.output_url, pngquant_range: params.pngquant_range, on_process: on_process)
case .jpeg:
    try compress_jpeg(input: input_url, output: params.output_url, quality: params.quality)
case .heic:
    try compress_heif(input: input_url, output: params.output_url, quality: params.quality)
case .webp:
    // handled in Step 4
case .same_as_input:
    // unreachable after resolution
}
```

Two consequences you must handle deliberately:

- **pngquant only accepts PNG input.** Routing a JPEG input to `compress_png`
  will fail. When the effective format is `.png` and the input is *not* a PNG,
  the image must first be re-encoded to PNG via `NSBitmapImageRep`
  (`representation(using: .png, properties: [:])`) before pngquant runs, or
  pngquant must be skipped entirely for that case. Choose one and note which in
  your report.
- The `tiff/bmp` branch's old bug (writing to `jpg_output` but returning
  `params.output_url`) disappears on its own, because the output path now
  always comes from `params.output_url`, whose extension
  `CompressionSettings.output_url(for:file_type:)` already set correctly.

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`

### Step 3: Make the returned URL always be the file that was written

`compress` currently returns `params.output_url` unconditionally. After Step 2
that should be true in every branch — confirm it by inspection, and add a guard
before the return so a silent mismatch can never reach the UI again:

```swift
guard FileManager.default.fileExists(atPath: params.output_url.path) else {
    throw ImageCompressorError.compression_failed("Encoder produced no output at \(params.output_url.lastPathComponent)")
}
return params.output_url
```

This is the check that would have caught the WebP bug. `CompressionQueue`
already catches thrown errors and surfaces them on the item
(`CompressionQueue.swift:229-233`), so a failure now shows as a failed item
instead of a phantom 0-byte success.

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`

### Step 4: Make WebP fail honestly instead of lying

Do **not** implement a WebP encoder in this plan. macOS provides no built-in
one, and adding `cwebp` or libwebp is a dependency decision for the maintainer,
not the executor.

Instead:

1. Delete `compress_webp` entirely.
2. Add a case to `ImageCompressorError`:

```swift
case webp_encoding_unsupported
```

with the description:

```swift
case .webp_encoding_unsupported:
    return "WebP output isn't supported yet. Choose JPEG, PNG, or HEIC."
```

3. Throw it from the `.webp` branch of the dispatch.

WebP *input* must keep working — `NSImage(contentsOf:)` decodes WebP on macOS
14+, so a WebP input converted to JPEG/PNG/HEIC will succeed. Only WebP as a
*target* throws.

4. Update `README.md`'s claim that WebP is a supported output format. The
   "Supported Formats" table lists WebP under Image, which stays accurate for
   input; the "Output formats" bullet must stop implying WebP output.
   *(`README.md` is added to the in-scope list for this step only.)*

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`, and
`grep -n "compress_webp" Sources/Compressyx/Services/ImageCompressor.swift`
returns no matches.

### Step 5: Verify every conversion produces the format it claims

Build and launch the app. Prepare four test inputs (any PNG, JPEG, HEIC and
TIFF you have; `/System/Library/Desktop Pictures/` and
`/System/Library/CoreServices/` contain usable samples).

For each output format (JPEG, PNG, HEIC) and each input, drop the file in,
compress, then run `file` on the produced `*_compressed.*`:

```
file ~/Desktop/*_compressed.*
```

**Verify**:
- A file named `.jpg` reports `JPEG image data`
- A file named `.png` reports `PNG image data`
- A file named `.heic` reports `ISO Media` / `HEIF`
- Selecting WebP as the output format produces a *failed* item in the UI with
  the message "WebP output isn't supported yet…", not a 0-byte success
- No produced file reports a format that disagrees with its extension

## Test plan

This repo has no test target, so there is nothing to model new tests on and
adding one is out of scope here (tracked separately in `plans/README.md`).
Verification is the `file(1)` matrix in Step 5.

Record in your report the exact input→output pairs you verified, so a reviewer
can see the matrix was actually exercised rather than spot-checked. The cases
that matter most, because they are the ones broken today:

- PNG input → JPEG output (currently writes PNG bytes to a `.jpg` name)
- JPEG input → PNG output (currently ignores the target entirely)
- TIFF input → JPEG output (currently writes to the wrong path and reports 0 bytes)
- Any input → WebP output (currently reports a phantom 0-byte success)

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `xcodegen generate` exits 0
- [ ] `xcodebuild ... build` exits 0 and prints `** BUILD SUCCEEDED **`
- [ ] `grep -n "compress_webp" Sources/Compressyx/Services/ImageCompressor.swift` returns no matches
- [ ] `grep -n "input_url.pathExtension.lowercased()" Sources/Compressyx/Services/ImageCompressor.swift` appears only inside the format-resolution helper, not in the encoder dispatch
- [ ] `grep -n "target_format" Sources/Compressyx/Services/ImageCompressor.swift Sources/Compressyx/Models/CompressionQueue.swift` returns matches in both files
- [ ] `file` output for every produced file in Step 5 matches its extension
- [ ] `git status --porcelain` lists only `ImageCompressor.swift`, `CompressionQueue.swift`, `README.md`, and `plans/README.md`
- [ ] `plans/README.md` status row for 002 updated

## STOP conditions

Stop and report back (do not improvise) if:

- The code at the cited locations does not match the "Current state" excerpts.
- Making PNG output work for non-PNG inputs requires changes outside
  `ImageCompressor.swift` — that indicates a deeper coupling this plan did not
  anticipate.
- You conclude a real WebP encoder is needed to finish. It is not; Step 4 is the
  intended resolution. If you disagree, report rather than adding a dependency.
- `xcodebuild` fails twice after a reasonable fix attempt.
- HEIC output fails for a specific input — `CIContext.writeHEIFRepresentation`
  has color-space constraints. Report the failing input and its color profile
  rather than silently falling back to JPEG.

## Maintenance notes

- The `guard FileManager.default.fileExists` added in Step 3 is the invariant
  that keeps this class of bug from returning. A reviewer should confirm every
  future encoder branch writes to `params.output_url` and nowhere else.
- `CompressionSettings.output_url(for:file_type:)` and this dispatch must agree
  on the extension for each format. They are now coupled through
  `ImageOutputFormat.file_extension`; adding a format means updating both.
- Deferred deliberately: real WebP encoding, AVIF support, and the
  `CGColorSpace(name:)!` force-unwrap in `compress_heif`.
- If pngquant is unavailable, PNG output now fails for *every* input rather
  than only PNG inputs, widening the blast radius of a missing dependency. This
  strengthens the case for bundling pngquant — see the direction finding in
  `plans/README.md`.
