# 12 — Writer: the app-side plan

The transport and the wire format are settled in doc 11. This document is the iOS side:
what gets built, in what order, where it is allowed to touch the existing app, and the
traps that are already known before a line is written.

## 1. Ratified in chat

- **Backup mode is a three-way setting: Off · Manual · Automatic**, in the profile card.
  Greyed out with a reason when the plugin is not installed.
- **Off shows nothing.** Manual and Automatic both show a `+` on the grid.
- **The picker is ours**, a local grid backed by `PHFetchResult`, reusing the layout, the
  cells, the month sections and the scrubber. `PHPickerViewController` is iOS 14 and
  `UIImagePickerController` takes one photo at a time, so the system pickers are useless
  on the only device this can be tested on.
- **Default scope: the camera roll minus screenshots.** `smartAlbumUserLibrary` minus
  `smartAlbumScreenshots`. Hidden and Recently Deleted are excluded unconditionally.
- ~~**After a successful upload the app inserts the row into its own index**, from the item
  id the plugin returns.~~ **Withdrawn — the plugin cannot return an item id.** Doc 11 §8
  settles it: filing the bytes and Jellyfin noticing them are separate events, the
  notification is debounced by `LibraryMonitorDelay` (60 s, restarted by every sibling), so
  a response carrying an id would promise something the server cannot deliver. The receipt
  is `{ key, path, created }` and nothing more. How the grid learns about an upload is
  therefore still open — see §9.
- **iCloud Photos is off on the target device**, so every original is local. The per-asset
  in-cloud check is still implemented — two lines — so this degrades correctly for someone
  else, but it drives no UI and makes no promise.

## 2. Isolation

The user's requirement is that the writer can be reworked later without disturbing the
reader. The discipline that already worked for `import CoreData` (two files, greppable) is
reused rather than invented.

- **Everything lives under `Writer/`.** One protocol, `UploadService`, declared in the same
  file as its single implementation — the arbitration already made for `PhotoStore`: the
  contract next to its only implementation is the one file to open on the day it changes,
  and it costs no edit to a hand-written `project.pbxproj`.
- **Invariant: `grep -rn "import Photos" jellypic/` returns only files under `Writer/`.**
  Same rule, same reason as Core Data. A hit anywhere else means the seam leaked.
- **No separate framework target.** The pbxproj is hand-written, and a dynamic framework
  costs launch time on an A7 for no benefit in a sideloaded personal app.
- **Exactly four touch points outside `Writer/`**, and they are listed here so that a fifth
  is visible in review:
  1. `Settings/SettingsViewController` — one section.
  2. `Grid/PhotoGridViewController` — one button.
  3. `AppServices` — owns the instance.
  4. `AppDelegate` — background fetch and `handleEventsForBackgroundURLSession`.

**The backup mode is persisted inside `Writer/`, not in `Preferences`.** It is the one
deviation from "every key lives in `Preferences`", and it is deliberate: a `backupMode`
there would make `Auth/Preferences.swift` a fifth file outside `Writer/` that names a
writer type, which is precisely what the count above exists to prevent.

**The writer does not extend `JellyfinAPI`.** That protocol is the reader's network
contract and its migration surface (doc 04); growing it with upload methods would couple
the two halves exactly where we are trying to separate them. `Writer/UploadClient.swift`
builds its own requests.

The one thing that must **not** be duplicated is the 10.11 `Authorization: MediaBrowser …`
header — a second, drifting copy of an auth format is how a client silently falls back to
a legacy header. It moves into a small free function in `Network/`, used by both sides.
That is a new file, not a new protocol method.

## 3. Info.plist, and a bug that exists today

- **`NSPhotoLibraryUsageDescription` is missing.** The app currently declares only
  `NSPhotoLibraryAddUsageDescription`, which covers saving a downloaded photo *into* the
  camera roll and nothing else. Reading the library requires the read key, and its absence
  is not a denied permission — **it is a crash on first access**. This must land before any
  `PHAsset` code.
- **`UIBackgroundModes` must gain `fetch`** for the automatic mode. A background
  `URLSession` needs no background mode; the periodic wake-up does.

## 4. Settings, ratified

```
BACKUP
┌────────────────────────────────┐
│  Off  │  Manual  │  Automatic  │
├────────────────────────────────┤
│ Requires the upload plugin on  │
│ your server                    │
└────────────────────────────────┘
```

