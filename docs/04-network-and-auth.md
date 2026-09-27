# L1.1 — Jellyfin client & auth

> Date: 2026-09-17
> Covers `jellypic/Network/` and `jellypic/Auth/`. This is the rationale that would otherwise live as code comments, which this project does not allow.

---

## 1. Shape

```
Network/
├── JellyfinAPI.swift      protocol + DeviceIdentity + JellyfinCredentials
├── JellyfinClient.swift   the only implementation
├── JellyfinError.swift    typed errors, LocalizedError copy
├── JellyfinModels.swift   DTOs, explicit CodingKeys
├── JellyfinDate.swift     the .NET date parser
└── ServerURL.swift        address normalisation
Auth/
├── Keychain.swift         thin SecItem wrapper
└── AuthStore.swift        what is persisted, and what survives logout
AppServices.swift          composition root
```

`JellyfinAPI` is a protocol for the reason given in doc 02 §7: if the backend ever becomes Immich, one layer is rewritten instead of the app. `AppServices` is the only place that knows how the pieces are wired together.

---

## 2. Decisions that are not obvious from the code

### 2.1 Explicit `CodingKeys` rather than a key-decoding strategy

Jellyfin serialises PascalCase (`ServerName`, `TotalRecordCount`). The tempting fix is one `JSONDecoder.keyDecodingStrategy = .custom` that lowercases the first character, and it works — until `ImageTags`.

`ImageTags` is a **dictionary**, `{"Primary": "<content-hash>"}`, and `keyDecodingStrategy` applies to dictionary keys too. The strategy would silently rewrite it to `{"primary": ...}` and every lookup of `"Primary"` would return nil. That lands in L1.3 as "thumbnails don't load" with nothing wrong at the call site.

So: explicit `CodingKeys` on every model. More typing, no action at a distance.

### 2.2 The date parser exists because .NET dates are not ISO8601-strict

Two independent problems, both fatal to `ISO8601DateFormatter` used naively.

**Seven fractional digits.** .NET emits `2019-03-12T18:22:11.0000000Z`. `ISO8601DateFormatter` with `.withFractionalSeconds` accepts at most three and returns `nil` for seven. This is the single most common Jellyfin-client date bug.

**No timezone designator at all.** `PremiereDate` is stored server-side as a `DateTime` with `Kind == Unspecified` (doc 02 §6.1), and .NET serialises that *without* a `Z` — `2019-03-12T18:22:11.0000000`. `ISO8601DateFormatter` rejects it outright.

