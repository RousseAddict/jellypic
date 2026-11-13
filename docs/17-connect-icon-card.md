# 17 — Connect: the icon card (plan, direction ratified 2026-11-12)

**What.** The connect flow keeps its one card that morphs between three steps — the part
the user likes — and takes the vocabulary of doc 16 plus the app's mark: direction "C · Icon
card" on the canvas *Jellypic connect flow* (claude.ai artifact, private). The petals sit
inside the card, everything is centred, the button is a capsule, going back is a sheet
disc, and on the sign-in step username and password share one field box.

**Ratified.** Direction C, and **the mark keeps its gradient**: it stays the one drawing in
the app that does not follow the palette (doc 05 §4), on light and dark alike. The
monochrome and tonal treatments on the canvas are set aside.

---

## 1. What changes, screen by screen

| | Today | C |
|---|---|---|
| All three steps | squircle card, left-aligned title and subtitle | same card (a surface keeps its corners, doc 16), **56 pt mark** at the top, title and subtitle **centred** |
| Server | field, hint, black squircle button | same field; hint centred; **capsule** button |
| Sign in | two 52 pt fields, 10 pt apart | **one field box**, two 48 pt rows and a hairline — 17 pt shorter |
| Library | option rows | same rows (their check is a circle since doc 16); centred header |
| Going back | the dots, or a swipe | the dots, a swipe, **and a back disc** in the card's corner on steps 2 and 3 |
| Step dots | 8 pt dots, the current one scaled to 1.25 | the current one becomes a **20 × 8 capsule** |
| Re-auth card | squircle button, the account inside a long caption | capsule button, the account on its own line (§6) |

## 2. The mark (K1)

`LogoMark.imageset` is drawn at 22 pt (22/44/66 px) for the grid's wordmark. Scaling it to
56 pt would blur it, and doc 05 §7's rule is that every size is rendered from the vector.
So `icon/render-icons.sh` renders a second set, **`LogoMarkLarge.imageset`, 56 pt
(56/112/168 px)**, from the same `icon/jellypic-mark.svg` through the same trim-and-square
step, and asserts it the same way. The grid keeps the 22 pt set. Asset catalog contents are
compiled whole by `actool`, so the new set costs no pbxproj edit.

## 3. The card's layout (K1)

- The mark: a `UIImageView`, 56 × 56, centred, 24 pt below the card's top; the title 14 pt
  below it. Everything else keeps today's spacing (doc 05 §5).
- Title, subtitle, error label and the server step's hint become **centred**. The fields'
  text stays leading-aligned.
- `ActionButton` draws `Capsule.path` instead of a 16 pt squircle, at its current 52 pt. It
  has two callers, this card and the re-auth card: both get the capsule, which is doc 16's
  rule for buttons.
- `CircleView` draws `Capsule.path`, so an 8 × 8 dot stays a circle and a 20 × 8 one is a
  pill. The current dot widens through its width constraint, animated with the morph,
  instead of scaling. Colours and the 36 × 44 targets are unchanged.

## 4. The back disc (K2)

A `GlyphButton` — the sheet disc of doc 16 — with a new **`BackGlyphView`** (a 7 × 12
left chevron, 1.7 pt, round joins) in `Design/FloatingButton.swift`, under that file's
existing `LEGACY(ios12)` marker. Pinned 9 pt from the card's top and leading edges, so the
30 pt disc sits 16 pt in; hidden on the server step, cross-faded by the morph. Its action is
`jump(to: step - 1)`, through the same `isMoving` lock as the dots and the swipe.

**This reverses doc 05 §5.1's "There is no back button".** The bare chevron tried then
read as a stray mark for want of a container; the disc *is* the container, and it is the
vocabulary every card has used since doc 16. The dots and the swipe stay: they cost
nothing and some people will reach for them.

## 5. The grouped credentials (K3)

A new `Design/GroupedInputView`: one squircle field box (14 pt, `palette.field`), two
`UITextField`s on 48 pt rows, a hairline between them inset 16 pt, `isInvalid` stroking the
**whole box** in `danger`. `CredentialsStepView` swaps its two `TextInputView`s for it and
keeps everything it configures today — `textContentType` `.username` / `.password`, the
return keys, the delegate that moves focus and clears the invalid state. Losing
`textContentType` would lose keychain fill and QuickType, the one thing doc 05 §5 insists
on.

## 6. The re-auth card: one field, and the account on its own line (K3b)

`ReauthViewController` hides the username field whenever the stored session has one, which
is almost always, leaving the password alone — the pattern iOS itself uses when a session
expires ("enter the password for this account"), and the honest one: re-auth can only be the
same account, since another would wipe the local index and `completeSignIn` refuses it. A box
built to group two rows would hold one, so the card keeps its fields and gets the capsule
button (§3).

