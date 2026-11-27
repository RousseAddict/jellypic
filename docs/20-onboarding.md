# 20 — Onboarding after sign-in (plan, ratified in chat 2026-11-24)

**What.** A short, dismissable card shown once after sign-in. It introduces the two things
nobody guesses: that backup needs **two server plugins**, and what the **three backup
modes** actually do. Step 1 checks the server and appears only when something is not
ready; step 2 picks the backup mode.

**Why.** Today both are invisible:

- a missing upload plugin shows as a greyed control and one line of text, deep in Settings
  (doc 12 §4);
- a missing HEIC plugin is the worst silent failure in the app: a modern iPhone's HEIC
  originals upload fine, then never become items in Jellyfin (no `Photo` item at all,
  `PhotoResolver` rejects the extension). The user backs up 500 photos and sees none;
- *Automatic* covers photos taken **from now on** (the W5 watermark), older photos are a
  separate one-time offer (W6), it only uploads on Wi-Fi, and swiping the app away stops
  it. None of that shows from the label.

**Ratified.** D1 card over the grid · D2 two steps, step 1 only when something is not ready
· D3 HEIC for Jelly reports itself (H5) · D4 an in-card *How to install* page for admins, a
share sheet for everyone else · D5 three option rows · D6 older photos as an inline switch
under Automatic · D7 X means Off, Off preselected · D8 existing users see it once if their
mode is Off. Each is below with the reasoning.

**Screens ratified 2026-11-24** on the canvas *Jellypic onboarding* (claude.ai artifact,
private): seven screens at 320 × 568, §5. The rule that came out of the first round is the
one to keep in mind while building: **nothing moves between screens** — same card height,
same top bar, one button in the same place.

---

## 1. Where it lives (D1)

A `CardSheetViewController` presented by the grid, the way `ReauthViewController` is
(`PhotoGridViewController.presentReauth`). Not steps 4–5 of `ConnectViewController`, and
not a passive checklist in Settings.

- **The first index sync runs behind it.** The grid exists and `SyncEngine` has started;
  the user reads two short screens while the photos arrive. Extra connect steps would
  hold the sync until they are done.
- **It is dismissable by construction**: the card already has its X.
- **The connect screen stays as it is.** It is the most delicate layout in the app
  (doc 17), and steps that only *sometimes* exist would make its step dots lie.
- A checklist in Settings teaches nothing, because nobody opens it before they need it.

### Isolation

The card touches `services.upload` and asks for Photos access, so **it lives under
`Writer/`** and is presented by the grid. The grid is already one of the four contact
points doc 12 §2 allows outside `Writer/`; a new `Onboarding/` folder would be a fifth.

## 2. When it shows (D8)

One rule: **when the grid appears with a session, the onboarding flag is unset, and the
backup mode is Off.** The flag is set when the card is finished or dismissed.

- The flag lives with the backup mode, in `Writer/`'s `UserDefaults` keys, and
  `JellyfinUploadService.reset` clears it at sign-out. Sign-out already resets the mode to
  Off (doc 12 §4), so a new sign-in shows the card again: same lifetime, same reason.
- **Re-authentication never shows it.** The re-auth card sits over a grid whose flag is
  already set.
- **Existing installs** see it once after the update if their mode is Off, since they may
  not know backup exists. A user who already chose Manual or Automatic never sees it.
- **Way back in:** from Settings (§7, open).

## 3. Step 1 — the server (D2, D3, D4)

Shown only when the upload plugin is not ready, or HEIC decoding is known to be off.
When everything is ready, including on the App Review demo server, the card opens on
step 2.

### What "ready" means

Not "installed". `GET /UploadForJelly/Targets` (doc 11 §4) already separates five states,
and each needs its own instruction:

| State | Source | Line on the card |
|---|---|---|
| not installed | 404 | install Upload for Jelly |
| wrong version | 2xx that does not decode | update Upload for Jelly |
| no library ticked | `NOT_CONFIGURED` | tick *this* library in the plugin's page |
| folder not writable | `READ_ONLY_MOUNT`, `PERMISSION_DENIED`, `PATH_MISSING`, `WRITE_FAILED` | the reason, in words (`BackupUploadError.refusalText`) |
| ready | `writable: true` | ✓ |

