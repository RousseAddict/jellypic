# 19. The demo server, as code

`demo-server/` builds the App Review server that `13-app-review-notes.md` asks for,
from a blank Debian to a signed-in grid, with one command. This file is the *why*;
`demo-server/deploy.sh` documents its own usage inline, like `build.sh`.

| | |
|---|---|
| Address | `https://demo.rousseaddict.online` — A and AAAA records, Let's Encrypt certificate |
| Machine | OVH VPS, Debian 13 (trixie), 2 vCPU, 3.7 GB RAM, 40 GB disk, IPv4 + IPv6 |
| Jellyfin | **12.4**, from Jellyfin's apt repository, pinned and held |
| Plugins | HEIC for Jelly 1.1.0.0 and Upload for Jelly 0.2.1.0, installed **from their published catalogues** |
| Library | `Photos`, typed `homevideos` with photos enabled: 99 photos and 2 videos |
| Accounts | `admin` (cannot sign in from the internet), `demo` (the one the review notes hand over) |

## 1. Running it

```sh
cd demo-server
./deploy.sh                    # everything; safe to re-run, a second run changes nothing
./deploy.sh --tags seed        # one phase: base, jellyfin, configure, seed, caddy
./deploy.sh --check --diff     # dry run
```

Two gitignored files carry every credential, the same rule as `.env.local` for
`build.sh`:

- `demo-server/.env.local` — `DEMO_PASS`, the ssh password (and optionally
  `DEMO_HOST`). Leave it unset once the VPS takes an ssh key.
- `demo-server/secrets.local.yml` — the Jellyfin admin and demo passwords. The
  template is `secrets.example.yml`. The demo password is the one pasted into App
  Store Connect.

The admin dashboard is reachable only from the VPS itself:
`ssh -L 8096:127.0.0.1:8096 debian@demo.rousseaddict.online`, then
`http://localhost:8096`.

## 2. Why Ansible, and why it runs on the VPS

Installing Jellyfin is the easy half. The rest — the setup wizard, plugin
repositories, plugin installs, the library, two accounts and their policies, the
upload plugin's allowlist — is configuration that lives in Jellyfin's database and
is only reachable through its REST API. Ansible's `uri` module turns each of those
into a read-then-write step that only writes when the state differs, so one tool
covers the OS and the application, and a re-run is a no-op (measured: `changed=0`).

- **Builtin modules only.** No Galaxy collection, no pip: the same rule as "no
  third-party actions" in CI. The firewall is a templated `nftables.conf` rather
  than the community `ufw` module.
- **The controller is the target.** `deploy.sh` ships the folder over ssh and runs
  `ansible-playbook -c local` on the VPS with Debian's own `ansible-core`. The Mac
  needs ssh and tar, nothing else — its Homebrew Python is newer than any
  ansible-core supports.
- **`--no-install-recommends`, or ten minutes lost.** `ansible-core` recommends
  Debian's `ansible` package: thousands of community collections, byte-compiled at
  install. On this VPS that took over ten minutes, for code the playbook never
  loads. The bootstrap installs `ansible-core` alone.
- **`sshpass -f`, not `-e`.** Two of six `-e` connections in a row reached sshd with
  an empty password — the journal shows them rejected before PAM ran — while `-f`
  never failed. `deploy.sh` writes the password to a 0600 temp file; `-p` stays out
  because it puts the password in `ps`.
- **ssh keepalives.** The first seed build is minutes without output, and an idle
  session was dropped mid-build ("Broken pipe"), killing the playbook between the
  build and the rsync. `ServerAliveInterval=30` keeps the session alive.
- **Idempotent means no write at all.** The seed builder rewrites its state file
  only when it differs: a rewrite bumps the seed folder's mtime, `rsync -a` carries
  it to the library, and every deploy would report a change and rescan.

## 3. Order is a security property

`site.yml` runs: base (firewall) → Jellyfin → configuration → seed → Caddy.

- **The firewall goes up before Jellyfin is installed.** Until its wizard is
  completed, Jellyfin hands the admin account to whoever reaches it first:
  `FirstTimeSetupHandler` (v12.4) succeeds for any caller while
  `IsStartupWizardCompleted` is false, with no network check. A fresh install
  listens on `0.0.0.0:8096`. The nftables policy is drop, with only 22, 80 and 443
  open (and udp 443 for HTTP/3), so that window is closed from outside.
