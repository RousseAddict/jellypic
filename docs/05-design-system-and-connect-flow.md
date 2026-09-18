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
| `FloatingButton` | 44 pt circle over content: surface, shadow, one `GlyphView` |
| `ShareGlyphView` / `StopGlyphView` | arrow-out-of-tray, and the filled square that replaces it mid-download |
| `CardSheetViewController` | the sheet all cards are built on — see §4.1 |
| `GlyphButton` | bare `GlyphView` in a fixed 44×44 target — `prominent: true` tints it primary |
| `PersonGlyphView` | user-circle — ring, head, shoulders; the grid's settings button. See doc 07 |

It was called `CardAccessoryButton` for as long as cards were the only place a
bare glyph could live. The grid's settings button is the same object outside a
card, so the name had to stop naming its first caller. `prominent` is the only
axis that separates the two uses: an accessory inside a card must not compete
with the card's title (`textSecondary`), a lone control over the grid has to
hold its own (`textPrimary`).

No SF Symbols (iOS 13+): every glyph is a `UIBezierPath`, so it stays crisp at
any size and costs no bundle space. The **one** image asset in the app is the
logo mark above the grid (`docs/07` §1) — an asset precisely because it is the
one drawing that must *not* follow the palette.

## 4.1 `CardSheetViewController`

The settings card and the viewer's details card were written separately and
converged on the same thing: a dimmed backdrop, a squircle pinned to the bottom
and overhanging it by 32 pt so only the top corners show, a spring slide-up on
`transform`, tap-outside, swipe-down, and a height cap. Roughly 160 duplicated
lines that had already started to drift — the two cards capped their height
differently and only one of them could actually be dismissed in landscape.

### The base class owns the whole skeleton, not just the chrome

The first version handed subclasses a `card` and a `UILayoutGuide` and let them
build their own header, their own scroll view and their own footer against it.
Both subclasses then wrote the same fifteen constraints slightly differently,
and both got them wrong — see "the X that floated" below. **The layout itself is
now in the base class**; a subclass supplies views, never geometry:

```
card
└ sheet            vertical stack, pinned to the card (or the safe area)
  ├ header         horizontal: [ headerView | accessories… closeButton ]
  ├ scrollView     the only scrolling region
  │ └ body         vertical stack — the subclass fills this
  └ footer         hidden until addFooterView is called
```

The API is two calls and two stacks: `setHeaderView(_:)`, `addAccessory(_:)`,
then `body` and `footer` to append to. No subclass activates a constraint that
touches the card, the sheet or the close button. `footer` starts hidden and stays
that way unless a subclass shows it — a visible-but-empty arranged subview would
still claim the stack's 22 pt of spacing, whereas a hidden one costs nothing.

This is also what makes the header extensible: `addAccessory` inserts before the
X, so a card can grow a second control (Share, say) without either subclass
touching the header layout.

**The X that floated.** `CardCloseButton` had a 44×44 `intrinsicContentSize` and
no width constraint, and the subclasses pinned their title with
`title.trailing == closeButton.leading - 12`. Horizontal content hugging is 251
on `UILabel` and 250 on a plain `UIControl`, so when the row had slack the solver
stretched the *button*, not the label: the 44 pt target became ~170 pt wide and
the glyph, centred in it, sat in the middle of the card with a gap after the
title. In the settings card, where the header was a `UIStackView` (hugging 250,
a tie), it went the other way and crushed the identity block instead.

Two rules come out of that, and they are the reason the skeleton moved into the
base class:

- **an icon target declares its size with constraints, not with
  `intrinsicContentSize`.** An intrinsic size is a preference the solver is free
  to overrule; `widthAnchor == 44` is not. `GlyphButton` carries both its
  44×44 and its glyph's size as required constraints.
- **the accessories stack hugs at `.required`**, so all horizontal slack in the
  header lands on the header view, which is the only thing that should absorb it.

### Bottom sheet or full sheet

Two constraint sets, swapped on `traitCollection.verticalSizeClass`:

| | `.regular` (portrait) | `.compact` (iPhone landscape) |
| --- | --- | --- |
| card top | `>= safeArea.top + 64` | `view.top - 32` |
| sheet top | `card.top + 24` | `safeArea.top + 24` |
| sheet sides | `card ± 24` | `safeArea ± 24` |

`sheet.bottom` is `safeArea.bottom - 24` in both modes, and the scroll view is
the only flexible element in the stack: `scrollView.height == body.height` at
**priority 500**. Under the cap it holds, the sheet is exactly as tall as its
content and nothing scrolls; over it, it breaks, the header and the footer keep
their sizes, and only the middle gives. One mechanism, one owner, both cards.

**500, not 999 — the number is the whole mechanism.** It was 999 first, which is
higher than the default compression resistance of 750, so when the sheet ran out
of room the solver did the opposite of what was wanted: it kept the scroll view
at its full content height and crushed the things around it. In landscape that
meant the settings card looked like it refused to scroll (it was the identity
header being flattened, not the scroll view growing) and the details card's
Share button simply vanished. The rule is that this constraint must sit **below**
compression resistance and **above** content hugging: 500 is the middle of that
band, so the scroll view is always the first thing to give and never the last.

Two other priority-band facts worth keeping: the mode swap runs behind
`guard isViewLoaded`, because `traitCollectionDidChange` fires as early as
`addChild` — before `viewDidLoad` has built the two constraint arrays. Without
the guard it recorded the new mode against two empty arrays, and `viewDidLoad`'s
own call then saw "already in that mode" and activated nothing at all: a sheet
with no top, no leading and no trailing constraint. That is why opening the card
in landscape looked different from rotating into it.

