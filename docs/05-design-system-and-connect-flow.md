# 05 — Design system and connect flow

Scope: livrable 1, step L1.1b — everything the user sees before the grid exists.
Target device is the iPhone 5s (A7, 1 GB RAM, 320×568 pt, iOS 12.5.7), so every
decision below is a performance decision first and an aesthetic one second.

## 1. The look

Requested: *"très épuré et léger, qui rappelle un peu liquid glass mais sans la
transparence"*.

Translated into constraints:

- **No blur, no transparency.** `UIVisualEffectView` is the single most expensive
  thing you can put on an A7 — it forces a full offscreen render pass every
  frame. The "glass" impression is rebuilt from the two cheap ingredients that
  actually carry it: a **soft squircle silhouette** and a **wide, low-opacity
  shadow** that lifts the card off the background.
- **One surface at a time.** A single card floats on a near-white background.
  Depth comes from that one elevation step, not from layering.
- **Monochrome.** The accent is near-black (`0x0B0B0C`) in light mode and
  near-white (`0xF2F2F4`) in dark. Nothing competes with the photos, which are
  the only colour the app should ever show.

## 2. Squircle by hand

`CALayerCornerCurve.continuous` is iOS 13+. On iOS 12 a rounded corner is a
circular arc, which reads visibly "sharper" than the Apple shape.

`Design/Squircle.swift` traces a superellipse (`|x|^n + |y|^n = r^n`, n = 4)
with 16 line segments per corner, walking the four corners in order and closing
the path. 16 samples is the point where the polygon is indistinguishable from
the curve at 2× on a 4-inch screen; going higher only costs path memory.

Two details matter:

- **`layerClass = CAShapeLayer.self`, never `layer.mask`.** Masking a view with
  a shape layer forces offscreen rendering on every frame *and* clips the
  shadow away. Making the view *be* the shape layer costs nothing and lets the
  path participate in `UIView.animate`.
- **`shadowPath` is always set explicitly** in `layoutSubviews`. Without it
  Core Animation derives the shadow from the alpha channel each frame, which is
  the classic way to drop a legacy device to single-digit FPS.

Because the point count of the path is constant regardless of the rect size
(4 × 17 + 1), a path swap interpolates cleanly — that is what makes the card
*morph* rather than jump when the step changes.

## 3. Theme tokens

`Design/Theme.swift` defines `ThemePalette` (background, surface, field, two
text levels, separator, accent/onAccent, danger, plus the four shadow
parameters) and two concrete palettes.

iOS 12 has neither dynamic `UIColor` nor `userInterfaceStyle`, so:

- `Theme.mode` is an explicit `system | light | dark` preference, persisted in
  `UserDefaults` via `Preferences.themeMode`.
- `Theme.isDark` resolves `.system` through `traitCollection.userInterfaceStyle`
  behind an `#available(iOS 13.0, *)` check, and answers `false` below that.
  The whole dark palette is therefore already reachable today by setting the
  preference manually; it becomes automatic the day the floor moves.
- Repainting is a push, not a pull: `Theme.didChangeNotification` +
  `UIView.applyThemeRecursively(_:)`, which walks the hierarchy and calls
  `applyTheme` on anything conforming to `Themed`.

Typography is five roles (title / headline / body / caption / button), all run
through `UIFontMetrics` so Dynamic Type works without per-label code.

## 4. Components

All in `Design/`, all shape-layer backed, all `Themed`:

| Component | Notes |
| --- | --- |
| `SquircleView` | the base surface; `fillColor`, `strokeColor`, `applyShadow` |
| `ActionButton` | `UIControl`, 52 pt, spinner replaces the title, 0.97 scale on press |
| `TextInputView` | squircle field, 52 pt; `isInvalid` paints a 1.5 pt danger stroke |
| `OptionRowView` | 56 pt selectable row, filled with `palette.field` when on |
| `CheckmarkView` | path drawn in code, `strokeEnd` animated on selection |
| `SelectionIndicatorView` | ring + checkmark, 24 pt |
| `StepIndicatorView` | onboarding dots; each dot is a 36×44 `UIControl` |

