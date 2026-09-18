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
The fix is a manual resync (`refresh(libraryId:)` restarts from 0 without
wiping), not a more clever cursor — Jellyfin has no opaque pagination token.

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

## 6. Not `NSBatchInsertRequest`

The obvious fast path for 20 000 rows is `NSBatchInsertRequest`. It is iOS 13+,
so it does not exist at this floor, and it cannot express an upsert without
`NSMergePolicy` + a uniqueness constraint anyway. The fetch-then-write loop is
what is left, and at 200 rows a page the fetch is one indexed `IN` query.

## 7. Not done yet

- No deletion detection: an item removed from the server stays in the index
  until a full resync. Needs a "seen this run" marker or a total-count
  comparison.
- No incremental sync. A refresh re-walks everything. Jellyfin has no
  "changed since" filter on `/Items`, so the cheap version would be to trust
  `TotalRecordCount` and only re-walk when it moves.
