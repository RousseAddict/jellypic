# 15 — Deleting a photo from the server (plan, ratified in chat 2026-11-11)

**Scope.** One photo, deleted from the viewer, removed from the Jellyfin server — file and
item — through Jellyfin's own `DELETE /Items/{id}`. No plugin involved. Not in scope:
deleting from the phone, propagating phone deletions to the server (still out, doc 11 §12),
multi-select in the grid, and **videos — §6 says why, and when to look again.**

**The one stated constraint:** when deleting is unavailable because the signed-in account
lacks the permission, the app must say so, clearly, somewhere. §3.3.

Everything in §1 was read in the **v10.11.6** sources (the server's version) and, where it
says *measured*, checked against this server's database on 2026-11-11.

---

## 1. What Jellyfin does

### 1.1 The endpoint

`Jellyfin.Api/Controllers/LibraryController.cs:DeleteItem`, `[Authorize]`:

| Case | Answer |
|---|---|
| item unknown, or not visible to the user | `404` |
| `item.CanDelete(user)` is false | **`401`**, body `"Unauthorized access"` |
| deleted | `204`, file removed (`DeleteOptions { DeleteFileLocation = true }`) |
| the file cannot be removed (`IOException`, `UnauthorizedAccessException`) | rethrown → `ExceptionMiddleware` → `500` |

The bulk form, `DELETE /Items?ids=…`, deletes **sequentially and stops at the first
refusal, after deleting the ones before it**. Partial, not atomic. Not used.

On a `500` the database row survives: `LibraryManager.DeleteItem` throws from
`DeleteItemPath` before `_itemRepository.DeleteItem`. Only the item's metadata cache
directory is already gone, which costs nothing. A file that is already missing
(`FileNotFoundException`) is caught: the row is removed and the answer is `204`.

### 1.2 The permission rule

`MediaBrowser.Controller/Entities/BaseItem.cs`:

```
CanDelete(user)         = CanDelete() && IsAuthorizedToDelete(user, …)
CanDelete()             = IsFileProtocol            (CollectionFolder: false, root Folder: false)
IsAuthorizedToDelete    = EnableContentDeletion
                          || library id ∈ EnableContentDeletionFromFolders
```

- **`IsAdministrator` grants nothing.** An admin without the flag gets the `401`.
- Both fields default to off (`UserPolicy` constructor). The only account created with
  `EnableContentDeletion = true` is the very first one the server makes
  (`UserManager.InitializeAsync`). Every user added later starts without it.
- **Measured: 1 account of 13 on this server can delete** (the admin). Whichever account
  jellypic signs in with, check it before the first test.
- Dashboard: *Users → (user) → Profile → **Allow media deletion from*** — an *All
  libraries* checkbox (`EnableContentDeletion`) and one per library
  (`EnableContentDeletionFromFolders`). String key `HeaderAllowMediaDeletionFrom`.

It is a property of the **user**, not of the token. The token inherits it, so
re-authenticating changes nothing; only an administrator can.

### 1.3 Asking the server instead of re-deriving the rule

`Emby.Server.Implementations/Dto/DtoService.cs`: with `fields=CanDelete`, every item
carries `CanDelete = item.CanDelete(user)` — **the same function the `DELETE` calls**.
That is the probe (§3.2). Reading `GET /Users/Me` and testing the policy client-side
would re-implement `IsAuthorizedToDelete`, including its collection-folder resolution,
and would drift the day Jellyfin changes the rule.

### 1.4 The two 401s

| | Where it comes from | Body |
|---|---|---|
| Token dead or revoked | `CustomAuthenticationHandler` returns `NoResult`, `[Authorize]` challenges | empty |
| Not permitted | `DeleteItem`, **after** authentication succeeded | `"Unauthorized access"` |

Same status code. Every 401 in the app today goes to `expireSession()`: `JellyfinClient.
reportIfTokenRejected`, `UploadClient` through `HTTPStatus.rejectsToken`, and `ImageLoader`.
**A delete client built like `UploadClient` would sign you out the first time a delete is
refused.** §3.4.

### 1.5 What a delete actually removes — and why videos are out

`GetDeletePaths()` decides what goes:

- **Photo**: `PhotoResolver` builds `new Photo { Path = … }` and never sets
  `IsInMixedFolder` → `GetLocalMetadataFilesToDelete()` returns nothing → **the file
  alone**. *Measured: 7 257 of 7 257 photos have `IsInMixedFolder = 0`.*
- **Video in a photo / home-video library** (`MovieResolver`): `IsInMixedFolder = true`
  on the single-file path, `resolverResult.Count > 1 || parent.IsTopParent` on the
  multi-file path.
  - **Mixed** → `BaseItem.GetDeletePaths` adds every file in the folder whose name
    *starts with* the video's stem, with an extension among `.png .jpg .jpeg .webp .tbn
    .gif .svg .nfo .xml .srt …`. Deleting `IMG_1234.MOV` deletes `IMG_1234.JPG`, and
    `IMG_12345.JPG`. *Measured: 491 videos.*
  - **Not mixed** — a folder holding exactly one video → `Video.GetDeletePaths` returns
    **the containing folder**, removed with `Directory.Delete(…, recursive: true)`.
    *Measured: 24 videos; their folders hold 980 photos (`2018/10/` alone: 209).*

This is Jellyfin's behaviour, not ours: the web dashboard's delete does exactly the same
thing. **jellypic never offers to delete a video** (§6), gated on the index's `isVideo`
column (doc 10). Doing it from the Jellyfin web UI deserves the same caution.

---

## 2. What the app already does that matters

- `PhotoViewerViewController.applyTimelineChangeIfIdle` **dismisses the viewer** when the
  current photo vanishes from the timeline. After a delete, that is the wrong answer.
- A viewer opened from the map (`PhotoBucketViewController`) runs on an immutable
  `PhotoListTimeline`: removing the row from Core Data does not remove it there.
- Sync is additive (doc 06 §5.4): nothing removes a row except a Resync. The delete must
  remove its own row.
- A catch-up or sync page **in flight** when the row is removed would re-insert it.
- **Re-upload.** The `mode` setter calls `catchUpEngine.offer(from:)` on *every* switch
  into Automatic, and the offer covers the whole library. If accepted, `/Have` reports a
  server-deleted photo as missing and it is sent again. A manual re-send does the same,
  deliberately.

---

## 3. The plan

### 3.1 Isolation

- New file `Writer/DeleteService.swift`: `protocol DeleteService` + `JellyfinDeleteService`,
  same file (the `PhotoStore` / `UploadService` pattern). Own requests, the shared
  `jellyfinAuthorization` header, its own foreground `URLSession`. **`JellyfinAPI` is not
  extended**, consistent with doc 12 §2. One file = 4 pbxproj insertions.
- Works **without upload-for-jelly** and regardless of the backup mode: it is core
  Jellyfin. It lives in `Writer/` because the writer is the half that changes the server.
- The writer does not touch Core Data. It answers "deleted"; the viewer — reader side —
  removes the row through `PhotoStore`.
- Touch points: `AppServices` (owns it, sets `credentials` + library id at the same places
  as `upload`) and `SettingsViewController` are existing ones. **`Viewer/` becomes the
  5th** (`PhotoDetailsViewController` + `PhotoViewerViewController`). Doc 12 §2 exists so
  that a fifth is visible in review: it gets listed there.
- `import Photos` invariant: unaffected.

### 3.2 The capability probe

```
GET Items?userId=…&parentId=<library>&recursive=true&includeItemTypes=Photo
         &limit=1&fields=CanDelete&enableImages=false&enableUserData=false
         &enableTotalRecordCount=false
```

| Answer | State |
|---|---|
| one item, `CanDelete: true` | `.allowed` |
| one item, `CanDelete: false` | `.notPermitted` |
| no item (empty library) | `.unknown` — nothing to delete anyway |
| 401 | session expired → `onTokenRejected` (here a 401 *is* the token: a GET is never refused for permission) |
| timeout, 5xx, offline | **unchanged** — same rule as the `Targets` probe (doc 12 §4) |

Held in memory for the process, not persisted (like `availability`). Probed when the
Settings card opens (next to `refreshAvailability`), on the grid's `viewDidAppear`, and on
`didBecomeActive`. A stale `.allowed` is caught by §3.4; a stale `.notPermitted` heals on
the next Settings open, which is exactly where someone who just got the permission looks.

### 3.3 The statement — the user's constraint

**Settings → Account**, a `SettingsNoteView` under *Sign out*. The permission belongs to
the account, and that is the section a reader of it opens.

- `.notPermitted`: *"Deleting is off for this account. Your Jellyfin server doesn't let
  «user» delete from «Library». An administrator can turn it on in the Jellyfin dashboard:
  Users → «user» → Allow media deletion from."*
- `.allowed`: *"This account can delete photos from «Library». A deleted photo is removed
  from your server for good."*
- `.unknown`: no note.

In the viewer, **the delete button is hidden unless `.allowed`** — the rule already
applied to the `+` (doc 12 §11: an entry that leads to a refusal is worse than no entry),
and the Settings note is what says why. Ratified over the alternative of a dimmed button
that explains itself on tap.

### 3.4 Telling the two 401s apart

The delete path **never** calls `onTokenRejected` and never uses `HTTPStatus.rejectsToken`
on its response. On a `401` from `DELETE`, it re-runs the probe of §3.2:

- probe `401` → the token is dead → `onTokenRejected` → the existing re-auth card;
- probe `CanDelete: false` → permission revoked since the last probe → state
  `.notPermitted`, alert with the §3.3 sentence, **the session stays alive**;
- probe `CanDelete: true` → treated as transient ("Try again").

The body (`"Unauthorized access"`) is not parsed: it is a message, not a contract.

### 3.5 The UI

- **Entry: a trash `GlyphButton` in the details card header**, next to share (`⋯` → card).
  Not on the viewer's chrome: the chrome is hidden by default, and two taps plus a
  confirmation is the right distance from a destructive action. `TrashGlyphView` joins
  `Design/FloatingButton.swift`, under that file's existing `LEGACY(ios12)` marker.
- Hidden for a video (§6), for a viewer opened from the map (`PhotoListTimeline`, §2 —
  the viewer gets an `allowsDeletion` flag at init), and unless `.allowed`.
- **Confirmation**: `UIAlertController` action sheet, destructive *Delete from server*.
  *"«file» will be removed from «server» for everyone who uses it. This can't be undone.
  The photo on this iPhone is not touched."* When the backup mode is not Off, one more
  line: *"If Jellypic backs up your library again, it will be sent again."* (§2).
- During the request the button shows a spinner and the card stays open; the request is
  not cancellable once sent (a `DELETE` is not something to abandon half-way).

### 3.6 After the answer

| Answer | Effect |
|---|---|
| `204` | `PhotoStore.remove(ids:)` → FRC → grid and viewer update, no Resync |
| `404` | already gone (deleted elsewhere): remove the row too |
| `401` | §3.4 |
| `500` | *"The server couldn't delete the file. Check that Jellyfin can write to the library folder."* Nothing removed locally — the server kept its row too |
| offline / timeout | *"Not deleted: the server didn't answer."* Nothing removed |

- **`PhotoStore.remove(ids:completion:)`** (new, `Index/PhotoStore.swift`): fetch by id on
  the background context, delete, save → the view context merges and the FRC animates.
  No batch delete — one row.
- **In-memory tombstones**: the store keeps the ids it removed this session and `write`
  skips them, so a sync or catch-up page already in flight cannot put the row back.
  Session-scoped on purpose: after a relaunch the server is the truth again.
- **Viewer steps to the neighbour.** Before calling `remove`, the viewer records the
  neighbouring id (the next *older* photo, else the next newer one). When the timeline
  change lands, `applyTimelineChangeIfIdle` moves there instead of dismissing; it still
  dismisses when nothing is left.

### 3.7 Not done, named

- **Re-upload after an accepted re-offer** (§2): stated in the confirmation, not
  prevented — ratified. Preventing it needs a tombstone the next scan can see — a record in
  upload-for-jelly (`Have` answering "deleted"), or a local set of the 16-hex short hash
  the plugin puts in every filename. Not v1.
- The map's markers stay stale until the map reloads.
- Image cache entries for the deleted item are left to normal eviction.

---

## 4. Milestones

| | Delivers | Testable alone |
|---|---|---|
| **D0** | `DeleteService` + probe + Settings note | the statement, with no delete button yet |
| **D1** | `delete(itemId:)` + §3.4 + `PhotoStore.remove` + tombstones | — |
| **D2** | glyph, card button, confirmation, neighbour step | the whole path |
| **D3** | docs: doc 12 §2 (5th touch point), doc 08 (viewer), rationale here | — |

D0 first on purpose: it settles the stated constraint and the permission state of the
real account before anything can be deleted.

## 5. Device tests

1. Account without the permission: the Settings note says so, with the dashboard path; no
   delete button anywhere.
2. Grant it in the dashboard, reopen Settings: the note flips, the button appears.
3. Delete a photo: the file is gone on disk, the item is gone from the API, the grid
   updates without a Resync, the viewer shows the neighbour.
4. Revoke the permission with the app open, then delete: the alert names the permission,
   **the session is not expired**, the Settings note is updated.
5. Revoke the session in the dashboard, then delete: re-auth card, not the permission alert.
6. A video: no delete button.
7. Library mounted read-only: the `500` message, the photo still in the grid.
8. Viewer opened from the map: no delete button.
9. Delete the last photo of a month: the section goes. Delete the only photo left: the
   viewer closes.
10. Backup mode Automatic: the confirmation carries the re-upload line.

---

## 6. Why videos are not deleted — and when to look again

**Decision, 2026-11-11: videos are out of delete for now. Jellyfin's native delete is not
safe for them in this library, and we are not adding machinery to work around it.**

### Why the native delete is unsafe for a video here

The photos and videos are separate *items* in Jellyfin (`Photo` and `Video`) and the app
shows them apart, but they are **not separate on disk**: the library is organised by year
and month, and a video sits in the same month folder as that month's photos. *Measured:
all 107 folders that hold a video also hold photos.* The upload plugin files the same way.

A delete acts on the disk, and for a video it does not stop at the video's file. A photos
or home-video library resolves its videos with the **movie** resolver, and the delete then
applies two movie rules (§1.5), with no check of the library type anywhere on the path:

- **The video is the only one in its folder** → "this folder is the movie's folder" → the
  whole folder is deleted, recursively. `2018/10/` holds `IMG_0084.MOV` and 209 photos:
  deleting that video deletes the 209 photos. *Measured: 24 videos in this situation,
  sharing their folders with 980 photos.*
- **The folder holds other videos too** → the video's file, plus every image or sidecar
  whose name *starts with* the video's name: `IMG_1234.MOV` takes `IMG_1234.JPG` and
  `IMG_12345.JPG`. *Measured: the other 491 videos.*

The flag that picks the rule (`IsInMixedFolder`) is set at scan time and **never sent to
clients**, so the app cannot even tell which rule a video falls under. Its value in this
server's database matches the rule for all 515 videos, without exception. A Jellyfin forum
report (10.10.7, "Folder wipe issue") shows the same thing in a server log —
`Deleting item path, Type: "Video", Path: "/media/home/main_directory"` — unanswered by the
maintainers.

### What was considered and set aside

- **A delete endpoint in upload-for-jelly** that removes exactly `item.Path`, then the item
  with `DeleteFileLocation = false` (verified: that removes the database row and touches no
  media file). Safe, but it is plugin work and makes video delete depend on the plugin.
- **Moving videos into their own tree** (`Videos/2018/10/…`). With no photos next to them,
  both rules become harmless. It means moving 515 files on the server and changing how the
  plugin files videos.

Both are sound; neither is worth it yet.

### When to look again

- **On every Jellyfin upgrade**, compare against v10.11.6: `Video.GetDeletePaths`,
  `BaseItem.GetDeletePaths` / `GetLocalMetadataFilesToDelete`, and the `isInMixedFolder`
  assignment in `MovieResolver`. If a library-type check or a narrower delete appears,
  re-measure on a throwaway folder (one copied video + two copied photos, delete the video,
  check the folder survives) before lifting the gate.
- If an upstream issue for this gets fixed. The state of the upstream tracker is recorded
  below.
- Lifting the gate is the `isVideo` check of §3.5 and nothing else: the probe, the 401
  handling and the Settings note already cover videos.

### Upstream status (checked 2026-11-11)

**Reported for other library types, never for photos or home videos, and unfixed.** The
delete code is identical in v10.11.6, v10.11.11, v12.4 (latest release, 2026-10-26) and
`master`: `Video.GetDeletePaths`, `BaseItem.GetDeletePaths` / `GetLocalMetadataFilesToDelete`
and its extension list, the `isInMixedFolder` line in `MovieResolver`, `DeleteItemPath`, and
the endpoints. No release note mentions it.

| Issue | Mechanism | Outcome |
|---|---|---|
| #12097 "media delete feature removes all other movies too" (10.9.6) | containing folder, movies library — the log deletes `/media1/Movies` | closed by the stale bot, *not planned*, 2025-03-11; no maintainer verdict |
| #13250 "…deleting a single 'extras' file deletes all extras in that folder (and the folder)" (10.10.3) | containing folder, traced to `IsInMixedFolder = false` | **treated as a bug**; PR #13536 (merged 2025-04-26) marks *extras* as mixed when their folder holds more than one file. `GetDeletePaths` untouched; extras only |
| #10755 "Deleting a video damaged the associated files of other videos" (10.8.13) | name prefix — `S30E1` took the sidecars of `S30E10`…`S30E19` | closed, put down to an unsupported naming scheme; no code change |
| #17289 "…mixed folder also deletes NFO/subtitles/artwork of other items whose names share a prefix" | name prefix | withdrawn by its author 9 minutes after opening, 2026-07-10 |

What this says for the recheck: the one precedent of a fix (#13536) corrected the *flag*
for one item kind instead of narrowing the delete, so a fix for our case would most likely
look the same — `MovieResolver` marking videos in `photos` / `homevideos` libraries as
mixed. That would close the folder delete but **not** the name-prefix delete, which the
team has so far treated as working as designed. Lifting the gate needs both closed, or
videos moved where no photo shares their folder (above).

---

## 7. What was built (D0–D2), and where it departs from §3

Files: `Writer/DeleteService.swift` (new — `DeleteCapability`, `DeleteOutcome`,
`DeleteService`, `JellyfinDeleteService`), `Index/PhotoStore.swift` (`remove(ids:)` +
tombstones), `Design/FloatingButton.swift` (`TrashGlyphView`),
`Viewer/PhotoDetailsViewController.swift`, `Viewer/PhotoViewerViewController.swift`,
`Grid/PhotoGridViewController.swift`, `Settings/SettingsViewController.swift`,
`AppServices.swift`. pbxproj: ids `…145` / `…146`.

### Departures, each deliberate

- **The probe runs when Settings opens and when the details card opens — not on the grid's
  `viewDidAppear` or `didBecomeActive`** (§3.2). The button lives in the card, so the card
  asks: one small request next to the two the card already makes, an answer that is never
  older than the card, and no grid code at all. A known answer shows the button at once;
  the refresh only corrects it.
- **The button is dimmed while the request runs, not replaced by a spinner** (§3.5). Same
  signal as the viewer's play button while playback starts; the share button dims with it
  and the card cannot be dismissed (`allowsUserDismissal = false`) until the answer lands.
  The button is also hidden while an original is downloading.
- **The row is removed from the card's completion, not by the viewer** (§3.1 said the
  viewer). Still reader code — the card is in `Viewer/` — but the closure captures
  `services.store` and `onDeleted` before the request, so a `204` removes the row even if
  the card is gone by the time it lands.
- **The viewer's step to the neighbour needs no change to `applyTimelineChangeIfIdle`.**
  `onDeleted` fires *before* `remove`: the viewer sets `currentPhotoId` to the neighbour
  (next older, else next newer, else `""`), and when the store's change arrives the
  existing re-resolve-by-id lands on it. `""` resolves to nothing, which is the existing
  "dismiss when the photo is gone" branch.
- **`prepareForReturn` in the grid now bounds-checks the index path.** A viewer that
  dismisses because its photo vanished reports a stale path, and `scrollToItem` on an
  invalid one raises. Deleting the last photo left would have hit it; so would a Resync with
  the viewer open, which predates this feature.
- **One home for the permission sentence.** `DeleteCapability.note(account:library:)` is
  what the Settings note shows *and* what the refusal alert says, so the two cannot drift.
- **A timeout says "Try again", never "Nothing was deleted."** The `DELETE` may have landed
  with its answer lost. Trying again answers `404`, which removes the row like a `204`.
- **`401` with a probe that still says `CanDelete: true` is `.unexpected`**, not a refusal.
- Map viewer: `allowsDeletion` defaults to `false`; only the grid sets it.

### Verification so far

Built on SERV2 (Xcode 13.2.1, Debug, floor 12.2) and reported working on the iPhone 5s on
2026-11-11. The tests of §5 were not reported one by one, so the edge cases — revocation
with the app open, read-only mount, deleting the last photo left — are still unconfirmed.
