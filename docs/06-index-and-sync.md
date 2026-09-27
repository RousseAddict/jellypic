# 06 — Core Data index and paged sync

Scope: livrable 1, step L1.2. Non-visual: the local index the grid will read from,
and the loop that fills it. The progress UI is deliberately not part of this step.

## 1. Why a local index at all

The grid has to scroll 20 000 items at 60 fps on an A7 with 1 GB of RAM. It
cannot ask the server for a window of items while the finger is on the screen —
one round trip per scroll is a guaranteed stutter, and a 20 000-item JSON array
is neither cheap to parse nor sane to hold in memory.

So the item list is mirrored locally, once, and the grid reads from Core Data
through a fetched-results controller. The server stays the source of *pixels*,
not of *order*.

## 2. Programmatic model, no `.xcdatamodeld`

`Index/PhotoItem.swift` builds the `NSManagedObjectModel` in code:
`NSEntityDescription` + seven `NSAttributeDescription` + two
`NSFetchIndexDescription` (`byId`, and `byTimeline` over the grid's three sort
keys — see §5.2).

Two reasons:

- The project file is **hand-written**. A `.xcdatamodeld` is a bundle that needs
  an `XCVersionGroup` node and a `momc` compile step in the resources phase —
  two things that are painful to maintain by hand and easy to get silently wrong.
- The store is a **rebuildable cache**, not user data. On a schema change the
  right answer is "wipe and resync", not a lightweight migration. Nothing here
  is worth a versioned model.

Integer attributes are non-optional with `defaultValue = 0`; without the default
Core Data refuses to save a freshly inserted object. Rows are created with
`NSEntityDescription.insertNewObject(forEntityName:into:)` rather than
`PhotoItem(context:)`, which is the safer call when the entity comes from a
model that was never code-generated.

## 2.1 The store owns the fetch

`makeTimeline()` builds the fetched results controller — the request, the three
sort descriptors, the `sectionNameKeyPath`, the batch size — and `viewContext`
is private. The grid used to assemble all of that itself, with attribute names
written as string literals that duplicated `PhotoItem`'s declarations; renaming
an attribute compiled cleanly and crashed at runtime. The names are now
`#keyPath(PhotoItem.monthKey)` and friends, so the same rename fails to build.

This is also the invariant behind §5.2: the sort order and the composite index
have to agree, and they cannot agree reliably when they are declared in two
files that never see each other.

## 2.2 The seam: `PhotoStore`, `PhotoTimeline`, `Photo`

`CLAUDE.md` promised "Core Data behind a `PhotoStore` protocol" from the start
and for a while that was simply false — `PhotoStore` was a concrete class, and
the `NSFetchedResultsController` itself crossed into the grid and on into the
viewer. Both view controllers imported `CoreData`.

There are now two protocols and a value type, all in `Index/PhotoStore.swift`
next to the only implementation. Keeping the contract and its implementation in
one file is deliberate: the day SwiftData arrives, the file to open is exactly
the one that already holds both halves. A separate header-like file would look
tidier and would buy nothing, at the cost of six `project.pbxproj` edits.

**`PhotoTimeline` is the interesting half.** Replacing a fetched results
controller means reproducing what it actually does for the grid — sections,
batched faulting, and a change callback — without leaking how. The protocol is
therefore narrow on purpose: `sectionCount`, `numberOfPhotos(inSection:)`,
`monthKey(forSection:)`, `photo(at:)`, `isEmpty`, and two closures. That is
the entire surface both view controllers were using; nothing was designed for
a hypothetical future reader.

`photo(at:)` returns a `Photo` struct, not the `PhotoItem` managed object. The
struct carries three fields — `id`, `imageTag`, `captureDate` — because those
are the only three the UI ever reads. `name`, `width` and `height` stay in the
store: the details card refetches metadata from the server, so mirroring them
into the value type would be inventing a requirement. The cost is one small
allocation per cell dequeue, which is noise next to the fault it replaces; the
gain is that a `PhotoItem` can no longer outlive its context inside a cell.

The two closures replace two mechanisms the grid used to own. `onChange` was
`NSFetchedResultsControllerDelegate` conformance; `onReset` was a
`NotificationCenter` observer on `PhotoStore.didResetNotification`. The
notification still exists — `reset()` has two callers that hold no reference to
the grid, see §5.1 — but it is now private to the store's file, and
`CoreDataTimeline` is the only observer. It refetches before firing `onReset`,
so the grid's handler is three lines of UIKit with no persistence knowledge.

