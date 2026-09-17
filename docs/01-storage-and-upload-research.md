# JellyPic — Storage, Upload & Multi-Device Research

> Status: research / decision proposal. No code written yet.
> Date: 2026-08-15
> Scope: how to get iPhone photos onto a Jellyfin-backed server, well organized, with multiple devices.

---

## 1. Goals

1. **Backup** — automatic + manual upload of photos/videos from one or more iPhones to a self-hosted server.
2. **Browse** — a Photos-app-like timeline experience, backed by a Jellyfin "Home Videos and Photos" library.
3. **Multi-device** — several phones (and later, other sources) writing into one coherent library without duplicates or collisions.

---

## 2. Findings that shape the design

These were verified against primary sources (Jellyfin docs, Jellyfin feature tracker, Apple developer docs). Confidence noted per item.

### 2.1 Jellyfin has no upload API in core — **high confidence**

Jellyfin is a *read-only media server*. There is no endpoint to push a file into a library. The community answer is consistently "use Syncthing / Nextcloud / a network share".

There is a third-party plugin (`MediaUploader`, exposing `/Plugins/MediaUploader/Upload`) but:
- it is unaffiliated with the Jellyfin project,
- it would sit in the privileged path of every photo we own.

> **Action required before any use:** per our security policy, this plugin's source must be audited (credential handling, outbound network calls, arbitrary path writes) before being cloned or deployed. Not recommended as a dependency — see §5.

**Consequence: we must build our own ingest service. Jellyfin is the viewer, not the front door.**

### 2.2 Jellyfin cannot display HEIC/HEIF — **verified in source, v10.11.0**

The HEIC feature request (filed May 2020, 73+ votes) is tagged **Blocked** — the image libraries Jellyfin uses (SkiaSharp) don't support it.

Confirmed directly in the v10.11.0 source (full detail in doc 02 §2.4): `PhotoResolver.IsImageFile()` gates on `ImageProcessor.SupportedInputFormats`, which contains no `heic`/`heif`. HEIC files therefore **never become library items at all** — they are invisible, not merely unthumbnailed.

Also verified: **AVIF and TIFF are not viable alternatives.** They pass the resolver but are absent from the Skia decoder's format list, so they index and then fail to render (jellyfin#9364). **The safe derivative format is JPEG.**

iPhones shoot HEIC by default. **A naive "copy the originals into the library" approach produces an empty library.**

Options:
| Option | Verdict |
|---|---|
| A. Transcode to JPEG on the phone, upload JPEG only | Rejected — destroys the original, phone battery/CPU cost |
| B. Upload the **original**, keep it in an archive, generate a **JPEG derivative** for Jellyfin | **Recommended** |
| C. Tell the user to set Camera → Formats → "Most Compatible" | Rejected as primary — only affects future photos, halves storage efficiency, user-hostile |

Option B costs extra storage but is the only one that is both lossless and viewable. Derivatives can be capped (e.g. long edge 4096, quality 85) to keep the overhead well under 1x.

### 2.3 The photo library type is folder-based and metadata-poor — **high confidence**

- The "Home Videos and Photos" library accepts loose files and subfolders; subfolders are the *only* real organizational primitive.
- There is no metadata provider (no TMDB equivalent for your holiday photos), so **organization must happen on the filesystem**, by us, at ingest time.
- There is no official docs page for this library type (`/docs/general/server/media/photos/` → 404), which is itself a signal about how much product investment it has.
- No face recognition, no dedup, no geo, no EXIF-driven timeline. Client apps (incl. Swiftfin) have open issues about even rendering folder views properly.

**Consequence: the "Photos app experience" is our app's job, not Jellyfin's.** Jellyfin gives us storage indexing, transcoding for videos, users/auth, and a streaming API. We supply the timeline, grouping and search from our own index (§6).

### 2.4 iOS background upload is unreliable by design — **high confidence**

- `PHPhotoLibraryChangeObserver` only fires **while the app is running**. iOS never wakes an app because a photo was taken. → we always need a full-library diff scan on launch.
- `BGProcessingTask` scheduling is entirely system-controlled (battery, charging, usage patterns). Multiple developer reports of it firing reliably in debug but rarely in TestFlight/production. Immich still has open discussions about background sync reliability in 2026.
- The supported mechanism for surviving suspension mid-transfer is a **background `URLSession`** (`.background` configuration) — the system continues the transfer even if the app is killed. Apple documents this specifically for PhotoKit asset resources.
- iOS 26 added `BGContinuedProcessingTask` (user-visible, long-running). Worth prototyping — may materially improve "plug in phone, everything catches up". *To verify.*