No SF Symbols (iOS 13+), no image assets: every glyph is a `UIBezierPath`, so
it stays crisp at any size and costs no bundle space.

## 5. The connect flow

Three steps, **one card that morphs in place** — no pushes, no modals:

1. **Server** — free-text address. `ServerURL.candidates(from:)` produces the
   list to try (raw input, then the same host with `:8096` appended when no
   port was given); `ConnectViewController.probe` walks that list sequentially
   and keeps the first URL that answers `/System/Info/Public`. The user never
   has to know about the port.
2. **Credentials** — username + password, submitted to
   `/Users/AuthenticateByName`. On success the token goes to the Keychain via
   `AppServices.signIn`.
3. **Library** — the result of `/Users/{id}/Views`, filtered to
   `holdsPhotos` (`CollectionType == "homevideos"`, which is what a Jellyfin
   photo library actually reports). If the filter empties the list we show
   every view rather than a dead end. The pick is stored in
   `Preferences.libraryId` / `libraryName`.

Mechanics worth remembering:

- The outgoing step view keeps its top/leading/trailing constraints but has its
  **bottom constraint deactivated** before the incoming view is installed, so
  the container height is driven by exactly one view during the animation and
  the card can grow or shrink smoothly.
- Labels cross-fade individually (`UIView.transition` on the leaf label). A
  transition on the *card* would snapshot it and fight the layout animation.
- The keyboard moves the card with `cardCenterY.constant`, using the duration
  and curve from the notification so it tracks the keyboard exactly, and it is
  clamped so the card top never goes above `safeAreaInsets.top + 24`.

## 5.1 Navigating between steps

There is **no back button**. A first attempt used a bare chevron floating above
the card and it read as a stray mark rather than a control — partly geometry
(5 pt wide for 18 tall is a far steeper V than the system chevron), partly the
absence of any container. It was removed rather than repaired, and replaced by
the onboarding pattern:

- **Three dots below the card**, on the background. They belong to the flow, not
  to the content, so the card stays a clean surface that only morphs.
- **The dots are the back control.** Each is a 36×44 pt `UIControl` — the dot
  itself is 8 pt, the target is not. Only steps already validated are tappable;
  the rest have `isUserInteractionEnabled = false`, so an unreachable step
  cannot even be pressed by accident. Three states: current (accent, scaled
  1.25), reachable (`textSecondary`), upcoming (`separator`).
- **Swipe right / left** does the same thing. `UISwipeGestureRecognizer`, not an
  interactive drag: the gesture is recognised and the existing morph animation
  plays. An interactive transition would relayout the card on every frame of the
  drag, which is exactly the kind of thing that drops an A7 below 60 fps.
- Both routes funnel through one `jump(to:)` that rejects anything past
  `reachedStep` or outside the enum, so the swipe needs no bounds checks of its
  own.
- `reachedStep` is **assigned, not maxed**: re-validating the server address
  sets it back to `.credentials`, which correctly makes the library step
  unreachable again until the new server has been authenticated against.
- Because the dots sit under the card, the *group* is centred rather than the
  card alone — `updateCardOffset` subtracts a fixed `indicatorSpace` (62 pt) so
  the dots never end up under the keyboard on a 568 pt screen. It runs from
  `viewDidLayoutSubviews` with a 0.5 pt epsilon guard, so a layout pass that
  changes nothing does not schedule another one.

## 6. Routing

`RootViewController` is a router with a single rule:

```
credentials in Keychain && Preferences.libraryId != nil  →  Home
otherwise                                                →  Connect
```

Children are swapped with a cross-fade. `AppDelegate` no longer wraps anything
in a `UINavigationController` — the app has no navigation bar anywhere.

`Home/HomeViewController` is a **placeholder**: library name, server address,
sign out. It exists only so the router has two destinations and so the sign-out
path is testable. L1.3 replaces it with the grid.

