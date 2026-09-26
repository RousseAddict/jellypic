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

`Writer/AssetExporter.swift` was the first file in the app to import `Photos`. It is now
five — `AssetExporter`, `AssetPickerViewController`, `AssetGridCell`, `UploadService`,
`UploadQueue` — and the invariant of §2 is the one that matters, not the count:
`grep -rn "import Photos" jellypic/` returns only files under `Writer/`.

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
**W4 shipped that window at one**, and §12 records why; **W5 widened it to three** once the
system, rather than a begged-for background task, does the scheduling — §13.

- A single background `URLSession` with a **stable identifier**, recreated at launch with
  that same identifier. Two sessions sharing an identifier is a hard failure, so the
  instance is owned by `AppServices` and created once. Built in W5, §13.
- `allowsCellularAccess = false`. Not overridable: nothing in the UI offers it.
- ~~`isDiscretionary = true` in Automatic, never in Manual.~~ **Reversed in W5:
  `isDiscretionary = false` always.** A `URLSessionConfiguration` is *copied* at session
  construction and a background session cannot be reconfigured, so one session could never
  have carried a per-mode flag. §13.
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

W2's second half — *the photo appears* — no longer costs a resync. The reader gained a
one-request catch-up on `minDateLastSaved` (docs/06 §5.4), fired from the grid's
`viewDidAppear`, from `didBecomeActive` and from the settings card's `onDismissed`, plus a
pull-to-refresh with a 48-hour lookback. The send alert says the photo is not there yet
rather than implying it is: the server's `LibraryMonitorDelay` is 60 s on this library and
no client-side trick beats it. This is a top-up, not a proof of the library — **W6's
`Have` reconciliation is still the only thing that establishes what the server does and
does not have.**

**W3 — the picker.** The biggest piece of UI in the writer: a `PHFetchResult`-backed grid
with multi-selection. Design ratified in chat, §10 below; built, §11 records where the
build departs from §10 and why.

**W4 — the queue.** The window, resumption, the error taxonomy, the Wi-Fi and discretionary
policy, the pause on token expiry, the launch sweep.
*Device test: send 200 photos, kill the app mid-run, relaunch, and confirm it resumes
without re-sending; then remount the library read-only and confirm the queue stops at once
with the reason instead of retrying.*

**W5 — automatic.** Background fetch enqueues; `handleEventsForBackgroundURLSession`
relaunches the app to finish. Built; §13 records what it reversed on the way.
*Device test: photograph something, lock the phone, and confirm it arrives without opening
the app.*

**W6 — reconciliation.** `POST /Have` in batches of 500, and a full-library pass that finds
everything never sent. Built; §14 records what it costs and where it stops.
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

- ~~How the grid learns about a photo it just sent.~~ Answered by the `minDateLastSaved`
  catch-up (docs/06 §5.4). What is still open is only the *delay*: the server's
  `LibraryMonitorDelay` is 60 s, so the catch-up that runs the instant the picker closes
  finds nothing and the one after it does. `POST /Library/Media/Updated` would skip the
  debounce; not worth a second contract before W4 makes "a run" a thing that ends.
- **The local hash memo of doc 11 §5** (`localIdentifier + modificationDate → sha256`) is
  not built. W2 hashes one photo on demand; the memo only pays for itself once W4 retries
  and W6 reconciles.
- ~~The background `URLSession` is not in yet.~~ **Built in W5** (§13). It was not a
  drop-in: a background session forbids the per-task completion handler, so `UploadClient`
  became the project's first `URLSessionDataDelegate` and reports outcomes keyed by
  `localIdentifier`. `upload(_:targetId:completion:)` survived, retargeted at the
  foreground `uploadSession`, and now means exactly one thing — the Settings *Send my
  latest photo* diagnostic.
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

## 11. What W3 built, and the four places it departs from §10

`Writer/AssetPickerViewController.swift` + `Writer/AssetGridCell.swift`, reached from a
`GlyphButton(glyph: PlusGlyphView(), prominent: true)` in the grid's top band, left of the
map and settings glyphs. The button is **hidden unless `mode != .off` and
`availability == .ready`** — an entry point that opens onto a refusal is worse than no
entry point. Availability is re-probed in `viewDidAppear` and in the settings card's
`onDismissed`, the two moments it can have changed.

The band was a reversal: a floating `+` bottom-right, level with the scrubber, was built
first and rejected on sight — a second floating control beside the scrubber crowds the
corner the scrubber already owns. Living in the band costs the action the **40 pt scroll
fade** the other two glyphs have, which is why the bottom was chosen in the first place.
It fades with them rather than against them: three glyphs on one row that behave
differently read as a bug, and `isUserInteractionEnabled` follows the alpha so a
transparent 44 pt target cannot eat taps on the photo beneath. The `+` is 18 pt at 1.5 pt
stroke, not 20 at 2 — a cross reaching the corners of its box outweighs a ring of the
same box, which is empty at the corners.

