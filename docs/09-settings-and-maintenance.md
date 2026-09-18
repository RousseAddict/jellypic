# 09 — Settings and maintenance

Scope: livrable 1, step L1.5. The settings card is the only place in the app that
is not photos, so it carries everything that has nowhere else to live: appearance,
cache, resync, sign out.

## 1. A card, not a screen

Settings is a child view controller presented over the grid with the same dimming
and swipe-down as the viewer's details card, not a pushed `UINavigationController`
screen. There is no navigation bar anywhere in the app; adding one for four rows
would have been the first piece of system chrome in the design system.

The card grows to its content and stays anchored to the bottom.

## 1.1 Identity header, then titled sections

Ratified in chat over a flat list and over a version with no section titles.

The top of the card is not a "Settings" title — it is the library name in the
title font, with the server URL and the indexed count under it in secondary text.
The card is opened from one button on one screen; a label saying "Settings" spends
the most prominent line in the card restating what the user just tapped. The
useful headline is *which library, which server, how much of it is here*.

Below that, three groups, each with a micro-header in uppercase semibold 12 with
0.9 pt of kerning: **Appearance**, **Storage**, **Account**. The uppercase header
is the convention every iOS user has read a thousand times, and it survives the
settings growing — an unlabelled group stops being self-evident at the fourth one.

`SettingsGroupView` is the squircle; the rows inside it are transparent. That is
the inversion from the first version, where each row carried its own background
and the card read as a stack of loose buttons. A group draws one `field`-coloured
squircle and inserts a hairline between consecutive rows, inset 16 pt on the
leading edge to line up with the row titles. The hairline is `1 / UIScreen.main.scale`
tall — a 1 pt line is two device pixels on the 5s and reads as a border.

`SettingsRowView` is a `UIControl`: a title on the left, a right-aligned detail
label with `.defaultLow` horizontal compression resistance so a long value shrinks
instead of pushing the title out, and 50 pt of intrinsic height. `isDestructive`
paints the title in `palette.danger`; `isHighlighted` and `isEnabled` both drive
`alpha`, which is all the feedback a transparent row needs.

Both live in `SettingsViewController.swift` rather than their own files — the
project file is hand-written, and two more entries for two small controls is six
pbxproj edits each.

**Sign out is a row, not a button** (ratified). It was a full-width accent
`ActionButton`, which made the rarest and most destructive action the most
attractive thing on the card. As a red row in the Account group it is findable and
unambiguous without being an invitation. The cost is the loading state: there is no
`isLoading` on a row, so the logout request shows as `detail = "Signing out…"` with
the row disabled.

**The card scrolls internally past 92 % of the screen height.** The content stack
is inside a `UIScrollView` whose height matches the content at priority 999, with
a `heightAnchor <= view.height * 0.92` cap at required priority. Under the cap the
card sizes itself to its content and nothing scrolls; over it, the cap wins, the
999 breaks, and the content scrolls inside a card that stops short of the top.
`alwaysBounceVertical = false` so a card that fits does not rubber-band and does
not fight the swipe-down dismissal.

The cap started at 0.85 and that was wrong on the 5s: the three sections came to
roughly 461 pt against 451 pt of visible card, so the Account group was clipped
with about 10 pt of scroll range — technically scrollable, indistinguishable from
broken. A card that overflows by a hair is the worst case, because there is no
visible cue that anything is below and no room for the bounce that would reveal
it. Two changes together: the cap to 0.92, and the content compacted (section
spacing 22 → 18, the gap under the identity header 26 → 22, the top inset 26 → 24,
row height 50 → 48). The card now fits outright at the 5s floor, and the scroll
view stays as the safety net for landscape and large Dynamic Type rather than as
the everyday mechanism. The scroll indicator was also re-enabled inside the card
— unlike the grid, there is no second indicator here to collide with, and it is
the only signal that content continues below the fold.

## 2. Appearance

A `UISegmentedControl`, because there are two or three mutually exclusive values
and the result is visible instantly behind the card — a picker or a push screen
would hide the thing being previewed.

The segments are built at runtime:

```swift
var modes: [ThemeMode] = [.light, .dark]
var titles = ["Light", "Dark"]

// LEGACY(ios12): userInterfaceStyle does not exist, so "System" could only ever answer light.
if #available(iOS 13.0, *) {
    modes.insert(.system, at: 0)
    titles.insert("System", at: 0)
}
```

