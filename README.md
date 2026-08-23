# Compressyx

A native macOS app for batch video and image compression. Built with SwiftUI, powered by FFmpeg, pngquant, and cwebp.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Video compression** with hardware-accelerated H.264/H.265 encoding via VideoToolbox
- **Image compression** for PNG (pngquant), JPEG, HEIC, WebP (cwebp), TIFF, and BMP
- **Drag and drop** files or whole folders — folders are expanded recursively
- **Batch processing** — queue multiple files and compress them all at once
- **Quality presets** — Highest, High, Medium, Low
- **Advanced video options** (behind "Advanced" in the sidebar) — downscale to 4K/1440p/1080p/720p/480p, re-encode or remove audio, cap the frame rate
- **Metadata control** — preserve EXIF, remove just the GPS location, or strip everything
- **Output formats** — video: MP4, MOV, MKV, WebM; image: JPEG, PNG, HEIC, WebP; or same as input
- **Real-time progress** in the app and in the Dock icon
- **Cancellation** — stop individual files or the entire batch
- **Retry failed** items with one click
- **Customizable keyboard shortcuts**
- **Auto-updates** via Sparkle
- **One-click dependency installation** from Settings — install all missing tools at once

### Supported Formats

| Type  | Formats                                          |
|-------|--------------------------------------------------|
| Video | MP4, MOV, M4V, AVI, MKV, WebM, WMV, FLV        |
| Image | JPG, JPEG, PNG, HEIC, HEIF, WebP, TIFF, BMP     |

## Screenshots

<!-- Add screenshots here -->
<!-- ![Main Window](screenshots/main.png) -->
<!-- ![Settings](screenshots/settings.png) -->

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16+ (to build)
- [Homebrew](https://brew.sh) (for dependencies)

### Runtime Dependencies

| Dependency | Purpose | Install |
|------------|---------|---------|
| [FFmpeg](https://ffmpeg.org) | Video compression | `brew install ffmpeg` |
| [pngquant](https://pngquant.org) | PNG compression | `brew install pngquant` |
| [cwebp](https://developers.google.com/speed/webp) | WebP compression | `brew install webp` |

> Both can also be installed from the app's **Settings → Dependencies** tab with one click.

## Getting Started

### 1. Clone

```bash
git clone https://github.com/treboryx/compressyx.git
cd compressyx
```

### 2. Install build tools

```bash
brew install xcodegen
```

### 3. Generate Xcode project

```bash
xcodegen generate
```

### 4. Open and run

```bash
open Compressyx.xcodeproj
```

Then press **Cmd+R** in Xcode to build and run.

### 5. Install runtime dependencies

Either from the terminal:

```bash
brew install ffmpeg pngquant webp
```

Or from within the app: **Settings → Dependencies → Install**.

## Keyboard Shortcuts

| Action     | Default Shortcut |
|------------|-----------------|
| Add Files  | `Cmd+O`        |
| Compress All | `Cmd+Return` |
| Cancel     | `Cmd+.`        |

All shortcuts are customizable in **Settings → Shortcuts**.

## Settings

| Option | Description |
|--------|-------------|
| Video Codec | H.264 or H.265 (HEVC) |
| Quality Preset | Highest / High / Medium / Low |
| Output Format | Same as input, MP4, MOV, MKV, or WebM |
| Output Folder | Same directory as source, or a custom folder |
| Remove Input File | Delete the original after successful compression |

## Architecture

```
Sources/Compressyx/
├── CompressyxApp.swift          # App entry point, Sparkle updater
├── Models/
│   ├── CompressionItem.swift   # File state, progress, cancellation
│   ├── CompressionQueue.swift  # Batch queue, dock progress
│   └── CompressionSettings.swift # Codecs, quality, output prefs
├── Services/
│   ├── VideoCompressor.swift   # FFmpeg wrapper with progress parsing
│   ├── ImageCompressor.swift   # pngquant + cwebp + native image APIs
│   └── ThumbnailGenerator.swift
├── Views/
│   ├── ContentView.swift       # Main window layout
│   ├── DropZoneView.swift      # Drag-and-drop target
│   ├── FileListView.swift      # Queue display
│   ├── FileRowView.swift       # Individual file row
│   ├── SettingsView.swift      # Tabbed settings window
│   └── UpdaterView.swift       # Check for Updates menu item
└── Utils/
    ├── FileUtils.swift         # File type detection, size formatting
    └── Shortcuts.swift         # Keyboard shortcut definitions
```

### How It Works

- **Video**: Shells out to `ffmpeg` using `hevc_videotoolbox` (H.265) or `h264_videotoolbox` (H.264) for hardware-accelerated encoding. Falls back to software CRF encoding for WebM (VP9). Progress is parsed from FFmpeg's pipe output.
- **Images**: JPEG and HEIC output go through ImageIO (`CGImageSource`/`CGImageDestination`), which carries EXIF and ICC through the re-encode. PNG output goes through `pngquant` and WebP through `cwebp`; sources those tools can't read are transcoded to PNG first. TIFF and BMP are decoded but written as JPEG when "same as input" is selected.
- **Metadata**: *Preserve* keeps everything, *Remove location* drops the GPS block, *Remove all* strips every tag. Orientation always survives — under *Remove all* the rotation is baked into the pixels instead. **PNG output cannot carry metadata**: PNG has no EXIF container and `pngquant` discards ancillary chunks, so PNG output is always metadata-free regardless of the setting.
- **Video downscaling** uses `scale=-2:'min(H,ih)'`, which preserves aspect ratio, keeps dimensions even for H.26x, and never upscales a smaller source.
- **Concurrency**: Swift 6 strict concurrency with `@Observable` and `@MainActor`. Compression runs in background tasks with cancellation support via `Process.terminate()`.

## Releasing

Releases happen **automatically** on every push to `main`. The GitHub Actions workflow will:

1. Extract the version from `project.yml`
2. Build a Release configuration
3. Create a DMG with an `/Applications` symlink
4. Create a GitHub release with the DMG attached
5. Update `appcast.xml` for Sparkle auto-updates
6. Push the updated appcast back to `main`

If a release for the current version already exists, the workflow skips — so bump `MARKETING_VERSION` and `CFBundleShortVersionString` in `project.yml` before pushing to create a new release.

### Manual releases

A release script is also included for local builds:

```bash
export GITHUB_REPO="treboryx/compressyx"
./scripts/release.sh 1.0.1
```

### First-time setup

Generate Sparkle signing keys (stored in your Keychain):

```bash
./scripts/generate-keys.sh
```

Copy the public key to `project.yml` → `SUPublicEDKey`.

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [Sparkle](https://github.com/sparkle-project/Sparkle) | 2.0+ | Auto-updates |
| [DockProgress](https://github.com/sindresorhus/DockProgress) | 5.0+ | Dock icon progress bar |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | 2.0+ | Customizable shortcuts |
| [SettingsAccess](https://github.com/orchetect/SettingsAccess) | 2.0+ | macOS Settings window |

## License

MIT