**No `POST /Have`.** §10 said the confirm step hashes the selection and asks the server
what it already holds. It does not, and the reason is that `/Have` buys nothing here: a
SHA-256 needs a full byte-for-byte read of the asset, which is the *same read* the export
already performs, so a `Have` pass costs a second pass over every selected photo to save
a request that `UploadWriter.WriteAsync` already answers for free — it returns
`created:false` on an existing hash without ever touching the request body. Duplicates are
therefore correct, just not free. `/Have` remains W6's, where it reconciles 20 000 photos
the app never selected and the hash memo of doc 11 §5 makes the read amortise.

**No new `CheckGlyphView`.** `Design/Icons.swift` already had `SelectionIndicatorView` —
a 22 pt accent ring with an animating `CheckmarkView` and an `applyTheme`. Reused as-is.

**The month key is local time, not UTC.** `MonthKey` (`Index/PhotoItem.swift`) formats in
UTC because it keys server items whose `PremiereDate` is wall-clock EXIF. Applying it to
`PHAsset.creationDate`, which is a real instant, would file a photo taken at 21:00 on 30
September under October. The picker carries its own `"yyyy-MM"` formatter in the device's
timezone. `MonthHeaderView` renders either key identically, so nothing else changes.

**The picker stays up during the send, and the grid owns the alert.** The `Send n` pill
becomes `Sending 3 of 12`, the collection view stops taking touches, and `Cancel` becomes
`Stop`. `UploadService.send` is sequential — export, `POST /Items`, discard, next — driven
by a self-tail-calling `sendNext` that is not recursion in any costly sense: every
completion hops to the main queue, so the stack never grows. `cancelSend()` bumps the same
`sendToken` the run captured, so the in-flight callback takes the guard exit, clears
`isSending` and fires the completion with the tally so far — a stop can never hang the
picker. On completion the picker dismisses and the *grid* presents the summary, because an
alert on a view controller that is disappearing is an alert nobody sees.
**W4 reverses this one deliberately — see §12.**

## 12. What W4 built

`Writer/UploadQueue.swift`, beside `UploadService.swift` so that file stays the policy
layer: the queue owns the durable list, the run loop, the backoff, the background task and
the notification, and nothing else.

**Tap Send and the picker closes at once.** That reverses §11's answer, which was the right
one for a send you had to watch and the wrong one for a run that now outlives the screen.
The grid's existing banner carries it instead — the same pill, the same
`… Tap to retry.` shape a failed sync already uses, so there is no new UI and no new
concept.

### Durability is cheap because the upload is idempotent

`POST /UploadForJelly/Items` answers 201 on create and 200 on replay (doc 11 §8), so a
photo the process died on costs one request and produces no second file. The queue
therefore does **not** write per completion: it persists every 10 completions, and
unconditionally on `willResignActive` and in the background-task expiration handler. Worst
case after a kill is a handful of idempotent replays.

One JSON file at `Library/Application Support/Uploads/queue.json`, consumed from the head.
Not `UserDefaults` — `Auth/Preferences.swift` is the reader's surface and §2 keeps backup
state under `Writer/`. Not `Caches/` — that is the *staging* directory precisely because
iOS may purge it, and a pending list must not be purgeable. Not Core Data — a
`PhotoModel.schemaVersion` bump forces a resync of 20 000 rows (doc 06 §2.2) and the queue
is worth none of it.

**The tally is durable too**, or the banner after a relaunch mid-run lies: `Sending N of M`
is computed as `sent + duplicates + failed` against that plus `pending`, so the count has
to survive the kill that the pending list survives.

Two things are deliberately **not** persisted. `stopReason` is an error, not data — a
relaunch re-runs the preflight and re-derives it, which is doc 11 §10's own instruction. And
the last error is kept as its rendered sentence (`lastErrorText`), not as the enum: the
`String` is what the banner shows, and it spares the state file a `Codable` conformance on
a type that exists to be read by a human.

`paused` **is** persisted, and it is the one flag that earns its place: "the user tapped
stop" and "the process was killed" are otherwise the same state — not running, pending > 0,
no stop reason — and they must behave in opposite ways. `UploadQueueState.canAutoResume`
folds that policy into the state, so the grid asks a question instead of carrying a rule.

### The window stays at one

Doc §6 allows one to three. One is the right end of it here: the binding constraint is the
temp file, not throughput, and three in flight would mean cancelling peers the moment one
of them returns a whole-queue refusal. Parallelism pays once the *system* schedules it,
which is W5's background session. Recorded here rather than left to look like an accident.

### The taxonomy, uncollapsed

