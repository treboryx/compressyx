# Plan 006: Advanced video options behind a disclosure group

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 5c5f8b8..HEAD -- Sources/Compressyx/Services/VideoCompressor.swift Sources/Compressyx/Models/CompressionSettings.swift Sources/Compressyx/Models/CompressionQueue.swift Sources/Compressyx/Views/ContentView.swift`
> If any of those changed since this plan was written, compare the "Current
> state" excerpts against the live code before proceeding; on a mismatch, treat
> it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `5c5f8b8`, 2026-08-23

## Why this matters

Video compression exposes exactly two controls: codec (H.264/H.265) and a
four-step quality preset. For the workload people most often bring to a Mac
compressor — screen recordings and phone video — **resolution is the dominant
lever and it is not exposed at all**. A 4K screen recording downscaled to 1080p
is roughly a quarter of the pixels before any CRF tuning happens. Audio is
always stream-copied, so a 320 kbps music bed survives untouched inside a video
you are trying to shrink.

These controls must not clutter the default UI. The four-preset simplicity is
the app's best quality. So they go behind a collapsed disclosure group —
invisible until wanted, complete when opened.

This plan supersedes the standalone "resize / max-dimension" direction finding
previously recorded in `plans/README.md`, folding it into one coherent video
panel rather than two overlapping features.

## Current state

**The ffmpeg argument builder** — `VideoCompressor.swift:56-75`:

```swift
        var args = [
            "-i", input_url.path,
            "-c:v", params.encoder,
        ]

        if params.use_crf {
            // Software encoder (VP9, etc.) uses CRF
            args.append(contentsOf: ["-crf", "\(params.crf)", "-b:v", "0"])
        } else {
            // VideoToolbox uses -q:v
            args.append(contentsOf: ["-q:v", "\(params.quality)"])
        }

        args.append(contentsOf: ["-c:a", "copy", "-y", "-progress", "pipe:1"])

        if params.is_h265 {
            args.append(contentsOf: ["-tag:v", "hvc1"])
        }

        args.append(params.output_url.path)
```

**The params struct** — `VideoCompressor.swift:21-28`:

```swift
struct VideoCompressionParams: Sendable {
    let encoder: String
    let quality: Int
    let is_h265: Bool
    let output_url: URL
    let use_crf: Bool  // true for software encoders (VP9), false for VideoToolbox
    let crf: Int
}
```

**The only call site** — `CompressionQueue.swift:173-184`:

```swift
            case .video:
                let format = settings.video_output_format
                let encoder = format.ffmpeg_encoder_override ?? settings.video_codec.ffmpeg_encoder
                let use_crf = format.requires_software_encoder
                let params = VideoCompressionParams(
                    encoder: encoder,
                    quality: settings.quality_preset.videotoolbox_quality,
                    is_h265: settings.video_codec == .h265 && !format.requires_software_encoder,
                    output_url: output_url,
                    use_crf: use_crf,
                    crf: settings.quality_preset.crf
                )