**"No library ticked" is the most likely state right after an install**: the plugin's
allowlist is empty by default (doc 11 §2). It must be its own line, not a generic refusal.

### HEIC: the plugin reports itself (H5)

heic-for-jelly adds no endpoint today, has no config page, and every Jellyfin route that
lists plugins requires an administrator (`PluginsController`, `PackageController`,
`DashboardController.GetConfigurationPages`, all `Policies.RequiresElevation` at
v10.11.6). Its only visible trace is its effect: HEIC files exist as photos, and a path is
returned to any user who asks (`DtoService.AttachBasicFields`, `ItemFields.Path`, no
admin check). That proves the plugin works only when HEIC files already exist; a new
library, or one filled from a 5s (A7 cannot capture HEIF, A10 and later can), looks
exactly like a missing plugin. Useless for onboarding.

So **heic-for-jelly 1.1.0.0 adds `GET /HeicForJelly/Status`**: any signed-in user, no
parameters, read-only.

```json
{ "decoding": true }
{ "decoding": false, "reason": "FFMPEG_TOO_OLD" }
{ "decoding": false, "reason": "FFMPEG_MISSING" }
{ "decoding": false, "reason": "ENCODER_NOT_DECORATED" }
```

**Shipped 2026-11-24** as heic-for-jelly 1.1.0.0 (`b4ab236`, catalogue `20b5776`); the
contract and its source checks are that repo's `docs/06-status-endpoint.md`. It reads the
very value that gates decoding, so it cannot disagree with the decoder. An HTTP call cannot
freeze decoding off by being first: Jellyfin answers every request 503 until startup has
validated ffmpeg (`ServerStartupMessageMiddleware`, 10.11.6 and 12.4). The third code,
added while implementing, covers an image encoder that is not the plugin's (the decoration
was declined, or another plugin wrapped it afterwards).

| Answer | Line on the card |
|---|---|
| `decoding: true` | ✓ Ready |
| `FFMPEG_TOO_OLD` | your server's ffmpeg is too old to read HEIC (it needs 7) |
| `FFMPEG_MISSING` | your server has no usable ffmpeg |
| any other code, `ENCODER_NOT_DECORATED` included | HEIC is off on your server — a code the app does not know never reads as success |
| 404 | not installed — 1.0.x also answers 404, so the instructions say *install or update* |
| 401 | the session, handled by the existing re-auth path, never by this card |
| timeout, anything else | unknown: the line is left as it was |

**Rejected: have Upload for Jelly report HEIC (H1).** It would read the image encoder's
`SupportedInputFormats`, which heic-for-jelly extends only when ffmpeg is new enough. But
heic-for-jelly's own source notes that nothing in Jellyfin reads that property, so a
native HEIC implementation would most likely not go through it. The day Jellyfin
supports HEIC, the upload plugin's field would turn wrong and need a release to follow.
**The two plugins stay independent**: either can be removed the day Jellyfin does its job,
without touching the other.

**What that costs, accepted:**

- heic-for-jelly's rule *"No new HTTP surface"* is narrowed to *no new surface that takes
  input or serves content*, with this one exception. The hole it guards against (a
  no-login endpoint taking a host path and serving the file, `docs/03-prior-art.md` in
  that repo) needs input and content; a status check has neither.
- **The app now knows heic-for-jelly by name.** The day Jellyfin supports HEIC natively and
  the plugin is uninstalled, the check answers 404 and the app would say "missing". The fix
  that day is one rule in the app: server version (`System/Info/Public`, no login) at or
  above the release that adds HEIC means supported. Not designed now.

**A missing HEIC plugin is a warning, not a blocker.** Backup works without it; the
photos stay invisible until it is installed. The card says so rather than disabling
anything.

### The library being browsed is the library being filled

`JellyfinUploadService.resolve` falls back to `targets.first` when the browsed library
(`Preferences.libraryId`) is not among the targets. Uploads would then land in a library
the grid never shows. **Recommended: drop the fallback** and treat the browsed library's
absence as "no library ticked", naming it. Open (§7).