Ratified in chat after the user asked for exactly this: *"je voudrai l'option 2,
mais l'option 1 sur ios 12 c'est possible ? Genre on cache le systeme pour ios 12"*.

The reason "System" cannot ship on the 5s is `UITraitCollection.userInterfaceStyle`,
which is iOS 13+. On iOS 12 there is no OS-level appearance to follow, so a
"System" segment would silently mean "Light" — an option that lies. Hiding it is
better than disabling it: a greyed segment invites the user to wonder what is
wrong with their phone.

`themeModes` is kept as a parallel array so the selected index maps back to a mode
without hardcoding offsets that differ per OS version. If the stored mode is not in
the list, selection falls back to `Theme.isDark ? .dark : .light` — the resolved
appearance rather than an arbitrary segment.

## 3. Image cache

`ImageLoader.clearCaches()` empties both the `URLCache` on disk and the `NSCache`
of decoded bitmaps. It does **not** touch credentials or the Core Data index —
the grid stays populated and the app stays signed in. Only pixels go.

The row is labelled by what it holds, not by what tapping it does: its detail
shows the current size, and tapping replaces it with "Cleared *n*". A row titled
"Reset cache" reading "184 MB" on the right is ambiguous about which of the two is
the value.

Honest limitation: the number is `URLCache.currentDiskUsage` only. `NSCache`
exposes no aggregate size — `totalCostLimit` is a limit, not a reading, and the
cost we set per entry is an estimate of decoded bytes, not a measured one. So the
figure under-reports by whatever is currently decoded in RAM. Reporting the disk
number alone is closer to true than summing a real number with a guess.

There is no confirmation. Clearing an image cache is free to undo — the next scroll
refetches — and an alert for a harmless action trains the user to dismiss alerts
without reading.

## 4. Resync library

Calls `SyncEngine.refresh(libraryId:)`, which re-pages `/Items` from the start and
upserts. It is **not** destructive: the store is never cleared, so the grid keeps
showing everything it already has while the pass runs. The alert says so, because
"Resync" otherwise sounds like "wipe and redownload" and on a 20 000-photo library
over a phone that would be alarming.

This one *does* confirm, ratified in chat. The pass costs minutes and heat on an
A7, and unlike the cache reset it cannot be undone by waiting.

The alert names a count when one is known:

```swift
let known = max(Preferences.syncTotal, services.store.count())
let scope = known > 0 ? "all \(known) photos" : "the whole library"
```

`Preferences.syncTotal` is the server's reported total from the last pass, and the
store count is what actually landed. Taking the max means a resync interrupted
halfway still quotes the real library size rather than the partial one.

The card dismisses itself after triggering, and the grid shows its "Indexing…"
banner — the same banner the first sync uses, so there is one indexing affordance
in the app, not two.

### What it does not fix

Deletion. `refresh` upserts; a photo removed on the server stays in the index and
its cell shows a broken thumbnail forever. Detecting deletions means diffing the
full server id set against the local one, which is the *point* of a resync and the
obvious next step — but it is a separate piece of work and it is not in L1.

## 5. Sign out

Unchanged from L1.1b: `POST /Sessions/Logout` first, local wipe second. Network
before local, or the token lingers in the server's device list with no way to
revoke it from the phone. The wipe clears credentials, preferences and the index;
the image caches go with it.

**It confirms, with a destructive button** (ratified). Sign out is one tap on a
row inside a card that also holds a harmless cache reset — the row is red, but
red is a colour, not a speed bump. The alert uses
`UIAlertAction.Style.destructive`, so the confirming button is itself red, unlike
Resync's `.default`; that is the whole difference in weight between the two
alerts, and it is deliberate. Resync costs time, sign out costs the index.

The message names the count, on the same argument as §4 — "The 18 432 photos
indexed on this device are deleted" is a number the user can weigh, where "your
data will be removed" is not — and it says explicitly that **nothing on the
server changes**, because "sign out wipes the index" is otherwise easy to read as
"sign out deletes my photos".

## 6. Not done yet

- **Dark mode has only been seen on the iOS 12 5s.** It is correct there, but the
  "System" segment — the one path that cannot exist at that floor — has never been
  exercised on a real device. Re-check appearance on an iOS 15/18/26 device once
  the signed CI build can be installed.
- No "server details" beyond name and user — no version, no reachability check.
- No cache size cap exposed. `URLCache` has one in code; the user cannot change it.
- No per-item cache eviction, only the blunt clear.
- Resync cannot be cancelled once started, and there is no progress beyond the
  grid banner.
- No deletion detection, per §4.
