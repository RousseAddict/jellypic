# 16 — Circles and capsules: buttons, pills, touch areas (plan, ratified in chat 2026-11-11)

**What changes.** Every control drawn over content becomes a true circle, every pill a true
capsule, and every button on a card one of Apple's grey sheet discs. Glyphs get lighter.
Every button accepts taps beyond what it draws. Large surfaces — cards, fields, setting
groups — keep their continuous corners: they are surfaces, not controls.

**Why.** The squircle plate (`Squircle`, n = 4, at a radius of half the height) reads as a
rounded square, not a circle, and the touch areas miss. Three directions were mocked on
the 5s; "B · Circles" (Photos, iOS 18) was chosen, then extended to every screen and
ratified with two additions: the pills become capsules too, and the picker's check
becomes a true circle. Reference canvas: *Jellypic icon buttons* (claude.ai artifact,
private), 12 screens at 320 × 568 pt.

---

## 1. Why taps miss today

- **The touch area is exactly the 44 pt frame.** Nothing extends it; Apple's bar buttons
  accept taps well outside what they draw.
- **The grid's buttons stop accepting taps once faded.** `updateHeaderAlpha` ties
  `isUserInteractionEnabled` to the alpha, which reaches 0 after 40 pt of scroll
  (`brandFadeDistance`). A tap where a button was then lands on the photo underneath and
  opens it — a misclick that does something.

## 2. Inventory

| Today | Where | Becomes |
|---|---|---|
| `FloatingButton` — squircle plate, 44 pt | viewer close / ⋯, map close, bucket close | circle, 36 pt drawn in the same 44 pt frame |
| `FloatingButton` — 64 pt | viewer play | circle, 60 pt in the same 64 pt frame |
| `GlyphButton(prominent:)` — bare glyph | grid `+`, map, settings | `FloatingButton` circles, **no longer fading** |
| `GlyphButton` — bare glyph | every card's close X (`CardSheetViewController`: details, Settings, re-auth), details share / stop / trash | sheet disc, 30 pt drawn in the same 44 pt frame |
| `SquircleView`, radius ≈ h/2 | date pill, conversion pill, sync banner, scrubber thumb and bubble, picker `SendPillButton`, viewer `RetryPillButton`, bucket title pill, map message pill | capsule |
| `SelectionIndicatorView` ring | picker check | circle |
| `SquircleView`, fixed radius | cards (32, 28), fields and option rows (14), setting groups (16) | **unchanged** |

Every frame keeps its size, so **no layout constraint moves**: the viewer's close circle
centres on (34, 50), exactly where the canvas puts it.

## 3. Primitives (I1)

- **A capsule path that is not the squircle.** A new `enum Capsule` in
  `Design/Squircle.swift`, below `Squircle`, building two half-circle arcs and two lines
  by hand. Not `UIBezierPath(roundedRect:cornerRadius:)`: its corner curve is Apple's own
  and is not guaranteed to be a true half-circle near half the height — and here the
  shape *is* the point. A square rect gives a circle. **No `LEGACY(ios12)` marker**: a capsule is not a
  stand-in for anything missing.
- **`SquircleView` gains `isCapsule`.** When set, `layoutSubviews` takes `Capsule.path`
  and ignores `cornerRadius`. The `shadowPath` rule of doc 05 §2 holds unchanged. The
  morphing card is untouched: its constant point count belongs to the squircle path.
- **Touch insets.** `FloatingButton` and `GlyphButton` gain `touchInsets: UIEdgeInsets`
  (negative = larger) and override `point(inside:with:)` with
  `bounds.inset(by: touchInsets)` — the pattern `MonthScrubberView` already uses.
  **Limit, and it dictates the numbers below:** a touch reaches a view only if it falls
  inside every ancestor's bounds, so a button can only grow within its superview.
  Neighbours split the gap between them, never overlap.
