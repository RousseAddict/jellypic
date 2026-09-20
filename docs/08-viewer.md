# 08 — The viewer: paging, zoom, and the transition

Scope: livrable 1, step L1.4. Opening a photo from the grid, swiping between
photos, zooming, and getting back out.

## 1. Container

A horizontally paged `UICollectionView` reading the **same**
`NSFetchedResultsController` instance as the grid. One cell per photo, recycled.

Not `UIPageViewController`: it holds a view controller per page and expects you
to hand it neighbours on demand, which is an awkward fit for a 20 000-row FRC and
gives up cell reuse for nothing.

Sharing the FRC rather than building a second one matters: a second controller
would mean a second fetch, a second copy of the section metadata, and two orders
that could disagree. The viewer only ever reads it.

### The gap between photos

Photos are separated by 20 pt of background — without it, dragging one photo
brings the next one flush against it and the two read as one image.

The naive way to get that gap is `minimumLineSpacing`, but paging snaps to
multiples of the *collection view's* width, so any spacing desynchronises the
pages from the items. Instead the collection view is made 20 pt **wider than the
screen** and offset by −10, `itemSize` equals its full width, and each cell insets
its own scroll view by 10 pt per side. Paging stays exactly one item wide, and
the gap is inside the cell where it costs nothing.

### Surviving a rotation

Paging stores position as a `contentOffset`, not as an index. Rotate, and the
offset that used to be page 40 is measured in the old width — the view lands
between two photos, and because `scrollViewDidScroll` fires during the rotation's
layout pass, `updateCurrentIndexPath` then commits whichever neighbour happens to
be under the midpoint. The photo changes under the user.

So the layout pass is gated on the size *actually changing* (`laidOutSize`) rather
than on a one-shot "did I scroll to the start" flag, and when it does change it
re-centres `currentIndexPath` explicitly. `isAdjustingLayout` suppresses
`updateCurrentIndexPath` for the whole rotation — set in
`viewWillTransition(to:with:)`, cleared in the coordinator's completion, because
UIKit keeps nudging the offset after our own synchronous re-centre returns.

`currentIndexPath` is the single source of truth across a rotation; the offset is
derived from it, never the other way round.

`isAdjustingLayout` is saved and restored around the layout pass, not set to
`true` then back to `false`. `viewDidLayoutSubviews` runs *inside* the rotation,
after `viewWillTransition` raised the flag and before the coordinator's completion
lowers it, so an unconditional `= false` handed the rotation back its own bug: the
window between the layout pass and the end of the animation was unguarded, and the
first `scrollViewDidScroll` in it committed a neighbour. The date pill, the details
card and Share then all followed the wrong photo. A flag that two callers raise for
overlapping spans has to be restored, not cleared — the alternative is a counter,
which is more machinery than two nesting levels deserve.

### Surviving the timeline changing underneath

The viewer reads the grid's fetched-results controller live, and that controller
keeps moving: a sync page lands every few seconds, and a sign-out or a schema
wipe empties it outright. `UICollectionView` was never told. It had been asked
for its item count once, at present time, and kept answering questions about
index paths that no longer meant anything — `photo(at:)` goes straight to
`controller.object(at:)`, which traps on an out-of-range path rather than
returning nil. Opening the last photo of an "Undated" section and letting a sync
page insert a month above it was a crash, not a glitch.

Two halves to the fix.

**The reads are made total.** `PhotoTimeline` gains a default-implemented
`photoIfPresent(at:)` that bounds-checks the section and the item before calling
`photo(at:)`, and the viewer uses it everywhere — the date pill, the details
card. A protocol extension rather than a change to `photo(at:)` itself: the grid
asks for index paths `UICollectionView` just handed it, and making the common
path optional would push a `guard` into every cell.

**The position is re-resolved by id, not by index.** The viewer keeps
`currentPhotoId` alongside `currentIndexPath`, updated wherever the pill is. On a
change it looks the id back up through `indexPath(forPhotoId:)` — a `fetchLimit`
1 predicate fetch plus `NSFetchedResultsController.indexPath(forObject:)`, which
is what makes this affordable at 20 000 rows against a linear scan of
`fetchedObjects` — then reloads and re-centres on the answer. The photo on screen
stays the photo on screen even though its index moved. If the id is gone from the
index entirely, the viewer dismisses: that is the sign-out case, and the
alternative is a full-screen view of something that no longer exists.