`upsert(_:completion:)` is the other half of the leak, and it is easy to miss.
The store used to expose `performBackground { context in }` plus
`upsert(_:in:)`, which meant `SyncEngine` — pure Foundation, no business being
anywhere near persistence — was handling an `NSManagedObjectContext` and
hopping back to the main queue by hand. The store now owns its queue and
delivers on the main queue, like `JellyfinAPI` already did, and `SyncEngine`
lost nine lines.

`grep -rn "import CoreData" jellypic/` returns two files, `Index/PhotoItem.swift`
and `Index/PhotoStore.swift`. That grep is the invariant; if it ever returns a
third, the seam has leaked.

## 3. The query

`GET /Items`, verified field by field against Jellyfin **v10.11.0** source
(`Jellyfin.Data/Enums/ItemSortBy.cs`, `BaseItemKind.cs`,
`MediaBrowser.Model/Querying/ItemFields.cs`) rather than against the docs:

| Param | Value | Why |
| --- | --- | --- |
| `parentId` | library id | scopes to the picked library |
| `recursive` | `true` | a photo library is a folder tree |
| `includeItemTypes` | `Photo` | `BaseItemKind.Photo` |
| `sortBy` | `PremiereDate,SortName` | see below |
| `sortOrder` | `Descending` | see below |
| `fields` | `DateCreated,Width,Height` | not returned by default |
| `enableImageTypes` | `Primary` + `imageTypeLimit=1` | we only ever draw the primary |
| `enableUserData` | `false` | no play state on a photo; smaller payload |
| `enableTotalRecordCount` | `true` on the first page only | it costs a `COUNT(*)` |

**`SortName` is a tiebreaker, not a preference.** Paging by `startIndex` is only
stable if the sort is total. A library where many photos share a
`PremiereDate` — a burst, or a folder with no EXIF at all — would otherwise let
the server return them in a different order on page 7 than on page 6, and items
would be skipped or duplicated.

`PremiereDate` and not `DateCreated`: doc 01 covers it, but the short version is
that Jellyfin stores the EXIF wall clock unconverted in `PremiereDate` and
`.ToUniversalTime()`-shifted in `DateCreated`, so `DateCreated` moves when the
server's `TZ` changes.

**`Descending` is a UI decision, not an API one.** The grid shows newest first,
so indexing newest first means the top of the screen fills on page 1 instead of
after the last page. It also keeps `contentOffset` stable: new rows land at the
*end* of the fetched results, below the visible window, so a `reloadData`
mid-sync does not shove the content the user is looking at.

## 4. Undated photos

`PhotoDTO.captureDate` is `premiereDate ?? dateCreated`. If both are absent the
photo is still indexed, with `captureDate == nil` and `monthKey == ""`. The grid
sorts `monthKey` descending and `""` is lexicographically smallest, so these land
at the **end** of the timeline in an "Undated" section. Nothing disappears
silently — a photo missing from the grid is a bug report we cannot diagnose,
a photo in a weird section is one the user can see and explain.

`monthKey` is formatted with a **UTC** `TimeZone` and `en_US_POSIX`. Using the
device calendar would re-introduce exactly the wall-clock shift that choosing
`PremiereDate` was meant to avoid: a photo taken at 00:30 would land in the
previous month for a user in a negative offset.

**That formatter is declared once, and both directions go through it.** `MonthKey`
owns `make(from:)`, `title(for:)` and `shortTitle(for:)` together, in `PhotoItem.swift`,
next to the attribute it encodes. The display strings used to live in an extension
declared from a *view* (`MonthHeaderView`), with its own private parser that was a
character-for-character clone — same `en_US_POSIX`, same UTC, same `"yyyy-MM"`.
Two copies of the invariant means one of them can drift, and a drifted parser does
not crash: photos simply appear under a different month than the one they are
indexed in, while the index itself stays correct and the fault looks like bad data.
The localised `MMMMyyyy` / `MMMyyyy` output formatters are a separate concern and
stay separate — they are deliberately *not* pinned to a locale, only to UTC.

## 5. Paging and resumability

`Index/SyncEngine.swift` walks pages of 200 serially — never in parallel. Two
concurrent pages would double peak memory for no wall-clock gain on a device
whose bottleneck is the SQLite write, not the network.

The reached index is persisted after every page (`Preferences.syncStartIndex`),
so a sync killed by the OS resumes instead of restarting. This is safe because
**every page is an upsert by `id`**: fetch `id IN %@` for the page, update the
matches, insert the rest. Replaying a page is a no-op.

