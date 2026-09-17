# JellyPic Reader — iOS App Plan

> Status: plan / proposal. No code written yet.
> Date: 2026-08-15
> Companion to `01-storage-and-upload-research.md`. This doc covers **read only**: connect → pick library → browse. Upload is out of scope here.

---

## 1. Scope

**In:** server connection, Jellyfin auth, library selection, a Photos-app-like timeline, full-screen viewer, video playback, settings with cache reset + logout, offline browse of cached content.

**Out (this phase):** uploading, albums/favourites editing, sharing to server, face grouping, search by content, multi-server.

**Design principle:** lean on native OS components wherever one exists, and be explicit where one doesn't. Target **zero third-party dependencies** — `URLSession`, `URLCache`, `NSCache`, SwiftData and SwiftUI cover everything here. That also means nothing to security-audit before we ship.

---

## 2. Verified API facts

Checked against the Jellyfin SDK docs and issue tracker, 2026-08-15.

### 2.1 Auth header changed in 10.11 — **high confidence, breaking**

Use the standard `Authorization` header with the `MediaBrowser` scheme:

```
Authorization: MediaBrowser Token="<token>", Client="JellyPic",
               Device="iPhone", DeviceId="<uuid>", Version="1.0.0"
```

`X-Emby-Authorization`, `X-Emby-Token` and `X-MediaBrowser-Token` are legacy. 10.11 lets an admin disable them entirely via `<EnableLegacyAuthorization>false</EnableLegacyAuthorization>` in `system.xml`, and third-party clients have already broken on this. Older servers accept the `Authorization` form too, so **send only `Authorization`** — no version branching needed.

There is also a known server bug where calling `/Users/AuthenticateByName` with a *valid* credential but a *malformed* Authorization header can wipe the server's Devices table (jellyfin#11484). Get the header right and validate it in tests.

### 2.2 Photos are first-class item types, and EXIF extraction is real — **verified in source**

`BaseItemKind` includes `Photo` and `PhotoAlbum`. `Emby.Photos/PhotoProvider.cs` (provider name: `"Embedded Information"`) parses EXIF via TagLib# and populates more than I first assumed:

`Width`, `Height`, `CameraMake`, `CameraModel`, `Aperture`, `ShutterSpeed`, `ExposureTime`, `FocalLength`, `IsoSpeedRating`, `Latitude`, `Longitude`, `Altitude`, `Orientation`, `Software`, plus `Name` from EXIF Title, `Overview` from Comment, `CommunityRating` from Rating, and `Tags` from IPTC keywords.

It also does `item.SetImagePath(ImageType.Primary, item.Path)` — **a photo is its own primary image**, which is why the thumbnail endpoint in §2.3 works with no separate artwork.

Enough for a full info panel and a map pin with zero client-side EXIF parsing.

**Only these extensions get EXIF parsed** (`_includeExtensions`, "other extensions might cause taglib to hang"):

```
.jpg .jpeg .png .tiff .cr2 .webp .avif
```

Reinforces §2.4: JPEG is the format that works end to end.

### 2.3 Image endpoint and cache keys — **high confidence**

```
GET /Items/{id}/Images/Primary?fillWidth=600&quality=80&tag={ImageTags.Primary}
```

The `tag` is a content hash of the image. **The URL is therefore immutable** — if the image changes, the tag changes, so the URL changes. This is the ideal cache key: we can cache aggressively and forever with no invalidation logic.

Caveat: jellyfin#1187 — *the server does not always return the exact requested dimensions*. Never assume the response matches `fillWidth`. Always downsample client-side to the real target.

### 2.4 The HEIC problem reaches the reader — **verified in source, v10.11.0**

Confirmed by reading the server, not by inference:

`PhotoResolver.IsImageFile()` gates on `imageProcessor.SupportedInputFormats`:

```csharp
// Emby.Server.Implementations/Library/Resolvers/PhotoResolver.cs
var extension = Path.GetExtension(path.AsSpan()).TrimStart('.');
if (!imageProcessor.SupportedInputFormats.Contains(extension, ...)) return false;
```

And that list (`src/Jellyfin.Drawing/ImageProcessor.cs`, v10.11.0) is:

```
tiff, tif, jpeg, jpg, png, aiff, cr2, crw, nef, orf, pef, arw, webp,
gif, bmp, erf, raf, rw2, nrw, dng, ico, astc, ktx, pkm, wbmp, avif
```

