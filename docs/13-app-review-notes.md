# 13. App Review notes and the demo server

Jellypic is useless without a Jellyfin server. A reviewer who opens it sees a
text field asking for an address they do not have. That is an instant 2.1
"unable to review" unless the review notes hand them a working server — this is
the single largest compliance cost of a self-hosted client, and the only one
that is not a bundle setting.

## 1. The official Jellyfin demo does not work for us

Checked 2026-09-26 by authenticating against it with Jellypic's own 10.11 header:

| | |
|---|---|
| `https://demo.jellyfin.org/stable`, user `demo`, empty password | HTTP 200, token issued |
| Server | "Stable Demo", version 12.1.0 |
| Libraries | Movies · Music · Playlists · Shows |
| Items of type `Photo` | **0** |
| Items of type `Video` in a photo library | **0** |

Four reasons it is not usable, in order of severity:

1. **No photo library at all.** Since §5.2 of doc 05 removed the fallback, the
   library step now says "No library on this server holds photos" and the button
   goes dead — correct behaviour, and a reviewer who cannot get past step 3 files
   a 2.1. Before that change it was worse: the fallback would have let them
   through onto a permanently empty grid, which reads as a broken app.
2. **No `upload-for-jelly`**, so the whole Backup section reports "Requires the
   upload plugin on your server" — an advertised feature that cannot be
   exercised.
3. **It is not ours.** Pointing review at infrastructure we do not control means
   a re-review during someone else's downtime pulls the app.

Useful thing it did tell us: a demo only needs **one photo library**. No
transcoding, no media library, no users. That is a very small machine.

## 2. What the demo server must actually be

- **One library, typed `Photos` or `Home videos`** — those are the only two
  `CollectionType`s `PhotoResolver` resolves photos in (doc 05 §5.2). If it is
  `Home videos`, `LibraryOptions.EnablePhotos` must be on, and the client cannot
  tell you if it is not: the library is listed, accepted, and indexes empty.
- **~150 photos.** Enough that the grid scrolls and the scrubber has travel,
  small enough that the first sync finishes while the reviewer is watching.
- **Capture dates spread over several months.** Month headers and the scrubber
  are most of what the grid *is*; 150 photos all dated the same afternoon makes
  the app look like a single unlabelled wall. The dates must be in EXIF —
  Jellyfin reads `DateTimeOriginal` into `PremiereDate`, and that is what we sort
  on (doc 06).
- **Some with GPS.** Without coordinates the map opens empty and looks broken.
  A handful of clusters in different places beats 150 points on one pin.
- **One or two videos**, so the duration badge, the play button and
  `PlaybackInfo` are reachable. Worth making one of them H.264 so direct play
  demonstrably works, since a "Needs converting" pill on every video invites a
  question.
- **JPEG.** HEIC needs `heic-for-jelly` on the server; do not make the demo
  depend on a second plugin to show any content at all.

Open question for whoever builds this: **is the upload plugin installed and the
library writable?** Leaving Backup unavailable is honest but shows a dead
feature. Making it writable means a publicly-credentialled endpoint that accepts
file uploads, on a server whose address is printed in App Store Connect. If it
is made writable, it wants a size cap and a periodic wipe.

## 3. The notes themselves

Placeholders in `<>` are filled once the server exists. Keep it short — review
notes are read fast.

> **Jellypic browses and backs up photos on a Jellyfin server that the user
> hosts themselves. It has no content of its own, so a demo server is provided.**
>
> Server address: `<URL>`
> Username: `<user>`
> Password: `<password>`
>
> **Getting in (about 30 seconds):**
> 1. On the first screen, type the server address **exactly as written above**
>    and tap Continue. The app tries port 8096 automatically if no port is given.
> 2. Enter the username and password, tap Continue.
> 3. Pick the library named `<library>`, tap "Use this library".
> 4. The photo grid appears and begins indexing. It is usable while it indexes.
>
> **Where the features are.** The buttons along the top of the grid fade out as
> you scroll down and come back when you scroll up.
> - **Grid** — scroll for month headers; drag the scrubber on the right edge.
> - **Viewer** — tap any photo. Pinch to zoom, drag down to dismiss, tap the ⋯
>   button for capture details and sharing.
> - **Map** — the map button at the top of the grid; photos with GPS are grouped
>   by place.
> - **Video** — the thumbnails with a duration badge play on tap.
> - **Settings** — the person button, top right of the grid: appearance, cache,
>   and the Backup section.
>
> **Photo library access.** Jellypic asks for the photo library only to *upload*
> photos to your own server, and only when you turn Backup on or tap "Send my
> latest photo" in Settings. Browsing the demo server needs no photo access at
> all, so the permission prompt can be declined and the app remains fully
> reviewable. Nothing is read from the library unless one of those two actions is
> taken.
>
> **App Transport Security.** Jellypic connects only to a Jellyfin server whose
> address the user enters at runtime. Those addresses cannot be known in advance,
> and self-hosted Jellyfin servers are commonly plain HTTP on a local network, so
> no `NSExceptionDomains` list can be authored. The app warns the user before
> sending credentials in cleartext to a non-private host.
>
> **No account creation.** Accounts are created by the server's own
> administrator, outside the app.

Two sentences carry an obligation:

- The ATS paragraph's last line is backed by `ServerURL.isPlaintextToPublicHost`
  (doc 03 §5.5). If that warning ever goes, the sentence goes with it.
- "Browsing needs no photo access" is true today because nothing on the read
  path touches `Photos`. It stops being true the moment a reader feature reads
  the library.

## 4. Not settled

- **Where the server runs.** Parked 2026-09-26. Whatever it is, it has to stay
  up for as long as the app is on the store, not just until the first approval —
  every update is re-reviewed against these same notes.
- **Whether Backup is exercisable on it** (§2).
- The demo account should be a **non-admin Jellyfin user**, so the notes cannot
  hand anyone the dashboard.