Known limit: if the library changed between two runs, resuming mid-way can miss
items, because `startIndex` addresses a server-side ordering that has shifted.
The fix is a manual resync (§5.5), not a more clever cursor — Jellyfin has no
opaque pagination token.

A run ends when a page comes back shorter than the page size; `syncCompleted` is
then set and `start` becomes a no-op until something calls `refresh`. Changing
library wipes the store and the counters, since `startIndex` means nothing
across parents.

`context.reset()` after each page save is not optional at 1 GB: without it the
background context's row cache keeps every object of the whole run alive and the
app is jetsammed somewhere past 10 000 items.

## 5.1 Sign-out wipes the index

`AppServices.signOut` cancels the sync **before** the network call, then wipes
the store and the counters in the completion, next to the Keychain clear. The
index is derived data belonging to one account on one server; leaving it behind
would let the next account see the previous one's timeline for as long as its
own sync takes to overwrite it.

`PhotoStore.reset()` runs its `NSBatchDeleteRequest` on the **background**
context with `performAndWait`, not on the view context. That is what serialises
it behind a page write that is already in flight; a delete on another queue
would race and leave rows from the wiped library behind.

### The view context cannot simply be reset

A batch delete goes straight to the store and leaves the view context holding
objects that no longer have rows. The first version answered that with
`viewContext.reset()`, which is worse than the problem: it turns every
`PhotoItem` into an inaccessible object while the grid's fetched results
controller is still alive and still holding them. Sign-out cross-fades over
**0.3 s with the grid on screen**, and a batch delete fires no delegate
callback by construction, so the controller never learns anything changed.
That is an `NSObjectInaccessibleException` with a 300 ms window, widening with
the size of the index.

The delete now asks for `resultType = .resultTypeObjectIDs` and feeds them to
`NSManagedObjectContext.mergeChanges(fromRemoteContextSave:into:)`. The view
context deletes exactly those objects and posts the notification the fetched
results controller is listening for.

That is enough for correctness but not for the redraw: L1.3 deliberately
defers `reloadData` until scrolling stops, and a deferred reload after the
controller has emptied itself is the same crash with a different trigger. So
`reset()` also posts a notification, `CoreDataTimeline` refetches on it and
fires `onReset`, and the grid reloads **immediately**, bypassing the
coalescing. A notification rather than a direct call because neither caller —
`AppServices.signOut` and `SyncEngine.start` on a library change — holds a
reference to the grid, and the app already uses this pattern for
`Theme.didChangeNotification`. The name is file-private (§2.2): the grid no
longer observes it, and nothing outside the store should.

## 5.2 Indexes, and why the model carries a version

The grid sorts on `monthKey`, then `captureDate`, then `id`, and sections on
`monthKey`. A single-column index on `captureDate` is useless to that query:
SQLite cannot use an index on the second column of an `ORDER BY`. The model
therefore declares one composite index over the three sort keys, in order. The
old `byCaptureDate` index is gone — nothing sorts on `captureDate` alone, so it
was write cost with no reader. `byId` stays; the upsert's `id IN %@` is the
hottest query in the sync.

**Fetch indexes are not part of the model's `versionHash`.** Changing them does
not make an existing store look incompatible, so no lightweight migration runs,
so the new index is never created on a store that already exists — the change
is silently inert for anyone who already synced. `PhotoModel.schemaVersion` is
the workaround: `PhotoStore.load` compares it to
`Preferences.indexSchemaVersion` and destroys the store when they differ. This
is the policy from §2 made explicit rather than assumed — the index is a
rebuildable cache, so a schema change is a wipe and a resync, and bumping the
constant is the whole migration story.

## 5.3 Cancelling a run, and why a boolean was not enough

`cancel()` used to set `isCancelled = true` and nothing else. The in-flight
request kept running to completion, so two things were wrong.

The visible one: `isRunning` stayed `true` until the request resolved — up to
the 15 s timeout. `start` is guarded by `guard !isRunning`, so signing out and
straight back in during that window silently indexed nothing, and the grid sat
empty with no banner and no error. Nothing in the UI could explain it.

The subtle one is why the fix is not just "keep the task and cancel it".
**A cancelled `URLSessionTask` still delivers its completion handler**, with
`NSURLErrorCancelled`. If a new run had started in between, that late callback
would land in the middle of it and `stop(with: error)` would tear down the
*new* sync and show its error in the banner. A boolean cannot tell "cancelled"
from "cancelled, then restarted": `start` resets it to `false`, and the stale
callback then reads it as live.