One change, ratified 2026-11-12: **the account moves out of the sentence onto its own line,
directly above the password field** — `jf · 192.168.0.12`, body size, `textPrimary`. Today
it is buried mid-caption ("…Sign in again as jf to keep browsing — the 7712 photos…"), about
four lines on a 5s. The caption shrinks to what reassures: *"The saved session has expired.
Your 7712 photos stay on this device."* (the count only when there is one). The line is
hidden whenever the username field is shown — an old install with no stored name, or after
a sign-in that returned another account — since the field then says it.

## 7. The keyboard (K4)

The arithmetic on the 5s, keyboard plus suggestion bar ≈ 253 pt: the card's top is clamped
44 pt down (`updateCardOffset`), so today the server step's button already sits about 7 pt
under the keyboard, and the sign-in step's about 16 pt. The mark adds 70 pt and would bury
the button entirely.

So **the mark folds away while the keyboard is up**: its height constraint 56 → 0 and its
14 pt gap → 0, alpha 0, animated in `keyboardWillChangeFrame` with the keyboard's own
duration and curve, before `updateCardOffset` runs. The card is then today's height on the
server step and 17 pt shorter on sign-in, which brings that button clear. The server step's
7 pt is today's and is left as it is; curing it means dropping the hint with the keyboard,
which is a separate decision.

The back disc stays while the mark is folded; the centred title clears it at the default
text size, since no step title is long enough to reach the card's leading 46 pt. At the
largest Dynamic Type sizes a title could run under it — the title's insets then widen to
clear the disc whenever the disc is visible.

## 8. Milestones

| | Delivers |
|---|---|
| **K1** | the 56 pt mark set, the mark in the card, centred texts, capsule button, capsule dot |
| **K2** | `BackGlyphView` and the back disc |
| **K3** | `GroupedInputView` on the sign-in step |
| **K3b** | the re-auth card's account line and shorter caption |
| **K4** | the mark folding with the keyboard |
| **K5** | docs 05 §4 (components), §5 (layout), §5.1 (the back disc), §7 (the second mark size) |

## 9. Device tests (5s)

1. The three steps, light and dark, against the canvas.
2. The back disc on steps 2 and 3: it goes back, and a tap just beside it still does.
3. The dots and the swipe still go back; nothing goes forward past `reachedStep`.
4. Keyboard up on each step: the mark folds, the card never rises under the status bar,
   the sign-in button is fully visible.
5. Keychain fill and QuickType on the grouped fields; a wrong password strokes the box.
6. The re-auth card: capsule button, the account on its own line above the password, the
   short caption; with no stored username, both fields and no account line.
7. Switching theme while on the connect screen repaints everything except the mark.

---

## 10. What was built, and where it departs from the plan

K1–K5 and K3b in one pass. Files: `Assets.xcassets/LogoMarkLarge.imageset` (new),
`icon/render-icons.sh`, `Design/GroupedInputView.swift` (new — pbxproj ids `…147` /
`…148`), `Design/ActionButton.swift`, `Design/StepIndicatorView.swift`,
`Design/FloatingButton.swift` (`BackGlyphView`), `Connect/ConnectViewController.swift`,
`Connect/CredentialsStepView.swift`, `Connect/ServerStepView.swift`,
`Connect/ReauthViewController.swift`, docs 05 and this one.

- **The first step no longer opens the keyboard by itself.** `viewDidAppear` used to
  focus the server field, so the keyboard rose the moment the screen appeared — and with
  §7's fold the mark would have shown for a fraction of a second and gone, defeating the
  point of putting it there. Now the card arrives with the mark; the first tap on the
  field brings the keyboard and folds it. Steps 2 and 3 still focus themselves after the
  morph, and going back to step 1 focuses it too. One line to restore if it is missed.
- **The current dot's pill is drawn with `layer.cornerRadius`, not `Capsule.path`.** A
  shape layer's path does not animate with the view's bounds — the pill would jump to its
  final width while the frame grew. A corner radius of half the height on the dot's
  background colour is the same shape, animates with the width constraint, and needs no
  mask.
- **The 56 pt PNGs were produced without Pillow**, which the dev Mac does not have: the
  script's exact steps in CoreGraphics, resampled with Accelerate's Lanczos, verified
  against the committed Pillow output (doc 05 §7). The script itself gained the 56 pt
  slots and regenerates both sets with Pillow.

The rest is as planned: the title's side insets widen to 56 pt whenever the back disc is
visible; the re-auth caption names the server only when there is no account line to
carry it.

Verification: the whole app type-checks as a Mac Catalyst target (zero errors); built on
SERV2, and the compiled `Assets.car` in the IPA holds both `LogoMark` and `LogoMarkLarge`.
Reported working on the iPhone 5s on 2026-11-12, with one bug found along the way — the
session-expired banner squeezing the grid's circles — which is doc 16's, not this one's,
and is fixed and recorded there.