A `UISegmentedControl` in a `SettingsGroupView(padding: 8)` — the shape the theme control
already uses — with the state beneath it.

- **`BACKUP` comes first, before `APPEARANCE`.** It is the only section that changes what
  the app *does*, and it sits directly under the card's identity header (library, server,
  "N photos indexed"), which is the same subject.
- **The state is a sentence alone, full width, left-aligned, `numberOfLines = 0`** — not a
  `SettingsRowView`. That row is one line with a right-aligned `Typography.caption` detail
  whose horizontal compression resistance is `.defaultLow`: "Requires the upload plugin on
  your server" truncates to "Requires the u…" on a 320 pt screen, i.e. exactly the message
  that matters is the one that disappears. There is also no useful title to put on the
  left — "Status" carries no information, and the sentence *is* the state. Hence
  `SettingsNoteView`, a label with four constraints, beside `SettingsGroupView` and
  `SettingsRowView` in the same file.
- **When the control is greyed it still shows the user's stored choice**, never Off. The
  preference is not rewritten (below), so painting Off would state something false about
  what is stored, and the control would then appear to move by itself the day the server
  comes back.
- **The `+` on the grid is not part of W1.** It opens the picker, which is W3. Its place is
  ratified: a `FloatingButton` at the **bottom left**. The two `GlyphButton`s in the top
  band fade out over the first 40 pt of scroll — correct for the brand and for settings,
  fatal for an action button — the scrubber owns the right-hand 40 pt for its full height,
  and the halo keeps the button legible over any thumbnail.

The state sentence is the only place that tells the truth about backup, so it must never be
vague:

| Situation | Sentence |
|---|---|
| plugin absent | `Requires the upload plugin on your server` |
| contract mismatch | `Update the upload plugin on your server` |
| target not writable | the `reason` from the preflight, in words |
| nothing known yet, or ready | what the selected mode means |
| running | `18 342 of 20 104 sent` |
| done | `Up to date` |
| paused, token expired | `Signed out — sign in to continue` |

When the plugin is absent or the contract mismatches, the segmented control is disabled
(`isEnabled = false`) and the mode is forced to Off in effect but **not written to
preferences** — a server that comes back should restore the user's choice, not silently
have erased it. A target that is merely not writable does **not** disable the control: the
setting is legitimate, the folder is the problem, and the sentence says so.

### Detection

`PluginsController` is entirely `[Authorize(Policy = Policies.RequiresElevation)]`, so a
non-administrator cannot enumerate plugins. Detection is therefore a call to our own
`GET /UploadForJelly/Targets`, **on each opening of the settings card** — not at launch.
Nothing outside that card consumes the answer until W4, and probing from `AppDelegate`
would spend a request per cold start for a screen most launches never open.

The discrimination must be exact:

- `404` → **not installed**. This is the only status that greys the setting.
- `2xx` whose body does not decode → **contract mismatch**. The endpoint answered, so the
  plugin is there; its answer is a shape we do not understand, which is a version skew and
  nothing else.
- `401`/`403` → session expired; the writer's client reports it through the same
  `onTokenRejected` hook as the reader, so the existing re-auth card owns it.
- anything else, including a timeout → **unknown**; keep the last known state.

Greying the setting whenever the server is unreachable would be both wrong and alarming:
"your plugin is gone" is a very different message from "your phone is on a plane". The last
known state lives in the service for the life of the process and is deliberately not
persisted: a cold start therefore begins at *unknown*, which reads as enabled — the
forgiving direction.

Sign-out resets the mode to Off. Everything else about the account is destroyed there, and
inheriting "Automatic" into the next account is the one failure that would upload without
being asked.

## 5. Reading an asset, and why the obvious API is the wrong one

`PHImageManager.requestImageDataAndOrientation` can hand back a re-encoded rendition. We
promised in doc 11 that **the original is the library**, so a silent JPEG transcode of a
HEIC would break the whole premise.

The correct API is **`PHAssetResourceManager.writeData(for:toFile:options:)`**, which
writes the resource's bytes unmodified, straight to a file. Two consequences, both good:
the bytes are exactly what the camera wrote, EXIF included, and we get the file that a
background `URLSessionUploadTask` requires anyway.

The SHA-256 is computed while that file is written — one pass, no second read.

