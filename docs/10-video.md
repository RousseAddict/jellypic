# 10 — Video

Why the reader shows videos, what that costs, and what is deliberately left for later.

The work is cut in three steps. **Step 1 (this document's subject) makes videos exist
in the app: indexed, in the timeline, marked, tappable.** Step 2 asks the server what
it can play and plays the direct-play case. Step 3 accepts the server's transcode.

---

## 1. The videos were already there

Nothing had to change on the server. A Jellyfin `homevideos` library resolves video
files as `Video` items on its own — `MovieResolver.Resolve` calls
`ResolveVideos<Video>(parent, files, false, collectionType, false)` for that collection
type. The library the app already points at has been indexing them the whole time.

The only thing hiding them was ours: `includeItemTypes=Photo` in `JellyfinClient.photos`.
Step 1 is, at its core, the one-word change to `Photo,Video`.

## 2. Thumbnails are free

`VideoImageProvider` ("Screen Grabber", `MediaBrowser.Providers/MediaInfo/`) extracts a
still at 10 % of `RunTimeTicks` (or 10 s when the duration is unknown) and publishes it
as `ImageType.Primary`. A video therefore answers
`Items/{id}/Images/Primary?fillWidth=…&format=Jpg` exactly like a photo.

**So the entire image pipeline applies unchanged** — the pixel ladder, the `NSCache`,
the `URLCache`, the `?tag=` immutability, the map markers, the viewer's progressive
display. There is no video-specific image code anywhere in the app, and there must
never be: the day a video stops looking like a photo to `ImageLoader` is the day
20 000 cells get a second code path.

This is also why step 1 can open the existing viewer on a video: the still frame is a
real image at a real URL, and the Details card is a real `/Items/{id}` fetch.

## 3. Two new columns, and why not one

`PhotoDTO` gains `Type` and `RunTimeTicks`. Neither needs a `fields=` entry — both are
always serialised on `BaseItemDto`, so the query cost of step 1 is zero.

The index stores them as `isVideo: Bool` and `duration: Double` (seconds).
`duration > 0` would *almost* serve as the video flag, but a video whose `ffprobe` pass
failed has no `RunTimeTicks`, and inferring from the duration would silently route it
back into the photo path. The flag says what the item *is*; the duration says what we
happen to know about it. They are not the same fact.

**Cost: `PhotoModel.schemaVersion` 3 → 4, so the store is destroyed and all 20 000+
items resync on first launch of this build.** That is the migration strategy (docs/06
§2.2), not an accident — new columns are not in a light migration's reach when the
model is built in code, and the index is a rebuildable cache.

## 4. The date trap — the real unknown of step 1

A photo's `PremiereDate` is raw EXIF wall-clock, stored unconverted. That is the whole
reason the timeline sorts on `PremiereDate` and not `DateCreated` (docs/06 §1).

A video's `PremiereDate` does **not** come from the same place. `ProbeResultNormalizer`
reads the container tags in order — `originaldate`, `retaildate`, `retail date`,
`retail_date`, `date_released`, `date`, `creation_time` — and `FFProbeHelpers.GetDateTime`
parses them with `DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal`.
**The value is normalised to UTC.** An iPhone writes `creation_time` in UTC in the
`mvhd` atom, so that part is honest; but the photo beside it is *not* in UTC, and the
app has no way to tell the two apart after the fact.

Concretely, at UTC−4: a video shot at 21:00 on the 31st carries 01:00 on the 1st, and
`MonthKey.make` — which runs on a GMT calendar at insert time — files it under the
*next* month. It will appear in the wrong section header, and because `monthKey` is
frozen in the row, no amount of re-reading fixes it without a resync.

**This is measured, not guessed away.** Step 1 ships without a correction precisely so
the offset can be read off the device: open a video in the viewer, compare the Details
card's Date row against the same file's timestamp in Photos. If it is shifted by the
local UTC offset, the fix is a per-item normalisation at insert, and it costs a second
resync. Applying a speculative offset now would make the symptom unobservable and the
bug permanent.

**Measured on device, 2026-09-21: no visible shift.** Videos land in the right month
and the Details card's date matches. So no correction is applied, and none should be
added on theory alone. The residual is narrow and worth knowing: the offset, if it
exists at all, is only *visible* on a video shot within a few hours of midnight, since
anywhere else in the day a UTC normalisation moves the clock but not the date. If a
late-evening video ever turns up one day early, this section is the explanation.

## 5. The duration badge

Bottom-right, white monospaced digits over a 28 pt gradient scrim, `0:42` / `1:02:03`.
This is the iOS Photos convention and the user chose it over the alternatives
(a play glyph, a tinted corner).

- **A `UILabel`, not a hand-drawn glyph.** The project draws its own icons because
  SF Symbols are iOS 13 (see CLAUDE.md), but a duration is text. The one hand-drawn
  shape a video would justify — a play triangle — says strictly less than the number.
- **Monospaced digits, and a fixed 12 pt, not `Typography.caption`.** Every other font
  in the app is Dynamic-Type-scaled. This one must not be: the badge sits inside a cell
  whose side is computed from the screen width, and a user at an accessibility text size
  would have the label eat the thumbnail. Monospaced digits keep it from twitching as
  the seconds change during scrolling.
- **The scrim is a `CAGradientLayer` with its implicit animations off.** `position`,
  `bounds` and `hidden` are mapped to `NSNull()`. Without that, every reused cell
  fades its scrim in over the default 0.25 s — visible as a shimmer down a fast scroll
  on an A7.
- **Both are hidden by default and reset in `prepareForReuse`.** A cell that showed a
  video and is reused for a photo must not keep the badge; `configure` only ever turns
  it *on*, reuse turns it off.
- `configure(duration:)` takes `Double?`, where `nil` means "not a video". The call
  sites pass `photo.isVideo ? photo.duration : nil`, so the decision stays with the
  model and the cell stays dumb. A video with no known duration renders `–`.

The map's bucket sheet reuses `PhotoCell`, so it gets the badge for free — which is why
`CoreDataPhotoStore.locations` fetches the two new columns too.

## 6. What tapping a video does, in step 1

It opens the existing viewer on the still frame. Same zoom transition, same Details
card, same share and download. **Nothing plays.** This is the honest shape of step 1:
the video is *in* the library, and the app does not yet pretend to play it.

It also happens to be the verification surface for §4 — the Details card's Date row is
where the UTC shift, if any, will show.

## 7. Not done yet

- **Step 2 — `POST /Items/{id}/PlaybackInfo`** with a `DeviceProfile` in the body. The
  response's `MediaSourceInfo` carries `SupportsDirectPlay`, `SupportsDirectStream`,
  `SupportsTranscoding`, `TranscodeReasons`, `TranscodingUrl`. Direct play into an
  `AVPlayer`; say so plainly when the server answers "needs transcoding" rather than
  failing silently.
- **Step 3 — accept `TranscodingUrl`** (HLS) in the same `AVPlayer`, and close the
  session with `/Sessions/Playing/Stopped` so ffmpeg does not keep running after the
  viewer is dismissed. **This is the step that costs the server real CPU**, which is
  why it is asked for per item and never turned on by default.
- **The A7 has no HEVC hardware decode**, and iPhones have filmed HEVC by default since
  iOS 11. So on the 5s most recent videos *will* take the transcode path while the
  user's iOS 15/18 devices direct-play the same files. Both paths are mandatory; the
  test device is the pessimistic one.
- No scrubbing UI, no audio session handling, no PiP, no video in the zoom transition.