```

**Where the UI goes** — the sidebar in `ContentView.swift:64-180` is a
`ScrollView` of labelled `VStack` sections: Video, Image, Quality, Output,
Dependencies. The Video section is `ContentView.swift:72-89`. Copy that section's
idiom exactly:

```swift
                VStack(alignment: .leading, spacing: 8) {
                    Text("Video")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("Codec", selection: $settings.video_codec) {
                        ForEach(VideoCodec.allCases, id: \.self) { codec in
                            Text(codec.rawValue).tag(codec)
                        }
                    }
                    .labelsHidden()
```

**Settings persistence pattern** — `CompressionSettings.swift:110-190`. Every
stored property has a `Key` constant, a `didSet` writing to `UserDefaults`, and
a restore line in `private init()`. Exemplar:

```swift
    var max_concurrent: Int = 3 {
        didSet { UserDefaults.standard.set(max_concurrent, forKey: Key.max_concurrent) }
    }
```

and in `private init()`, note the guard — `integer(forKey:)` returns `0` for a
missing key:

```swift
        let stored_concurrent = defaults.integer(forKey: Key.max_concurrent)
        if stored_concurrent > 0 {
            max_concurrent = stored_concurrent
        }
```

Repo conventions you must match:

- `snake_case` for variables, properties, functions; `PascalCase` for types.
- Settings enums are `String`-backed + `CaseIterable`, driving `Picker` via
  `ForEach(X.allCases, id: \.self)`. Their `rawValue` is both the display string
  **and** the persisted value — choose once, never rename.
- Near-zero comments; only a non-obvious *why*.
- No force-unwrapping in new code.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Regenerate project | `xcodegen generate` | exit 0 |
| Build | `xcodebuild -project Compressyx.xcodeproj -scheme Compressyx -configuration Release -derivedDataPath .build/xcode CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build` | exit 0, `** BUILD SUCCEEDED **` |
| Inspect a produced video | `ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate,bit_rate -of default=noprint_wrappers=1 <file>` | prints the stream properties you set |

**`ffmpeg` is not installed on the machine this plan was written on.** You must
have it (`brew install ffmpeg`) or you cannot verify a single step of this plan.
Confirm `ffmpeg -version` works before starting; if it does not, that is a STOP
condition.

There is no test suite and no linter.

## Scope

**In scope** (the only files you should modify):
- `Sources/Compressyx/Models/CompressionSettings.swift`
- `Sources/Compressyx/Services/VideoCompressor.swift`
- `Sources/Compressyx/Models/CompressionQueue.swift` (the `VideoCompressionParams` construction only)
- `Sources/Compressyx/Views/ContentView.swift` (the sidebar Video section only)
- `README.md`, `CHANGELOG.md`

**Out of scope** (do NOT touch, even though they look related):
- Image compression. Resolution scaling for images is a real want, but it needs a
  different mechanism and belongs in its own plan. Do not add it here.
- `Sources/Compressyx/Views/SettingsView.swift`. These are per-job knobs and
  belong in the sidebar with the other per-job controls, not in the preferences
  window.
- The existing `QualityPreset` values (`CompressionSettings.swift:65-108`). Do
  not retune `crf` or `videotoolbox_quality`; changing what "High" means for
  existing users is a separate decision.
- Trimming, cropping, subtitle and multi-track handling.
- **The `-c:a copy` audio-codec bug.** WebM output almost certainly fails for any
  input with AAC audio, because the WebM muxer accepts only Vorbis/Opus. It is
  recorded as a separate unplanned finding in `plans/README.md`. You will be
  editing the exact line involved, so the temptation is real — resist it. Fixing
  it needs its own verification, and bundling it here makes both changes harder
  to review. Step 3 does add an audio-bitrate path; keep it strictly additive and
  leave the `copy` default alone.

## Git workflow

- Branch: `advisor/006-advanced-video-options`
- Commit per step or per logical unit.
- Commit message style from `git log`: short imperative subject, blank line,
  prose explaining why. Example: `Add WebP output, persist settings, and fix image format conversion`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add the settings

In `CompressionSettings.swift`, add two enums near the other output enums
(after `VideoOutputFormat`, around line 42):

```swift
enum VideoResolution: String, CaseIterable, Sendable {
    case original = "Original"
    case uhd_2160 = "4K (2160p)"
    case qhd_1440 = "1440p"
    case fhd_1080 = "1080p"
    case hd_720 = "720p"
    case sd_480 = "480p"

    var max_height: Int? {
        switch self {
        case .original: return nil
        case .uhd_2160: return 2160
        case .qhd_1440: return 1440
        case .fhd_1080: return 1080
        case .hd_720: return 720
        case .sd_480: return 480
        }
    }
}

enum AudioHandling: String, CaseIterable, Sendable {
    case copy_original = "Keep original"
    case aac_128 = "AAC 128 kbps"
    case aac_96 = "AAC 96 kbps"
    case remove = "Remove audio"

    var ffmpeg_args: [String] {
        switch self {
        case .copy_original: return ["-c:a", "copy"]
        case .aac_128: return ["-c:a", "aac", "-b:a", "128k"]
        case .aac_96: return ["-c:a", "aac", "-b:a", "96k"]
        case .remove: return ["-an"]
        }
    }
}
```

Then add three properties to `CompressionSettings`, each following the
`Key` + `didSet` + `init` restore pattern shown in "Current state":

- `video_resolution: VideoResolution = .original`
- `audio_handling: AudioHandling = .copy_original`
- `video_fps_cap: Int = 0` — `0` means "unchanged". Because
  `defaults.integer(forKey:)` also returns `0` for a missing key, this one needs
  **no** guard in `init`, unlike `max_concurrent`. That is deliberate; do not
  add one.

All three defaults reproduce today's behavior exactly, so an existing user sees
no change until they open the disclosure group.

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`

### Step 2: Extend the params struct and its call site

Add to `VideoCompressionParams` (`VideoCompressor.swift:21-28`):

```swift
    let max_height: Int?
    let fps_cap: Int
    let audio_args: [String]
```

and populate them at `CompressionQueue.swift:177-184`:

```swift
                    max_height: settings.video_resolution.max_height,
                    fps_cap: settings.video_fps_cap,
                    audio_args: settings.audio_handling.ffmpeg_args
```

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`

### Step 3: Build the ffmpeg arguments

Rewrite the argument assembly in `VideoCompressor.compress`
(`VideoCompressor.swift:56-75`). Replace the hardcoded `["-c:a", "copy", ...]`
with `params.audio_args`, and insert the video filter and fps cap.

The scale filter — this exact expression matters:

```swift
        if let max_height = params.max_height {
            args.append(contentsOf: ["-vf", "scale=-2:'min(\(max_height),ih)'"])
        }
```

Four things are load-bearing:

- `-2` (not `-1`) for width makes ffmpeg pick the width that preserves aspect
  ratio **rounded to an even number**. H.264 and H.265 require even dimensions;
  `-1` produces odd widths on some inputs and the encoder fails outright.
- `min(H,ih)` means never *upscale*. A 720p source with "1080p" selected stays
  720p instead of being blown up into a larger file — which is exactly the
  failure this plan exists to prevent.
- Height is the constraint, not width, so portrait video behaves sensibly.
- The single quotes around the `min()` expression are required — ffmpeg's filter
  parser treats a bare comma inside the expression as an argument separator.

The fps cap:

```swift
        if params.fps_cap > 0 {
            args.append(contentsOf: ["-r", "\(params.fps_cap)"])
        }
```

Keep the argument order: input, video codec, quality/CRF, **video filter**,
**fps**, **audio**, `-y -progress pipe:1`, then the `hvc1` tag, then the output
path. Filters must precede the output; the existing code already appends the
output path last, so append the new flags before that line.

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`

### Step 4: Add the disclosure group to the sidebar

In `ContentView.swift`, inside the existing Video section
(`ContentView.swift:72-89`), append a collapsed `DisclosureGroup` after the
existing codec and format pickers:

```swift
                    DisclosureGroup("Advanced") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Resolution")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Resolution", selection: $settings.video_resolution) {
                                ForEach(VideoResolution.allCases, id: \.self) { resolution in
                                    Text(resolution.rawValue).tag(resolution)
                                }
                            }
                            .labelsHidden()

                            Text("Audio")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Audio", selection: $settings.audio_handling) {
                                ForEach(AudioHandling.allCases, id: \.self) { handling in
                                    Text(handling.rawValue).tag(handling)
                                }
                            }
                            .labelsHidden()

                            Toggle("Cap frame rate", isOn: Binding(
                                get: { settings.video_fps_cap > 0 },
                                set: { settings.video_fps_cap = $0 ? 30 : 0 }
                            ))
                            .font(.callout)

                            if settings.video_fps_cap > 0 {
                                Stepper("\(settings.video_fps_cap) fps", value: $settings.video_fps_cap, in: 15...60, step: 5)
                                    .font(.callout)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.callout)
```

`DisclosureGroup` defaults to collapsed, which is the requirement — the default
sidebar must look exactly as it does today. Do not add an `isExpanded` binding
or persist the open/closed state; a disclosure group that remembers it was open
defeats the purpose of hiding the complexity.

**Verify**: `xcodebuild ... build` → `** BUILD SUCCEEDED **`, then launch and
confirm the sidebar is visually unchanged until "Advanced" is clicked.

### Step 5: Verify the encodes

Produce a test input — a 4K, 60 fps clip with AAC audio:

```
ffmpeg -f lavfi -i testsrc=size=3840x2160:rate=60:duration=5 \
       -f lavfi -i sine=frequency=440:duration=5 \
       -c:v libx264 -c:a aac -shortest /tmp/vid/src.mp4
ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate -of default=noprint_wrappers=1 /tmp/vid/src.mp4
```

Then run each combination through the app and inspect with `ffprobe`.

**Verify** against this table:

| Resolution | Audio | fps cap | Expected `ffprobe` |
|---|---|---|---|
| Original | Keep original | off | 3840×2160, audio `aac` |
| 1080p | Keep original | off | width 1920, height 1080, **even** dimensions |
| 720p | AAC 96 kbps | off | 1280×720, audio `aac` ~96 kbps |
| 1080p | Remove audio | off | 1920×1080, **no audio stream** |
| Original | Keep original | 30 | 3840×2160, `r_frame_rate=30/1` |
| **4K (2160p)** on a **720p source** | Keep original | off | **still 1280×720 — not upscaled** |

The last row is the `min()` guard. If that output is 3840×2160, Step 3 is wrong.

Also verify a **portrait** input (swap the testsrc size to `2160x3840`)
downscales by height and keeps its aspect ratio.

### Step 6: Document it

- `README.md`: add a bullet for advanced video options near the feature list
  (lines ~12-22), naming resolution, audio and fps. Note they live behind
  "Advanced" in the sidebar.
- `CHANGELOG.md`: add to the existing `## [Unreleased]` section following the
  house style in the 1.0.2 entry — what changed and why it matters, not a
  commit list. State explicitly that defaults are unchanged.

**Verify**: `grep -n -i "resolution" README.md CHANGELOG.md` returns matches in both.

## Test plan

No test target exists, so verification is the Step 5 `ffprobe` matrix. Record in
your report the exact `ffprobe` output for at least the 1080p and the
no-upscale rows.

`VideoResolution.max_height` and `AudioHandling.ffmpeg_args` are pure functions
over enums and are the natural unit tests if a test target is ever added.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `xcodegen generate` exits 0
- [ ] `xcodebuild ... build` exits 0 and prints `** BUILD SUCCEEDED **`
- [ ] `grep -n "scale=-2" Sources/Compressyx/Services/VideoCompressor.swift` returns a match
- [ ] `grep -n "DisclosureGroup" Sources/Compressyx/Views/ContentView.swift` returns a match
- [ ] `grep -n '"-c:a", "copy"' Sources/Compressyx/Services/VideoCompressor.swift` returns **no** matches (it moved into `AudioHandling`)
- [ ] `defaults read com.compressyx.app | grep -E "video_resolution|audio_handling"` returns values after changing them in a running build
- [ ] Every row of the Step 5 table matches, including the no-upscale row
- [ ] With all three controls at their defaults, the generated ffmpeg arguments are byte-identical to today's
- [ ] `git status --porcelain` lists only the six in-scope files plus `plans/README.md`
- [ ] `plans/README.md` status row for 006 updated

## STOP conditions

Stop and report back (do not improvise) if:

- `ffmpeg -version` does not work. You cannot verify anything in this plan
  without it, and shipping unverified encoder flags is how the WebM bug got in.
- The code at the cited locations doesn't match the "Current state" excerpts.
- Scaling makes VideoToolbox fail with an encoder error. Hardware encoders have
  dimension constraints beyond evenness on some Apple silicon; report the exact
  ffmpeg stderr rather than switching to a software encoder, which would silently
  make compression far slower.
- WebM (VP9) output fails once you add the filter. WebM is already suspected
  broken for a different reason — the `-c:a copy` bug listed as out of scope.
  Report whether the filter made it worse, and do not fix the audio bug here.
- `-vf scale` conflicts with something in the existing argument order in a way
  you cannot resolve by reordering within the constraints in Step 3.
- `xcodebuild` fails twice after a reasonable fix attempt.

## Maintenance notes

- Any future video flag goes through `VideoCompressionParams`, never read from
  `CompressionSettings.shared` inside `VideoCompressor` — the service is
  deliberately settings-agnostic and that separation is worth keeping.
- A reviewer should check the `min(H,ih)` guard survives refactors. Without it,
  "compress" can upscale a small video into a much larger file, which is the
  most embarrassing possible behavior for this app.
- Adding more than one `-vf` filter later (a crop, a denoise) requires chaining
  them comma-separated in a single `-vf` argument. A second `-vf` silently
  overrides the first rather than erroring.
- Deferred deliberately: image resolution scaling, trimming, two-pass bitrate
  targeting, and the `-c:a copy` WebM bug.
- If plan 004 (metadata policy) lands, consider whether video metadata should
  follow the same policy via `-map_metadata`. Today video metadata passes
  through untouched, which is inconsistent with whatever images end up doing.
