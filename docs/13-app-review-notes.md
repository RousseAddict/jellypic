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
- **An account that never expires.** App Store Connect's sign-in field says the demo
  account *"must not expire"*, and every update is re-reviewed with the same one.

Open question for whoever builds this: **is the upload plugin installed and the
library writable?** Leaving Backup unavailable is honest but shows a dead
feature. Making it writable means a publicly-credentialled endpoint that accepts
file uploads, on a server whose address is printed in App Store Connect. If it
is made writable, it wants a size cap and a periodic wipe.

## 3. The notes themselves

Placeholders in `<>` are filled once the server exists. Keep it short — review
notes are read fast — but specific: since 2026-10-16, guideline 2.3.1(a) says
*"generic descriptions will be rejected"*, which is why the walkthrough names every
feature and where to find it. Brought up to date with the app on 2026-11-13.

**Give a host name.** A private LAN address cannot be reached from Apple at all. A
public IPv4 address would work: on Apple's IPv6-only review network, `URLSession`
synthesises an IPv6 address from an IPv4 literal (guideline 2.5.5,
`18-app-store-submission.md` §4 — corrected 2026-11-13, this paragraph used to say it
could not). But a name survives a server move, is what an https certificate needs,
and with an AAAA record keeps NAT64 out of the path altogether. Plain `http://` with a
name reaches the server too.

**`https://` is recommended, not required.** Over plain HTTP to a host outside the
local network, the sign-in step shows a red warning under its subtitle — "Your
password will travel unencrypted" (`ServerURL.isPlaintextToPublicHost`). It blocks
nothing, but the reviewer would watch the app warn about its own demo, and a public
demo on HTTP weakens the ATS paragraph below, which argues that plain HTTP is a
local-network matter. Once there is a name, a free certificate costs little:
a reverse proxy such as Caddy in front of Jellyfin obtains one by itself.

> **Jellypic browses and backs up photos on a Jellyfin server that the user
> hosts themselves. It has no content of its own, so a demo server is provided.**
>
> Server address: `<host name, https:// recommended>`
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
> **Where the features are.**
> - **Grid** — scroll for month headers; while scrolling, a scrubber appears on
>   the right edge and can be dragged.
> - **Viewer** — tap any photo. Pinch to zoom, drag down to dismiss, tap the
>   photo to hide or show the buttons. The ⋯ button opens the capture details,
>   with sharing.
> - **Map** — the map button at the top of the grid; photos with GPS are grouped
>   by place.
> - **Video** — the thumbnails with a duration badge are videos: open one and tap
>   the play button.
> - **Settings** — the person button at the top of the grid: Backup, appearance,
>   storage, account, and the privacy policy under About.
> - **Backup** — needs the Upload for Jelly plugin on the server, which is
>   `<installed / not installed>` on this demo server. `<If installed: set Backup
>   to Manual in Settings, then tap + on the grid to choose photos.>`
> - **Delete** — offered only to accounts the server allows to delete. The demo
>   account `<can / cannot>`; Settings › Account says which.
>
> **Photo library access.** Jellypic asks for the photo library only to *upload*
> photos to your own server, and only when you open the photo picker (the +
> button, shown once Backup is set to Manual or Automatic) or accept the "Back up
> everything?" offer. Browsing the demo server needs no photo access at all, so
> the permission prompt can be declined and the app remains fully reviewable.
> Nothing is read from the library unless one of those two actions is taken.
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
- The walkthrough names buttons and labels as they are on 2026-11-13. Re-read it
  against the app before every submission: two of its sentences had gone stale
  within two months (a "Send my latest photo" button that no longer exists, and
  grid buttons that no longer fade on scroll).

## 4. Not settled

- **Where the server runs.** Parked 2026-09-26. Whatever it is, it has to stay
  up for as long as the app is on the store, not just until the first approval —
  every update is re-reviewed against these same notes.
- **Whether Backup is exercisable on it** (§2).
- The demo account should be a **non-admin Jellyfin user**, so the notes cannot
  hand anyone the dashboard.
- **Whether the demo account may delete.** Recommended: no. Every reviewer who
  tries the trash button would shrink the demo library for the next one, and
  Settings › Account already says plainly that deleting is off for that account.
- **A name and an AAAA record for the server**, decided before it is built: the
  name is what §3 hands over, and the AAAA record keeps the review independent of
  NAT64 altogether.