Sign-out order is unchanged from doc 04 — `POST /Sessions/Logout` first, local
wipe second, and the wipe now also clears the library preference so the next
launch lands on the connect flow rather than on a home pointing at nothing.

## 6.1 App Transport Security

`Info.plist` carries `NSAllowsArbitraryLoads` and **nothing else** under
`NSAppTransportSecurity`.

`NSAllowsLocalNetworking` alone — what doc 04 §4 shipped — was not enough. It
only covers unqualified hostnames, `.local` and link-local addresses, so a
Jellyfin reached through a DDNS name, a public IP, a VPN or Tailscale was
refused by ATS. Since the whole point is that the user types an address we
cannot predict, the blanket exception is the honest answer.

**Keeping both keys was a bug, and it is the one that made
`http://home.domain.com:8096` fail.** From Apple's reference for
`NSAllowsArbitraryLoads`:

> In iOS 10 and later and macOS 10.12 and later, the value of the
> `NSAllowsArbitraryLoads` key is ignored — and the default value of `NO` used
> instead — if any of the following keys are present:
> `NSAllowsArbitraryLoadsInWebContent`, `NSAllowsArbitraryLoadsForMedia`,
> `NSAllowsLocalNetworking`.

The precedence runs the opposite way to what the first version of this section
claimed. Setting `NSAllowsLocalNetworking` did not *back up* the blanket
exception, it **disabled** it, leaving only the local-networking exemptions in
force. That is exactly the symptom: a LAN IP worked (ATS does not apply to
IP-address literals at all), HTTPS worked (no exception needed), and plain HTTP
to a fully-qualified domain was refused — with no ATS-specific error, just a
connection failure that reads as "server unreachable".

Dropping the key restores the blanket exception. Nothing is lost:
`NSAllowsArbitraryLoads` is a strict superset of `NSAllowsLocalNetworking`.

`NSLocalNetworkUsageDescription` stays. It is not an ATS key — it is the purpose
string for the iOS 14+ local-network *privacy* prompt, a separate mechanism, and
removing it would turn a permission dialog into a hard failure on newer phones.

On App Store review: `NSAllowsArbitraryLoads` triggers a request for written
justification, not an automatic rejection. "Client for a self-hosted server
whose address the user supplies" is the textbook accepted case — every
Jellyfin, Plex and Home Assistant client ships with it. Apple announced
enforcement in 2016, postponed it indefinitely, and has never turned it on.

The real cost is not review, it is the wire: over plain HTTP the password goes
to `/Users/AuthenticateByName` in clear. On a LAN that is irrelevant; exposed
to the internet it is not — hence the warning below.

## 6.2 The plaintext warning

`ServerURL.isPlaintextToPublicHost(_:)` answers true when the scheme is `http`
and the host is not obviously private. Private means: `localhost`, any
unqualified name, a `.local` / `.lan` / `.home.arpa` / `.internal` suffix,
RFC1918 (`10/8`, `172.16/12`, `192.168/16`), loopback `127/8`, link-local
`169.254/16`, IPv6 `::1`, ULA `fc00::/7` and IPv6 link-local `fe80::/10`.

A DDNS hostname resolves as public because it does not match any of those, which
is the desired answer — the traffic really is leaving the house.

The warning lives on the **credentials** step, not under the server field, in
danger red appended to the subtitle. Two reasons: the flow advances the moment
the probe succeeds, so a warning on the server step would only flash; and the
credentials step is where the password is about to be typed and sent, which is
the thing actually at risk.

It is a warning, not a gate. Nothing is disabled and there is no alert to
dismiss — self-hosting over plain HTTP through a tunnel or a VPN is a legitimate
setup, and the app has no way to tell that from a truly exposed server.

Because the subtitle is an `NSAttributedString` with two colours,
`themeDidChange()` calls `applyPalette()` and then re-runs `renderStep` — the
attributed string holds its colours, so a plain `textColor` assignment would
leave the old palette's red behind.

## 7. Not done yet

- No "remember several servers" — one server, one account, one library.
- Error text is English-only and not localised.
- The connect flow has no automated test; it is exercised by hand on the 5s.