So the engine carries a monotonic `runToken`, incremented by both `start` and
`cancel`. Every callback captures the token it was issued under and returns
immediately if it no longer matches. Three places check it — the page response,
the upsert completion, and `advance` after `onProgress` — because each is a
separate hop back to the main queue and a cancel can land in any of the gaps.

The check in `advance` matters most: it is what stops `Preferences.syncStartIndex`
from advancing for a run that no longer exists. A stale index is worse than a
stale page, since §5 makes it the resume point for the *next* run.

`cancel` also clears `isRunning` synchronously rather than waiting for the
callback, which is what makes an immediate re-login work.

Not fixed by this: a page already handed to `upsert` is written even if the
cancel arrives while it is in flight, because the write happens inside the
store. It is harmless in both real callers — `AppServices.signOut` wipes the
index *after* a network round trip, so the write lands before the wipe, and
`SyncEngine.start`'s library change is guarded by `!isRunning`.

## 5.4 Catch-up: the one request that picks up what the writer sent

The full sync is the only thing that ever wrote to the index, and it
short-circuits on `syncCompleted`. That was fine while the app could only read;
once it could *create* an item (docs/12), the only way to see one's own upload
was Settings → Resync — 39 pages and 7 710 re-upserts on an A7. `catchUp` is the
cheap alternative: one request, no banner, no timer.

**`minDateLastSaved`, not `DateCreated`.** `DateCreated` is EXIF-derived for
photos (`Emby.Photos/PhotoProvider.cs` sets
`item.DateCreated = dateTaken.ToUniversalTime()`), so a 2014 photo uploaded
today sorts into the middle of the library and a "newest first" scan would never
reach it. Ascending `DateCreated` on the live library starts at
`1970-01-01T05:00:00Z`. `minDateLastSaved` is a real server-side filter and
composes with the existing `sortBy=PremiereDate,SortName`: measured against the
server, `minDateLastSaved=2026-09-23T00:00:00.0000000Z` returned exactly 2 items
of 7 712 and a far-future value returned 0. Nothing is persisted from the
catch-up that is not already persisted by a sync page, so
`PhotoModel.schemaVersion` does not move and nobody re-syncs 20 000 rows.

**`DateLastSaved` is a filter you can send, NOT a field you can read back.**
This cost a whole first implementation. `fields=DateLastSaved` changes nothing:
the item JSON simply has no such key. Measured, the complete key set of an item
from this query is

```
BackdropImageTags, ChannelId, DateCreated, Id, ImageBlurHashes, ImageOrientation,
ImageTags, LocationType, MediaType, Name, ServerId, Type, UserData
```

so a `dateLastSaved` on `PhotoDTO` decodes to `nil` for every item, forever, and
a watermark derived from it can never move. **Do not put it back.** `sortBy=DateLastSaved`
is equally inert — it silently falls back to name order, which is what makes this
look like it works when you eyeball the first page.

**So the watermark is the server's own clock, read from the `Date` response
header** (`Date: Wed, 23 Sep 2026 20:42:11 GMT`, verified present). Server clock
rather than `Date()` on purpose: the value is compared server-side against
`DateLastSaved`, so a device clock running *ahead* would skip a window
permanently, and silently. The device clock is now read nowhere in this feature.

The committed value is the server time of the **first** page of the run, not the
last, and it is committed only once the run ends cleanly. Anything saved while
the run was in flight therefore falls inside the next run rather than between
two of them. A full sync commits it too, at `syncCompleted`, so a Resync always
repairs a bad watermark.

An install with a completed sync and no watermark seeds itself with a `limit=1`
request whose items are discarded — it is there purely to read the `Date`
header. That is one cheap request, once per install, and it is what removed the
last device-clock read.

The filter is inclusive, so every catch-up re-fetches the single newest item.
That is deliberate rather than tolerated: `upsert` is idempotent, and the
alternative — storing watermark + 1 tick — is how an item that landed on the
same tick gets lost forever.

**Paging.** One page is the normal case. It loops only while a page comes back
full, advancing `startIndex` within the *same* `minDateLastSaved`. Holding the
filter still is what makes a W4 queue landing 250 photos arrive whole; a
mid-loop failure just leaves the watermark low and the next catch-up redoes
idempotent work, which is the safe direction to fail in.

**It is silent, and shares the engine's existing discipline.** It takes
`isRunning` (so it can never race the full sync, and a duplicate call is a
no-op), bumps `runToken` and stores its `pageTask`, so `cancel()` and the
stale-callback checks of §5.3 apply unchanged. It never calls `onFinish` —
that closure drives the grid's sync banner, and a background top-up must not put
a banner on screen. It does not touch `syncStartIndex` or `syncCompleted`: it is
not a sync run. The new rows reach the UI through `store.upsert`, the FRC and the
grid's existing coalesced reload, so there is no new UI path at all.