**Settled: we send the edit.** `PHAssetResource` offers both `.photo` (the camera original)
and `.fullSizePhoto` (the rendered edit) for a retouched asset. We take `.fullSizePhoto`
when it exists and fall back to `.photo` otherwise, because a backup that silently reverts
your crops is a bad backup: what the user sees in Photos is what must arrive on the server.

This does not weaken "the original is the library" — the file is still a full-resolution
rendition written by Photos, never a transcode of ours. But it does mean **re-editing a
photo produces a second file on the server**, since the bytes change and therefore the
SHA-256 changes. Deletion propagation is out of scope (doc 11 §12), so the superseded
version stays. That is the honest cost of this choice and it is the right trade: keeping
one too many is recoverable, silently keeping the wrong one is not.

### What W2 actually built, and the four decisions it forced

`Writer/AssetExporter.swift` is the only file in the app that imports `Photos`, and the
invariant of §2 still holds: `grep -rn "import Photos" jellypic/` returns that one line.

- **`requestData(for:options:dataReceivedHandler:completionHandler:)`, not
  `writeData(for:toFile:)`.** §5 named the latter, and it is still the right *class* of
  API — raw resource bytes, no re-encode — but it writes the file itself, which leaves no
  seam to hash through. The chunked variant hands us each `Data` as it arrives, so the
  `OutputStream` write and the `CC_SHA256_Update` happen in the same pass, which is what §5
  promised. Same guarantee about the bytes, one read instead of two.
- **`CommonCrypto`, not `CryptoKit`.** `CryptoKit` is iOS 13. `import CommonCrypto` has been
  a first-class Swift module since Xcode 10, needs no bridging header, and ships in the SDK,
  so the zero-dependency rule survives. This is *not* marked `LEGACY(ios12)`: `CC_SHA256` is
  not a shim for a missing API, it is a perfectly good one that happens to be older.
- **`OutputStream`, not `FileHandle`.** On the 12.0 floor `FileHandle.write(_:)` reports a
  failed write by raising an Objective-C exception, which Swift cannot catch — a full disk
  would terminate the app. `OutputStream.write(_:maxLength:)` returns the count and exposes
  `streamError`, and its short-write loop is three lines.
- **Every `+` in the query is percent-encoded by hand.** `URLQueryItem` does not encode `+`,
  because it is a legal query character; ASP.NET's model binder then reads it as a space. A
  `capturedAt` of `2026-09-21T18:42:33+02:00` would arrive as `18:42:33 02:00`, fail to
  parse, and file the photo under `undated/` — a silent wrong answer, not an error. So the
  request rewrites `percentEncodedQuery` and replaces `+` with `%2B` after building it,
  which also covers a `+` in a filename.

Two smaller things settled while building it:

- **The device slug is the hardware model identifier** (`iPhone6,1`), read from `uname`, not
  `UIDevice.current.name`. The name is user-chosen and routinely contains a person's real
  name; it would end up in every filename on the server. The plugin slugifies whatever it
  receives, so `iPhone6,1` lands as `iphone6-1`.
- **`capturedAt` is sent as a local wall clock with its offset**, formatted
  `yyyy-MM-dd'T'HH:mm:ssXXXXX` under `en_US_POSIX`. The plugin parses it as a
  `DateTimeOffset` and then takes `.DateTime`, i.e. it keeps the wall clock and drops the
  zone — deliberately, per doc 11 §8. Known and accepted residual: `PHAsset.creationDate`
  is an absolute instant with no capture timezone attached, so a photo taken abroad is
  rendered in the *current* zone and can land in a neighbouring month's folder. It affects
  the folder only; Jellyfin reads EXIF for the timeline and the reader sorts on
  `PremiereDate`. Same class of residual as the video date question measured in doc 10, and
  the same verdict: do not add a correction on theory.

The staging directory is `Library/Caches/Uploads`, swept on `JellyfinUploadService.init`
rather than from `AppDelegate` — the sweep is a writer concern and routing it through
`AppDelegate` would spend one of the four touch points of §2 on a `try?`.

## 6. The queue

**A temporary file per pending upload is the binding constraint.** 20 000 × 3 MB is 60 GB;
the queue therefore materialises a window of one to three assets, and re-arms on each
completion. It is slower than a fat pipeline and it is the only shape that fits.