W3 mapped `.stopQueue(code)` and `.rejected(code)` to the same `.refused(text)`, so a
read-only mount would have failed 200 photos one at a time, each with its own pointless
round trip. A private `Outcome` enum now decides what a failure does to the *queue*:
`halt` keeps the pending list and stops (401, `404`/`409`/`507`, no Wi-Fi, photo access
denied), `retry` backs off 1 s / 4 s / 15 s, `failItem` charges one photo and moves on.
The text tables did not move to a second home — `BackupUploadError.from(_:)` and
`refusalText(_:)` became statics on the error, shared by both the queue's verdict and the
one-photo debug path.

`UploadFailure.offline` is new, and narrow: `NSURLErrorDataNotAllowed` (-1020) is the exact
error `allowsCellularAccess = false` produces when only cellular is up. It is the
user-visible face of the Wi-Fi policy, and everything else stays `.transient`.

### Banner precedence: expired > queue > sync

Three states now want one pill. The precedence is enforced the way expiry already was — a
boolean flag consulted by a guard, not a refactor: `showBanner` (the sync path) refuses
when `isSessionExpired || isQueueBannerVisible`, and `showQueueBanner` refuses to paint
when the session is expired but still raises its flag, so re-authenticating repaints the
run instead of losing it. `hideQueueBanner` falls back to `Indexing…` when a sync is still
running, rather than hiding a banner that has something to say.

The banner is fed by `UploadQueue.didChangeNotification` and not by a closure, for the
reason `Theme.didChangeNotification` exists: `SettingsViewController` holds the same
`services.upload` and a second owner would clobber a closure.

One affordance, and the text says which way it goes: `Sending 3 of 12 — tap to stop` ·
`Paused — tap to resume` · `Your server's photo folder is read-only. Tap to retry.` ·
`2 not sent. … Tap to dismiss.`

**What makes relaunch resume the run** is not a new call site: `updateSendButton()` already
fires from `viewDidAppear`, from `didBecomeActive` and from the settings card's
`onDismissed`, and it now asks `canAutoResume` once availability comes back `.ready`. A
stop reason sends `resumeQueue()` through `refreshAvailability` first — doc 11 §10's
"re-run the preflight" — so tapping a read-only refusal after remounting the library
re-checks before it re-sends.

## 13. What W5 built

The app stops needing you. A photo taken with the app closed is on the server before you
next open it, the transfer is scheduled by the system rather than by a background task we
beg for, and the run reassembles itself after a launch it did not ask for.

### One background session, and `isDiscretionary` reversed

`com.rousseaddict.jellypic.uploads`, shared by Manual and Automatic,
`allowsCellularAccess = false`, `sessionSendsLaunchEvents = true`,
`httpMaximumConnectionsPerHost = 3`, and **`isDiscretionary = false`**, which reverses §6.
Two reasons, and the second is decisive: a personal backup that defers for hours reads as
broken; and a `URLSessionConfiguration` is *copied* at session construction while a
background session cannot be reconfigured, so a per-mode flag was never implementable with
one session — and two sessions sharing work is the failure §6 already forbids.

`timeoutIntervalForRequest` is deliberately **not** set: the 7-day
`timeoutIntervalForResource` default is what lets a transfer survive a night without Wi-Fi.
The foreground `session` (`/Targets`) and `uploadSession` (the diagnostic) are untouched.

### The delegate replaces the façade rather than hiding behind it

A handler registry over a background session works in-process and cannot work after a
relaunch, so an orphan path would have been needed either way — and that path would then
run *only* after a process kill, the one thing you cannot exercise casually on a sideloaded
5s. One `localIdentifier`-keyed callback means the post-relaunch path is exercised by every
upload, forever.

Exactly three delegate methods, and each is load-bearing:

| Method | Why |
|---|---|
| `urlSession(_:dataTask:didReceive:)` | an upload task **is** a data task; the 201/200 JSON body arrives here and nowhere else. Accumulated in `bodies[taskIdentifier]`. |
| `urlSession(_:task:didCompleteWithError:)` | terminal. Feeds the unchanged `receipt(data:response:error:)`, and is the one and only site that discards the staged file. |
| `urlSessionDidFinishEvents(forBackgroundURLSession:)` | the only legal place to call the stored system handler. |

Five traps, in descending nastiness:

- **Conform to `URLSessionDataDelegate`, not `URLSessionTaskDelegate`.** Declaring only the
  latter compiles, `didCompleteWithError` fires normally, and `didReceive data:` is never
  called — so every 2xx has `data == nil`, `receipt` returns `.rejected("INCOMPATIBLE")`,
  and the banner says *Update the upload plugin on your server* about a plugin that works.
- **`delegateQueue: .main`, never `nil`.** `UploadQueue` has no locks and is correct only
  because every mutation is main-queue serialised; a private `OperationQueue` breaks that
  with zero compiler help. `.main` also satisfies "call the background completion handler
  on the main thread" for free, and the bodies are ~100 bytes of JSON.