- **Glyphs.** `GlyphView` sets `lineJoin = .round` (caps are already round). Glyph size
  becomes an init parameter with today's value as the default, because the same X is 12 pt
  in a circle and 10 pt in a disc. Paths already scale to their rect.
- **Theme tokens** in `Theme.swift`, light / dark:

  | token | light | dark |
  |---|---|---|
  | `hairline` | black 8 % | white 10 % |
  | `discFill` | `#EDEDF0` | `#2C2C30` |
  | floating shadow (opacity, radius, offset) | 0.14, 4, (0, 2) | 0.5, 5, (0, 2) |

  `field` (`#F2F2F4`) is too close to the white card for a disc, hence `discFill`. The
  floating shadow is separate from the card's: a 24 pt, 10 % shadow is right under a card
  and far too heavy under a 36 pt circle.

## 4. Floating circles (I2)

`FloatingButton` draws its surface as a capsule (`isCapsule`) inset to 36 pt inside the
44 pt frame (60 inside 64 for play), filled with `surface` at 92 % opacity, a 0.5 pt
`hairline` stroke and the floating shadow. Pressed: today's 0.94 scale, plus the fill
moving to `discFill`. `touchInsets` = −2 all round → 48 pt (68 for play).

Viewer, map and bucket get it for free: same component, same frames. If the 92 % fill
looks muddy over the shadow on the device, go opaque — it is one constant.

## 5. Grid (I3)

- `settingsButton`, `mapButton`, `sendButton` become `FloatingButton`s with the new glyph
  sizes. Frames unchanged (centres 206 / 250 / 294).