The reload is **deferred while the finger is down**, the same bargain the grid
makes (doc 07 §5): `timelineDidChange` sets `pendingTimelineChange`, and the work
happens either immediately or from `scrollViewDidEndDragging` /
`scrollViewDidEndDecelerating`. A `reloadData` mid-swipe kills the swipe. It runs
inside `isAdjustingLayout` for the same reason the rotation does — the
`scrollToItem` that follows would otherwise let `scrollViewDidScroll` commit a
neighbour.

The grid holds the viewer `weak` and pokes it from both `onChange` and `onReset`.
The viewer does not subscribe to the timeline itself: those two closures already
belong to the grid, and a second subscriber would have to be handed ownership of
callbacks it does not own.

## 2. Zoom

Each cell is a `UIScrollView` with the image view as its `viewForZooming`,
`minimumZoomScale = 1`, `maximumZoomScale = 4`, double-tap to 2.5× at the tapped
point.

The image view is sized to the **fitted rect** (aspect-fit computed by hand) and
the scroll view's `contentSize` matches it, rather than leaving the image view at
cell size with `.scaleAspectFit`. The lazy version is two lines shorter and lets
you pan into the empty letterbox bars once zoomed, which looks broken. Centring
when the content is smaller than the viewport is done with `contentInset`,
recomputed in `scrollViewDidZoom`.

`layoutSubviews` only re-runs the fit when the scroll view's size actually
changed, otherwise every layout pass would reset the user's zoom.

## 3. Progressive display

`configure` puts the **already-cached grid thumbnail** into the image view
synchronously, then requests the full-size image. The thumbnail is
stretched and soft for a few hundred milliseconds, then swapped.

This is what makes the open feel instant on a home network, and it is also what
gives the transition something to animate — the zoom animator needs a real image
at the moment the gesture happens, not one that arrives 300 ms later.

If the user has already zoomed by the time the full image lands, the swap skips
the re-fit: the aspect ratio is identical, so the picture just gets sharper in
place instead of jumping back to 1×.

## 4. Resolution and memory

`maxPixels = min(longestScreenSideInPixels * 2, 2048)`.

