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

All in the Keychain with `kSecAttrAccessibleAfterFirstUnlock`.

**`deviceId` surviving `clear()` is the point of the whole design.** Keychain items outlive app deletion on iOS, so a reinstall, a logout, or a restore all keep the same identity and the server's device list shows one jellypic rather than one per install. This is also why it is not `identifierForVendor`, which changes when the last app from a vendor is removed. Doc 01 §7 sets the same rule for the writer.

**Keychain writes are checked, not hoped for.** `Keychain.set` returns the raw
`OSStatus`, `AuthStore.save` returns the first failure, and
`ConnectViewController` refuses to advance to the library step when the token
could not be persisted — it shows the code instead. Discarding those statuses
was how a missing entitlements blob (doc 03 §5.1) turned into a silent bounce
back to the first connect step: the sign-in and the library list both worked
because the token was in memory, and only the router noticed that
`authStore.credentials` read back `nil`.

`accessToken` is only half-revoked by `clear()`. `AppServices.signOut` calls `POST /Sessions/Logout` **first** and wipes local state in the completion regardless of the outcome — order matters, because wiping first would strand a live token that can no longer be revoked. The token surviving a failed network call is the lesser evil; it at least remains revocable from the Jellyfin admin UI.

---

## 4. Info.plist additions

- ~~`NSAppTransportSecurity` / `NSAllowsLocalNetworking`~~ — **superseded, see doc 05 §6.1.** The reasoning was that a LAN-only exemption is the tight, correct one. It is too tight for a server whose address the user types, and the key silently cancels `NSAllowsArbitraryLoads` when both are present. The plist now carries `NSAllowsArbitraryLoads` alone.
- `NSLocalNetworkUsageDescription` — required from iOS 14 to reach `192.168.x.x` at all. Irrelevant on the iOS 12 target device, but the app is meant to run on the iOS 15/18 phones too, and a missing string there is a hard failure rather than a prompt.

---

## 5. Not done yet

- **No verification against a live server.** The layer compiles and is exercised by nothing. Every entry point needs a UI to be driven from, and UI is a separate conversation (doc 02 §8.4). The Connect screen is the first real test of §2.4 and §2.5.
- **Library selection is not persisted.** `libraries()` returns every view with `holdsPhotos` available for filtering; deciding and storing the choice belongs with the picker screen.
- **No token revalidation on launch.** Doc 02 §3 wants relaunch to go straight to the timeline while revalidating in the background. There is no timeline yet.
