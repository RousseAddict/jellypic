# 07 — The grid, the image pipeline, and the floating chrome

Scope: livrable 1, step L1.3. The first screen that is actually the app: a
full-bleed photo grid reading the L1.2 index, thumbnails fetched and decoded on
a budget, and every control floating on top instead of stealing rows.

## 1. The layout mandate

Ratified in chat, not derived: **square thumbnails, month headers that scroll
away, the whole screen dedicated to photos.** No navigation bar, no tab bar, no
toolbar. Actions live on floating buttons — for now a single "more" button
top-right that opens settings.

`spacing = 1` rather than 0. A hairline gutter is what separates "a grid of
photos" from "a collage"; at 1 pt it costs 2 pt of the 320 and reads as a
deliberate seam.

Cell side is `floor(available / 3)`, not `available / 3`. A fractional item size
makes the flow layout round each cell independently and the seams drift by a
pixel across the row. The few leftover points go to the right edge, where nobody
looks.

### Column count

The brief was "3 columns on an iPhone 12, 4 on the wider ones". Those two points
sit either side of a single threshold, so no breakpoint table is needed:

```
columns = max(3, round(width / 118))
```

| Device | Width | Columns | Cell |
| --- | --- | --- | --- |
| 5s / SE | 320 | 3 | 106 pt |
| SE2 / 8 | 375 | 3 | 124 pt |
| iPhone 12 | 390 | 3 | 129 pt |
| XR / Plus | 414 | 4 | 103 pt |
| Pro Max | 430 | 4 | 107 pt |
| 5s landscape | 568 | 5 | 112 pt |
| 12 landscape | 844 | 7 | 119 pt |

The invariant is not the column count, it is the **physical size of a photo**:
~105–130 pt everywhere. A thumbnail should be the same size in the hand on a 5s
and on a Pro Max; only the number that fit changes.

The floor of 3 exists because the formula alone would give 2 on a 240 pt screen
that does not exist, and because 2 columns stops reading as a grid.

### Landscape and the safe area

Landscape is supported (ratified in chat), which the full-bleed mandate makes
non-trivial: a flow layout ignores the safe area on the horizontal axis, so
cells would run under the notch. The horizontal safe-area inset is therefore
applied as `sectionInset.left/right`, and `max(left, right)` is used for both so
the grid stays symmetric instead of shifting depending on which way the phone is
turned.

Headers do **not** honour `sectionInset` — a flow-layout header always spans the
full width — so the inset is passed explicitly into `MonthHeaderView.configure`.
The tempting alternative, constraining the label to the header's own
`safeAreaLayoutGuide`, is wrong here: a view inside a scroll view has its safe
area recomputed as it scrolls through the unsafe region, which would trigger a
constraint pass per header per frame.

The floating chrome is pinned to `view.safeAreaLayoutGuide` horizontally rather
than to `view`, for the same reason.

### Non-sticky headers

`UICollectionViewFlowLayout` with `headerReferenceSize`, and
`sectionHeadersPinToVisibleBounds` left **off**. Sticky headers are an iOS 9+
one-liner, so this is a choice: a pinned header permanently occupies 44 pt of a
568 pt screen, which contradicts the mandate. The month is context, not
navigation — it matters when you cross a boundary, not while you scroll inside
one.

### Floating chrome and the content inset

The "more" button and the sync banner are siblings of the collection view, not
subviews of it — they must not scroll. The collection view gets a 56 pt
`contentInset.top` so the first row starts below them, and the same value on
`scrollIndicatorInsets` so the scrollbar does not run under the button.

Inset rather than a constraint on the collection view's top: the grid stays
full-bleed, so photos pass *under* the floating controls when scrolling, which
is the point of floating them.

## 2. The image pipeline

Three layers, `Images/ImageLoader.swift`:

| Layer | What | Size |
| --- | --- | --- |
| `URLCache` (disk) | JPEG bytes | 200 MB disk / 2 MB memory |
| `NSCache` | decoded `UIImage` | 24 MB, cost = `bytesPerRow * height` |
| — | in-flight `URLSessionTask`, owned by the cell | — |

**The server does the resizing.** `fillWidth`/`fillHeight` at the cell's pixel
size means a 24 MP original arrives as a ~212 px JPEG. Downloading originals and
scaling on device is the one decision that would make this app unusable on an
A7 — both for the network and for the 1 GB of RAM.

`quality=80`: below that the JPEG ringing is visible at thumbnail size; above it
the bytes grow with no perceptible gain.

`format=Jpg` is pinned, not negotiated. Jellyfin will happily serve WebP and
**iOS 12 cannot decode it** — the request succeeds, the data is valid, and
`UIImage` returns `nil`. This is the kind of failure that looks like a bug in
our code for a day. Carries a `// LEGACY(ios12):` marker in the source.

`cachePolicy = .returnCacheDataElseLoad` is safe *because* `?tag=` is a content
hash: a given URL can only ever return the same pixels, so there is no
invalidation problem to solve. Change the photo, change the tag, change the URL.

### The pixel ladder

The requested size is rounded **up to the next multiple of 64 px** rather than
sent exactly. The cell side is in the URL, so every distinct side is a distinct
cache entry — and with adaptive columns the side now changes on rotation. Left
exact, turning the phone would re-download every visible thumbnail.

Snapping to 64 px collapses neighbouring sizes onto one URL. A 5s asks for 256 px
in both orientations (212 and 224 px both round to 256), so it never refetches on
rotation at all. Wider devices still cross a bucket sometimes; that is the
accepted residue. `scaleAspectFill` absorbs the few surplus pixels, and asking
slightly large is the right direction to err.