- **`didReceive response:completionHandler:` is deliberately absent.** Its absence defaults
  to `.allow`; its presence obliges you to call the handler and stalls every upload if you
  forget. Same reasoning for `didSendBodyData` — the banner is per photo, not per byte.
- **`taskIdentifier` is not a correlation key.** Unique within a session, reused across
  launches. Fine for `bodies`, never for the route back to a queue item — that is
  `taskDescription`.
- **A `URLSession` retains its delegate until invalidated**, so `UploadClient` is now
  immortal. Harmless (`AppServices.shared` owns it) but nothing may go in `deinit`.

`NSURLErrorCancelled` is intercepted **before** `receipt` and routed to
`onUploadCancelled`. Cancellation is a lifecycle event, not a network outcome: through
`receipt` it would become `.transient` — three backoff rounds per item on every *stop*, and
a force-quit, which cancels every task, would charge three failures against the tally.

### The window widens to three, and `retire` is what makes it safe

§12 shipped one because the system was not scheduling; now it is, and with a window of one
the system can end up relaunching the app once per photo. `attempts` moved out of the queue
and into a per-identifier `Slot`: three items backing off against one shared counter
presents as "one photo failed and took two others with it".

**An item leaves `pending` only in `retire`, only on a terminal outcome.** That single
invariant is what makes out-of-order completion safe and what makes `.halt` free — the
peers it cancels were never removed, so they are still pending by construction. `finish`
bumps `runToken`, drains `inFlight` and calls `cancelUploads(for:)`, which matches through
`getAllTasks` on `taskDescription` and **not** an in-memory `[String: URLSessionTask]`:
that map misses tasks adopted after a relaunch, which are exactly the ones a post-relaunch
halt must cancel.

**A crash, not a wrong answer:** no start may complete synchronously, because its
completion mutates `pending` while the pump iterates it. One path did — the
`asset(for:)` → `.failItem` fall-through — and is now wrapped in `DispatchQueue.main.async`.
Invariant: *no completion may be delivered on the same turn of the run loop as the call
that started it.*

The `runToken` discipline is untouched. One bump now orphans three callbacks instead of
one; that is the whole argument for this shape over any alternative.

### `isRunning` redefined, which is a bug fix

```swift
isRunning: isPumpArmed || !inFlight.isEmpty || isReconciling
```

The stored flag means "the pump is armed in *this* process". After a relaunch it is `false`
while three uploads are genuinely in flight, so the banner would read *Paused — tap to
resume* and — worse, without any tap — `canAutoResume` would be `true` and **opening the app
mid-run would restart it**, double-staging live items. The redefinition fixes
`canAutoResume` for free, with no change to its definition and none to the grid. Folding in
`isReconciling` also removes the *Paused* flash between `viewDidAppear` and the
`getAllTasks` callback on a cold start.

### Reconciliation, and why the launch sweep moved

`adoptInFlight` is `getAllTasks`: `.running` → live, `.suspended` → `resume()` + live,
`taskDescription == nil` → `cancel()`. Its completion arrives on the delegate queue, which
is `.main`, so it is ordered against the delegate callbacks rather than racing them.
**Nothing may start work before that callback lands** — not the pump (`run()` guards on
`isReconciling`), not the staging sweep, not the watermark sweep.

Staged filenames became `sha256(localIdentifier)` instead of `UUID()`. Three consequences:
the staging directory is self-describing after a cold start with nothing persisted; a retry
overwrites its own file instead of leaking one per attempt (a real leak in W4's `.retry`
path); and the launch sweep can be handed the live set directly.

W4 ran `exporter.sweep()` in `init`, deleting *every* staged file. Under a background
session, files staged before a kill may still back live tasks. Apple does not document
whether `uploadTask(with:fromFile:)` copies the file for a background session — a DTS forum
reply says it does (APFS clone), Apple's own guidance says delete the file in
`didCompleteWithError`, and `NSInvalidArgumentException "Cannot read file at …"` proves the
path is read at least once. So: **be correct under both answers** and never delete a file
an outstanding task names. The sweep therefore runs inside the reconciliation callback as
`sweep(keeping:)`.

Ambiguity after a relaunch is always resolved in the **forgiving** direction, because
`POST /Items` is idempotent (doc 11 §8): an adopted identifier missing from `pending` — the
kill landed between `retire` and `persist` — is re-inserted at the *head*. One replay beats
a lost photo. `taskDescription` surviving a launch is treated as an optimisation, never as a
contract.

### Persistence gains two mandatory flush points

During a system-driven run the app may be woken only at the *end* of a batch, so
`sincePersist` can go 0 → 3 and never reach 10 before suspension. The counter alone is no
longer sufficient:

| When | New in W5? |
|---|---|
| every 10 terminal outcomes · `willResignActive` · `finish` | no |
| `urlSessionDidFinishEvents`, **before** the system handler | yes, mandatory |
| the background-fetch path, **before** its completion handler | yes, mandatory |

If that ever proves too coarse the fix is an append-only done-log, **not** a smaller
interval: `queue.json` at 20 000 identifiers is ~1 MB and writing it per completion on an A7
is not free. Said here so it does not get tuned into one.

### The blocker that would have silently defeated the milestone

`enqueue` opens with `guard case .ready(let target) = availability`, and `availability` is
`.unknown` on every cold start by design (§4). **A background-fetch wake is a cold start.**
The sweep would have run, found the photo, called `enqueue`, and done nothing — no error, no
banner, no request. The fix is doc 11 §10's own "re-run the preflight", made strictly
sequential: `performBackgroundSweep` guards mode and `PHPhotoLibrary.authorizationStatus()`,
then `refreshAvailability`, then the `.ready` guard, then the enqueue.

`completion(Bool)` maps to `.newData` / `.noData`. Get it wrong and iOS learns not to
schedule us. And **never** call `requestAuthorization` from a background wake — there is no
UI to present; check `authorizationStatus()` and bail on `.notDetermined`.

### The watermark

Turning Automatic on stamps the watermark at *now*: it covers photos taken from then on.
The existing library is what the W3 picker is for, and W6's `POST /Have` is what will offer
to catch it up properly. A switch must never silently start a 7712-photo run.

The stamp is armed in `mode`'s setter, and the `mode != .automatic` guard is load-bearing:
`backupModeChanged` writes `mode` on every `valueChanged`, so without it a stray tap on the
already-selected segment re-stamps the watermark forward and skips photos. Accepted
consequence: **Automatic → Manual → Automatic skips the interval.** Recorded, not reopened.

Three traps in the sweep itself:

- **Advance the watermark to the `creationDate` of the last asset actually enqueued, never
  to `Date()`.** Stamping "now" drops anything created between the fetch and the stamp —
  the classic off-by-one, and it loses photos permanently and silently.
- **`>=` plus a remembered `watermarkIdentifier`, not `>`.** With `>` a burst pair sharing a
  millisecond loses the second forever; with `>=` alone the last photo is re-enqueued on
  every sweep, since `UploadQueue.enqueue` dedupes against `pending`, not against sent.
- `UploadQueue.enqueue` zeroes the tally when `pending.isEmpty && !isRunning`, so a
  background sweep can erase a previous run's "2 not sent" before the user saw it. Accepted;
  named.

The predicate is `mediaType == image AND creationDate >= watermark`, ascending, over the
user library — the same predicate the W3 picker uses, so Automatic covers exactly what the
picker offers and **videos are out of v1 automatic backup**, recorded rather than inherited.

No `PHPhotoLibraryChangeObserver`: the app is not running when you press the shutter, so an
observer cannot deliver the milestone test. It would be pure latency optimisation on top of
the sweep that does all the work.

### `beginBackgroundTask` moves from the transfer to the export

A background session removes the need for it around the *upload*. It does not around the
*export*: `PHAssetResourceManager.requestData` is app code in our process, the system
schedules nothing on its behalf, and staging a 3 MB HEIC on an A7 takes seconds. With a
window of three that is up to three short concurrent background tasks — legal, and ownership
now sits where the work is.

**W4's expiry handler was a W5 regression:** it did `persist()` + `finish(reason: nil)`,
i.e. it stopped the whole queue the first time the phone was locked during an export —
which is the milestone test verbatim. The new handler belongs to the export: close the
stream, delete the partial file, fail *that one export* with `.write`, which `verdict(_:)`
already maps to `.retry(limit: 1)`. The queue is not told anything.

### The two system entry points, and the sweep diagnostic

`AppDelegate` gains `performFetchWithCompletionHandler` and
`handleEventsForBackgroundURLSession` (plus `setMinimumBackgroundFetchInterval`), all three
marked `// LEGACY(ios12):` per §8. If the session identifier does not match, **call the
handler immediately** — nobody else will. Touching `AppServices.shared` there is what
lazily constructs the session, which must happen before events can be delivered.

In `urlSessionDidFinishEvents`: nil the stored handler **before** calling it (a second batch
must not re-call a consumed handler; not calling it at all gets the app killed by the
watchdog), and persist before calling it (the app may be suspended the instant it returns).
Then sweep again — every system wake is another chance to notice new photos, and it costs
nothing.

`didBecomeActive` is observed **here**, in `Writer/`, not in the grid: `UploadQueue` already
observes `willResignActive` from inside `Writer/`, it costs zero touch points against §2's
count of four, and it works when the grid is off screen (connect flow, picker, map). Launch
is covered by `init`.