**Consequence: "automatic" means opportunistic, not instant.** Design for: bulk upload in foreground, background session for in-flight items, BG task for catch-up, and honest UI ("142 items pending, open the app to finish").

### 2.5 iCloud "Optimize iPhone Storage" — **high confidence**

If enabled, originals are not on the device. Fetching them requires `PHAssetResourceManager` with `networkAccessAllowed = true`, which is slow, can be metered, and can fail. This must be a first-class state in the upload queue, not an error path.

---

## 3. Recommended architecture

```
iPhone app                  Ingest service (ours)              Jellyfin
──────────                  ─────────────────────              ────────
scan PHAsset                POST /v1/assets/precheck   ──►  (not involved)
  ↓ sha256                    ◄── exists? skip
upload original             POST /v1/assets (resumable)
  ↓                           ├─ verify hash
                              ├─ read EXIF / QuickTime
                              ├─ place in /archive/...
                              ├─ derive JPEG → /library/...
                              ├─ write index row + sidecar
                              └─ notify Jellyfin  ──────────►  /Library/Media/Updated
browse timeline             GET /v1/timeline  ◄─ our index
view/stream                 ───────────────────────────────►  Jellyfin image/video API
```

Jellyfin points **only** at `/library`. `/archive` is never scanned by it.

---

## 4. Storage layout

### 4.1 Top level

```
/srv/jellypic/
├── archive/          # originals, bit-exact, never mutated. NOT a Jellyfin library.
├── library/          # viewable derivatives + native-compatible originals. Jellyfin libraries.
├── index/            # sqlite/postgres + sidecar JSON
└── incoming/         # per-upload temp, atomically moved out on completion
```

**Why split archive/library:** originals are the asset of record (HEIC, RAW, ProRes, full-res video). The library is a disposable, regenerable projection. If we change derivative settings, we rebuild `library/` from `archive/` without risk.

### 4.2 Inside `library/` — the part Jellyfin sees

```
library/
├── shared/                       # Jellyfin library "Family Photos", all users
│   └── 2026/
│       └── 2026-08/
│           ├── 20260815-141233_iphone-jf_a1b2c3d4.jpg
│           └── 20260815-141240_iphone-jf_e5f6a7b8.mp4
└── people/
    ├── jf/                       # Jellyfin library "JF Photos", restricted to user jf
    │   └── 2026/2026-08/...
    └── partner/
        └── 2026/2026-08/...
```

**Key constraint driving this:** Jellyfin access control is **per-library, not per-folder**. If you want anything private, it must be its own library with its own user grants. So the shared/personal split has to exist at the top of the tree — retrofitting it later means re-pathing everything.

### 4.3 Date bucketing: `YYYY/YYYY-MM`

- `YYYY/MM/DD` → thousands of folders, 3 clicks to reach a photo, terrible in Jellyfin's folder UI.
- Flat → unusable at 50k files, and slow to scan.
- `YYYY/YYYY-MM` → ~12 folders/year, ~200 items/folder for a typical shooter. The redundant year prefix in the month folder keeps names unambiguous when a client flattens the view.

**Bucket by capture time in the capture's local timezone**, not UTC. A photo taken at 23:40 in Paris must land in that day, not the next.

> **Correction (verified in Jellyfin source, v10.11.0 — see doc 02 §6.1/§6.2).**
> An earlier version of this section claimed that setting file **mtime** to capture time would make Jellyfin's timeline correct. That is wrong: Jellyfin's fallback reads `CreationTimeUtc` (birth time), not mtime, and .NET's birth-time support on Linux filesystems is inconsistent.
>
> What actually matters: Jellyfin's `PhotoProvider` reads **EXIF** `DateTime` and uses it when present. So the binding requirement on the writer is:
> **when transcoding HEIC → JPEG, preserve the EXIF block.** If EXIF survives, dates are correct and filesystem timestamps are irrelevant. If it's stripped, every photo silently falls back to file-creation or scan time and the entire library gets stamped with the import date.
> Add an ingest assertion that the derivative still carries `DateTimeOriginal`.

Time source priority:
1. EXIF `DateTimeOriginal` (+ `OffsetTimeOriginal` for tz)
2. QuickTime `com.apple.quicktime.creationdate` (carries tz offset) for video
3. `PHAsset.creationDate` (+ device tz at upload)
4. File mtime — last resort, flag the asset as `date_unreliable` so the UI can show it

