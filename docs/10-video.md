# 10 — Video

Why the reader shows videos, what that costs, and what is deliberately left for later.

The work is cut in three steps. **Step 1 makes videos exist in the app**: indexed, in
the timeline, marked, tappable. **Step 2 asks the server what this device can play, and
plays it when the answer is "as-is".** Step 3 accepts the server's transcode.

Sections 1–6 cover step 1, section 7 covers step 2.

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

## 7. Step 2 — asking the server, and playing the direct-play case

### The profile is not optional, and silence looks like success

`POST /Items/{id}/PlaybackInfo` only tells the truth if a `DeviceProfile` reaches it.
`MediaInfoController.GetPostedPlaybackInfo` falls back to the capabilities registered
for the `DeviceId` and, finding none, leaves `profile` null — in which case
`SetDeviceSpecificData` is **never called**. The response still returns 200 with a
`MediaSources` array, and `SupportsDirectPlay` sits at its constructor default of
`true` while `TranscodingUrl` is null. A client that trusts it plays everything and
fails on the files that matter. **The profile is posted in the body, always.**

### The profile is built from a runtime probe, not written down

`VideoCapabilities.supportsHEVC` is `VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)`,
and `hevc` enters the `DirectPlayProfiles` video codec list only when it answers yes.

This is the single most important line of step 2. **The A7 in the 5s has no HEVC
decoder, and iPhones have filmed HEVC by default since iOS 11.** Hard-coding `hevc`
into the profile would make the server answer "direct play" for most recent footage,
and `AVPlayer` would show a black rectangle with no error — the exact silent failure
the whole PlaybackInfo round-trip exists to prevent, reintroduced by a constant. A
hard-coded profile without `hevc` is equally wrong in the other direction: it would
force a transcode on the iOS 15/18 devices that can play those files natively.

VideoToolbox costs nothing to reach: the `Frameworks` build phase is empty and MapKit
already works, because Swift autolinking emits the load commands. **Adding a framework
to this hand-written `project.pbxproj` was never necessary** — `import AVKit` and
`import VideoToolbox` are the whole of it.

### Why the reason shown to the user is dug out of a URL

`MediaSourceInfo.TranscodeReasons` is marked `[JsonIgnore]`. It is never serialised,
so the obvious field is not there to decode. But `StreamInfo.ToUrl` appends
`&TranscodeReasons=VideoCodecNotSupported,…` to the transcoding URL it builds, so the
server's own verdict *is* on the wire — inside `TranscodingUrl`. `MediaSourceDTO`
parses it back out with `URLComponents`.

That is worth the oddity: the alert shown when a video cannot be direct-played prints
the server's reason rather than our guess at it, which is what will say whether step 3
needs to handle one codec or five.

### One file, so the video frameworks have one door

`Viewer/VideoPlayback.swift` holds the capability probe, the profile, and the small
controller that runs the request and presents the player. It is the only file that
imports `AVKit`, `AVFoundation` or `VideoToolbox` — `grep -rn "import AVKit" jellypic/`
is the check, the same discipline as `import CoreData` (docs/06). The network layer
takes the profile as a plain `[String: Any]`, so `JellyfinClient` never learns that
VideoToolbox exists.

### Playback details that are not obvious

- **`AVPlayerViewController`, not a hand-rolled player.** Controls, scrubber, rotation
  lock, AirPlay and headphone handling all arrive free and all exist at iOS 8, so there
  is not one `#available` in the file. Drawing our own transport controls would be the
  largest piece of UI in the project, for a screen the system already ships.
- **The audio session is set to `.playback`.** The default category respects the ring/
  silent switch, so a video played with the switch on would be mute and look broken.
- **`api_key` in the stream URL, not an `Authorization` header.** `AVURLAsset` has no
  supported way to attach headers, and Jellyfin builds its own `TranscodingUrl` with
  `api_key` — the server expects it on stream URLs.
- **A re-entrancy guard, not a spinner.** `play(itemId:)` returns early while a request
  is in flight, and `onBusyChanged` dims the button so the tap does not feel dead.
  Without the guard, an impatient double-tap opens two players.

### Where the button lives, and why it ignores the chrome

A 64 pt `FloatingButton` with a hand-drawn `PlayGlyphView`, centred, **outside the
chrome's show/hide**. Chrome is hidden by default in the viewer (docs/08 §7), so a
play button that followed it would leave a video indistinguishable from a photo on
open. The triangle is nudged right by 8 % of its width: a triangle's centroid sits left
of its bounding box, so a geometrically centred one reads as off-centre.

It still has to disappear for the two animations that move the photo — the zoom
transition and the drag-to-dismiss — or it floats, unmoved, over a shrinking image.
Those set its `alpha`; `isHidden` stays reserved for "this item is not a video", so the
two concerns compose instead of fighting over one property.

## 8. Not done yet

- **Step 3 — accept `TranscodingUrl`** (HLS) in the same `AVPlayer`, and close the
  session with `/Sessions/Playing/Stopped` so ffmpeg does not keep running after the
  viewer is dismissed. **This is the step that costs the server real CPU**, which is
  why it is asked for per item and never turned on by default. The `TranscodingProfiles`
  entry is already posted, so the server already returns a usable URL — step 3 is
  mostly deciding when it is acceptable to fetch it.
- Nothing reports playback progress to the server, so Jellyfin will not show these as
  watched and the session list will not show the app as playing.
- No PiP, no background audio, no video frame in the zoom transition (it animates the
  still, then the player appears over it).
