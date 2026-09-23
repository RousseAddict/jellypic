# 11 — Writer: the upload contract

The writer's transport is a **second Jellyfin server plugin**, `upload-for-jelly`, in its
own repository beside `heic-for-jelly`. This document is the contract between the iOS app
and that plugin. It is written before either side exists, because the hard decisions are
in the protocol, not in the code.

Everything asserted about Jellyfin here was read in the sources at tag **v10.11.0** and is
cited `file:symbol`. Nothing is inferred from documentation or search results.

## 1. Why a plugin, and why a second one

The constraint that settled it is not "no extra server" alone — it is **"the app may be
used by other people"**. A transport that depends on what the host happens to run means
supporting three or four protocols and asking each user what their box is. Only a plugin
gives the same endpoint to everybody.

The alternatives were eliminated by measurement, not by taste:

- **60 API controllers at v10.11.0; exactly five endpoints accept bytes**, and none of
  them creates a library item from uploaded content. `ImageController` (four sites, base64
  through `GetFromBase64Stream`, requires an existing item, writes artwork),
  `POST Audio/{itemId}/Lyrics`, `POST Videos/{itemId}/Subtitles`, `POST Document`
  (`ClientLogController` — log folder, server-chosen filename, `AllowClientLogUpload` off
  by default, 1 MB cap), and plugin configuration JSON. The only two DTOs named `Upload`
  in the entire repository are subtitles and lyrics.
- **`Upnp`: 0 occurrences. `ContentDirectory`: 0. `Dav`: 0. `Ftp`: 0.** UPnP was the one
  serious non-plugin lead, because it is HTTP and would therefore have survived the
  background-transfer filter below. It does not exist here: what remains of DLNA in core
  is only the `DeviceProfile` model — the DLNA server has been a plugin since 10.9.
- **`URLSessionConfiguration.background` carries HTTP(S) only.** Anything else cannot
  upload while the app is not in the foreground, which disqualifies SSH/SFTP, SMB, FTP and
  rsync before the zero-dependency rule is even consulted. iOS also ships no SSH client,
  and `CryptoKit` is iOS 13+.

Deliberately refused: smuggling photos through the lyrics or subtitle endpoints. They do
accept a caller-supplied extension, but they require a pre-existing item per photo and
they lean on a validation weakness rather than a contract.

**Two plugins, not one.** `heic-for-jelly` advertises *"No HTTP endpoint is added"* — it
decorates `IImageEncoder`, which is exactly why it inherits auth, per-library ACL, the
resized-image cache and ETags without exposing a surface. Bolting a write endpoint onto it
would destroy its one safety property and couple a read-path decoder to a write-path
ingest with a different release cadence, a different risk profile and different policies.

Plugins may register their own controllers: `Jellyfin.Server/Startup.cs:74`,
`services.AddJellyfinApi(_serverApplicationHost.GetApiPluginAssemblies(), …)`.

## 2. Ratified decisions this contract encodes

- **The original IS the library.** No `archive/` + `library/` split, no JPEG derivative.
  `heic-for-jelly` makes the original viewable and EXIF-dated, which deletes the reason
  doc 01 §3 existed. Doc 01 §4 (naming and bucketing) survives; **doc 01 §3 is dead.**
- **A photo is identified by the SHA-256 of its bytes.** It is the only key that is true
  across devices and survives an iOS restore, and the server can re-verify it.
- **The server is the sole judge of what is already stored.** The app never asserts that a
  photo is backed up.
- **The app keeps a local memo of the hash computation, not of the upload state.**

## 3. Filesystem write access is not granted by Jellyfin permissions

The two layers are unrelated. Jellyfin policies authorise the *call*; writing a file is an
`open(2)` subject to POSIX modes, ACLs, mount flags and SELinux. The plugin runs in the
Jellyfin process and has exactly the rights that process has.

The failure is common, not exotic. Jellyfin's own container documentation offers the
read-only mount as its Podman example: *"This example mounts your media library read-only
by setting `ro=true`; set this to `ro=false` if you wish to give Jellyfin write access to
your media."* Add `--user uid:gid` against media owned by someone else, NFS `root_squash`,
a read-only SMB mount, an SELinux relabel.