- **Caddy goes up last**, because Caddy is what exposes Jellyfin; by then the wizard
  is closed and the accounts are in shape.

## 4. Jellyfin facts the playbook depends on

All read in the v12.4 sources, then measured on this server.

- **`KnownProxies` is what makes the internet remote.** Without it, Jellyfin ignores
  `X-Forwarded-For`, every request through Caddy arrives from `127.0.0.1`, and
  `HttpContext.IsLocal()` calls it local — so the admin's "no remote access" policy
  would silently do nothing. With `KnownProxies: ["127.0.0.1"]`, an admin sign-in
  from the internet answers **403** (measured), while an ssh tunnel, which sends no
  forwarded header, still counts as local. Caddy sets `X-Forwarded-For` from the
  connection and discards any the client sends, so it cannot be spoofed to
  `127.0.0.1`.
- **`LoginAttemptsBeforeLockout: -1` means never.** `UpdatePolicyAsync` maps -1 to
  null (no lockout) and 0 to 3. The demo account is set to -1: with lockout on,
  anyone who guesses the user name `demo` could disable the reviewer's account with
  three wrong passwords. Its password is therefore long — 16 random lowercase
  letters, typeable on a phone keyboard.
- **A library cannot be created typed `photos`.** `CollectionTypeOptions`, the enum
  `POST /Library/VirtualFolders` binds, is `movies, tvshows, music, musicvideos,
  homevideos, boxsets, books, mixed`. An unknown value is dropped and the library is
  created *untyped* — which the app lists, accepts, and indexes empty, since
  `PhotoResolver` resolves photos only under `photos` or `homevideos` + `EnablePhotos`
  (doc 05 §5.2). The dashboard's "Home Videos and Photos" is `homevideos`, and so is
  the demo library.
- **A library's type lives in two places, and only one of them counts.**
  `/Library/VirtualFolders` reports the `<type>.collection` file on disk. Resolution
  uses the type stored on the library's item, which `SpecialFolderResolver` sets
  when it first creates that item; afterwards `Folder` keeps the existing item for
  the same id, and `UpdateFromResolvedItem` copies `IsInMixedFolder` and nothing
  else. The id derives from the library's name, so a library deleted and recreated
  under the same name gets the old item back, **old type included**, unless the
  delete was sent with `refreshLibrary=true` — the only variant that runs the
  top-level validation, which drops the item, before answering. Measured the hard
  way: the first replacement used `false`; the dashboard and `VirtualFolders` said
  `homevideos`, the scan indexed the two videos as `Movie` and not one photo, and
  the demo account saw an empty library. The playbook now reads the type from the
  item itself (`GET /Items?ids=`), replaces on either mismatch, and asserts the
  resolved type afterwards.
- **Creating a library can take longer than 30 s** on two cores while startup tasks
  run, which is `uri`'s default timeout: `AddVirtualFolder` always awaits a
  top-level validation, whatever `refreshLibrary` says. It gets 300 s. It is created
  with `refreshLibrary=true`: on a first deploy the scan finds an empty folder, and
  when a library is replaced, it indexes the files already there, which the seed
  phase's rsync would not otherwise report as changed.
- **A video's first thumbnail attempt times out, harmlessly.** On this VPS both
  videos logged "I-frame image extraction failed, will attempt standard way" after
  10 s; the standard way succeeded, and both have a `Primary` image (measured).
- **Startup lies twice before it answers.** First a 503, then for a while a 200 whose
  body is not the real one. Only the real `/System/Info/Public` carries
  `StartupWizardCompleted`, so that is what the wait checks. First boot took 3 min
  22 s of migrations.
- **`POST /Repositories` replaces the whole list**, so the playbook sends back
  Jellyfin's own catalogue with the two plugin manifests appended.
- **A catalogue install is integrity-checked.** `InstallationManager` refuses a zip
  whose MD5 differs from the manifest's `checksum`.
- **Binding to loopback works.** `LocalNetworkAddresses: ["127.0.0.1"]` makes
  Kestrel listen on `127.0.0.1` only (measured with `ss`), behind the firewall that
  already blocks 8096.

