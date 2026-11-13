# Privacy policy

Jellypic · effective 12 November 2026

**In short:** Jellypic sends nothing to its developer. Your photos, your server address and
your credentials go to the Jellyfin server you sign in to, and nowhere else. The only
other connections are the map screen, which loads its maps from Apple, and this policy,
which opens from GitHub.

## Who is responsible

Jellypic is an independent app made by one person, not a company. It is not made or
endorsed by the Jellyfin project. Questions about this policy go to the address under
[Contact](#contact).

## What the developer collects

Nothing. Jellypic has no account of its own, no analytics, no advertising, no tracking and
no third-party code. The developer runs no server and never receives your photos, your
server's address, your username or your password.

If you have chosen in iOS Settings to share analytics with app developers, or if you test
the app through TestFlight, Apple may pass crash reports and the feedback you send on to
the developer. Apple's privacy policy covers that, not this one.

## What goes to your Jellyfin server

Jellypic only works with a Jellyfin server, run by you or by whoever gave you an account.
That server receives:

- **When you sign in:** your username and password, sent once to open a session. The
  password is never stored.
- **With every request:** the app's name and version, a random identifier the app creates
  for your iPhone, and your iPhone's name as set in Settings › General › About. Jellyfin
  shows these in its list of devices.
- **When you browse:** requests for the library's contents, thumbnails, photos and videos.
- **When backup is on:** the photos themselves, as original files with all the information
  they carry — including where a photo was taken, if it records that — and a fingerprint
  of each photo (SHA-256) so it is never sent twice.
- **When you delete a photo:** a request to delete that photo.
- **When you sign out:** a request to end the session.

What the server does with this is up to whoever runs it. Jellypic allows plain HTTP so it
can reach a server on your home network; over plain HTTP, traffic is not encrypted. Use an
`https://` address for a server reached over the internet.

## Apple Maps and GitHub

The map screen uses Apple's MapKit. To draw it, your iPhone downloads map images from Apple
for the area you are looking at, under Apple's privacy policy. The photos' locations are
placed on the map on your iPhone and are not sent to Apple.

*Privacy policy* in Settings opens this page from GitHub, in Safari inside the app, under
GitHub's privacy policy. Nothing is loaded from GitHub unless you tap it.

## What stays on your iPhone

- **In the Keychain:** your server's address, your username, the session, and the device
  identifier.
- **In the app's own storage:** an index of your library (dates, sizes and, for photos that
  have one, their location), cached thumbnails and photos, the backup queue, and your
  settings.

None of it leaves your iPhone except as described above.

## Permissions

- **Photos (full access):** asked only when you turn backup on or open the photo picker, and
  used only to back photos up. If you allow only selected photos, Jellypic respects that
  and backup becomes manual only.
- **Photos (add only):** asked by iOS if you choose *Save Image* when sharing a photo.
- **Local network:** to reach a Jellyfin server on your network.

Jellypic does not use your location, camera, microphone or contacts. Browsing does not need
access to your photos.

## Sharing

When you share a photo, it goes where you choose in the iOS share sheet. Jellypic hands
the photo over and has no part in what happens next.

## Deleting your data

**Signing out** tells the server to end the session, then erases from your iPhone the
session, the index, the cached photos and the backup queue. The device identifier is kept,
so the server recognises the same iPhone when you sign back in.

**Deleting the app** removes its storage. iOS can keep an app's Keychain entries after the
app is deleted; signing out first removes the session from them.

Photos already backed up stay on your server. Delete them there, or from Jellypic if your
Jellyfin account is allowed to delete.

## Children

Jellypic is not aimed at children, and it collects nothing from anyone.

## Changes

Any change to this policy is published in this file, with its new effective date. Earlier
versions remain in the repository's history.

## Contact

Open an issue at <https://github.com/RousseAddict/jellypic/issues>.