**No `heic`, no `heif`.** So it's worse than "thumbnails fail": the resolver returns `null`, the file never becomes a `Photo` item, and it is **completely invisible** — absent from `/Items`, absent from counts. Nothing to debug, nothing in the logs.

**Don't reach for AVIF or TIFF as the derivative format either.** They pass the resolver, but the actual decoder (`src/Jellyfin.Drawing.Skia/SkiaEncoder.cs`) supports only:

```
jpeg, jpg, png, dng, webp, gif, bmp, ico, astc, ktx, pkm, wbmp, cr2, nef, arw, svg
```

AVIF and TIFF are in the resolver list but *not* the decoder list — they get indexed and then fail to render. That mismatch is precisely jellyfin#9364.

**Safe intersection for our derivatives: JPEG.** (PNG and WebP also work but are wrong for photos.)

**Consequence:** the reader is only useful against a library the writer has populated with JPEGs. Build against a JPEG fixture library, and write an empty-state that names this cause rather than saying "No photos".

---

## 3. User flow

```
┌─────────────┐   ┌──────────┐   ┌──────────────┐   ┌──────────┐
│ Connect     │──►│ Sign in  │──►│ Pick library │──►│ Timeline │
│ server URL  │   │ user/pw  │   │ (homevideos) │   │          │
└─────────────┘   └──────────┘   └──────────────┘   └────┬─────┘
   validate via                    persisted              │
 /System/Info/Public                                 ┌────▼─────┐  ┌──────────┐
   (unauthenticated)                                 │ Viewer   │  │ Settings │
                                                     └──────────┘  └──────────┘
```

Relaunch skips straight to Timeline while revalidating the token in the background.

---

## 4. Screens

### 4.1 Connect

- Manual URL entry, primary path. Normalize aggressively: add scheme if missing, strip trailing slash, try `:8096` if no port and the bare host fails.
- Validate with `GET /System/Info/Public` — **unauthenticated**, confirms it's really Jellyfin, returns `ServerName` and `Version`. Do this *before* asking for a password so a typo'd URL doesn't look like a wrong password.
- Warn if `Version` < 10.10 (untested territory for us).
- **Two gotchas to handle explicitly, both classic self-hosted pain:**
  - **App Transport Security** blocks plain `http://` — a LAN Jellyfin usually has no TLS. Need `NSAllowsLocalNetworking` in the plist, and a clear error when the user points at an `http://` public host.
  - **Local Network privacy permission** (iOS 14+) is required to reach `192.168.x.x` / `.local` at all. Must include `NSLocalNetworkUsageDescription` and handle denial with real guidance, not a generic failure.
- *Phase 2:* Jellyfin's UDP broadcast discovery on port **7359** via `Network.framework` `NWConnection` — auto-find the server on the LAN. Nice, not load-bearing.

### 4.2 Sign in

- `POST /Users/AuthenticateByName` with `{ Username, Pw }`.
- Response gives `AccessToken`, `User.Id`, `ServerId` — all three persisted.
- `DeviceId`: UUID generated once, stored in **Keychain** so it survives reinstall. Same rule as the writer (doc 01 §7) — keep them consistent, ideally literally the same value via a shared Keychain access group, so the server sees one device rather than two.
- *Phase 2:* **Quick Connect** (`POST /QuickConnect/Initiate` → show 6-char code → poll `/QuickConnect/Connect`). Typing a strong password on a phone keyboard is the single worst moment in this flow, and this is the native Jellyfin answer to it.

### 4.3 Library picker