## 5. What is trusted, and how it is checked

| Component | Source | Check |
|---|---|---|
| Debian packages (nftables, caddy, ansible-core, exiftool, rsync) | Debian archive | apt signatures |
| Jellyfin | `repo.jellyfin.org`, pinned `12.4+deb13` | repo key pinned by sha256 in `vars.yml`; the key served on 2026-11-23 is byte-identical to the copy Debian ships in `extrepo-offline-data` (1.0.6~deb13u1), an independent, Debian-signed source |
| The two plugins | their GitHub catalogues | Jellyfin's MD5 check against the manifest |
| Seed photos and videos | Wikimedia Commons originals | the sha1 Commons publishes, pinned in `seed/library.yml` |

Jellyfin's own install script fetches its key from the same host it trusts, so it
could not serve as the second source; Debian's copy could.

## 6. The library

`seed/library.yml` is the library's source of truth; `build-seed.py` turns it into
files on the VPS.

- **Content.** 99 photos and 2 videos by the US National Park Service, public domain
  as federal works (`PD-USGov-NPS`). Chosen by hand from Commons for looking like a
  camera roll: landscapes, wildlife, trails — no maps, ceremonies, roadworks, or
  scanned slides with black borders. Keyword searches for CC0 city photos were tried
  first and gave mostly museum statues and police vans.
- **An invented year.** Twelve parks become trips from January to October 2026, so
  the grid has seven month sections and the scrubber has travel. Times are spread
  through each day, deterministically. Coordinates are the Commons ones where the
  file has them, otherwise the park's centre with a fixed per-file offset, so the
  map shows clusters across the US, Alaska included.
- **Photos** are rotated upright by hand (ffmpeg runs with `-noautorotate`, so no
  orientation is applied twice), scaled to 3024 px on the long edge — the originals
  run to 6000 px, and a two-core server resizes every first thumbnail request —
  and given `DateTimeOriginal`, GPS and an NPS credit by exiftool.
- **Videos.** Baring Falls (Glacier) is HEVC, as an iPhone records; Upper Falls of
  the Yellowstone is H.264, so direct play is demonstrable on any device (doc 13 §2).
  Their `creation_time` is UTC, as an iPhone writes it — which is why their
  `PremiereDate` is UTC while a photo's is wall-clock (doc 10).
- **Downloads go through curl over HTTP/2.** From this VPS, `upload.wikimedia.org`
  answers every HTTP/1.1 request with 429 "Too many requests" and serves HTTP/2
  ones — measured side by side: `curl` 200 over h2, `curl --http1.1` 429, Python's
  `urllib` (HTTP/1.1 only) 429 with `Retry-After: 120`, for ten minutes of retries.
  The same requests from a residential address all succeed, which is why the
  thumbnails fetched while curating gave no hint. The builder shells out to curl,
  waits 2 s between originals, and caches them by sha1, so only the first build
  downloads. Ansible's `get_url` is urllib too, which is why it is not used here.
  The manifest's URLs carry no `utm_` suffix: Commons appends one to every
  `imageinfo` URL.
- **The library is the seed, exactly.** Each deploy `rsync --delete`s the seed over
  the library and rescans: whatever a reviewer uploaded is gone. Upload for Jelly's
  staging directory, `.upload-for-jelly/`, is left alone; the plugin recreates it per
  upload.

## 7. Not done yet

- **ssh still accepts passwords**, and the password is reused. In the first 40
  minutes of this VPS's life its journal logged 180 failed password attempts from
  bots, mostly against `root` and `ubuntu`. Installing a key and turning password
  authentication off is deferred to the user; `deploy.sh` switches to key auth by
  itself when `DEMO_PASS` is unset.
- **No nightly reset.** The library is public and writable, so it should go back to
  the seed on a timer, not only on deploy.
- **No size cap** on the library volume. The plugin answers 507 on a full disk, but
  the disk is the VPS's root.
- **Not yet opened in the app.** Verified over the API as `demo`, from the
  internet: view `Photos` typed `homevideos`, 99 `Photo` + 2 `Video`, seven months,
  every item dated, with a `Primary` image, and GPS on every photo. A sign-in from
  the app on a device has not been done.