Settings' Automatic note carries a line built from `lastSweepAt` / `lastSweepResult`. This
is not polish: iOS 12 background fetch is entirely at the system's discretion and the gap
can be hours, so without it the device test cannot distinguish "our code is broken" from
"iOS never scheduled us" — on a sideloaded 5s with no debugger, that is a coin flip, not a
test.

### Testing protocol note that will otherwise waste a day

**Do not force-quit the app from the switcher.** A force-quit cancels every
background-session task with `NSURLErrorCancelled` /
`NSURLErrorCancelledReasonUserForceQuitApplication` *and* suppresses background fetch until
the user manually launches the app again. It looks exactly like a broken implementation.
Background with the Home button; kill from Xcode when a kill is what you mean.

## 14. What W6 built

### `/Have` saves requests, not reads

The milestone's headline — 20 000 photos in ~40 requests — is a **network** figure and
nothing else. `/Have` is keyed by the sha256 of the bytes, and a sha256 needs every byte, so
the local read of the entire camera roll is unavoidable and is the real cost of this
milestone. What the batching buys is one round trip per 500 photos instead of one upload per
photo, which is the difference between a reconciliation and a re-upload of the library.

The other half of the test was already paid for in W2: `AssetExporter` sets
`isNetworkAccessAllowed = false`, so an iCloud-only photo fails locally rather than being
downloaded. W6 inherits that by construction, because it reuses the same read.

### One month function, one timezone

`AssetPickerViewController.monthKey(for:)` was already exactly the function `/Have` needs, so
it moved to `AssetExporter` rather than being copied. The server does
`DateTimeOffset.TryParse(capturedAt).DateTime` — it drops the offset and files by wall clock
— then buckets on `yyyy-MM`. `UploadClient.capturedAtFormatter` has no explicit `timeZone`,
so it already emits device-local wall clock plus offset, and the two agree. **A second,
differently-configured formatter is how they would stop agreeing**, which is the whole reason
the function was promoted instead of duplicated.

Empty month is not a stub: `UploadWriter.Bucket` maps null-or-empty to `undated/`, exactly
where an upload with no `capturedAt` goes. `monthKey(for: nil) == ""` is the right answer.

### Hashing reuses the export path, minus the write

`AssetExporter.read(_:into:isAborted:completion:)` is now the single `requestData` call site;
`export` passes an `OutputStream` and `hash` passes `nil`. There is deliberately no second
call site, because `isNetworkAccessAllowed = false` and the resource-preference order
(`[.fullSizePhoto, .photo]`) must not get two owners.

No `beginBackgroundTask` around the hash pass. The scan is foreground-only, so an in-flight
hash at the moment of backgrounding is simply abandoned, the cursor does not advance, and
that one photo is re-hashed on resume. The background task stays on the export, where W5 put
it, because an export has a partial file to clean up and a queue slot waiting on it.

### The cursor is a date plus a set of identifiers, never an index

W5's watermark rule, inverted. The scan walks `creationDate <= cursor` descending and
remembers the identifiers of the assets it consumed *at that exact date*, so they are not
re-consumed.

**An index into the fetch result cannot work.** Photos are added and deleted between batches,
so the roll shifts under you and an index silently skips or repeats — the same class of bug
as stamping the watermark at `Date()`.

**A single identifier does not work either, and the failure is a scan that never ends.** The
predicate has to be `<=`, not `<`, or anything sharing the cursor asset's date is skipped
unseen. So when the oldest remaining photos share a `creationDate` — a burst, a bulk import,
anything saved in one go — skipping only the last one consumed lets the others come back on
the next fetch, where one of them becomes the new "last one" and readmits the first. The
batch is never empty, `.finished` is never reached, and the scan re-hashes the same handful
forever while `scanned` keeps climbing, which reads on screen as healthy progress.

The fix is to skip the whole tied set, and to **union it with the previous set whenever the
cursor date does not move**. That makes the skip list grow monotonically until the fetch
finally comes back empty, and bounds it by the number of assets sharing one timestamp rather
than by the library size.

**The boundary is the watermark.** The scan owns everything older than it; the W5 sweep owns
everything newer. The initial cursor *is* the watermark, so the two meet exactly once and
never overlap. That is also why the offer is seeded inside `mode`'s setter, in the same
`newValue == .automatic && mode != .automatic` branch that stamps the watermark.

### Undated photos need a second pass, and it is capped

`creationDate <= cursor` never matches a nil `creationDate` — SQL comparison semantics, not a
Photos quirk — so the date walk cannot reach an undated asset at all, and no sort descriptor
rescues it: Photos will not sort on `localIdentifier`, and where nils land in a
`creationDate` sort is undocumented. Relying on that order would risk the first batch being
all nils and the entire dated library being declared finished behind it.