Failures are ignored, exactly like the `libraries()` launch probe of docs/04 §6:
an unreachable server must not produce a banner, and a 401 is already handled by
`JellyfinClient.onTokenRejected`.

### Triggers, and the one that was missing

The grid fires it from `viewDidAppear`, from
`UIApplication.didBecomeActiveNotification`, and from the settings card's
`onDismissed`. The third is not decoration — **it is why the feature shipped
broken the first time.**

`CardSheetViewController.present(over:)` is child-VC containment
(`parent.addChild` + `addSubview`), not a modal presentation. The grid therefore
never disappears behind the settings card, and closing the card fires **no**
appearance callback on the grid. Combined with the seeding path returning
without a request, a fresh install that sent a photo and closed the card made
*zero* catch-up requests, forever, until the app was backgrounded. Nothing in
the UI could explain it — the same failure shape as §5.3's stuck `isRunning`.

The other two are both still needed and neither is redundant: `didBecomeActive`
does not fire when returning from the viewer, and `viewDidAppear` does not fire
on a foreground with the grid already up. Cold launch fires two of them, and the
`!isRunning` guard makes the second a no-op.

### Pull to refresh

A plain `UIRefreshControl` on the collection view, running the same catch-up
with a **48-hour lookback** subtracted from the watermark. It is the manual
escape hatch: the automatic path can only ever move forward, so without a
lookback a pull could not recover anything the watermark had already passed —
including the seeding gap on a fresh install, which is precisely the state a
user reaches for a refresh gesture in. On an install with no watermark at all
the pull seeds first and then immediately runs the looked-back page, so a pull
is never a no-op.

The spinner is the only feedback, and `SyncBannerView` is deliberately left
alone: docs/07 §4.2 gives the banner to the expired session, and a routine
refresh must not compete for that corner. A failed refresh just ends the
spinner. `cancel()` fires the pending completion as well, so a sign-out mid-pull
cannot strand it.

## 5.5 *Resync* empties the index first

`refresh(libraryId:)` used to reset only `syncStartIndex` and `syncCompleted`.
Every page being an upsert by `id` (§5), that made a resync **purely
additive**: a photo deleted on the server stayed in the grid forever, and only
signing out removed it — while the confirmation promised to "re-read all N
photos from the server". The promise and the code disagreed, and the code was
wrong.

It now calls `Preferences.clearSync()` and hands over to `start`, whose existing
`syncLibraryId != libraryId` branch already wipes the store. That is deliberate:
one reset path rather than two, and it is the path that already goes through
`PhotoStore.didResetNotification` — §5.1 explains why a live grid left fetching
a store it no longer has rows for is a crash, not a glitch.

The cost is real and is now named in the alert rather than denied by it: the
grid empties and fills back up over the length of a full sync. The alternative —
keeping rows visible and sweeping only the ones the run did not touch — needs a
per-run marker on every row, therefore a schema bump, therefore a full resync
anyway (§5.2). There is no cheap version of this.

Second half of the same defect: the last page used to write
`Preferences.syncTotal = next`, overwriting the count the **server declared**
with the count we happened to index. A short run — a page cut off, a server-side
filter, a library that shrank mid-sync — then became indistinguishable from a
complete one after the fact, and Settings displayed it as complete. The server's
total is left alone now. Nothing downstream needed the overwrite: `onProgress`
already guards with `max(syncTotal, next)`, and the "N photos indexed" line
reads `store.count()`.

## 6. Not `NSBatchInsertRequest`

The obvious fast path for 20 000 rows is `NSBatchInsertRequest`. It is iOS 13+,
so it does not exist at this floor, and it cannot express an upsert without
`NSMergePolicy` + a uniqueness constraint anyway. The fetch-then-write loop is
what is left, and at 200 rows a page the fetch is one indexed `IN` query.

## 7. Not done yet

- No deletion detection: an item removed from the server stays in the index
  until a full resync. Needs a "seen this run" marker or a total-count
  comparison.
- No incremental sync in the general sense. §5.4's catch-up covers what the
  server saves *after* the watermark, which is exactly the writer's own uploads;
  anything added to the library by other means before the watermark still needs
  a full Resync. The claim that once stood here — that Jellyfin has no "changed
  since" filter on `/Items` — was wrong: `minDateLastSaved` is one.
