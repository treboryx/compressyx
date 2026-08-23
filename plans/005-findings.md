# Plan 005 findings — compress from the Finder

Investigated 2026-08-23 against commit `5c5f8b8`, on macOS 26 / Xcode 26.2.

## Recommendation

**Build it, via `NSServices` — not an app extension.** A Services entry declared
in the existing app target's `Info.plist` registers successfully with no new
target, no framework split, and no App Group. That removes every architectural
risk this spike was written to investigate: the two questions most likely to kill
the design (does the compression code need to move into a shared framework, and
can an extension spawn Homebrew binaries) are both **moot**, because the service
is handled in-process by the app itself — the same process that already runs
`ffmpeg` today. Estimated effort drops from **L to S–M**.

## Q1 — Which extension point? **ANSWERED: Services**

Tested empirically rather than by reading docs. I copied the built
`Compressyx.app` to a scratch directory, injected an `NSServices` array into its
`Info.plist` with PlistBuddy, ad-hoc re-signed it, and registered it:

```
lsregister -f <path>/Compressyx.app
/System/Library/CoreServices/pbs -flush
/System/Library/CoreServices/pbs -dump_pboard
```

The service appears in the pasteboard-services registry:

```
NSBundleIdentifier = "com.compressyx.app";
NSMenuItem = { default = "Compress with Compressyx"; };
NSMessage = compressFiles;
NSPortName = Compressyx;
NSSendFileTypes = ( "public.image", "public.movie", "public.folder" );
```

`public.folder` is accepted alongside the file types, so a Finder selection of
mixed files and folders reaches the app in one message — which is exactly what
`FileUtils.expand(urls:)` (plan 003) was built to consume.

The other two routes are **not needed** and should not be pursued:

- **Finder Sync / Action extension** — a separate target and process. Buys
  richer menu placement at the cost of the framework split, an App Group, and
  the Homebrew-spawning risk. Not worth it for this gesture.
- **Automator `.workflow` Quick Action** — ships as a separate installable
  artifact, awkward to distribute inside a DMG and awkward to update via
  Sparkle. Rejected.

## Q2 — Does the compression code need to move? **NO**

Moot given Q1. `NSServices` is handled by an object in the running app, so
`ImageCompressor`, `VideoCompressor` and `CompressionQueue` stay exactly where
they are. `project.yml` gains an `info.properties.NSServices` block and nothing
else — no new target, no `Sources/` reorganisation.

The `CompressionSettings` cross-process concern raised in the plan also
disappears: there is only one process, so the existing
`UserDefaults.standard`-backed `@MainActor` singleton is fine as-is, and the
`settings.*` keys persisted since 1.0.2 need no migration.

## Q3 — Can an extension shell out to Homebrew binaries? **MOOT**

This was flagged as the highest-risk unknown and a potential blocker on the
unresolved ffmpeg-bundling licensing question. It no longer applies: the service
handler runs inside the main app, which is not sandboxed
(`ENABLE_APP_SANDBOX: false` in `project.yml`) and already spawns
`/opt/homebrew/bin/{ffmpeg,pngquant,cwebp}` successfully in production.

**This spike therefore does not become blocked on bundling ffmpeg.** That
finding stays open on its own merits (adoption for non-Homebrew users), but it is
no longer a prerequisite for Finder integration.

## Q4 — What happens after the click? **Recommendation: hand off to the app**

Recommend: the service adds the selection to the queue, brings the window
forward, and lets the user press Compress. Do **not** compress silently.

The reason is concrete and specific to this app: `remove_input_file` is a
persisted setting. A silent background compression triggered from a Finder
right-click could delete the user's originals using a preference they set weeks
ago and cannot see at the moment of the click. Handing off keeps the settings
visible before anything destructive happens, needs no new progress or error
surface for a windowless context, and is far cheaper to build.

A "Compress immediately" variant could be added later as a *second* service
entry, once there is a notification path for failures.

## Q5 — What does the release workflow need? **NOTHING**

Verified by inspection of `.github/workflows/release.yml` (not modified, per the
plan's scope). The "Sign app bundle" step signs Sparkle's nested helpers
inside-out, then frameworks, then the app. An `NSServices` declaration adds no
nested signable code — it is Info.plist metadata inside the existing bundle,
covered by the app signature that already exists.

Had this gone the extension route, `Contents/PlugIns/<name>.appex` would have
needed its own `codesign --options runtime` pass before the outer bundle, plus
verification that `--deep --strict` still passed. Avoided entirely.

## Follow-up plan sketch

Small enough to be one plan, roughly S–M:

1. **`project.yml`** — add `NSServices` under the target's `info.properties`:
   `NSMessage: compressFiles`, `NSPortName: Compressyx`, `NSMenuItem.default:
   "Compress with Compressyx"`, `NSSendFileTypes: [public.image, public.movie,
   public.folder]`.
2. **New `Sources/Compressyx/Services/ServiceHandler.swift`** — an
   `NSObject` subclass with
   `@objc func compressFiles(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>)`.
   Read `NSURL` objects off the pasteboard, pass them straight to
   `queue.add_files(_:)` — which already expands folders and dedupes as of
   plan 003.
3. **`CompressyxApp.swift`** — register the handler via
   `NSApplication.shared.servicesProvider = ...` at launch, and call
   `NSUpdateDynamicServices()` once so the entry registers on first run.
4. **Reaching the queue** — this is the one real design question left.
   `CompressionQueue` is currently `@State` private to `ContentView`
   (`ContentView.swift:5`), so a service handler cannot see it. Either lift the
   queue to a shared singleton like `CompressionSettings.shared`, or route
   through an `AppDelegate` that holds it. Lifting it is cleaner and is a small,
   contained refactor.
5. **Verification** — `pbs -dump_pboard | grep Compressyx` for registration, then
   a real Finder right-click on a mixed file/folder selection.

## Blockers

None architectural. One open design question — item 4 above, how the service
handler reaches the queue — which is a small refactor, not a risk.

## What I did not test

Stated plainly, because the registration test is not the same as the feature
working:

- **The menu item actually appearing in Finder's right-click menu.** I confirmed
  registration in the services registry, not the rendered menu. macOS filters the
  Services menu by selection type and by whether the user has enabled the entry
  under System Settings → Keyboard → Keyboard Shortcuts → Services. Some services
  arrive disabled by default. This needs a human with a mouse.
- **The round trip.** No `compressFiles` handler was implemented, so nothing
  verified that the pasteboard actually delivers the URLs, or that a folder
  arrives as one `NSURL` rather than pre-expanded by Finder.
- **Behaviour when the app is not running.** `NSPortName` should launch it;
  untested.
- **Signed + notarized behaviour.** The test bundle was ad-hoc signed and run from
  a scratch directory. Services registration can behave differently for a
  quarantined app launched from `/Applications`.

The first and second of those are the ones that could still cost real time. They
are cheap to check once item 4 is done.
