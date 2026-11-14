# 18 — App Store submission: the listing, the review risks, and where each item stands

The other parts of a submission each have a home: the bundle's compliance is
`03-xcode-project.md` §5, the signing and upload runbook is `14-testflight-setup.md`,
the review notes and the demo server are `13-app-review-notes.md`, and the privacy policy
is `PRIVACY.md`, linked in the app as described in `09-settings-and-maintenance.md` §6.
This file holds the rest: everything App Store Connect asks for that is not in the
binary, the guidelines that bite a client for a self-hosted server, and a checklist
of where each item stands.

Sources: the App Review Guidelines, read against the binary on 2026-09-27 and again,
as revised on 2026-10-16, on 2026-11-13; three Jellyfin clients already on the store
(Swiftfin, Finamp, Jellyfin Mobile), surveyed on 2026-09-28, and Immich, the closest
analogue, on 2026-11-13; Apple's screenshot specification, upcoming requirements and
App Store Connect help, and Jellyfin's branding page, all read on 2026-11-13.

## 1. Where things stand (2026-11-13)

| Item | State | Where |
|---|---|---|
| Bundle compliance: floor, iPhone only, privacy manifest, icon, export compliance, no embedded Swift | done, asserted by CI | 03 §5 |
| Build numbers | done, from the CI run number | 03 §5.6 |
| Store signing and TestFlight upload | done: run #11 signed, run #15 uploaded build 1.0 (15) | 14 §5 |
| Internal TestFlight testing | build available to an internal group; an install from TestFlight is not recorded yet | 14 §6 |
| Privacy policy | done, `PRIVACY.md` | §3.2 |
| Privacy policy linked in the app | built, not yet tried on a device | 09 §6 |
| Support URL | decided | §3.2 |
| App record | exists, named Jellypic | 14 §1.4 |
| **The name itself** | **open decision**: Jellyfin's branding page discourages "Jelly[word]" | §2.1 |
| Subtitle, category, age rating answers | decided below, not entered | §2.1, §2.2 |
| Copyright, content rights, review contact | to enter | §2.5 |
| Description, promotional text, keywords | drafted below, not entered | §2.3 |
| Screenshots | not made | §2.4 |
| App Privacy label | decided, not entered | §3.1 |
| **EU trader status** | **open decision**, required even without EU distribution | §3.3 |
| Accessibility Nutrition Labels | optional for now; left empty | §2.5 |
| Device tests the review depends on | not done | §4 |
| Review notes | drafted, waiting for the server | 13 §3 |
| Demo server | parked since 2026-09-26 | 13 §2, §4 |

Everything above the review notes can be done without the demo server. The two open
decisions come first: the name appears everywhere else in the listing, and an app with
no trader status is removed from the EU storefronts.

## 2. The listing

### 2.1 Name and subtitle

**Name: Jellypic** (the limit is 30 characters).

**Subtitle** (30 characters): *Photos on your Jellyfin server*.

The primary source is Jellyfin's own branding page
(`jellyfin.org/docs/general/contributing/branding`, undated, read 2026-11-13): *"You may
reference Jellyfin in a subtitle, description, etc. as an indication of
interoperability"*, while *"3rd party developers should not use the name Jellyfin
directly."* The subtitle above is exactly that kind of reference.

The precedents agree. Swiftfin's subtitle is "A native Jellyfin
client"; Finamp, which is a third party and not the Jellyfin project, uses "Jellyfin
Music Player"; and third-party apps carry it in their name ("Finy - Jellyfin Client",
"Phyn: Jellyfin Media Player"). **The line not to cross is claiming to be official**
(guideline 5.2.1). Swiftfin's description says it is "an official Jellyfin companion
app", but Swiftfin and Jellyfin Mobile are published by the Jellyfin project itself.
Jellypic says the opposite, in the description and in the README.