### 4.4 Filename: `YYYYMMDD-HHMMSS_<device-slug>_<sha8>.<ext>`

`20260815-141233_iphone-jf_a1b2c3d4.jpg`

- **Lexicographic sort == chronological sort.** Critical, because Jellyfin will sort these by name and nothing smarter.
- Device slug makes multi-device provenance visible without opening the index.
- 8 hex chars of the content SHA-256 makes collisions structurally impossible and makes accidental duplicates obvious to the naked eye.
- Never reuse the original filename (`IMG_4823.HEIC`) — two phones collide within weeks.

### 4.5 Inside `archive/` — content-addressed

```
archive/a1/b2/a1b2c3d4...ff.heic
```

Sharded by the first 2 bytes of the hash. Immutable, dedup is free, no rename logic, no date-correction reshuffles. The human-readable structure lives in `library/` and the index; the archive is a blob store.

### 4.6 Live Photos, edits, RAW+JPEG

These are **one logical asset with several resources** — modelling them as separate files creates a library full of 3-second silent clips.

- Live Photo: still (`.heic`) + motion (`.mov`), same `PHAsset`. Archive both, link them in the index, publish **only the still** into `library/`.
- Edited versions: iOS keeps original + adjusted render. Archive both; publish the edited one; index links `derived_from`.
- RAW+JPEG pairs: same treatment.
- If any of these must live under `library/`, put them in an excluded subfolder. *To verify: whether Jellyfin still honours a `.ignore` file in a directory to skip it during scan — needs testing against 10.11 before relying on it.*

---

## 5. Upload transport — options considered

| Option | Organizes? | Dedup? | Resumable? | Verdict |
|---|---|---|---|---|
| **Custom HTTP ingest service** | yes | yes | yes | **Recommended** |
| WebDAV + PhotoSync/rclone | no | no | partial | Good *fallback / non-iOS sources*, no organization logic |
| SMB share | no | no | no | LAN-only, poor on mobile, drops on network change |
| Syncthing | no | no | yes | **Avoid as primary** — it's a mirror, so a delete on the phone propagates a delete on the server. That is the opposite of a backup. |
| `MediaUploader` Jellyfin plugin | no | no | no | Unvetted third-party in a privileged path; requires a security audit before it's even cloned. Not recommended. |
| Immich as the backend, Jellyfin for video only | yes | yes | yes | **Real escape hatch** — see §8 |

### Proposed ingest API

```
POST /v1/assets/precheck        { sha256, size, deviceId, deviceAssetId }
     → 200 {status: "have"}     → phone marks done, uploads 0 bytes
     → 200 {status: "want", uploadUrl, offset}

PUT  /v1/assets/{uploadId}      resumable chunks (tus-style, or Range PUT)
     headers: x-content-sha256, x-device-id, x-device-asset-id,
              x-capture-time, x-capture-tz

POST /v1/assets/{uploadId}/complete
     → server verifies hash, extracts metadata, places files, notifies Jellyfin
```

- **Idempotency key = content SHA-256.** Re-running the whole upload is always safe.
- Reject on hash mismatch, never on "file already exists".
- Notify Jellyfin with a targeted `POST /Library/Media/Updated` (path-scoped) rather than a full `/Library/Refresh`, which rescans everything and gets slow fast. *To verify: exact payload shape on 10.11.*

---

## 6. The index (this is where the "Photos app" actually comes from)

Jellyfin cannot give us a timeline, so we own one.

```
assets       id, sha256 (unique), capture_time, capture_tz, date_reliable,
             kind, width, height, duration, lat, lon, camera_make, camera_model,
             archive_path, library_path, owner, visibility
resources    asset_id, role (original|motion|edited|derivative), sha256, path
device_links asset_id, device_id, device_asset_id, seen_at
devices      id, name, slug, platform, owner, registered_at
```

- `sha256` is asset identity. `device_asset_id` is *not* — it's per-device and changes on restore.
- `device_links` is many-to-many on purpose: the same photo AirDropped to a second phone is one asset seen by two devices, and both phones should be told "already backed up".
- Perceptual hash for near-duplicates (re-compressed, resized, screenshot-of) is a **later** phase. Content hash first — it's exact and cheap.

---

## 7. Multi-device specifics