But the request is not unreasonable: **Jellyfin already writes into media folders when
configured to.** `LibraryOptions.SaveLocalMetadata`, `SaveLyricsWithMedia`,
`SaveTrickplayWithMedia`, and `SaveSubtitlesWithMedia` — which **defaults to `true`**. Many
installations already grant this without knowing it.

**There is no built-in probe.** `MediaBrowser.Model/IO/IFileSystem.cs` exposes no
`CanWrite`/`IsWritable`, and checking mode bits would be wrong anyway: ACLs, mount flags,
SELinux and quotas all lie to a `stat()`. The only honest test is to create and delete a
file in the exact target directory.

## 4. `GET /UploadForJelly/Targets` — the preflight

Returns, for each photo library the plugin is configured for and the caller may see:

```json
{ "targets": [
  { "id": "a1b2…", "name": "Photos",
    "writable": true, "reason": null,
    "freeBytes": 812345678 } ] }
```

`reason` when `writable` is false: `READ_ONLY_MOUNT`, `PERMISSION_DENIED`, `PATH_MISSING`,
`NOT_CONFIGURED`.

The probe creates and deletes a temporary file **in the target root**, every time the
endpoint is called. It is not cached for the process lifetime: volumes get remounted and
disks fill.

The absolute server path is **not** returned. The app never needs it, and it would leak
host layout to a non-administrator.

The app calls this when the user arms backup, and **refuses to arm against a target that
is not writable**, showing the reason. Discovering `EACCES` on photo 1 of 20 000 is the
version we are avoiding.

## 5. Identity: SHA-256, computed once, memoised locally

The objection to hashing on an A7 — "reading every byte is expensive" — does not apply,
because **the background upload already forces us to materialise each asset into a
temporary file**. The hash is computed in the same pass that writes it. The marginal cost
is near zero.

What the local table stores is therefore a *memo of a pure, expensive function*, not a
claim about the server:

```
localIdentifier + modificationDate  →  sha256
```

Including `modificationDate` is what makes edits correct: a retouched photo invalidates the
memo, is re-hashed, and legitimately becomes a new upload.

The distinction matters. Had the local table stored "uploaded: yes", losing it would mean
20 000 re-uploads and a server-side deletion would become a permanent hole. Storing a hash
memo has neither failure mode: the worst case is recomputation.

## 6. `POST /UploadForJelly/Have` — what is missing, in batches

```
POST  { "targetId": "a1b2…",
        "keys": [ { "sha": "<64 hex>", "month": "2026-09" }, … ] }   // ≤ 500
  →   { "missing": [ "<sha>", … ] }
```

Batching does not weaken "the server judges" — 500 keys in one request is the same
authority as 500 requests, decided by the same code. It is transport, not semantics.
20 000 photos become 40 requests and, crucially, **zero iCloud downloads** for photos
already known.

**The plugin keeps no database.** The hash is in the filename (§7), so the month sent with
each key tells the server which single directory to enumerate. At 20 000 photos over ~120
months that is ~170 entries per directory, a handful of directories per batch. The
filesystem is the index — nothing to migrate, nothing to corrupt, nothing to rebuild.

Photos with no capture date go to an `undated/` bucket, matching the reader's existing
undated fallback (doc 06).

Known limit: a photo already placed there by some other tool, under some other name, will
not be recognised. We deduplicate our own uploads, not the whole folder.

## 7. Layout on disk, and why eight hex characters is not enough

```
<library>/2026/2026-09/20260921-184233_iphone-15_9f3c1a4b7e2d05c8.heic
<library>/undated/…
```

Doc 01 §4 proposed `_<sha8>`. **That is wrong at this scale.** Birthday collision over
`n` files with `b` bits is about `n² / 2^(b+1)`:

| hex chars | bits | 20 000 files | 100 000 files |
|---|---|---|---|
| 8 | 32 | **~4.7 %** | effectively certain |
| 16 | 64 | 1.1 × 10⁻¹¹ | 2.7 × 10⁻¹⁰ |

So the filename carries **16 hex characters**. `Have` matches on that 64-bit prefix; the
upload path re-verifies the full 256 bits against the received bytes.