### Decoding

`CGImageSourceCreateThumbnailAtIndex` with
`kCGImageSourceShouldCacheImmediately: true`, on a `.userInitiated` queue.
`UIImage(data:)` defers decompression to the first draw — which happens on the
main thread, inside the scroll loop, and is exactly the classic collection-view
stutter. ImageIO does the work on our queue instead and hands back an image
that is already a bitmap.

`kCGImageSourceCreateThumbnailWithTransform: true` bakes the EXIF orientation
into the pixels, so the cell never has to reason about it.

`httpMaximumConnectionsPerHost = 6`. Every cache miss makes the *server* resize
an image; a self-hosted Jellyfin on modest hardware is a far more fragile
resource than the phone. 6 is the browser default and a reasonable citizen.

The memory cache is dropped wholesale on
`UIApplication.didReceiveMemoryWarningNotification`. `NSCache` evicts under
pressure on its own, but not fast enough to matter at 1 GB — the warning is the
last signal before a jetsam.

### Cell reuse

`PhotoCell` cancels its task and clears its image in `prepareForReuse`, and
carries a monotonic `token`. Cancellation is not sufficient on its own: a
request that already completed and is waiting on the main queue still delivers,
into a cell that is now showing a different photo. The token is checked in the
completion; a mismatch drops the result.

Cache hits are drawn synchronously with no animation; only a network hit fades
in (0.18 s). Fading in an image we already had makes fast scrolling look like it
is loading when it is not.

## 3. Coalesced reloads

`NSFetchedResultsControllerDelegate` fires `controllerDidChangeContent` once per
200-row page. Calling `reloadData` there while the user is scrolling drops
frames and — with headers appearing — can move the content under the finger.

So a change during a drag or a deceleration sets `pendingReload` and stops.
The reload happens on `scrollViewDidEndDragging(willDecelerate: false)` or
`scrollViewDidEndDecelerating`. The user never sees a reload they did not stop
for.

Full `reloadData` rather than incremental `performBatchUpdates`: 200 inserts
that create sections is where `UICollectionView` is historically fragile, and
the animation is neither wanted nor free. `reloadData` on an idle grid only
builds the visible cells.

Sort is `monthKey` desc, `captureDate` desc, `id` desc. `id` is the same total-order
tiebreaker argument as `SortName` server-side: without it, equal-dated photos can
swap places between two fetches and cells flicker.

## 4. The sync banner

A floating pill, left of the "more" button, visible for as long as indexing runs
and showing `Indexing n of m`. Ratified in chat over the alternative
(a transient toast).

The reasoning: a first sync of a large library takes minutes, during which the
grid is visibly incomplete. A toast that disappears leaves the user looking at a
half-empty library with no explanation. The banner is the explanation, and it
removes itself when it is no longer true.

Errors reuse it: `onFinish` with an error swaps the text instead of hiding.
A failed sync is not a modal-alert situation — the grid still works with what it
has.

`UIActivityIndicatorView(style: .white)` with `color` overridden. `.medium` is
iOS 13+; setting the colour on the legacy style is the equivalent that compiles
at this floor. Marked `// LEGACY(ios12):`.

## 5. Settings as a card

Ratified in chat over a pushed screen or a full-screen modal: a card that slides
up over a dimmed grid.

There is no navigation controller to push onto — that is the cost of the
full-bleed mandate — and a full-screen modal for three read-only lines and one
button is heavy. A child view controller with a spring-animated transform is
~40 lines and dismisses on tap-outside or swipe-down, both of which are
discoverable.

The card is pinned `leading`/`trailing` to the screen and overhangs the bottom
by 32 pt, so only the two top corners are visibly rounded and no seam shows
below the home indicator area. The slide is a `CGAffineTransform` on the card,
never an animated constraint — the layout stays valid throughout and there is no
second bottom constraint to conflict with the first.

It shows library name, server URL, and index progress (`n photos indexed`, or
`n of m` while a sync is unfinished), plus **Sign out**. Read-only for now; the
theme switch lands later.

**Sign out leaves nothing behind.** `AppServices.signOut` cancels the sync first
(so no page in flight writes into a store that is about to be wiped), then in the
`POST /Sessions/Logout` completion clears the Keychain, the Core Data index, the
`NSCache` of bitmaps, the 200 MB `URLCache` on disk, and the library preferences.
The wipe is in the completion but not conditional on success — the token must be
revoked server-side if we can reach it, and the device must be clean either way,
including offline.

## 6. Not done yet

- No tap-to-open. The viewer is L1.4; cells are currently inert.
- No prefetching (`UICollectionViewDataSourcePrefetching`). Worth measuring on
  the 5s before adding — it trades scroll smoothness for concurrent load on the
  server, and the server is the weaker end.
- No scrubber / fast-scroll affordance. Designed but deferred until after the
  viewer: a right-edge rail replacing the system scroll indicator, fading out
  when idle, with a month bubble while dragging — and image loading suppressed
  for the duration of the drag, or a fast scrub over 20 000 items fires thousands
  of server-side resizes. It shares a screen and a gesture surface with the
  viewer's open transition, so it is cheaper to build once that exists.
- No pull-to-refresh; `SyncEngine.refresh(libraryId:)` exists but nothing calls
  it from the UI.
- The empty state is a single label. It does not distinguish "library is empty"
  from "sync has not started yet".