- `GET /UserViews` → filter to `CollectionType == "homevideos"` (that's what "Home Videos and Photos" reports).
- Single selection for v1, persisted. If exactly one qualifying library exists, auto-select and skip the screen.
- Reachable again from Settings.

### 4.4 Timeline — the main screen

- `LazyVGrid`, `pinnedViews: [.sectionHeaders]`, sections grouped by month, sticky headers.
- Pinch to change density (`MagnifyGesture`) — Photos does 1 / 3 / 5 / 10 columns; we do 3 / 5 / 10.
- Fast scrubber on the right edge, driven by the local index (§6) since we know total count and date distribution up front.
- Prefetch thumbnails a screen ahead; cancel on scroll-away.

**Honest caveat:** `LazyVGrid` with pinned headers degrades past roughly 10k items — cell reuse isn't real reuse, and sticky headers make it worse. The proven path for a genuine photo library is `UICollectionView` with a compositional layout and `UICollectionViewDataSourcePrefetching`. **Plan: build on `LazyVGrid`, measure against a 50k-item fixture, and keep the grid behind a protocol so it can be swapped for a `UIViewRepresentable` collection view without touching the rest of the app.** Assume we will need to.

### 4.5 Viewer

- **`.navigationTransition(.zoom(sourceID:in:))` + `.matchedTransitionSource(id:in:)`** (iOS 18+) — this is the exact Photos-app open/close zoom, for free, including the interactive swipe-down dismiss. The single biggest "feels native" win available.
  - Use the **stable item ID** as `sourceID`, never the array index — indices shift on filter/sort/paging and the transition silently breaks.
  - Known glitch during interactive swipe-back (Apple Forums thread 810944); verify on device.
- Horizontal paging between items: `ScrollView(.horizontal)` + `.scrollTargetBehavior(.paging)`.
- **Pinch-to-zoom: no native SwiftUI equivalent.** The real Photos app uses `UIScrollView` zooming, and so should we — a small `UIViewRepresentable` wrapper with `zoomScale`/`doubleTapToZoom`. Rolling it from `MagnifyGesture` looks fine in a demo and feels wrong in the hand.
- **Video:** `VideoPlayer` + `AVPlayer` against Jellyfin's HLS (`/Videos/{id}/master.m3u8`). AVPlayer speaks HLS natively including adaptive bitrate — no player library needed.
- **Live Text:** `ImageAnalysisInteraction` (VisionKit). Genuinely native, a few lines, and makes photos of receipts/signs searchable-by-eye.
- **Share:** `ShareLink` with the original file (`/Items/{id}/Download`).
- **Info panel:** EXIF straight from `BaseItemDto` (§2.2) + a `Map` pin when lat/lon are present.

### 4.6 Settings

- **Server** — name, version, signed-in user, change library.
- **Cache** — per-tier size breakdown, `Reset Cache` (destructive role + confirmation).
- **Logout** — destructive role + confirmation.
- **Appearance** — default grid density.
- **Cellular** — allow/deny full-res loads off Wi-Fi (`allowsExpensiveNetworkAccess`).

**Reset Cache** clears the image disk cache, the decoded-image memory cache, and the local item index — but *keeps* credentials. Next launch re-syncs.

**Logout** calls `POST /Sessions/Logout` to invalidate the token **server-side** (otherwise it lives on in the server's device list forever), then wipes Keychain + all three cache tiers, then returns to Connect. Order matters: network call first, local wipe second, so a failed call doesn't strand a valid token we can no longer revoke.

---

## 5. Caching — three tiers

This is the core of the app's feel, so it's worth being precise. Each tier is a native component.

| Tier | Component | Holds | Size | Cleared by |
|---|---|---|---|---|
| 1. Bytes on disk | `URLCache` (own instance, not `.shared`) | JPEG bytes as served | 64 MB mem / 2 GB disk | Reset Cache |
| 2. Decoded bitmaps | `NSCache<NSString, UIImage>` | ready-to-draw images | cost-limited ~80 MB | Reset Cache + auto on memory pressure |
| 3. Metadata index | SwiftData | item rows (id, dates, size, tag) | small | Reset Cache |

**Why `URLCache` rather than a hand-rolled file cache:** it's disk-backed, survives relaunch, and implements HTTP caching semantics including ETag revalidation for free. Combined with §2.3's immutable tagged URLs, thumbnails become a pure cache hit after first fetch. A custom cache would be more code and worse.

**Why a separate `NSCache` on top:** `URLCache` returns *bytes*; decoding a JPEG on every cell reuse is what makes a grid stutter. `NSCache` holds the decoded result and — critically — evicts itself automatically under memory pressure, which a `Dictionary` will not.

**Downsampling:** `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize`, off the main thread, then `UIImage.byPreparingForDisplay()`. Never hand a full-size `UIImage` to a 120pt cell — a 4000×3000 decode is ~48 MB of RAM per image and it's the #1 cause of photo-grid jank.

**Size discipline:** request three variants — grid (`fillWidth` = cell pt × screen scale), preview (~1600px), original (on demand only). Cap concurrent image requests at ~6: every miss makes the *server* resize an image, and a Raspberry Pi handed 60 parallel resizes will fall over. This is a server-protection limit as much as a client one.

---

## 6. Sync & the local index

**Why a local index at all:** Jellyfin has no cheap "give me all IDs" call, and we need the complete ordered list up front for month headers, the scrubber, and instant cold launch. So we mirror it.

- **First sync:** page `GET /Items?parentId={lib}&recursive=true&includeItemTypes=Photo,Video&sortBy=PremiereDate&sortOrder=Descending` at ~1000/page (see §6.1 for why `PremiereDate`). `TotalRecordCount` in the response gives us a real progress bar.
- Keep the payload lean: request only the `fields` we use, `enableUserData=false`.
- **Incremental sync:** there's no reliable "changed since" for photos, so pull-to-refresh re-pages IDs + tags and diffs. ~50 requests for 50k items — acceptable, and it's the only correct option available.
- Cold launch renders from SwiftData immediately, syncs behind it. Offline = browse everything already cached.

### 6.1 Sort key: `PremiereDate`, not `DateCreated` — **verified in source, corrected**

An earlier draft of this plan flagged "DateCreated may be import time, not capture time" as a blocking risk. **That was wrong.** `PhotoProvider` does read EXIF capture time:

```csharp
// Emby.Photos/PhotoProvider.cs, v10.11.0
var dateTaken = image.ImageTag.DateTime;
if (dateTaken.HasValue)
{
    item.DateCreated  = dateTaken.Value.ToUniversalTime();  // <-- tz-mangled
    item.PremiereDate = dateTaken.Value;                    // <-- raw EXIF value
    item.ProductionYear = dateTaken.Value.Year;
}
```

So the timeline *will* be chronologically correct for JPEGs with EXIF. But reading the actual line surfaced a subtler problem worth more than the original worry:

**EXIF `DateTime` carries no timezone.** TagLib hands back a `DateTime` with `Kind == Unspecified`, and .NET's `ToUniversalTime()` on an Unspecified value **assumes the machine's local timezone**. So `DateCreated` is shifted by whatever `TZ` the Jellyfin *server* happens to run in — the same photo yields a different UTC instant on a UTC container vs. a Europe/Paris host, and a 23:40 shot can land on the wrong day, which is exactly the month-boundary bug that makes a photo grid look broken.

`PremiereDate` is stored **unconverted** — the literal EXIF value, which is what "capture time in the photographer's local time" actually means.

**Decision: sort and group on `PremiereDate`, fall back to `DateCreated` when null.**
`sortBy=PremiereDate&sortOrder=Descending`. *The `Kind == Unspecified` step is inference from .NET semantics — confirm empirically by changing the server container's `TZ` and re-scanning.*

### 6.2 Fallback when there's no EXIF — **verified in source**

If EXIF is missing or the extension isn't in `_includeExtensions`, the date comes from `ResolverHelper.SetDateCreated()`:

```csharp
if (config.UseFileCreationTimeForDateAdded)   // defaults to TRUE
    item.DateCreated = info.CreationTimeUtc;  // birth time, NOT mtime
else
    item.DateCreated = DateTime.UtcNow;       // = scan time
```

**This corrects doc 01 §4.3.** That doc claimed "the writer sets file mtime to capture time, making the reader correct by construction". Wrong on two counts: Jellyfin reads `CreationTimeUtc` (birth time), not mtime, and .NET's birth-time support on Linux filesystems is inconsistent.

**The real requirement is simpler and fully in our control: the writer must preserve the EXIF block when transcoding HEIC → JPEG.** Then the EXIF path in §6.1 wins and none of the filesystem-timestamp fragility matters. Strip EXIF and every photo silently falls back to file-creation or scan time — i.e. the whole library stamped with the day we ran the import.

---

## 7. Architecture

```
JellyPicKit/
├── Network/   JellyfinClient      async/await over URLSession, behind a protocol
├── Auth/      AuthStore           Keychain: token, serverURL, userId, deviceId
├── Index/     SwiftData models + SyncService
├── Images/    ImageLoader         URLCache + NSCache + downsample + concurrency cap
└── Cache/     CacheManager        one place that knows how to measure and wipe all tiers
JellyPicApp/   SwiftUI views, @Observable view models
```

`JellyfinClient` stays behind a protocol for the same reason as doc 01 §8: if the backend ever becomes Immich, we rewrite one layer, not the app. `CacheManager` exists so "Reset Cache" can't drift out of sync with reality as tiers are added — a single call site that both reports and clears.

---

## 8. Milestones

- **M1** — Connect, validate, auth, Keychain, library picker.
- **M2** — Full sync into SwiftData, `LazyVGrid` timeline with month headers.
- **M3** — Three-tier cache, image loader, prefetch; Settings with cache size + reset + logout.
- **M4** — Viewer: zoom transition, paging, `UIScrollView` pinch-zoom.
- **M5** — Video playback, Live Text, info panel + map, share.
- **M6** — Perf pass against a 50k fixture; decide `LazyVGrid` vs `UICollectionView`.

M1–M3 is the honest MVP: it connects, it shows your photos, it's fast on second launch, and you can log out.

---

## 9. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| HEIC library → items **invisible**, not just unthumbnailed | **Blocking**, verified | Reader depends on writer emitting JPEG; explicit empty-state naming the cause; JPEG dev fixture |
| ~~`DateCreated` ≠ capture date~~ — **resolved**, EXIF is read | — | Was a false alarm; see §6.1 |
| `DateCreated` shifted by *server* timezone | Medium — wrong month grouping at day boundaries | Sort on `PremiereDate` (raw EXIF); confirm by flipping container `TZ` |
| Writer strips EXIF on HEIC→JPEG | High — whole library dated at import time | Explicit requirement on the writer; assert EXIF present in ingest tests |
| `LazyVGrid` perf at scale | High | Protocol boundary, measure at M6, `UICollectionView` fallback |
| Server thumbnail load | Medium — can stall a weak server | Concurrency cap 6, aggressive caching |
| ATS / Local Network permission | Medium — looks like "app is broken" | Plist entries + specific error copy |
| 10.11 auth header | Medium | Send `Authorization` only; test against 10.10 and 10.11 |
| Zoom transition glitch on swipe-back | Low | Known Apple issue; verify on device |

---

## 10. Open questions

1. Single library or multi-library merged timeline in v1? (Affects the index schema — cheap now, annoying later.)
2. ~~Does `DateCreated` carry EXIF capture time?~~ **Answered: yes** (§6.1). Remaining sub-question: confirm the server-timezone shift empirically.
3. Minimum iOS version — the zoom transition needs 18. Committing to **iOS 18+** unlocks the best native components; iOS 17 support costs a hand-rolled transition. Recommend 18+.
4. Should the reader ship before the writer, given §2.4? Probably needs at least a manual JPEG conversion path to be demoable.
5. Offline: cache-on-demand only, or an explicit "download this month" pin?
6. Do we want favourites/ratings sync back to Jellyfin (it does support `UserData`), or stay strictly read-only?

---

## 11. Sources

- [Jellyfin API Authorization — nielsvanvelzen gist](https://gist.github.com/nielsvanvelzen/ea047d9028f676185832e51ffaf12a6f)
- [seerr — Jellyfin 10.11.x auth fails, wrong authorization header name (#2361)](https://github.com/seerr-team/seerr/issues/2361)
- [jellyfin — AuthenticateByName with invalid Authorization header wipes Devices table (#11484)](https://github.com/jellyfin/jellyfin/issues/11484)
- [jellyfin.org — X-Emby-Authorization header isn't documented (#499)](https://github.com/jellyfin/jellyfin.org/issues/499)
- [Jellyfin TypeScript SDK — BaseItemDto](https://typescript-sdk.jellyfin.org/interfaces/generated-client.BaseItemDto.html)
- [Jellyfin TypeScript SDK — BaseItemKind](https://typescript-sdk.jellyfin.org/variables/generated-client.BaseItemKind.html)
- [Jellyfin TypeScript SDK — ImageRequestParameters](https://typescript-sdk.jellyfin.org/interfaces/models_api.ImageRequestParameters.html)
- [jellyfin — Server doesn't return images of the requested dimensions (#1187)](https://github.com/jellyfin/jellyfin/issues/1187)
- [Jellyfin Kotlin SDK — Authentication guide](https://kotlin-sdk.jellyfin.org/guide/authentication.html)
- [The Swift Dev — Add iOS 18 zoom navigation transitions to a SwiftUI grid](https://www.theswift.dev/posts/swiftui-zoom-navigation-transition/)
- [Create with Swift — Using the zoom navigation transition in SwiftUI](https://www.createwithswift.com/using-the-zoom-navigation-transition-in-swiftui/)
- [Apple Developer Forums — navigationTransition(.zoom) glitches during interactive swipe-back](https://developer.apple.com/forums/thread/810944)