**The name is an open decision.** The same page says: *"we discourage projects from
using the combination of "Jelly[word]" or "[word]fin" to avoid confusion"*. Jellypic is
that pattern exactly. It is a request, not a prohibition, and Apple does not enforce
it — but it is the project's stated wish, and a rename costs least before the first
public release. The options: keep it, rename, or ask the Jellyfin team. The icon is
clear of the same page: it forbids their logo's shape, *"rotate[d]"* or *"inside of
another logo"*, and *"permit[s] the use of our colour gradient"*; ours is six petals,
not their triangle.

### 2.2 Category and age rating

- **Primary category: Photo & Video.** The video clients choose Entertainment, Finamp
  chooses Music: each picks what it shows.
- **Age rating: 4+**, like all three Jellyfin clients and Immich. Apple revised the
  questionnaire in 2025: the tiers are now 4+, 9+, 13+, 16+ and 18+, and existing apps
  had to answer the new questions by 31 January 2026. The answers:

| Question | Answer | Why |
|---|---|---|
| Parental controls, age assurance (in-app controls) | No | none in the app |
| Unrestricted web access | **No** | see below |
| User-generated content | No | no sharing between users in the app; the content is the user's own server's |
| Social media, messaging and chat, advertising | No | none |
| Mature themes, medical, sexuality or nudity, violence, chance-based | None | the app ships no content |

  **Unrestricted web access is the one judgement.** Answering yes means 16+; Apple's
  definition is *"Users can navigate to any webpage within the app or freely browse the
  web. May include: embedded browser functionality."* The app has no browser: the
  privacy-policy sheet opens one fixed page. But that page is GitHub's, and a user can
  follow its links outwards. Apple has published no ruling on that case; the answer is
  No, and this paragraph is the reasoning if review asks.

### 2.3 Description, promotional text, keywords

The description's first lines follow the official Jellyfin app's wording almost word
for word. That is the clearest answer to guideline 2.3.1 (the listing must not promise
something the user cannot get): the app is useless without a server, so the listing
says so before anything else. Backing up depends on a plugin, so the description says
that too.

> To use Jellypic, you need a Jellyfin server set up and running. Find out more at
> https://jellyfin.org.
>
> Jellypic shows the photos on your own Jellyfin server the way the Photos app shows
> your camera roll, and backs your iPhone's photos up to it.
>
> BROWSE
> • One timeline of your whole library, sorted by when each photo was taken, with month
>   headers and a scrubber. Built for libraries of tens of thousands of photos.
> • Pinch to zoom, see when, where and with which camera a photo was taken, and share
>   the optimised image or the original file.
> • Watch your videos: played directly when your iPhone can, converted by your server
>   when it cannot.
> • See your photos on a map.
> • Delete a photo from your server, if your Jellyfin account is allowed to.
>
> BACK UP
> • Manual: pick the photos to send. Automatic: new photos are sent in the background,
>   even with the app closed.
> • Originals are sent untouched — a HEIC stays a HEIC — and nothing is sent twice.
> • Wi-Fi only.
> • Backing up needs the free Upload for Jelly plugin on your server. Showing HEIC
>   photos needs the free HEIC for Jelly plugin.
>
> PRIVATE BY DESIGN
> Jellypic has no account of its own, no analytics and no ads. Your photos go to your
> server and nowhere else.
>
> Jellypic is an independent app. It is not made or endorsed by the Jellyfin project.

**Promotional text** (170 characters, editable without a new build):

> Your Jellyfin photo library, as easy to browse as your camera roll — and your
> iPhone's photos backed up to your own server.

**Keywords** (100 characters, comma-separated):

> backup,self-hosted,selfhosted,gallery,home server,nas,camera roll,timeline,map,heic,private

Words already in the name or subtitle ("photos", "Jellyfin") earn nothing in the
keywords and are left out. So are other products' names: guideline 2.3.7 forbids them,
however natural "Google Photos alternative" would be.

### 2.4 Screenshots

Apple's specification, checked on 2026-11-13:

- **Required: at least one screenshot for "iPhone with Dynamic Island (medium
  display)"**, 1179 × 2556 or 1206 × 2622 pixels in portrait.