On the 5s that is 2048 px (the screen's long side is 1136 px), which decodes to
roughly 2048×1536 → **~12.6 MB** as a bitmap. `maxWidth`/`maxHeight` are used
rather than `fillWidth`/`fillHeight` because the viewer fits, it does not crop —
`fill` would silently trim the edges of every photo.

`quality=90` rather than the grid's 80: compression artefacts that are invisible
on a 106 pt thumbnail are obvious at full screen and worse under zoom.

**Full-size images live in their own `NSCache`, not the thumbnail one.** Three
full-size bitmaps would evict the entire 24 MB thumbnail cache, and the user
would come back from the viewer to a grid of grey squares. The full-size cache is
capped at 3 entries (current, previous, next) and is dropped entirely on a memory
warning.

This is the first number to lower if the 5s struggles — the whole reason it is
the primary target.

### Emptying it when the viewer closes

Three entries at ~12.6 MB is ~37 MB held for a screen that no longer exists — a
third of what the 5s gives a foreground app. So `PhotoViewerViewController.deinit`
calls `ImageLoader.releaseFullSize()`.

**`deinit`, not `viewDidDisappear`.** At the iOS 12 floor a presented view
controller is full-screen by default, so the share sheet and every alert raised
from the details card fire `viewDidDisappear` on the viewer — the cache would be
dumped in the middle of a share, and the photo behind the sheet would have to be
re-fetched on the way back. `deinit` says the one thing that is actually meant
here: this viewer is gone.

Keeping the last-viewed photo alive by lowering `countLimit` to 1 on close was
considered and dropped. `NSCache`'s limits are advisory — it is not required to
evict on the spot — so the saving would have been unpredictable, and re-opening
the same photo is a `URLCache` disk hit and a decode, not a round trip to the
server.

## 5. The transition

Ratified in chat over a cross-fade: the thumbnail grows out of its cell into the
full-screen photo, and settles back into its cell on the way out.

`ZoomTransition` is a plain `UIViewControllerAnimatedTransitioning` used for both
directions. Both sides implement one small protocol:

```swift
protocol ZoomTransitionEndpoint: AnyObject {
    func zoomTransitionImage() -> UIImage?
    func zoomTransitionRect(in container: UIView) -> CGRect?
    func zoomTransitionSetHidden(_ hidden: Bool)
}
```

The animator hides both endpoints' content, flies a single temporary
`UIImageView` between the two rects, and fades the viewer's view. One image view
moving is cheap even on an A7 — there is no snapshotting and no layout during the
animation.

`contentMode = .scaleAspectFill` on the travelling view is what makes it read as
a morph rather than a stretch: the grid cell is a square crop, the destination
rect has the photo's own aspect ratio, so at the end of the animation aspect-fill
and aspect-fit coincide exactly and the crop has *opened up* rather than the
image having been squashed.

Either endpoint returning `nil` (no image loaded, cell off-screen) degrades to a
cross-fade instead of failing.

**Reduce Motion takes that same exit.** `UIAccessibility.isReduceMotionEnabled` is
the first clause of the `guard` that computes the two endpoints, so the setting
costs one condition rather than a second code path — the graceful degradation was
already written and tested for the off-screen case. A zoom that flies a photo
across the screen is exactly the class of animation the setting exists to suppress,
and the cross-fade keeps the same duration, so the viewer still arrives when it
used to. The property is back-annotated `@available(iOS 8.0, *)`, so it is free at
the 12.0 floor.

`modalPresentationStyle = .overFullScreen`, not `.fullScreen`: the latter removes
the presenting view once the transition ends, and the grid must stay on screen
underneath for the dismissal to have something to land on.

### Returning to a photo you swiped to

If you open photo 40 and swipe to photo 900, the cell to land in is not on
screen — and probably never was. Before the dismiss animator runs, the viewer
hands its current index path back to the grid, which scrolls it into view
(non-animated) and forces a layout so the cell exists and has a frame.

## 6. Dismissing by dragging

Swiping down moves and shrinks the photo with the finger and fades the
background; past ~16% of the screen height, or on a fast flick, it dismisses.

This is done by hand — transforming the collection view and setting the backdrop
alpha directly — rather than with `UIViewControllerInteractiveTransitioning`.
The interactive-transition API is built around a 0–1 completion percentage, which
does not express "the photo is wherever the finger left it"; driving the views
directly does, and the dismiss animator then picks up from the current on-screen
rect because `zoomTransitionRect` is computed with `convert(_:to:)`, which already
accounts for the transform.

The gesture is on the viewer's root view with a delegate that only lets it begin
when the current cell is **not** zoomed and the drag is dominantly downward —
otherwise it would steal panning from a zoomed photo and fight the horizontal
paging. `shouldRecognizeSimultaneouslyWith` returns true so the scroll view's own
recogniser does not block it, and horizontal scrolling is switched off for the
duration of the drag.

### The bug where it died after one swipe

Reported on device: dragging down worked on the photo you opened, and stopped
working the moment you swiped to another one. The gesture was innocent. The
delegate resolves "the current cell" through `currentIndexPath`, and
`updateCurrentIndexPath` was asking the layout about the wrong point:

```swift
let point = CGPoint(x: collectionView.contentOffset.x + collectionView.bounds.midX, …)
```

On a `UIScrollView`, `bounds.origin` **is** `contentOffset` — that is how
scrolling is implemented — so `bounds.midX` already means "the middle of what you
are looking at, in content coordinates". Adding `contentOffset.x` to it counts the
scroll position twice. On the first photo the offset is 0, the error is 0, and
everything looks correct; one page later the query lands a page and a half too far
right. `indexPathForItem(at:)` then returns a cell that is not on screen, so
`cellForItem` returns `nil`, so `gestureRecognizerShouldBegin` bails on its
`guard let cell = currentCell` and the drag never starts again.

The same stale index path fed the date pill and the details card, so both were
showing the wrong photo after a swipe — one arithmetic error with three symptoms,
two of which nobody had noticed. Fixed by asking for `bounds.midX` alone.

## 7. Chrome

Ratified in chat: nothing over the photo by default, a tap reveals the chrome,
another tap hides it. Consistent with the grid's mandate, and it is what Photos
does. The chrome is a close cross on the left, the capture date in the middle, and
the same three-dot button as the grid on the right.

The backdrop is hard-coded `.black`, not `Theme.palette.background`. A photo is
judged against black; a light-grey surround shifts its perceived contrast and
white balance, which is why every photo viewer ever written is black regardless of
the surrounding app's theme. The cards presented *over* the viewer still follow the
palette — it is the photo's immediate surround that is fixed, not the whole screen.

The date is `dMMMyyyy` ("3 Sept 2025"), not the full weekday-and-month form. The
pill sits between the two buttons, and a long date was winning the compression
fight against the more button's 44 pt intrinsic width and shrinking it. The format
change fixes the common case; `dateLabel`'s horizontal compression resistance is
also dropped to `.defaultLow` so that in a locale with a longer date the pill
truncates instead of eating the button.

The pill and both buttons reuse the existing floating vocabulary (squircle, shadow,
no blur). `FloatingButton` was generalised for this: it used to hardcode the
three-dot glyph, and now takes a `GlyphView` subclass, so the close cross is a path
in code like everything else — no SF Symbols at this floor.

The status bar is hidden for the whole viewer
(`modalPresentationCapturesStatusBarAppearance` is needed for that to take effect
under `.overFullScreen`).

## 8. Details and share

The three-dot button opens a `CardSheetViewController` — the same base class as the
settings card, carrying the dimming, the slide-up, the gestures, the close button
and the portrait/landscape sizing (`docs/05` §4.1) — with the metadata as key/value
rows and a **Share** button at the bottom. Ratified in chat over an action sheet:
the details are the common case and deserve one tap, and the action sheet's system
look does not belong next to the rest of the design system.

Title in the base class's header (via `setHeaderView`), rows appended to `body`,
and **Share as a 44×44 accessory next to the X** (ratified in chat). The old cap
on the scroll view (half the view height) is gone — it was what let the card
overflow the screen in landscape in the first place, leaving a 38 pt strip of
backdrop as the only way out.

**Share moved out of the footer.** It was a 52 pt full-width accent `ActionButton`,
which cost about 76 pt of card with its spacing — a quarter of the sheet on a 5s
in landscape, spent on one verb. As a header icon the footer disappears entirely
and that space becomes metadata rows, which are the reason the card exists.

The trade is legibility: an icon has to be read rather than spelled out. The
arrow-out-of-a-tray glyph is the one iOS convention strong enough to carry that,
which is why it is drawn as such (`ShareGlyphView`) rather than as a download
arrow — the sheet it opens also offers Mail, AirDrop and Save Image, so "share"
is the honest label, not "download". An icon *with* the word next to it was
considered and dropped: it squeezes the title, and the same header shape has to
work for the settings card, where the library name already fills the row.

The download state stays one control in one slot: `shareButton` hides,
`cancelButton` (a filled square, `StopGlyphView`) takes its place, and `footer`
un-hides to carry the byte counter and the track. The footer is hidden the rest
of the time, so it costs no height at all — this is the only card that uses it.

While the card is up, `gestureRecognizerShouldBegin` refuses the viewer's dismiss
pan. Without that, dragging the card downwards also drags the photo out from
behind it.

### Where the metadata comes from

Not from the index. `PhotoItem` stores six columns; adding a dozen EXIF fields
would bloat 20 000+ rows and force a full resync for data that is read on a handful
of photos. The card fetches `GET /Items/{id}?userId=…` on open.

Verified in Jellyfin v10.11.0 source rather than assumed:

- `DtoService.SetPhotoProperties` is called unconditionally for any `Photo`
  (`DtoService.cs:1341`), so **no `fields=` parameter is needed** for the camera,
  EXIF and GPS values. `Path` and `Container` do need it, and
  `UserLibraryController.GetItem` already passes `new DtoOptions()` — all fields.
- `RefreshItemOnDemandIfNeeded` returns immediately for anything that is not a
  `Person`, so the call has no hidden metadata-refresh cost.
- `/Users/{userId}/Items/{itemId}` is marked `[Obsolete]`; `/Items/{itemId}` with
  `userId` as a query parameter is the current form.

Both requests hand back their `URLSessionTask` — the pattern `photos` and
`downloadOriginal` already use — and `deinit` cancels them alongside the download.
Closing the card used to leave them running: two requests per open, and the
file-size probe is a `Range: bytes=0-0` on `/Items/{id}/File`, so the server opens
the original to answer it. Flicking the card open and shut on a phone is cheap;
making the server do it repeatedly is not.

### When the fetch fails

`fetch` used to drop the `.failure` on the floor, so an unreachable server left the
card reading "Loading…" until it was closed — a spinner with no end, which is the
one thing worse than an error. The result is now kept in `detailsError` beside
`details`, and `render` falls back to `detailsError?.shortDescription` in the same
single row the placeholder used. No retry button: the card is one tap to close and
one tap to reopen, which *is* the retry, and a button would need its own state in a
view whose whole job is to display someone else's.

The file-size probe is deliberately not wired to that: it fails silently and the
Share button stays enabled, because downloading the original is a different request
that may well succeed when the metadata one did not.

### Aperture and shutter speed are APEX, not what they look like

`PhotoProvider.cs` reads the raw EXIF entries:

```csharp
ExifEntryTag.ApertureValue     -> item.Aperture       // APEX Av
ExifEntryTag.ShutterSpeedValue -> item.ShutterSpeed   // APEX Tv
image.ImageTag.ExposureTime    -> item.ExposureTime   // real seconds
```

An iPhone at ƒ/1.6 reports `Aperture = 1.356`. Printing that as "ƒ/1.36" would be
wrong and quietly plausible, which is worse. The f-number is `2^(Av/2)`; for the
shutter, `ExposureTime` is preferred because it is already in seconds, with
`1 / 2^Tv` as the fallback when it is absent.

Empty rows are omitted rather than shown blank, so a photo with no EXIF displays
just the file name and the date.

### File size needs a second request

**`BaseItemDto` has no `Size` field** and photos carry no `MediaSources`, so the
byte count is simply not in the item JSON. A second request has to ask for it,
fired in parallel with the metadata fetch; the card re-renders when it lands.
Without it the share picker would be asking the user to choose the original sight
unseen.

The obvious request is a `HEAD` on `/Items/{id}/File` read off `Content-Length`.
That is what shipped first, and **it silently returned nothing** — the Size row
stayed blank, and nobody noticed until the user asked for a feature that was
already written. The route is declared `[HttpGet("Items/{itemId}/File")]` in
`LibraryController.cs` and nothing else, and ASP.NET Core endpoint routing has no
HEAD→GET fallback: `HttpMethodDictionaryPolicyJumpTable.GetDestination` is a plain
dictionary lookup on `Request.Method`. A `HEAD` to a GET-only route is a 405, a
405 carries no `Content-Length` for the file, the parse yields `nil`, and the row
is omitted. Nothing is ever surfaced as an error, which is why it read as "the
row does not exist" rather than "the request failed".

The fix is a **ranged GET**. Jellyfin serves the file with
`PhysicalFile(item.Path, mime, true)` — that third argument is
`enableRangeProcessing` — so `Range: bytes=0-0` comes back 206 with
`Content-Range: bytes 0-0/<total>`. One byte over the wire for the real number,
on a verb the route actually answers. `totalBytes(from:)` parses the tail of
`Content-Range` and falls back to `expectedContentLength` if a server ignores the
range and answers 200 with the whole file.

Reading that header is a two-line detour at the iOS 12 floor:
`HTTPURLResponse.value(forHTTPHeaderField:)` is iOS 13+, so `header(_:in:)` walks
`allHeaderFields` with a `caseInsensitiveCompare`. Header names are
case-insensitive and `allHeaderFields` does not normalise them, so the comparison
has to be too.

### Choosing what gets shared

Ratified in chat: rather than picking one, the Share button asks.

- **Optimised photo** — the 2048 px `UIImage` already decoded for the viewer.
  Instant, no network. It is a server-side re-encode, so the EXIF is gone.
- **Original file** — downloaded from `/Items/{id}/File` to `NSTemporaryDirectory()`
  under its real name, shared as a file URL, and deleted in the activity
  controller's completion handler.

`/File` rather than `/Download`: the latter is gated on `Policies.Download` plus
`item.CanDownload(user)`, and writes a server activity-log entry per download.
`/File` is `[Authorize]` only and returns the same bytes.

**"Its real name" is server-supplied, so it is sanitised twice.** `Path` comes
back from Jellyfin verbatim, and `appendingPathComponent` resolves `..` — a
`Path` ending in `../../Library/Preferences/x.plist` would have written outside
the temporary directory. `lastPathComponent` alone is not enough either: it is
total, so it answers `""` for an empty string and `".."` for `".."`, and both
make `appendingPathComponent` return the directory itself, which then fails to
write with an error about a name nobody typed.

So `PhotoDetailsDTO.fileName` rejects rather than repairs — empty, `.`, `..`, or
anything still containing a separator returns nil, and the share sheet falls back
to the `Name` field or, failing that, offers only the optimised photo. A name
that cannot be trusted is not a name. `FileDownloader.temporaryDestination`
repeats the check on the way in regardless: it is the function that actually
builds the path, and it is one `lastPathComponent` plus a three-way comparison,
which is cheaper than a rule that the only caller must remember.

`UIActivityViewController` cannot swap its payload once open, so "share the
derivative now and upgrade in the background" is not a real option — hence the
explicit choice up front.

Both the picker and the activity sheet set `popoverPresentationController.sourceView`:
`TARGETED_DEVICE_FAMILY` is `1,2`, and an unanchored action sheet is a crash on iPad.

**"Save Image" needs `NSPhotoLibraryAddUsageDescription`.** Without it the app is
terminated the moment the activity runs — not an error, not a denied permission,
a kill. It is the one activity in the sheet that touches a privacy-gated
framework, which is why the other rows (Mail, AirDrop, Files) worked and this one
did not: those are out-of-process extensions, `UIActivityTypeSaveToCameraRoll`
calls `PHPhotoLibrary` inside our process. The *Add* key is deliberate — write-only
access — rather than `NSPhotoLibraryUsageDescription`, which would also ask for
read permission the app has no use for.

### Progress and cancellation on the original

A 10 MB original over a home uplink is long enough that a spinner alone reads as a
hang. The card grows a footer with a byte counter and a filled track, and the
header's share icon becomes a stop square for the duration — one slot, two states,
rather than a second control that is dead most of the time.

The download moved out of the shared `JellyfinClient` session into
`FileDownloader`, a `URLSession` with a `URLSessionDownloadDelegate` and
`delegateQueue: .main`. The alternative — KVO on `URLSessionTask.progress` — was
rejected: that property is documented for the delegate-style task, and its
behaviour alongside a completion handler at the iOS 12 floor is not something to
bet the UI on. The delegate gives `didWriteData` directly.

The denominator is free: the ranged GET fired for the file size already returned
the total, so the bar starts with a real one instead of growing
indefinitely. When the total is unknown the counter still shows bytes received and
the bar stays empty.

`didCompleteWithError` swallows `NSURLErrorCancelled` and returns silently. A
cancel is a user action, not a failure, and surfacing an error alert after the user
asked to stop would be noise.

The progress box is an `isHidden`-toggled arranged subview of a vertical
`UIStackView` that also holds the button, so showing and hiding it collapses the
layout on its own — no height constraint to animate.

## 9. Not done yet

- No prefetch of the neighbouring full-size images. Swiping is a thumbnail for a
  beat, then sharp. Worth measuring before spending memory on it.
- No zoom-aware resolution: zooming past 2× shows the 2048 px image magnified
  rather than requesting a sharper crop.
- No delete or favourite — both out of livrable 1.
- The details card shows coordinates as decimal degrees, with no map and no reverse
  geocoding. MapKit would be the first non-trivial framework in the app.
- Rotation keeps the right photo and re-fits it, but the zoom level is reset rather
  than carried across, and the chrome has not been laid out for a landscape 5s.