### Instructions: admin or not (D4)

A non-administrator cannot install anything, so step 1 has two shapes — **one row, in the
same place**, under the plugin list:

- **Admin**: *How to install ›* (or *How to finish setup ›* when only the library tick is
  missing) opens a page **inside the same card**: the back disc in the top bar, the numbered
  steps, one *Copy* per plugin link (Jellyfin adds repositories one at a time), and *Open
  plugin settings ↗*. The steps are those of the plugin READMEs: add the repositories,
  install from the catalogue, restart the server, tick the library in Upload for Jelly.
  The page lists only the steps still needed.
- **Not admin**: *Send setup instructions* opens a share sheet with the same steps and both
  repository URLs, meant for whoever runs the server. One text, two uses: the page and the
  shared message are built from the same source.

**The deep links, verified in jellyfin-web 10.11.6 and 12.4** (`src/apps/dashboard/routes/
_asyncRoutes.ts`, a hash router in `RootAppRouter.tsx`, identical in both):

| Target | URL |
|---|---|
| repositories | `<server>/web/#/dashboard/plugins/repositories` |
| one plugin, its settings included | `<server>/web/#/dashboard/plugins/<id>`, id = the GUID without dashes |

`<server>` is the base URL the app already holds, so a path prefix (`https://host/jellyfin`)
is kept. A server that does not host the web client breaks the link; *Copy* still works.