## 8. `POST /UploadForJelly/Items` — the upload

Raw bytes in the body, **not base64**. Core uses base64 in `ImageController` because those
are JSON-ish fields; base64 costs 33 % on the wire and forces buffering. `LyricsController`
is the precedent for raw: `[AcceptsFile(…)]` plus `Request.Body`.

```
POST /UploadForJelly/Items?targetId=…&sha256=…&capturedAt=…&deviceSlug=…&fileName=…
Content-Type: image/heic
<bytes>

201  { "key": "…", "path": "2026/2026-09/…", "created": true  }
200  { "key": "…", "path": "2026/2026-09/…", "created": false }   // idempotent replay
```

`capturedAt` is used **only to choose the folder**. Jellyfin still reads EXIF itself for
the timeline, and the reader still sorts on `PremiereDate` (doc 04). We are not a metadata
source.

Write algorithm:

1. Stream the body to `<library>/.upload-for-jelly/<guid>.part`, hashing in the same pass.
2. Compare to the declared `sha256`. Mismatch → delete and `422`.
3. `File.Move` onto the final path. The staging directory is **inside the library root** so
   that this is an atomic rename rather than a copy across filesystems.
4. Notify the library of the new path.

**Trap: ASP.NET's default request body limit is ~30 MB.** A 4K video sails past it and the
client gets a `413` that looks like a policy refusal. The endpoint must lift the limit
explicitly, and the plugin must document the Kestrel-level ceiling.

## 9. The staging directory, and two independent reasons the scanner ignores it

Verified, because getting this wrong means the scanner indexes half-written files:

- `Emby.Server.Implementations/Library/IgnorePatterns.cs` includes `"**/.*"` under *"Unix
  hidden files"*. **But the glob only covers the final segment** — which is exactly why the
  list spells out `"**/.actors"` *and* `"**/.actors/**"` for every hidden directory it
  means to exclude wholesale. A dot-prefixed directory alone guarantees nothing about the
  files inside it.
- `Emby.Server.Implementations/Library/DotIgnoreIgnoreRule.cs` walks up the ancestors from
  any entry, and **an empty `.ignore` file makes everything beneath it ignored** —
  `if (string.IsNullOrWhiteSpace(ignoreFileString)) return true;`, on the file branch as
  well as the directory branch.

So the plugin creates `.upload-for-jelly/` **and** drops an empty `.ignore` inside it. Two
mechanisms, neither depending on the other.

(This also settles a question open since August in doc 01 §9: **10.11 does honour
`.ignore`.**)

## 10. Error taxonomy: terminal versus retryable

This belongs in the contract from the first line, because it is what stops a read-only
mount from producing 20 000 retries.

| Status | Meaning | Client behaviour |
|---|---|---|
| `401` / `403` | token rejected | terminal — reuse the reader's existing re-auth card (doc 04 §6) |
| `409 TARGET_NOT_WRITABLE` | filesystem refused | **terminal for the whole queue**, banner, re-run preflight |
| `507 INSUFFICIENT_STORAGE` | disk full | **terminal for the whole queue**, banner |
| `422 HASH_MISMATCH` | bytes corrupted in transit | retry this item once, then terminal for this item |
| `413` | above the body limit | terminal for this item |
| `404 UNKNOWN_TARGET` | library removed or unconfigured | terminal, re-run preflight |
| `5xx`, timeout | transient | retry with backoff |

The split is "whole queue" versus "this item". Getting that wrong is how a single
misconfiguration burns a battery overnight.

## 11. Authorisation

Jellyfin has no built-in "may upload photos" policy, so the plugin defines its own:

- The caller must be authenticated and must be able to see the target library (its normal
  per-library ACL).
- Plugin configuration holds an **allowlist of target library ids**, set by an
  administrator. **It is empty by default.**

That default is the point: **installing the plugin must not, by itself, open a write
surface on the host.** An administrator opts one library in, deliberately.

## 12. Out of scope for v1

Live Photos (a linked pair of files), burst sets, albums, deletion propagation, and any
write path other than "add a new original". Each of these is a contract change, not an
implementation detail, and each earns its own section here before it earns any code.
