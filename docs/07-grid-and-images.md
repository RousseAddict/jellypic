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

Its contents and internal structure are doc 09.

**Sign out leaves nothing behind.** `AppServices.signOut` cancels the sync first
(so no page in flight writes into a store that is about to be wiped), then in the
`POST /Sessions/Logout` completion clears the Keychain, the Core Data index, the
`NSCache` of bitmaps, the 200 MB `URLCache` on disk, and the library preferences.
The wipe is in the completion but not conditional on success — the token must be
revoked server-side if we can reach it, and the device must be clean either way,
including offline.

## 6. The month scrubber

`MonthScrubberView` is a draggable thumb on the right edge with a month bubble.
Ratified in chat over an always-visible rail and over a bubble-only variant
riding the system indicator: at 320 pt a permanent bar is a tax on every screen,
and the system indicator is too thin to catch with a thumb.

**There is exactly one indicator.** The first version drew a track behind the
thumb and left the system scroll indicator visible, which meant three vertical
marks in the same 12 pt of screen. `showsVerticalScrollIndicator = false` on the
collection view and the track deleted — the thumb *is* the scroll indicator now,
so anything else in that column is a duplicate. `scrollIndicatorInsets` went with
it; there is no indicator left to inset.

**The thumb is a handle, not a pill.** Removing the track was not enough: a bare
10 × 56 capsule still read as decoration, because nothing about it said "grab
me". It carries three dots down the middle — a `HandleGlyphView`, the same
`CAShapeLayer` glyph as the grid's ⋯ button turned to the vertical axis, so the
two three-dot controls in the app are visibly one family. Width is the point: at
10 pt the dots do not fit at all.

**Final size is 20 × 44**, after a 26 × 56 pass the user called too big. 20 pt of
width leaves 8 pt either side of the 4 pt glyph, which is the least that still
reads as a margin rather than as dots touching the rounded edge; 44 pt of height
is Apple's minimum touch target, so the handle is as small as it can be while
staying both legible and grabbable. Shrinking it costs nothing in usability
because the *grabbable* area is not the handle — see below.

The drag feedback is a uniform `scale 1.1`. The narrow version used `scaleX: 1.6`
to fatten a thin bar on grab, which on a dotted handle would stretch the dots
into ellipses.

**It clears the ⋯ button.** The handle and the button share the right-hand
column, and the scrubber's travel used to start at `chromeInset` (56), the same
inset the collection view uses — which left exactly 4 pt between the bottom of
the 44 pt button and the top of the handle at the top of the list. They read as
one crowded stack. The scrubber now starts at its own `scrubberInset` of 72,
giving 20 pt of air. The content inset stays at 56: the grid should still begin
under the chrome, it is only the *travel* that starts lower. The handle is then
no longer pixel-aligned with the top of the content, which is invisible in use —
the mapping stays proportional over the travel it has.

**It does not steal touches from the grid.** The view is 40 pt wide so the thumb
is grabbable, which would otherwise swallow every tap in the right-hand column.
`point(inside:with:)` is overridden to accept only touches landing within the
thumb's frame inset by 14 pt — and to reject everything while the thumb is faded
out, so an invisible control is never also an invisible obstacle. The inset is
what absorbs the shrink: 20 × 44 plus 14 pt on every side is a 48 × 72 target,
so the handle got smaller and the thing you actually hit did not.

**Fading is driven by scroll events, not by a timer per frame.** `reveal()` shows
the thumb and cancels any pending fade; `scheduleFade()` arms the 1.5 s timer and
is called only from `scrollViewDidEndDecelerating` and from
`scrollViewDidEndDragging` when there is no deceleration to wait for. Arming the
timer inside `scrollViewDidScroll` instead would allocate and invalidate a
`Timer` on every frame of every scroll, on an A7.

**The mapping is proportional to content height, not per-section.** A scrubber
anchored on section boundaries sounds more correct and behaves worse: months
hold wildly different counts, so the thumb would crawl through a heavy month and
teleport through a light one. Proportional mapping is what the system indicator
does and what the finger expects.

**The bubble label is read back from reality, not predicted.** After
`setContentOffset`, the grid asks for the lowest section among
`indexPathsForVisibleItems` and formats that month key. Computing which section
covers a given `y` would mean interrogating the layout for 20 000 items;
reading the visible cells is O(visible) and cannot disagree with what is on
screen. The template is `MMMyyyy`, not the header's `MMMMyyyy` — "September 2026"
makes the bubble wider than the thumb has room for.

**Image loading is suspended for the duration of the drag.** `ImageLoader`
gained an `isSuspended` flag, checked after the memory-cache lookup: a cache hit
still resolves, a miss returns `nil` without starting a task. A fast scrub across
the whole library otherwise queues thousands of requests, each of which makes the
*server* resize an image nobody will see. On release the grid reloads the visible
index paths inside `performWithoutAnimation`, which re-runs `configure` and lets
the loads it skipped start for real.

## 7. Not done yet

- No prefetching (`UICollectionViewDataSourcePrefetching`). Worth measuring on
  the 5s before adding — it trades scroll smoothness for concurrent load on the
  server, and the server is the weaker end.
- No pull-to-refresh. Resync is a Settings row (doc 09) rather than a gesture,
  because a full re-page is too expensive to trigger by accident.
- The empty state is a single label. It does not distinguish "library is empty"
  from "sync has not started yet".