- A single background `URLSession` with a **stable identifier**, recreated at launch with
  that same identifier. Two sessions sharing an identifier is a hard failure, so the
  instance is owned by `AppServices` and created once.
- `allowsCellularAccess = false` by default, overridable.
- `isDiscretionary = true` in Automatic — the system picks charging and Wi-Fi — and
  **never** in Manual, where the user is watching the screen.
- Orphaned temporary files are swept at launch. A crash mid-upload otherwise leaks a file
  per attempt, forever.
- The error taxonomy of doc 11 §10 is implemented as written: `409`/`507` stop the whole
  queue and raise the banner, `422`/`413` fail one item, `5xx` and timeouts back off. A
  `401` pauses and reuses the existing re-auth card rather than failing 20 000 items.

## 7. Milestones

**W0 — Info.plist.** The read usage description and the background mode. Nothing visible.
*Device test: the app still launches and the existing share-to-camera-roll still works.*

**W1 — detection and the settings section.** The `Backup` section, the preflight call, the
three-way control, the status row. Nothing uploads.
*Device test: with the plugin absent the control is greyed with the right sentence; in
airplane mode it is NOT greyed; installing the plugin enables it without reinstalling the
app.*

**W2 — one photo, end to end.** `UploadService`, `UploadClient`, `PHAssetResourceManager`
to a temp file, SHA-256 in the same pass, `POST /Items`. Driven from a debug entry point, no
picker yet. The plugin needs only `Targets` and `Items` at this stage. **No index insertion**
— see §1: there is no item id to insert from.
*Device test: the call returns `created: true` with a path in the right month folder; a
resync then shows the photo in the grid, and opening it shows the real original — not a
re-encode. Sending the same photo twice returns `created: false` and produces no second
file.*

**W3 — the picker.** The biggest piece of UI in the writer: a `PHFetchResult`-backed grid
with multi-selection. Design ratified in chat, §10 below.

**W4 — the queue.** The window, resumption, the error taxonomy, the Wi-Fi and discretionary
policy, the pause on token expiry, the launch sweep.
*Device test: send 200 photos, kill the app mid-run, relaunch, and confirm it resumes
without re-sending; then remount the library read-only and confirm the queue stops at once
with the reason instead of retrying.*

**W5 — automatic.** Background fetch enqueues; `handleEventsForBackgroundURLSession`
relaunches the app to finish.
*Device test: photograph something, lock the phone, and confirm it arrives without opening
the app.*

**W6 — reconciliation.** `POST /Have` in batches of 500, and a full-library pass that finds
everything never sent.
*Device test: 20 000 photos reconciled in ~40 requests and no iCloud traffic.*

## 8. What is legacy, and what only looks like it

`// LEGACY(ios12):` markers this adds:

| Site | Freed at |
|---|---|
| `setMinimumBackgroundFetchInterval` + `performFetchWithCompletionHandler` instead of `BGTaskScheduler` | iOS 13 |
| `PHPhotoLibrary.requestAuthorization` with no `.limited` branch | iOS 14 |

**The custom picker is NOT legacy debt.** It is the same call as the grid in CLAUDE.md.
Three reasons, and the third is the one that settles it:

- `UIImagePickerController` takes **one photo per presentation**, and
  `PHPickerViewController` is **iOS 14**. At the 12.0 floor there is no native
  multi-selection picker at all, so ours is not a preference.
- PHPicker runs out of process, so it cannot carry the app's palette, its squircles or its
  month scrubber — two devices would give two different experiences.
- **PHPicker hands back `NSItemProvider`, and `loadFileRepresentation` may transcode** — a
  HEIC can arrive as a JPEG, which breaks "the original is the library" (doc 11 §2). To
  get the real bytes you must build it with `PHPickerConfiguration(photoLibrary:)`, read
  `assetIdentifier`, re-fetch the `PHAsset` and go through `PHAssetResourceManager`
  anyway — i.e. keep all of the asset code *and* request full library authorisation,
  which is the one thing PHPicker exists to avoid.

Adopting it behind `if #available(iOS 14)` would therefore add a second picker rather than
remove ours, on a path that cannot be tested on any reachable device. Do not "fix" this
when the SDK rises.

## 9. Still open