So undated assets get their own pass, run **first**, over `creationDate == nil`, and
`catchUpUndatedDone` records that it happened. It is **capped at one batch of 500**: within
the nil-dated set there is no cursor to advance, because the only stable ordering key is the
one that is nil. A roll with more than 500 undated photos is not covered by W6. Named and
accepted rather than half-built.

### Each missing photo is read twice

Once to hash it, once to export and send it. `docs/11` §5's
`localIdentifier + modificationDate → sha256` memo would remove the second read and is
deliberately out of v1: the cursor already makes this a one-time run, and the memo only pays
for a repeat one.

### 25 then 500

500 is what buys the milestone's "~40 requests" at 20 000 photos and it is the plugin's
`MaxKeys` (over → 400, enforced rather than trimmed). But 500 hashes is **minutes** of
reading on an A7 before a single upload starts, and per decision 2 the grid shows nothing new
— the W4 queue banner is the whole story. So the first batch is 25, purely so the banner
appears within seconds of tapping *Back up*. Every batch after it is 500.

Hashing inside a batch is **serial**. Three concurrent `requestData` reads on an A7 with 1 GB
is how this becomes a jetsam rather than a slow scan. An asset that fails to hash is counted
as scanned and skipped — it would fail to export too.

The shas come back from `/Have` in ask order, but the batch keeps its own sha→identifier
dictionary and maps through that. Convenient is not the same as relied upon.

### Availability is `.unknown` on every cold start

The same blocker W5 hit. A resume must `refreshAvailability` first and take the target id
from the resolved `.ready`, never from a remembered value. `LibraryCatchUp` therefore does
not own availability at all: `JellyfinUploadService` hands it a `resolveTarget` closure, the
same wiring pattern `UploadQueue` uses for `UploadClient`'s callbacks.

### Where the scan stops, and what restarts it

| Condition | Phase | Restarted by |
|---|---|---|
| fetch returns nothing | `.finished` | nothing; a new flip to Automatic re-offers |
| `.unauthorized` | `.paused` | W5's re-auth card |
| `.transient` / unreachable server | `.paused` | the next `didBecomeActive` |
| `.rejected` | `.paused`, reason recorded | nothing this app session |
| library access not granted | `.paused` | the next `didBecomeActive` |
| `willResignActive` | `.paused`, cursor not advanced | the next `didBecomeActive`, silently |
| backup leaves Automatic | `.paused`, cursor not advanced | a new flip to Automatic, which re-offers |

`.rejected` is the one that must not auto-retry: retrying a malformed batch just loops. It is
held by an **in-memory** `isHalted` flag rather than a seventh persisted key, so a relaunch
does retry once — which is what you want after updating the plugin, and is not a loop.

**Leaving Automatic has to stop the scan, and the phase alone cannot express that.** Nothing
in `LibraryCatchUp` knows the mode, so a scan left `.running` when the switch goes to Off
would be resumed by the very next `didBecomeActive` and quietly keep feeding the queue after
the user asked the app to stop sending photos. The mode setter therefore calls `suspend()` on
the way out — the same body `willResignActive` uses — and both resume points go through
`resumeCatchUpIfAllowed()`, which is `guard mode == .automatic`. The switch stays the single
place the mode is decided; the engine stays ignorant of it.

`didBecomeActive` is already observed in `UploadService`; the resume is a line inside the
existing handler, no new observer. **`resumeQueue()` also resumes the scan**, because that is
the method `sessionDidResume` calls after a re-auth and no `didBecomeActive` fires when the
app never left the foreground — without it, verification 7 stalls until the next lock/unlock.

`runToken` is the same defence as `SyncEngine`'s and `UploadQueue`'s: `willResignActive`
bumps it, so the completion of a hash or a `/Have` that lands afterwards is dropped instead
of advancing a cursor for a dead run.

### Progress lives only in the Settings note

Per decision 2 the grid shows nothing new, which makes the note load-bearing rather than
polish: without it a scan paused on a `.transient` is indistinguishable from one that
finished. **Departure from the plan:** the change notification fires per *photo*, not per
batch. A batch is minutes on an A7, and a counter frozen for minutes on the only progress
surface is the same failure the note exists to prevent. One `NotificationCenter.post` setting
one label string is free against a multi-megabyte SHA-256.

For the same reason `.paused` never prints the bare word "paused". `lastErrorText` is
in-memory only, so it is nil after a relaunch **and** on the ordinary path where the app was
simply backgrounded — the most common pause there is. With no reason to give, the note shows
the count reached instead, and keeps the alarming wording for the cases that earned it.

### The entry point is an offer, not a control

Ratified in chat **against the recommendation**: the catch-up is offered by a one-shot alert
on the Off/Manual → Automatic transition, not by a permanent *Back up everything* row in
Settings. The reasoning is that a backfill is a decision you make once, not a control you
live with. What a permanent row would have bought is a way to re-run it after the phone has
been restored from a backup, or to restart a `.rejected` run without toggling the mode; both
are reachable today by flipping to Manual and back.

