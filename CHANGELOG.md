# Changelog

All notable changes to Compressyx are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] — 2026-08-23

### Added

- WebP output, via `cwebp`. Works from every supported input, including HEIC.
  On a 600×600 sample it produced the smallest file of any format — 12.5 KB,
  against 15.4 KB for HEIC and 43 KB for JPEG.
- **Install All Missing** in Settings → Dependencies, which installs FFmpeg,
  pngquant and cwebp in a single Homebrew invocation.
- Settings now persist across launches. Codec, quality preset, output formats,
  output folder, delete-original and concurrency are all remembered.

### Fixed

- **The image output format picker did nothing.** It changed the output file's
  extension without changing the encoder, so choosing PNG → JPEG wrote PNG bytes
  into a file named `.jpg`. The encoder is now selected from the chosen format
  rather than the input file's extension.
- **WebP output silently produced nothing.** The old code encoded JPEG, wrote it
  to a sibling `.jpg` path, then reported success for a `.webp` file that was
  never created — surfacing in the UI as a 0-byte compression.
- TIFF and BMP with "same as input" selected produced a file named `.tiff`
  containing JPEG data.
- PNG output from a non-PNG source failed, because pngquant only reads PNG.
  Such sources are now transcoded first.
- When pngquant declined to compress, the fallback copied the *original* input
  to the output path, which could write JPEG bytes to a `.png` name.
- The Dependencies tab's Install buttons did nothing when Homebrew was absent.
  It now says Homebrew is required and links to brew.sh.

### Changed

- Dependency status refreshes when the Settings tab appears, so tools installed
  in Terminal are picked up without relaunching.
- A failed install now names the exact `brew install` command to run manually.
- `compress()` verifies the output file exists before returning, so an encoder
  that writes nothing fails loudly instead of reporting a 0-byte success.

## [1.0.1] — 2026-08-23

### Changed

- New app icon.
- `CFBundleVersion` now tracks the marketing version instead of being pinned
  at `1`.

## [1.0.0] — 2026-08-23

First release under the Compressyx name, signed with a Developer ID certificate
and notarized by Apple. Installs and updates without Gatekeeper warnings.

### Added

- Batch video compression with hardware-accelerated H.264/H.265 via VideoToolbox.
- Image compression for PNG, JPEG, HEIC, TIFF and BMP.
- Drag and drop for files and folders.
- Quality presets, output format selection and a configurable output folder.
- Live progress in-app and on the Dock icon; per-item and batch cancellation.
- Retry for failed items.
- Customizable keyboard shortcuts.
- Automatic updates via Sparkle.

[1.0.2]: https://github.com/treboryx/compressyx/releases/tag/v1.0.2
[1.0.1]: https://github.com/treboryx/compressyx/releases/tag/v1.0.1
[1.0.0]: https://github.com/treboryx/compressyx/releases/tag/v1.0.0