- "iPhone with Face ID (large display)", 1284 × 2778 or 1242 × 2688, is "required if
  app runs on iPhone and screenshots for iPhone with Dynamic Island (large display)
  aren't provided" (1260 × 2736, 1290 × 2796 or 1320 × 2868).
- Up to 10 per size, PNG or JPEG, no alpha channel. App Store Connect scales a set
  down to smaller devices, never up.
- No iPad set: the app is iPhone only (03 §5.3). The 5s's 640 × 1136 is one of the
  smallest groups, which can only ever be filled by scaling down: it cannot be the
  set a submission is made with.

**Screenshots do not need the demo server.** Apple wants the app in use, not the app
connected to *the* demo. The practical route is a TestFlight install on a Dynamic
Island iPhone, signed in to your own server. Two cautions follow from that:

- **The photos become public.** Use photos you are happy to publish, ideally without
  other people's faces.
- **The Settings header prints the server's address.** Leave it out of a screenshot,
  or sign in through an address you would publish anyway.

A set that shows every feature in seven images: the grid with month headers and the
scrubber; a photo in the viewer; the details card; the map; a video with its play
button; Settings with the Backup section; the connect card.

### 2.5 The other fields

- **Copyright** — required and public: *"The name of the person or entity that owns
  the exclusive rights to the app, preceded by the year"*. The `LICENSE` holder is jf;
  the field takes whatever legal name the account wants shown.
- **Content rights** — *"Apps that contain, show, or access third-party content must
  have all the necessary rights."* Answer: no third-party content. The app ships none;
  what it shows is the user's own server's.
- **App Review contact** — a name, an email, and a phone number in international `+`
  format. Seen by App Review only.
- **Sign-in information** — the demo account from 13 §3, which *"must not expire"*.
- **Notes** — up to 4000 bytes, which 13 §3 fits.
- **Accessibility Nutrition Labels** — *"voluntary to start"*, mandatory later with no
  date announced. Left empty: without them the page says the developer *"hasn't
  indicated support yet"*, which is the honest state — the app carries two
  `accessibilityLabel`s in total, so claiming VoiceOver support would be false.

## 3. Privacy in App Store Connect

### 3.1 App Privacy label: Data Not Collected

Apple's definition of "collect" is transmitting data off the device in a way that the
developer or its partners can access beyond servicing the request in real time.
Jellypic transmits to the user's own server — the device identifier and the iPhone's
name included — and never to the developer. Map tiles come from Apple, and Apple's
page says: *"You are not responsible for disclosing data collected by Apple."*

This is a judgement, not an obvious call, and the two apps the Jellyfin project
publishes disagree: Swiftfin declares *Data Not Collected*; Jellyfin Mobile declares
*Device ID, not linked to identity*. Jellypic does what Swiftfin does, so it declares
what Swiftfin declares — as do Immich and Nextcloud, both self-hosted clients. The label, `PRIVACY.md` and the privacy manifest's empty
`NSPrivacyCollectedDataTypes` (03 §5.4) must keep saying the same thing.

### 3.2 URLs

| Field | Value |
|---|---|
| Privacy Policy URL | `https://github.com/RousseAddict/jellypic/blob/main/PRIVACY.md` |
| Support URL | `https://github.com/RousseAddict/jellypic/issues` |
| Marketing URL (optional) | `https://github.com/RousseAddict/jellypic` |

This is Finamp's arrangement: its privacy policy is a `PRIVACY.md` on GitHub, linked
as the rendered page, and its support is the issue tracker. The repository is public
and issues are enabled; both are conditions for these URLs to work.

The rendered page was kept over `raw.githubusercontent.com`, which serves the Markdown
as plain text with no mobile layout. GitHub Pages would give a lighter page with no
GitHub cookies, if that ever matters; it is a repository setting, and the address
lives in `SettingsViewController` and in this table.

### 3.3 EU trader status (Digital Services Act)