Declined is re-offered on every flip into Automatic. Re-selecting the already-selected
segment does not ask, and does not re-stamp the watermark — the `mode != .automatic` guard
that W5 added for the watermark gives that for free.

**The alert closes a real W5 gap.** Nothing in the app asked for photo-library access when
you flipped to Automatic, so until you happened to open the picker the sweep silently found
nothing. *Back up* calls `PHPhotoLibrary.requestAuthorization` and starts on `.authorized`.
The count in the message is included only when access is already granted: without it the
count is 0, and a wrong number is worse than none.

### Accepted, and named

`UploadQueue.enqueue` zeroes the tally when `pending.isEmpty && !isRunning`, so if the queue
drains between two batches the banner's counts restart. In practice uploading 500 photos
outlasts hashing the next 500, so this only shows when almost nothing is missing — the case
where the banner has nothing to say anyway. The fix would be a cumulative run counter; not in
W6.

### Videos are out

The scan's predicate is `mediaType == image`, the same predicate family as the picker and the
W5 sweep. **Videos are out of the catch-up exactly as they are out of Automatic** — recorded,
not inherited.

## 15. Limited photo access

Built 2026-09-26. An App Store compliance item on paper, a live bug in practice: the
legacy `PHPhotoLibrary.requestAuthorization(_:)` **already returns `.limited` on
iOS 14+**, so the daily-driver phones could land in a state every one of the app's
seven `== .authorized` tests read as "denied".

**An app cannot ask for limited access.** There is no such request. The user picks
*Limited Access → Select Photos…* from the system sheet, and the app is told after
the fact. So this is not a permission to request differently, it is a state to
survive.

### The rule: limited means manual-only

The one thing `.limited` genuinely cannot do is **automatic backup**. A photo taken
later is *never* added to the selection, so a sweep would find nothing, forever.
Accepting `.limited` everywhere would swap a visible dead end for a silent lie.

| Path | `.limited` |
|---|---|
| Picker, exporter, catch-up scan | accepted — `allowsLibraryRead` |
| Background sweep (`performBackgroundSweep`) | refused — `allowsAutomaticBackup` |

The mode is **not** forced back to Manual behind the user's back. The Automatic
segment is disabled, the note under it says why, and a new *Allow access to all
photos* row opens Settings. Explaining beats silently rewriting a setting the user
chose.

### `PhotoAccess` is the seam

`Writer/PhotoAccess.swift`, a three-case enum with `allowsLibraryRead` /
`allowsAutomaticBackup`. Seven scattered `PHPhotoLibrary.authorizationStatus() ==
.authorized` tests across five files became one place where the mapping lives —
which is also the only place the `#available(iOS 14)` split exists. `.denied`,
`.restricted` and `.notDetermined` all still collapse to `.denied`; only `.limited`
changed meaning.

**`presentLimitedLibraryPicker(from:)` is declared in `PhotosUI`, not `Photos`.**
Nothing in the compiler error says so — it reads as "`PHPhotoLibrary` has no member",
which looks like an availability problem and is not. `import PhotosUI` is the whole
fix; autolinking handles the framework, as with MapKit and AVKit (see docs/10).

### The picker, when limited

- An *Add More* `BandTextButton` takes the free trailing slot of the 56 pt band, at
  the same 16 pt ink inset as *Cancel*. Hidden under full access.
- `PHPhotoLibraryChangeObserver` is registered **only when access is `.limited`**.
  It is the first one in the app, and deliberately not a general-purpose feature: on
  a 7712-item library under full access, waking a full reload on every library
  change is a cost with no payer.
- After a selection change, `pruneSelection()` drops identifiers that are gone. Both
  `chosen` and `order` must be pruned — `order` feeds `fetchAssets(withLocalIdentifiers:)`
  in `send()`, so a stale id there is a photo silently missing from the batch.
- `loadAssets()` gained `hideNotice()` at its head: it used to be a one-shot path, and
  the re-load can now arrive with the notice on screen.
- The empty state is worded for the case: "Jellypic can only see the photos you gave
  it access to" is actionable, "No photos on this device" is a lie.

`PHPhotoLibraryPreventAutomaticLimitedAccessAlert` is `true` in `Info.plist`. The
system's own per-launch "review selected photos?" alert would fire before the app has
said anything, and *Add More* is the same action under the app's own words.

### Not measured

Whether `fetchAssets(in: smartAlbumUserLibrary)` returns the limited subset or an
empty result is **assumed, not verified on device**. If it comes back empty, all four
fetch sites need re-pointing at `PHAsset.fetchAssets(with:options:)`. That is the
first thing to check when testing this.