- **How the grid learns about a photo it just sent.** The plugin returns no item id (§1) and
  the reader has no incremental sync, so today the answer is "at the next resync". The
  options, none chosen: a single targeted `/Items` query after a run, keyed on the 16 hex
  characters the filename carries, once the debounced scan has had time to fire; or
  `POST /Library/Media/Updated` to skip the debounce and then query. Both cost a round trip
  and a delay, and neither is worth designing before W4 makes "a run" a thing that ends.
- **The local hash memo of doc 11 §5** (`localIdentifier + modificationDate → sha256`) is
  not built. W2 hashes one photo on demand; the memo only pays for itself once W4 retries
  and W6 reconciles.
- **The background `URLSession` is not in yet.** W2 uploads from a foreground session with a
  one-hour resource timeout. W4 owns the switch, and it is not a drop-in: a background
  session forbids the per-task completion handler this code uses, so `UploadClient` gains a
  delegate then. The `upload(_:targetId:completion:)` signature is meant to survive it.
- Live Photos, bursts, albums, and deletion propagation are out of scope for v1 by doc 11
  §12; each is a contract change before it is an app change.

## 10. The picker (W3), ratified

```
┌──────────────────────────────┐
│ Cancel        12 selected    │  56 pt, the grid's own band geometry
├──────────────────────────────┤
│ September 2026               │
│ ▣▣▣  ▣▣▣  ▢▢▢             ┃S┃
│ ▣▣▣  ▢▢▢  ▢▢▢             ┃c┃
│ August 2026                ┃r┃
│ ▢▢▢  ▢▢▢  ▢▢▢             ┃u┃
│         ╭───────────╮      ┃b┃
│         │ Send 12   │         │
│         ╰───────────╯         │
└──────────────────────────────┘
```

- **Full-screen modal.** The picker *is* a grid, so it needs the whole height; on a 5s a
  card sheet leaves ~380 pt of scroll and a scrubber with no useful travel. Its band
  reuses the grid's 56 pt geometry: `Cancel` on the left where the brand lives, the count
  centred.
- **Selected = inset 6 pt + a check badge bottom-right.** The inset opens a visible
  gutter, so selection reads as a *shape* and survives a white photo as well as a black
  one — the defect already fixed once on the grid's ⋯ button. The badge is a 22 pt accent
  pill carrying a new `CheckGlyphView` in `Design/`, drawn like every other glyph.
- **Send is a floating pill, absent at zero selection.** It fades in and rises 8 pt on the
  first tap, so the screen never shows a dead control, and it sits in the thumb's reach —
  which the top-right corner is not. Same squircle and halo as `FloatingButton`.
- **Nothing is marked as already sent.** On confirm we hash the selection and call
  `POST /Have`; what the server already has is dropped silently. Painting the grid would
  mean hashing the whole camera roll on open — 20 000 byte-for-byte reads — and would
  create a second client-side truth, which doc 11 §2 refuses.
- **No select-all, no drag-to-select.** Manual mode is deliberate selection; "send
  everything" is W6 reconciliation, which does it without 20 000 taps. A pan-select
  gesture fights both the scroll and the scrubber, and is purely additive later.

### Traps, before the first line

- **`PhotoCell` is not reusable and must not be made reusable.** Its `configure` takes an
  `ImageLoader` and an `itemId`; the picker's images come from `PHImageManager`, and
  `import Photos` may not appear under `Grid/`. The picker gets its own cell under
  `Writer/`, sharing only `GridMetrics`. Roughly forty duplicated lines, and that is the
  price of the invariant — pay it, do not "fix" it.
- **Never materialise the `PHFetchResult`.** It is lazy by design; mapping it to
  `[PHAsset]` is 20 000 objects on a 1 GB device. Index into it, and derive the month
  sections from one `enumerateObjects` pass over `creationDate` alone.
- **Selection is a `Set<String>` of `localIdentifier`, never a set of indexes.** A library
  change shifts indexes under us; the identifier is stable.
- **`PHCachingImageManager`, with `stopCachingImagesForAllAssets()` on dismiss.** Without
  the prefetch the A7 cannot fill a fast scroll; without the stop the cache outlives the
  screen. `deliveryMode = .opportunistic` calls the handler twice — guard on the cell's
  token exactly as `PhotoCell` already does.
- **The 6 pt inset is a `transform`, not a layout change.** Re-laying out a cell per tap
  is work the A7 does not need to do.