Required of every developer since 17 February 2025: *"Apps without trader status will
be removed from the App Store in the European Union (EU) until trader status is
provided and verified"*, and *"Even if you don't distribute apps in the EU, you'll still
need to declare a trader status."*

- **Not a trader:** *"This is not a trader account. You won't need to provide any
  contact information."* EU customers are told that consumer-protection law does not
  apply to the purchase.
- **Trader:** the address (or P.O. box), phone number and email are published on the
  product page in the 27 EU countries.

*"Apple can't determine whether you're a trader."* A free hobby app with no revenue
plausibly is not one, but that is the account holder's legal call, not a technical
one — **open decision**.

## 4. The guidelines that bite a self-hosted client

| Guideline | The risk here | The answer | State |
|---|---|---|---|
| 2.1 App completeness | the reviewer has no Jellyfin server | a demo server and the notes that hand it over; a demo mode is not an option (below) | parked (13) |
| 2.3.1(a) Notes for review | *"generic descriptions will be rejected"* | 13 §3 walks through every feature by name | drafted |
| 2.5.5 IPv6 | review runs on an IPv6-only network with NAT64/DNS64 | a host name in the notes; an AAAA record on the demo server | notes fixed (13 §3) |
| 2.5.19 Hidden features | *"Don't include any hidden, dormant, or undocumented features"* (added 2026-10-16) | nothing hidden; rules out a secret demo-mode trigger | done |
| 2.3.1 Accurate metadata | Backup needs a plugin the reviewer may not have | said in the description and in the notes | open (13 §4) |
| 4.2 Minimum functionality | a client of a server the reviewer cannot see reads as empty | a live demo with real content | depends on the server |
| 5.1.1(i) Privacy policy | must be in App Store Connect *and* in the app | `PRIVACY.md`, Settings › About | done |
| 5.1.1(iv) Refused permissions | the app must stay usable with every permission refused | browsing needs no photo access | not tested on a device |
| 5.2.1 Intellectual property | "Jellyfin" in the listing | descriptive only, never "official" | done in the drafts |
| 2.5.4 Background modes | `UIBackgroundModes` must be used | `fetch` drives automatic backup | done |
| 2.5.1 Public APIs | private API use | grepped clean (no `NSClassFromString`, `performSelector`, `dlopen`…) | done |
| 1.5 Support | a working support URL | the issue tracker | done |

**2.5.5 in detail.** The guideline itself says only *"Apps must be fully functional on
IPv6-only networks."* The review network comes from Apple's IPv6 guide: an IPv6-only
network with DNS64/NAT64. On it, a host name works through the AAAA record DNS64
synthesises, and — corrected 2026-11-13, an earlier version of this section said the
opposite — so does a *public* IPv4 address, because *"NSURLSession and CFNetwork
automatically synthesize IPv6 addresses from IPv4 literals locally"* since iOS 9. A
private LAN address cannot work, but only because Apple cannot reach a LAN. The notes
still give a name: it is stable, it is what an https certificate needs (13 §3), and an
AAAA record keeps NAT64 out of the path altogether. What remains to test is the app's
own address handling, below.

**A demo mode instead of a demo server is not open to this app.** Guideline 2.1(a):
*"If you are unable to provide a demo account due to legal or security obligations, you
may include a built-in demo mode in lieu of a demo account with prior approval by
Apple."* Jellypic has no such obligation, only no server; a demo mode could not show
Backup or the real network path; and a hidden way into one would break 2.5.19. Immich,
the closest analogue, publishes a public demo server instead. For a feature that is
hard to replicate — Backup, if the demo server does not carry the plugin — the App
Review page sanctions *"a demo video"* as a complement.

Device tests the review depends on, none done yet:

1. An IPv6 literal typed into the connect screen (`[2001:db8::1]`), against
   `ServerURL.isPrivate`'s bracket handling.
2. Photo access refused outright: browsing works, Backup explains itself.
3. Limited photo access: whether `smartAlbumUserLibrary` returns the selected subset
   (12 §15).
