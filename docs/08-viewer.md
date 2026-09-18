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

The three-dot button opens a card built exactly like the settings card — child view
controller, dimming, swipe-down — with the metadata as key/value rows and a
**Share** button at the bottom. Ratified in chat over an action sheet: the details
are the common case and deserve one tap, and the action sheet's system look does
not belong next to the rest of the design system.

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
byte count is simply not in the item JSON. It comes from a `HEAD` on
`/Items/{id}/File` read off `Content-Length`, fired in parallel with the metadata
fetch; the card re-renders when it lands. Without it the share picker would be
asking the user to choose the original sight unseen.

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

`UIActivityViewController` cannot swap its payload once open, so "share the
derivative now and upgrade in the background" is not a real option — hence the
explicit choice up front.

Both the picker and the activity sheet set `popoverPresentationController.sourceView`:
`TARGETED_DEVICE_FAMILY` is `1,2`, and an unanchored action sheet is a crash on iPad.

## 9. Not done yet

- No prefetch of the neighbouring full-size images. Swiping is a thumbnail for a
  beat, then sharp. Worth measuring before spending memory on it.
- No zoom-aware resolution: zooming past 2× shows the 2048 px image magnified
  rather than requesting a sharper crop.
- No delete or favourite — both out of livrable 1.
- The details card shows coordinates as decimal degrees, with no map and no reverse
  geocoding. MapKit would be the first non-trivial framework in the app.
- The original download has no progress indication beyond the button's spinner,
  and no way to cancel from the UI.
- Rotation keeps the right photo and re-fits it, but the zoom level is reset rather
  than carried across, and the chrome has not been laid out for a landscape 5s.