- **Device identity:** UUID generated on first launch, stored in the **Keychain** (not UserDefaults) so it survives app reinstall. `identifierForVendor` resets when all your apps are removed.
- **Device restore / new phone:** `PHAsset.localIdentifier` is not stable across restores. Never treat it as global identity — this is exactly why dedup is content-hashed.
- **Precheck-before-upload** makes a new phone joining an existing library cheap: it hashes locally, asks, and uploads only what's genuinely missing.
- **Slug collisions:** two phones both named "iPhone" → server assigns the slug (`iphone-jf`, `iphone-jf-2`), phone doesn't get to pick it.
- **Concurrency:** two devices uploading the same asset simultaneously — the atomic move into the content-addressed archive path is the serialization point. Last writer wins on identical bytes, which is a no-op.

---

## 8. The honest risk

Jellyfin was not built for photos, and the two blockers above (no HEIC, no upload API) are not accidents — they reflect where the project's priorities are. We are building a photo app that uses Jellyfin as a file-backed streaming server.

The pragmatic alternative is **Immich** for photos (purpose-built: timeline, faces, mobile auto-backup, dedup by SHA-1 checksum header, a documented `/assets` upload API) with Jellyfin kept for movies/TV. That deletes ~70% of this document's scope.

Reasons to still do JellyPic: you already run Jellyfin and want one server, one auth, one client story; or the build itself is the point. Both are legitimate — but this should be a deliberate choice, not a default.

**Suggested de-risking:** the ingest service in §3 is deliberately backend-agnostic. It writes files and calls a "publish" hook. Swapping Jellyfin for Immich later means rewriting that hook, not the app.

---

## 9. Open questions

1. Shared-first or personal-first library layout? (Affects §4.2, expensive to change later.)
2. Storage budget — do we keep full-res video originals in `archive/`, or transcode above a threshold?
3. Derivative cap: full-res JPEG, or long-edge 4096?
4. Does Jellyfin 10.11 still honour `.ignore`? (blocks §4.6)
5. Exact `/Library/Media/Updated` contract on 10.11 (blocks §5)
6. Is `BGContinuedProcessingTask` (iOS 26) viable for catch-up uploads?
7. Deletion policy: phone deletes a photo — server keeps it forever, soft-deletes, or tombstones?
8. Server stack (the ingest service is the first thing to build; language/runtime undecided).

---

## 10. Sources

- [Jellyfin — Libraries documentation](https://jellyfin.org/docs/general/server/libraries/)
- [Jellyfin — External Files / media docs](https://jellyfin.org/docs/general/server/media/external-files/)
- [Jellyfin Feature Requests — HEIC Support (status: Blocked)](https://features.jellyfin.org/posts/651/heic-support-apple-iphone-picture-format)
- [Jellyfin Feature Requests — HEIF Photo support](https://features.jellyfin.org/posts/749/heif-photo-support)
- [jellyfin/jellyfin — AVIF images not showing up in Photo Library (#9364)](https://github.com/jellyfin/jellyfin/issues/9364)
- [jellyfin/jellyfin — Release 10.11.0](https://github.com/jellyfin/jellyfin/releases/tag/v10.11.0)
- [jellyfin/Swiftfin — Use folder view for Home Videos and Photos (#1896)](https://github.com/jellyfin/Swiftfin/issues/1896)
- [Jellyfin Forum — Using Jellyfin for photos](https://forum.jellyfin.org/t-using-jellyfin-for-photo-s)
- [TheAnonymous/MediaUploader — third-party upload plugin (unvetted)](https://github.com/TheAnonymous/MediaUploader)
- [Apple — Uploading asset resources in the background](https://developer.apple.com/documentation/photokit/uploading-asset-resources-in-the-background)
- [Apple — PHPhotoLibrary](https://developer.apple.com/reference/photos/phphotolibrary)
- [Apple Developer Forums — BGProcessingTask + background upload not executing reliably on TestFlight](https://developer.apple.com/forums/thread/807754)
- [Apple Developer Forums — iOS app in background for photo uploads](https://developer.apple.com/forums/thread/696678)
- [WWDC 2025 — BGContinuedProcessingTask (iOS 26 background APIs)](https://dev.to/arshtechpro/wwdc-2025-ios-26-background-apis-explained-bgcontinuedprocessingtask-changes-everything-9b5)
- [Immich — Mobile Backup docs](https://docs.immich.app/features/mobile-backup/)
- [immich-app/immich — Add deduplication hash to backup headers (PR #16133)](https://github.com/immich-app/immich/pull/16133)
- [immich-app/immich — iOS 26.1 background photo sync support (#23245)](https://github.com/immich-app/immich/discussions/23245)