`JellyfinDate.normalize` handles both: it splits off whatever timezone designator is present (`Z`, `+hh:mm`, or a `-hh:mm` found *after* the `T`, so the date's own hyphens are not mistaken for a negative offset), truncates or pads the fraction to exactly three digits, and appends `Z` when no designator was present.

**Treating a naive timestamp as UTC is deliberate, not a shortcut.** `PremiereDate` is the raw EXIF wall-clock — "18:22 where the photographer stood". Parsing it as UTC and later formatting it back with a UTC calendar round-trips that wall-clock value unchanged. Parsing it as device-local would shift every photo by the phone's current offset, which is exactly the month-boundary bug doc 02 §6.1 warns about.

**Consequence for L1.2: `monthKey` must be formatted with a UTC calendar and an `en_US_POSIX` locale.** Using the device timezone there would re-introduce the shift this parser exists to avoid.

**A date that still fails to parse must not fail the page.** `normalize` covers the two known .NET shapes, but "a shape nobody predicted" stays a live possibility, and the first design threw on it. Since `PremiereDate` is decoded *inside* the `Items` array, one unreadable date failed the whole page, `SyncEngine` stopped, `Preferences.syncStartIndex` did not advance, and every later launch and every *Resync* restarted at the same offset — a single exotic photo froze the index permanently, with nothing naming the culprit (doc 06 §5.5).

A `dateDecodingStrategy` cannot fix that. The closure's return type is `Date`, so its only way to signal failure is to throw, and a throw is *not* absorbed by `decodeIfPresent` — that only returns `nil` for a missing key or an explicit JSON null. So the tolerance has to live in a type: `LenientDate` is a one-field `Decodable` that pulls the raw `String` and maps a parse failure to `nil`. The schema already models an absent date (optional `captureDate`, the `undated` bucket of doc 06 §4), so `nil` is a value the rest of the app handles. `JellyfinClient`'s custom strategy is deleted with it: `LenientDate` is the only path a date takes now, and it cannot throw.

### 2.3 The Authorization header is sanitised, and that is a safety measure

Only the `Authorization: MediaBrowser …` form is sent — never `X-Emby-Authorization` or `X-Emby-Token`, which 10.11 lets an admin disable (doc 02 §2.1).

Every injected value passes through `sanitized()`, which strips `"`, `\`, `,`, CR and LF. This is not cosmetic: jellyfin#11484 is a server bug where `AuthenticateByName` with valid credentials but a *malformed* Authorization header can wipe the server's Devices table. `UIDevice.current.name` is user-supplied ("JF's iPhone", quotes and commas included) and goes straight into a quoted header field. It gets sanitised before it can break the grammar.

An empty field after sanitising becomes `unknown` rather than `""`, so the header stays well-formed no matter what.

### 2.4 `publicSystemInfo` maps decoding failures to `notAJellyfinServer`

A typo'd address usually reaches *something* — a router page, a different service — which returns HTTP 200 and HTML. Reporting "the server answered in a format jellypic does not understand" is technically accurate and useless. On this endpoint only, a decoding failure means the address is wrong, and that is what the user is told. A missing `Version` field is treated the same way.

This check runs before the password is ever requested, so a bad URL cannot masquerade as a bad password.

### 2.5 `ServerURL` produces candidates, it does not guess schemes

Trim, strip trailing slashes, prepend `http://` when no scheme is given, and — only when no port was specified — append a second candidate on `:8096`. Non-http(s) schemes are rejected outright.

It deliberately does *not* try to be clever about https-for-public / http-for-private. The caller tries the candidates in order; a user who types `https://` gets exactly that.

### 2.6 Completions are delivered on the main queue

Decoding happens on the URLSession queue, delivery hops to main. Callers never have to remember, and the L1.3 grid cannot accidentally touch UIKit off-thread. At 1000 items per page in L1.2 the decode cost stays off the main thread, which is the part that actually matters on an A7.

### 2.7 `requestCachePolicy = .reloadIgnoringLocalCacheData`

This session is for the API, where a stale `/Items` response is a bug. The image loader in L1.3 gets its **own** `URLSession` with its own `URLCache`, which is where caching is wanted and where doc 02 §5's budgets apply. Two sessions, two policies, no shared surprises.

---

## 3. What `AuthStore` persists — and the logout rule

| Key | Holds | Survives `clear()` |
|---|---|---|
| `deviceId` | UUID, generated once | **yes** |
| `serverURL` | normalised base URL | no |
| `accessToken` | Jellyfin token | no |
| `userId` | Jellyfin user id | no |
| `serverId` | Jellyfin server id | no |
| `username` | Jellyfin account name | no |

All in the Keychain with `kSecAttrAccessibleAfterFirstUnlock`.

`username` exists only so the re-auth card (§6) can ask for a password and
nothing else. It is the name the *server* returned (`AuthenticationResult.user.name`),
not what was typed, so it round-trips whatever casing Jellyfin considers canonical.

**`deviceId` surviving `clear()` is the point of the whole design.** Keychain items outlive app deletion on iOS, so a reinstall, a logout, or a restore all keep the same identity and the server's device list shows one jellypic rather than one per install. This is also why it is not `identifierForVendor`, which changes when the last app from a vendor is removed. Doc 01 §7 sets the same rule for the writer.

**Keychain writes are checked, not hoped for.** `Keychain.set` returns the raw
`OSStatus`, `AuthStore.save` returns the first failure, and
`ConnectViewController` refuses to advance to the library step when the token
could not be persisted — it shows the code instead. Discarding those statuses
was how a missing entitlements blob (doc 03 §5.1) turned into a silent bounce
back to the first connect step: the sign-in and the library list both worked
because the token was in memory, and only the router noticed that
`authStore.credentials` read back `nil`.

Two writes used to escape that check. **`deviceId` is written from
`AuthStore.init`**, where there is no screen to report to and nothing has been
attempted yet; its status is stored and folded into `save()`'s return instead, so
it surfaces at the one moment a failure matters and a human is watching. And
**`serverId` was written with its status dropped**, which made the *one* optional
key the only unverified one. `save` now appends it to the same list, or removes
the stale key when the server did not send an id — leaving a previous server's id
behind was the alternative.

`AppServices.signIn` acts on that return value rather than beside it: the
in-memory `client.credentials` is now assigned **after** the status is checked,
so a failed write leaves the app signed out in memory as well as on disk. It used
to assign first and return the status afterwards, which produced the one state
nothing handles — a session that works perfectly until the process dies.

**The destructive half of `signIn` moved after the same check.** Signing in as a
different user resets the store, empties the image caches and forgets the library;
that block used to run *before* `save`, so the very failure the previous paragraph
is about — the `-34018` that already bit this project once — deleted 20 000 rows
and then returned an error, leaving the user on the old account with an empty
index and no explanation. Writing first and destroying only on success means the
worst case is an error message and an unchanged app. The `previous` session is
still read at the top of the function, before `save` overwrites it, which is what
makes the reordering possible at all.

Only the token is rolled back. `save` calls `clearToken()` when any of its writes
failed, so a half-written sign-in cannot leave a secret in the Keychain that no
code path will ever delete — but `clear()` would take `serverURL` and `userId`
with it, and those are exactly what §6.4 needs to keep the cached index
browsable. A server and a user without a token is a state the app already knows
by another name: an expired session, with the re-auth card as its exit.

`username` and `serverId` are read back through `nonEmpty(_:)`. A Keychain hit
that returns an empty string is not a value, and the one caller that cares —
the re-auth card, §6.3 — branches on `session.username == nil` to decide whether
to ask for a name. An empty string would have passed that test and produced a
card that demands a password for an account it cannot name.

`accessToken` is only half-revoked by `clear()`. `AppServices.signOut` calls `POST /Sessions/Logout` **first** and wipes local state in the completion regardless of the outcome — order matters, because wiping first would strand a live token that can no longer be revoked. The token surviving a failed network call is the lesser evil; it at least remains revocable from the Jellyfin admin UI.

---

## 3.1 Reads are checked too

Everything above is about writes. The read side collapsed *absent* and
*unreadable* into the same `nil`, which is the same mistake by the other end:
`SecItemCopyMatching` returning `errSecInteractionNotAllowed` or the `-34018` of
doc 03 §5.1 was indistinguishable from a key that was never written.

`Keychain.read(_:)` returns `KeychainRead` — `.found(Data)` / `.absent` /
`.failed(OSStatus)` — and `data(for:)` / `string(for:)` are written on top of it,
so every existing caller is unchanged. Only the two decisions that cannot survive
the ambiguity read the enum.

**`AuthStore.init` no longer mints a new `deviceId` on a read failure.** It used
to fall into the `else` branch of `if let existing = keychain.string(…)`, so a
transient failure rotated the device identity — the one value the whole design
keeps stable across reinstalls (§3 above), and the one carried in every
`Authorization` header. The server would have shown a second jellypic and
orphaned the session entry of the first. A failure now yields an in-memory UUID
for this launch only and records the status; `.absent` is still the one case that
writes.

**`AppServices.signIn` treats an unreadable previous session as a different
account.** The audit predicted a spurious wipe; the code did the opposite. The
guard was `if let previous = previous, previous.userId != …`, so a `nil` from an
unreadable Keychain meant **no** wipe — account A's 20 000 rows would have
survived under account B, which is a privacy defect, not a performance one. The
decision is now `authStore.isSessionUnreadable || (previous userId differs)`,
computed before `save` overwrites the keys, exactly like `previous` itself.
Resyncing a cache that is reconstructible by definition is the cheap side of that
trade.

What is deliberately *not* done here is telling the user. A refusing Keychain
still presents itself as a first launch or as an account switch, and saying so is
a wording decision, which is a chat decision.

---

## 4. Info.plist additions

- ~~`NSAppTransportSecurity` / `NSAllowsLocalNetworking`~~ — **superseded, see doc 05 §6.1.** The reasoning was that a LAN-only exemption is the tight, correct one. It is too tight for a server whose address the user types, and the key silently cancels `NSAllowsArbitraryLoads` when both are present. The plist now carries `NSAllowsArbitraryLoads` alone.
- `NSLocalNetworkUsageDescription` — required from iOS 14 to reach `192.168.x.x` at all. Irrelevant on the iOS 12 target device, but the app is meant to run on the iOS 15/18 phones too, and a missing string there is a hard failure rather than a prompt.

---

## 5. Not done yet

- **No verification against a live server.** The layer compiles and is exercised by nothing. Every entry point needs a UI to be driven from, and UI is a separate conversation (doc 02 §8.4). The Connect screen is the first real test of §2.4 and §2.5.
- **Library selection is not persisted.** `libraries()` returns every view with `holdsPhotos` available for filtering; deciding and storing the choice belongs with the picker screen.
- ~~**No token revalidation on launch.**~~ — **done, see §6.**

---

## 6. Session expiry: the index must survive it

Doc 02 §3 asks for a relaunch that goes straight to the timeline and revalidates
in the background. The hard part is not the probe, it is what happens when the
probe fails.

### 6.1 Why a dead token could not simply sign you out

Before this, the only route out of a rejected token was Settings → Sign out, and
`AppServices.signOut` wipes the Core Data index, the 200 MB `URLCache`, the
`NSCache` and the library preferences. On a 20 000-item library that is a
multi-minute resync and a lot of heat on an A7 — an unreasonable price for a
token that expired while the photos on disk are still perfectly valid.

Worse, nothing *said* the token was dead. `SyncEngine.start` short-circuits on
`Preferences.syncCompleted`, so a fully indexed install makes no request at all
until a thumbnail misses the cache; the first visible symptom was the viewer
showing *"Wrong username or password"* — `.unauthorized`'s text, written for the
connect screen.

### 6.2 Three seams, none of them destructive

- **`JellyfinClient.onTokenRejected`** fires when a 401 comes back from a request
  that actually **carried** a token. The discriminator is the `Token="` field in
  the `Authorization` header: `authenticate` builds its request with `token: nil`,
  so a wrong password can never be mistaken for a rejected session. The hook is
  wired into `perform` only, **not** `performIgnoringBody` — that one is used
  exclusively by `logout`, and its completion is dispatched *after* the hook, so
  a 401 there would raise "session expired" in the middle of a sign-out. The two
  methods that build their own tasks instead of going through `perform` —
  `originalFileSize`'s ranged GET and `downloadOriginal`'s handoff to
  `FileDownloader` — call the hook by hand. They are the whole of the share
  flow, and a share is exactly when a user is most likely to discover the token
  died: the details card would otherwise report a raw HTTP status and leave the
  grid convinced it was still signed in.
- **`AppServices.expireSession`** cancels the sync, calls `authStore.clearToken()`
  — which removes the `accessToken` key and **nothing else** — and posts
  `sessionExpiredNotification`. The distinction `AuthStore` already drew between
  `session` (server + user + name, no token) and `credentials` (token required)
  is what makes this expressible: the app stays signed in, it just cannot talk.
  `RootViewController.isSignedIn` therefore tests `hasSession`, not `credentials`,
  and keeps showing the grid.
- **`AppServices.revalidateSession`** is the probe. It is `libraries()`,
  i.e. `GET /UserViews` — the cheapest authenticated call, and it answers both
  "is the token alive" and "does that library still exist". It **ignores its own
  result**: the reaction is entirely `onTokenRejected`, so an unreachable server
  is a natural no-op. That matters, because the app is usable offline — index
  plus cached thumbnails — and only a real 401 may expire anything.

**The probe runs on `UIApplication.didBecomeActiveNotification`, not once at
launch.** `RootViewController` registers the observer in `viewDidLoad`, which
returns before `didFinishLaunchingWithOptions` does, so the first activation is
still covered — cold launch behaves exactly as before. What changes is the phone
that is never actually relaunched: iOS keeps a suspended app alive for days, and
a token revoked from the admin UI on Monday would otherwise stay undetected
until something happened to miss the cache. A `guard isSignedIn` keeps it off the
connect flow, where there is no token to probe.

`ImageLoader` **is** a detector, through `onUnauthorized`. The worry that kept it
out — a scroll over 20 000 cells is 20 000 chances to fire the hook — is answered
by `expireSession` being idempotent (it returns early once `isSessionExpired`),
and by what expiry does to the requests themselves: see §6.4. In exchange, the
case that actually happens on this app is covered. A fully indexed install makes
no API call at all between activations; the thumbnails are the only traffic, so
they were the only thing that could notice.

### 6.3 Why the banner, and why only a password

The grid already owns a floating pill for sync progress, so expiry reuses it:
spinner off, *"Session expired — tap to sign in"*, and it outranks any sync text
(`showBanner` returns early while expired). A modal on launch would have been the
loud option, but the app is still fully usable — browsing cached photos does not
need the server, and interrupting that to demand a password is the wrong trade.

Tapping it opens `ReauthViewController`, a `CardSheetViewController` over the
live grid — deliberately *over* it, so the photos stay visible behind the card
and the "nothing is lost" claim is visible rather than promised. It is not a
fourth step in `ConnectViewController`: that file's morphing three-step card is
the most delicate layout in the app, and re-auth needs none of it.

The card asks for a password alone, since the server, user id and username are
all still in the Keychain. The username field is built but hidden, and appears
only when `session.username` is nil — which is exactly what an install that
predates the `username` key looks like, and, thanks to `nonEmpty(_:)` in §3, also
what a blank stored name looks like.

It also appears **when the account check below rejects the sign-in**. That branch
marks the username field invalid and prints "that is a different account", which
on a card where the field is hidden is an accusation about something the user
cannot see — the only editable control is the password. Revealing the field first
turns the error into an instruction.

**The account is checked before the save.** `signIn` wipes the index when the
user id changes, which is right for a genuine account switch and catastrophic
here, so `completeSignIn` refuses an `AuthenticationResult` whose `user.id` is
not the stored one and says so. Typing the wrong username into a re-auth card
must not silently cost 20 000 rows.

On success the card dismisses, the grid clears the banner, reloads the visible
thumbnails (their requests returned nil while the token was gone) and calls
`startSync()` again — which resumes from `Preferences.syncStartIndex` if the
sync had been cancelled mid-run, or finishes immediately if it was already
complete.

### 6.4 The cached thumbnails have to stay reachable

§6.2 promises the app is "usable offline — index plus cached thumbnails". Until
now the second half was false. `imageRequest(…)` starts with
`guard let credentials = credentials`, and `clearToken()` makes that nil — so an
expired session returned no request at all, every cell drew empty, and the grid
behind the re-auth card was a wall of placeholders arguing the opposite of what
the card claims.

The fix rests on one fact: **`URLCache`'s key is the URL and the method. Request
headers, `Authorization` included, do not enter it.** A request built without a
token therefore reaches exactly the same 200 MB of disk entries the signed-in one
wrote. So the two image builders were reduced to a query and a shared
`primaryImageRequest(…)`, which takes the base URL from `credentials` **or** from
`cachedImageBaseURL` — a field `AppServices` keeps in step with the Keychain, set
on launch and on `signIn`, cleared on `signOut`, and deliberately *not* cleared by
`expireSession`. The token becomes `credentials?.accessToken`, i.e. nil when
expired.

The cache policy carries the rest: `.returnCacheDataElseLoad` normally,
**`.returnCacheDataDontLoad` when there is no token.** A tokenless request never
touches the network, so it can neither hand the server an unauthenticated GET nor
produce a 401 — which is also why `ImageLoader.reportIfUnauthorized` needs no
`Token="` discriminator, unlike its `JellyfinClient` counterpart. It is the same
property that caps the "20 000 chances" of §6.2: once expired, the thumbnails
stop reaching the network entirely, so at most one scroll's worth of in-flight
requests can report the 401 that caused the expiry.

### 6.5 A 403 is not an expired session

Three places decided independently what "the server rejected our token" meant,
and they disagreed. `ImageLoader.reportIfUnauthorized` and
`JellyfinClient.failure(response:error:)` both read `401 || 403`;
`FileDownloader` read only 401.

The 403 is the defect. Jellyfin answers **401 when authentication fails and 403
when an authenticated user lacks the right** — that is the difference between
`CustomAuthenticationHandler` failing and an `[Authorize(Policy…)]` refusing.
Calling the second one an expiry produces a loop with no exit: revalidate,
expire, show the re-auth card, sign in successfully, hit the same 403, expire
again. The card cannot fix a permission, so it can only be shown forever.

The predicate now exists once, as `HTTPStatus.rejectsToken` in
`JellyfinError.swift`, and it is `== 401`. A 403 falls through to
`.httpStatus(403)`, which at least says what happened. One named function for a
one-line test is worth it here precisely because the drift *is* the bug — six
call sites each deciding for themselves is how the three detectors stopped
agreeing.

The writer's `UploadClient` carried the same `401 || 403` three times. There a
403 means the Jellyfin account may not write to the target, so it is not a
per-photo rejection worth retrying: it maps to `.stopQueue("FORBIDDEN")`,
beside 409's `TARGET_NOT_WRITABLE`, and the queue halts with a reason instead of
grinding through the whole roll.

One claim in the audit was already stale: a 401 on the original-file download
*does* reach `onTokenRejected`, because `downloadOriginal` calls
`reportIfTokenRejected` on its own completion rather than relying on `perform`.

### 6.6 Screens that read `credentials` when they mean `session`

The two accessors are not interchangeable and the distinction is the entire
mechanism of §6.2: `credentials` requires `accessToken`, and `expireSession`
removes exactly that key. Anything an expired session is still supposed to
display must therefore read `session`.

Settings read `authStore.credentials?.baseURL` for its server row, so opening
Settings while expired showed a blank address — in the one state where the
address is the only thing that explains what is going on, and one tap away from
the Sign out button. `session?.baseURL` survives `clearToken()` because that is
what it was written for.

The general rule, cheap to apply: **`credentials` is for making a request,
`session` is for describing one.**