Portrait is unchanged in spirit: the card grows to its content and stops 64 pt
below the safe area, leaving a dimmed strip to tap. That `>= 64` replaces two
different magic multipliers — settings capped the card at 0.92 of the view, the
details card capped its scroll view at 0.5 — neither of which said what it was
protecting. The strip does.

Landscape is a full sheet, ratified in chat. On a 320 pt-tall screen the same
rule would leave a 64 pt card, so the card takes the screen and the X becomes
the only exit. It is pinned 32 pt *above* the view as well as below, so the
32 pt corners fall off both ends and the sheet reads edge-to-edge rather than as
a card wedged into the display. In that mode the sheet follows the safe area
instead of the card, which is what keeps content clear of the notch when the
phone is turned lens-left.

`verticalSizeClass`, not `bounds.width > bounds.height`: an iPad in landscape
has plenty of height and correctly stays a bottom sheet.

### Why the X, and where

Swipe-down is on the card, so a scroll view in the middle of it eats the
gesture — the swipe only ever worked over the title and the footer. That was
survivable while tap-outside existed; in a full sheet it is a trap. The X is
the guaranteed exit, and it is present in portrait too rather than being an
orientation special case: a control that appears and disappears with rotation
is worse than one that is always there.

It is the last arranged subview of the header row, top-aligned, so it tracks the
first line of whatever the subclass put there and can never overlap it at large
Dynamic Type sizes. The 44 pt target against a ~34 pt title line means the glyph
sits a few points below the title's optical centre; that is the cost of keeping
Apple's minimum touch target, and it is cheaper than hard-coding a font metric.

No `FloatingButton`: a surface and a shadow on top of a card is a card on a
card. `GlyphButton` is the bare glyph in `palette.textSecondary`, in a
44 pt target, dimming on press.

### A card with a text field lifts on its transform

`ReauthViewController` (doc 04 §6) is the first sheet to hold a keyboard, and on
a 4-inch screen the keyboard covers the card outright. It moves on
`card.transform`, not on a constraint: the base class already animates that same
property for present and dismiss, so a translated card composes with them
(`.beginFromCurrentState`) instead of fighting a layout pass mid-animation.

The 32 pt overhang pays for itself here. Lifting the card by the keyboard
overlap puts its bottom edge exactly 32 pt *behind* the keyboard's top, so the
rounded bottom corners stay hidden and the sheet still reads as anchored rather
than floating. The content stops `safeArea.bottom + 24` above the keyboard for
free, because the inner stack is pinned to the safe area, not to the card.

Dismissal calls `view.endEditing(true)` first, so the keyboard leaves with the
card rather than after it.

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

## 7. The app icon

Source of truth is `icon/jellypic-icon.svg`; `icon/render-icons.sh` rasterises it
into the eighteen slots of `AppIcon.appiconset`. The PNGs are committed too, so a
clone builds without `rsvg-convert` ever being installed.

The artwork is six petals in the `#9C61C5 → #0E9EDA` gradient on a full-bleed
white field. The drawing arrived as a gradient *ring* enclosing the petals, and
three things about that could not ship.

**It was 62 % transparent.** Not a stylistic choice: the frame is one path with
`fill-rule="evenodd"`, so its interior is a hole, and the whole canvas outside it
is empty. It only looked white because image viewers composite onto white. An iOS
icon must be opaque — alpha is rejected outright by App Store Connect, and the
home screen composites what is left onto black. `render-icons.sh` asserts
`mode == 'RGB'` on every output rather than trusting the pipeline.

**It drew its own rounded square.** iOS applies a continuous-curvature squircle
mask to every icon, so artwork that rounds its own corners produces a rounded
rectangle inside a rounded rectangle. The two do not even agree on shape: the
drawing used circular arcs of radius 320 on a 1024 canvas, where the system mask
is a superellipse of radius ≈ 0.2237 × side, which is 229 px — a different curve
family, not a different number. The fix is to delete the frame and let the mask
be the only rounding in the picture.

**It left a 5.5 % margin** (content spanned 56 → 968), which makes an icon read
smaller than every neighbour on the home screen, and the petals themselves only
covered 46 % of the canvas — about 18 px of motif in the 40 px Settings slot.
They are now scaled to 62 %, which is the largest that keeps the petals clear of
the mask's corners at every size.

Every size is rendered from the vector rather than downsampled from the 1024, so
the 20 px slot is as crisp as the marketing one. Files are named by pixel size
and several slots share one file — iPhone 20@2x and iPad 40@1x are both 40 px,
and shipping those bytes twice would be silly. `actool` accepts the reuse.

The PNGs are also tagged sRGB, which `rsvg-convert` does not do. `sips` can
convert between profiles but cannot tag an untagged file, so that one step goes
through Pillow.

The source SVG was stripped of a 9 KB C2PA provenance manifest on the way in —
it was five sixths of the file and says nothing about the drawing.

## 8. Not done yet

- No "remember several servers" — one server, one account, one library.
- Error text is English-only and not localised.
- The connect flow has no automated test; it is exercised by hand on the 5s.
- The icon is light-only. iOS 18's dark and tinted variants need SDK 18, which
  is above the current ceiling, and would be a separate `AppIcon` appearance set.