4. Settings › About on the 5s (09 §6).
5. The whole walkthrough of 13 §3 on the latest released iOS, through TestFlight:
   *"Your app will be tested on a device running the latest released version of iOS."*

Not applicable, checked against the guidelines' text: all of 3.x (payments), 1.2 (user
generated content), 2.5.2 (downloaded code), 2.5.18 (ads), and 5.1.1(v) (account
deletion), since the app cannot create an account.

## 5. The store build is not the sideload build

**App Store Connect refuses a 12.2 floor.** Measured on 2026-11-11 (run #13), at the
validation step, so nothing was consumed: *ITMS-90068: iOS apps must target iOS version
from 13 to 27.3*, with the warning *Starting in April 2027, iOS apps must target 15.0
or later*. Apple's upcoming-requirements page dates the rule: since 9 September 2026,
uploads must target iOS 13 or later. Jellyfin Mobile ships on the store at 12.4, which
proved nothing about today's upload rule.

The SDK side is already met: since 28 April 2026 uploads must be built with Xcode 26
and an iOS 26 SDK, and CI builds with Xcode 26.6 and the iOS 26.5 SDK.

So there are two floors:

| Build | Floor | Where it is set |
|---|---|---|
| Store (CI, push and dispatch) | **15.0** | `build.yml`, `deployment_target` input, default `15.0` |
| Sideload for the 5s (SERV2) | **12.2** | `build.sh`, `DEPLOYMENT_TARGET` default |

No code changes between the two: every `#available` check is at 13 or 14, so at 15.0
they are only warnings. The 12.2 in `CLAUDE.md` and in 03 §5.2 is the floor of the
source and of the sideload, not of the store. A CI artifact built from a push is at
15.0, so it does not install on the 5s; dispatch with `deployment_target` 12.2 for that.

## 6. TestFlight: internal and external testers

**Internal testers go through no review**, which is why TestFlight came first: it is
the first route onto the iOS 15, 18 and 26 iPhones that ad-hoc signing cannot reach,
and it needs neither the demo server, nor screenshots, nor the listing.

**External testers need Beta App Review.** App Store Connect asks for test
information — a beta app description (required), a feedback email, the review contact
and sign-in details of §2.5 — so the demo server becomes a blocker there exactly as it
is for the store.

## 7. Coming

- **April 2027:** store builds must be built with the **iOS 27 SDK** and target 15.0
  or later (*"iOS and iPadOS apps must be built with the iOS & iPadOS 27 SDK or later,
  and target iOS 15 or later"*). The target is already the CI default; the SDK means
  Xcode 27 on the runner.
- **April 2027:** iPhone Duo screenshots become required for apps built with the iOS
  27.1 SDK or later (screenshot specification, 2026-11-13).
- **April 2027, through the SDK rule above: the `UIScene` lifecycle.** TN3187: *"In
  the next major release following iOS 26, UIScene lifecycle will be required when
  building with the latest SDK; otherwise, your app won't launch."* The iOS 27 SDK
  becomes mandatory for uploads in April 2027, so that is the deadline for store
  builds. The app still uses the pre-`UIScene` lifecycle (03 §4). A scene manifest is
  ignored on iOS 12, so this can be adopted without touching the sideload floor.
- **Later, no date announced:** Accessibility Nutrition Labels become mandatory.
- **November 2027:** the distribution certificate and the App Store profile expire.
  14 is written to be re-followed from scratch.
- **Every TestFlight build expires 90 days after upload.**

## 8. Order of the remaining work

0. Decide the name (§2.1) and the trader status (§3.3).
1. Enter what is decided: subtitle, category, age rating answers, the other fields,
   App Privacy label, URLs (§2.1–§2.5, §3).
2. Enter the description, promotional text and keywords (§2.3).
3. The device tests in §4, on the 5s and on a TestFlight install.
4. Screenshots from a TestFlight install on a Dynamic Island iPhone (§2.4).
5. The demo server, then the review notes' placeholders, then the Backup decision
   (13 §2–4).
6. Submit.