Rejected for the steps: expanding a red row inline (the content height changes and the
shared steps repeat per plugin), and linking to the GitHub README (always current, but it
leaves the app and cannot name the user's library).

`User.Policy.IsAdministrator` is in the sign-in response (`AuthenticationResult.User`,
filled by `UserManager.GetUserDto`, verified at 10.11.6). It is decoded leniently — a
missing `Policy` or flag is `nil`, never a failed sign-in — and persisted at sign-in in
`Preferences.isAdministrator`, cleared at sign-out. **An install that signed in before this
ships has no value, and unknown takes the share shape**: the instructions it sends work for
anyone, an admin included, whereas install steps shown to a non-admin are a dead end.

Repository URLs, both already published:

```
https://raw.githubusercontent.com/RousseAddict/upload-for-jelly/main/manifest.json
https://raw.githubusercontent.com/RousseAddict/heic-for-jelly/main/manifest.json
```

A single combined repository would save the admin one step; it is not part of this plan.

### Coming back

Installing means leaving the app, restarting the server, coming back. The card re-checks
**when the app becomes active**, and on ***Check again***, a small link on the list's header
line (*CHECKED JUST NOW · Check again*) — never a button beside the main one. While the
server restarts the check times out, which must read as *unknown* — the line keeps its last
state, it never flips to "missing".

## 4. Step 2 — the backup mode (D5, D6, D7)

Three `OptionRowView` rows, each with a one- or two-line description, so the three can be
compared at a glance — a segmented control shows one description at a time. **Off is
preselected**; *Done* with Off and the X do the same thing. Nothing uploads without an
explicit choice.

### What each choice does

- **Off** — nothing else happens.
- **Manual** — sets the mode. No Photos prompt here: the picker asks when it first opens,
  next to the photos it is asking about.
- **Automatic** — asks for Photos access **now** (the sweep needs it, and W6 found nothing
  asked before). Then:
  - *full* access: the mode is set; with the older-photos switch on, `beginCatchUp()`,
    otherwise `declineCatchUp()`;
  - *limited* access: Automatic cannot work (doc 12 §15). The card says why, offers *Allow
    access to all photos*, and keeps Manual available;
  - refused: the card says so and stays on Off.
- **Background App Refresh off** (`UIApplication.backgroundRefreshStatus` is `.denied` or
  `.restricted`): a warning under Automatic, since photos would then only go when the app
  is opened.

### Older photos (D6)

An inline switch under Automatic — iOS has no checkbox control: *Also send older photos*,
with *N already on this iPhone* beneath. It is the only thing the Automatic row adds when
chosen. Setting
the mode to Automatic already arms the offer (`JellyfinUploadService.mode` →
`catchUpEngine.offer`); the card answers it directly, so the W6 alert — which lives in
`SettingsViewController.backupModeChanged` — never pops over the card. Settings keeps its
alert. The count appears only once access is granted, as in W6: a wrong number is worse
than none.

### When the upload plugin is not ready

Step 2 is still shown so the concepts are introduced, with Manual and Automatic disabled
and the reason on one line. To confirm in the screen design (§7).

### Concepts the card carries

Short, and only where they apply:

| Concept | Where |
|---|---|
| Automatic uploads go on Wi-Fi only (per request since doc 12 §16; picked photos may use cellular) | the Automatic row's description, *New photos · Wi-Fi only*, readable before choosing |
| photos only — videos stay on the iPhone, though the grid shows the server's videos | footer, Manual and Automatic |
| one-way: deleting a photo on the iPhone keeps the server copy | footer, Manual and Automatic |
| everyone who can open *this library* on the server sees what you send | footer, Manual and Automatic |
| nothing leaves the iPhone; backup can be turned on later in Settings | footer, Off |

The footer follows the selection: under Off the backup concepts do not apply.

Screenshots **are** backed up since 2026-11-12 (doc 12 §1): the card must not promise
otherwise.

**Taken off the card**, each for a reason:

- **Swiping the app away.** It is real — iOS cancels a force-quit app's background
  transfers (`NSURLErrorCancelled`, reason `NSURLErrorCancelledReasonUserForceQuitApplication`)
  and stops waking it until it is opened by hand — but a warning nobody needs yet is noise.
  Better: **say it when it happens.** The cancellation carries its reason under
  `NSURLErrorBackgroundTaskCancelledReasonKey`; `UploadClient` routes the cancel to
  `onUploadCancelled` without reading it. A separate change, not part of onboarding.
- **iCloud-only photos are skipped** and **a sent photo appears after about a minute**: true,
  but they belong where they happen (the queue banner already says the second).
- ~~**A cellular option** is a later discussion.~~ **Settled 2026-11-26, doc 12 §16:**
  photos picked with `+` may always use cellular, with no setting; Automatic stays on Wi-Fi.
  Cellular is allowed on the session and decided per upload request, as foreseen here. The
  Automatic row's *Wi-Fi only* stays true and the card needs no change.

## 5. Screens (ratified 2026-11-24)

### The layout rule: nothing moves

The first mockup let the card follow its content, so the button landed at a different
height on each screen, and step 1 had two buttons where step 2 had one. Rejected as a no-go.
Every screen of the flow now shares one frame:

- **One card height for the whole flow: the tallest screen's**, measured once when the card
  is built, capped at the sheet's maximum (64 pt below the top, doc 05 §4.1). On the 5s the
  cap wins and every screen is full height; on a larger phone the card stops at the tallest
  screen instead of opening a mostly empty sheet. If a screen still does not fit (large
  accessibility text), its content scrolls under a fixed footer.
- **One top bar**: back disc on the left when there is a page to return to, step dots in the
  middle when there are two steps, the X on the right. Empty slots keep their width, so the
  title starts at the same height on every screen.
- **One pinned footer, one full-width button**, 24 pt above the bottom of the screen: *Next*
  on step 1 (the *How to install* page included), *Done* on step 2. Nothing else ever goes
  there; secondary actions live in the content.

`CardSheetViewController` today sizes the card from its body and scrolls the whole body,
button included (doc 05 §4.1), so this needs a fixed-height mode with a pinned footer.

### The seven screens

| | Screen | Notes |
|---|---|---|
| 1a | admin, both plugins missing | two ✕ lines, *How to install ›* |
| 1a › | *How to install* | back disc; steps; *Copy* × 2; *Open plugin settings ↗* |
| 1b | admin, no library ticked | ! on Upload for Jelly, ✓ on HEIC; *How to finish setup ›* |
| 1c | not admin, both missing | *Send setup instructions* in the same row slot |
| 2a | server ready, Off preselected | no dots: step 1 was skipped |
| 2b | Automatic chosen | the row grows by the older-photos switch only |
| 2c | upload plugin not ready | Manual and Automatic disabled, one line why; back disc to step 1 |

Status symbols: red ✕ missing, grey ! a step left, black ✓ ready. The palette has no green
(doc 05 §3), and every state also carries a word.

## 6. Milestones

| | Delivers |
|---|---|
| **O0** | **DONE 2026-11-24.** heic-for-jelly 1.1.0.0 released; the user's own server untouched (it never had the HEIC repository). Demo server pinned to 1.1.0.0 (`demo-server/vars.yml`) and redeployed: `/HeicForJelly/Status` answers `{"decoding":true}` to the demo user, 401 anonymously |
| **O1** | **Built 2026-11-24** (§6.1). App groundwork: decode and persist `IsAdministrator`; the HEIC status probe; one readiness value built from both probes; the onboarding flag and §2's rule; the `targets.first` fallback dropped |
| **O2** | **Built 2026-11-24.** The card itself: fixed height, top bar, pinned footer (§5); step 1, the *How to install* page, the share text, *Check again*, re-check on becoming active |
| **O3** | **Built 2026-11-24.** Step 2: the three rows, Photos access, limited access, the older-photos switch, the Background App Refresh warning |
| **O4** | **Built 2026-11-24**: the way back in from Settings; doc 12 §4. **Left:** doc 13 (the reviewer now meets step 2 after signing in) and the device tests (§8) |

## 6.1 What was built (2026-11-24, O1–O4 in one pass)

**Build green on SERV2** (Xcode 13.2.1, floor 12.2), no warning in the touched files. **Not
yet tested on a device.**

| Where | What |
|---|---|
| `Network/JellyfinModels.swift`, `Auth/Preferences.swift`, `AppServices.swift` | `JellyfinUserPolicy`, `Preferences.isAdministrator`, written at sign-in, cleared at sign-out |
| `Writer/UploadClient.swift` | `heicStatus(completion:)`: 404 → not installed, 401 → the re-auth hook, an undecodable 2xx → unknown |
| `Writer/UploadService.swift` | `HeicStatus`, `BackupAvailability.notConfigured`, the fallback dropped, `needsOnboarding` / `markOnboardingSeen` (key `backupOnboardingSeen`, cleared by `reset`), `localPhotoCount()` |
| `Writer/ServerSetup.swift` (new) | the model: both lines, subtitle, help kind, steps, links, dashboard URL, share text — the page and the shared message read the same `steps` |
| `Writer/OnboardingViewController.swift` (new) | the card: three pages swapped in one fixed-height body, top bar, one pinned button |
| `Design/CardSheetViewController.swift` | `setFixedBodyHeight(_:)`, `sheetSpacing`, `scrollBodyToTop()` (doc 05 §4.1) |
| `Design/FloatingButton.swift` | `ExclamationGlyphView`, `ExternalLinkGlyphView` |
| `Grid/PhotoGridViewController.swift` | offers the card once per grid, after both probes answer; opens it again when Settings asks |
| `Settings/SettingsViewController.swift` | the tappable note; `SettingsNoteView.action` |

Two contact points outside `Writer/` gained lines (the grid, Settings); none was added.

**Departures from the canvas, each forced by the real components:**

- **The top bar is 44 pt, not 32.** It is the base card's header row, and the back disc and
  X are `GlyphButton`s (44 pt targets, 30 pt discs). The sheet spacing drops from 22 to 12
  to pay most of it back.
- **The card is shown only once both probes have answered** — present first and fill later
  would make step 1 appear or vanish under the user's finger, the one thing §5 forbids.
- **The mode rows are the onboarding's own** (`ModeRowView`, private to the file), not
  `OptionRowView`: that one has no description line, fills only the selected row, and
  cannot hold the older-photos switch.
- **The switch's tint is the accent**: black in light, near-white in dark, where the white
  thumb loses some contrast. To look at on the device.

**First device test (5s, step 2 only), and what it changed.** Two layout bugs, both in the
fixed-height mode (doc 05 §4.1): the *Off* row stretched to fill the body, and the *Done*
button was squeezed to 27 pt once Automatic expanded. Both fixed in the base card. The
budget was also wrong by 20 pt — the card has 484 pt on the 5s, not 504 — so the card now
sits 8 pt below its top edge instead of 24, the header/body/footer gaps are 8 pt, and each
page's internal spacing is tighter (step 2: 10 between blocks, 6 between rows). Estimated
content at the default text size against the 340 pt the body gets: Automatic chosen 330,
step 1 with the non-admin subtitle 326, *How to install* 324.

**Second device test (5s and 13 Pro Max on iOS 18, every page), and what it changed.**
Nothing moves between pages on either phone. Two fixes and one copy change:

- The back arrow came back on step 1 after tapping it, visible but dead. `GlyphButton`
  sets its alpha from the highlight, and UIKit clears the highlight *after* running the
  tap's action, so the action's `alpha = 0` was undone. The arrow is now hidden, not faded.
  *Check again* had the same race against its disabled look; its alpha now derives from
  both states.
- The status lines read as a state of the server ("Not installed — shows iPhone photos").
  They now say what the plugin is for: *Not installed — needed to send photos*, *Missing or
  outdated — needed for iPhone photos*. "Outdated" because 1.0.x has no status route and
  answers 404 like an absent plugin; the step now says *install or update* for that case,
  as the table in §3 planned.
- On the 13 Pro Max the footnote under an expanded Automatic sat 11 pt above *Done* and
  14 pt below the rows, so it read as the button's caption. The body-to-footer gap is now
  16 pt (`footerSpacing`, doc 05 §4.1); the header-to-body gap stays 8. That spends 8 of
  the ~11 pt the 5s had left.
- The tallest-page measurement used the plain footnote, so with Background App Refresh off
  the warning fell below the fold. It now measures the footnote Automatic would really
  show. A large phone grows the card to fit; the 5s hits its cap and step 2 scrolls by
  a few points, the button still fixed.

**Known gaps, accepted for now:**

- The Settings note only becomes the way back in when the **upload** plugin is not ready.
  A server where only HEIC is missing has no way back to step 1 from Settings; the Settings
  card does not probe HEIC.
- **Height on the 5s.** The real header costs more than the canvas, so 2b (Automatic
  chosen) and the *How to install* page may scroll by a few points at the default text
  size; the button does not move either way. First thing to measure on the device.

## 7. Settled, and what is left for later

Settled 2026-11-24:

1. **The `targets.first` fallback is dropped.** Uploads only ever go into the browsed
   library; when it is not open for upload, that is "no library is open yet" (1b), named.
2. **The way back in is the Settings backup note.** When the server is not ready, the note
   under the Off/Manual/Automatic control becomes tappable and opens step 1. Nothing new on
   screen when everything is ready.
3. Step 2 is shown with Manual and Automatic disabled when the upload plugin is not ready
   (2c); the deep links are verified (§3); the copy is the canvas's, to re-measure on the 5s.

Later, separately: the force-quit banner (§4), one combined plugin
repository (saves the admin a *Copy* and a paste).

## 8. Device tests

1. Fresh sign-in against a server with both plugins ready: step 2 only; X leaves the mode
   Off and the card never returns.
2. Upload plugin absent, then installed without a ticked library, then ticked: three
   different lines; *Check again* and coming back from Safari both re-check.
3. Server restarting during a check: lines keep their last state.
4. HEIC for Jelly absent, 1.0.x, 1.1 with ffmpeg 6, 1.1 with ffmpeg 7: the four lines.
5. Admin and non-admin accounts: the two instruction shapes; the share sheet's text.
6. *How to install*: each *Copy* puts the right URL on the pasteboard; *Open plugin
   settings* lands on the right dashboard page on 10.11 and on 12; back returns to step 1.
7. Walk every screen: the card height, the title and the button never move — on the 5s
   and on a large phone.
8. Automatic with full, limited and refused Photos access; with the older-photos switch on
   and off; no W6 alert over the card.
9. Background App Refresh off: the warning shows.
10. Re-auth after a token expiry: no card. Sign out and in: the card again.
11. An install that predates this build, mode Off: the card once. Mode Manual: never.
12. The 5s: everything fits on 568 pt, light and dark.