- **`updateHeaderAlpha` stops touching them.** The brand still fades; the circles stay,
  over the photos, always tappable. This reverses a cost accepted in W3 (doc 12 §11: "the
  `+` takes the 40 pt fade"); that cost existed because a bare glyph is unreadable over a
  photo, which a circle is not.
- Touch: −4 top and bottom → 52 pt tall. Widths stay 44: the three frames already touch.
  `settingsButton` also takes −4 on the right, reaching the screen edge.

## 6. Card discs (I4)

`GlyphButton` becomes the sheet disc: a 30 pt circle (`Capsule` path on a square)
filled with `discFill`, centred in the same 44 pt frame, glyph in `textSecondary`.
Pressed: today's 0.5 alpha. Its only remaining callers are card accessories, so
`prominent:` goes. Every card gets the disc X at once — details, Settings, re-auth —
because the X belongs to `CardSheetViewController`.

Touch: −2 left and right, into the accessories stack's 4 pt spacing. **No vertical
extension**: the stack is exactly 44 pt tall and would clip it (§3). 44 pt is Apple's
minimum; the disc is smaller than its target, which is the point.

## 7. Capsules (I5)

`isCapsule = true` on the date pill, conversion pill, sync banner surface, scrubber
thumb and bubble, `SendPillButton`, `RetryPillButton`, bucket title pill and map message
pill; each drops its `cornerRadius = bounds.height / 2` line (or `min(h/2, 16)` for the
banner, `16` for the bubble). `SelectionIndicatorView`'s ring becomes a circle the same
way. The date and conversion pills also get the hairline and the floating shadow, to
match the circles beside them.

## 8. Glyph sizes (I6)

Effective strokes in points, as drawn on the canvas:

| Glyph | In a circle | In a disc |
|---|---|---|
| close X | 12 pt, 1.65 | 10 pt, 1.7 |
| ⋯ | 16 × 4, dots ⌀ 3.2 | — |
| `+` | 14 pt, 1.5 | — |
| map | 18 × 16, 1.45 | — |
| person | 18 pt, 1.45 | — |
| play | 20 × 22, filled, corners rounded by a 2.4 stroke | — |
| trash | — | 13 × 15, 1.4, rounded body and handle |
| share | — | 13 × 15, 1.45, rounded tray |

Trash and share change shape (rounded corners, the tray open at the top), as drawn on the
canvas. Stop, chevron, broken image and the scrubber grip keep theirs, with round joins.

## 9. Milestones

| | Delivers | Visible change |
|---|---|---|
| **I1** | `Capsule`, `isCapsule`, `touchInsets`, glyph size parameter, round joins, tokens | slightly softer glyph corners only |
| **I2** | floating circles | viewer, map, bucket |
| **I3** | grid circles, no fade | grid |
| **I4** | sheet discs | every card |
| **I5** | capsules + selection circle | pills, scrubber, picker |
| **I6** | glyph sizes and the two new shapes | everywhere |
| **I7** | docs: 05 §1–2 and §4 (squircle for surfaces only), 07 (grid buttons, scrubber), 08 (viewer controls), 12 §11 (the `+` fade reversed) | — |

Each milestone builds and runs alone. I1–I6 touch only `Design/` plus one-line call-site
changes, except I3 (the grid's fade logic).

## 10. Device tests (5s)

1. Each of the 12 canvas screens, light and dark, against the canvas.
2. Taps just outside each circle (2 pt) and each disc (2 pt sideways) land; taps in the
   gaps between the grid's circles go to the right neighbour.
3. Scroll the grid, then tap the circles: they open the picker, the map, Settings —
   never the photo underneath.
4. Grid scrolling stays smooth with three shadowed, translucent circles over moving
   photos (A7, 7712 items).
5. Theme switch at runtime repaints circles, discs, hairlines and shadows.
6. Viewer chrome hide/show by tap still hides the circles and the date capsule; play and
   the conversion capsule keep their own rule (doc 10).
7. Drag-to-dismiss and the zoom transition still carry the controls' alpha.

## 11. Not in scope

Cards, fields and option rows keep their squircle corners. The segmented controls are
UIKit's. No blur anywhere (doc 05 §1). The map's photo markers keep their rounded
corners: they are thumbnails, not controls.

---

## 12. What was built, and where it departs from the plan

All of I1–I7, in one pass. Files: `Design/Squircle.swift` (`Capsule`, `isCapsule`,
`applyFloatingShadow`), `Design/Theme.swift` (tokens), `Design/FloatingButton.swift`
(glyphs, `GlyphView` size parameter and round joins, both buttons), `Design/Icons.swift`
(selection ring), `Design/CardSheetViewController.swift` (disc X at 10 pt),
`Grid/PhotoGridViewController.swift`, `Grid/SyncBannerView.swift`,
`Grid/MonthScrubberView.swift`, `Viewer/PhotoViewerViewController.swift`,
`Viewer/ZoomablePhotoCell.swift`, `Writer/AssetPickerViewController.swift`,
`Map/MapViewController.swift`, `Map/PhotoBucketViewController.swift`. No new file, so no
pbxproj edit.

- **Glyph sizes landed with I2, not I6.** The circles needed them at once. Each glyph's
  natural size is now its size where it is used (circle or disc), so only the cards' X —
  12 pt in a circle, 10 pt in a disc — passes a size explicitly.
- **The hairline and the floating shadow reach further than §7 said**: the sync banner,
  the scrubber thumb, the bucket title and the map message pill get them too, not only
  the date and conversion pills. All of them float over photos next to the circles, as
  the canvas draws them.
- **The scrubber bubble keeps its accent fill.** The canvas drew it light; the plan asked
  for the shape only, and the shape is what changed. One line in `applyTheme` if the
  canvas version is wanted.
- Pressed `FloatingButton`: 0.94 scale and the fill moving to `discFill`, as planned.
  The resting opacity is `FloatingButton.restingOpacity` (0.92), the one constant to
  change if the fill looks muddy over its shadow on the device.

Verification: the whole app type-checks as a Mac Catalyst target with Swift 5.5.2 (zero
errors); built on SERV2 and reported working on the iPhone 5s on 2026-11-11. The tests
of §10 were not reported one by one, so scroll smoothness and the runtime theme switch
are still unconfirmed in detail.
