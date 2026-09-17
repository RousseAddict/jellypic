# jellypic

iPhone photo backup + Photos-like browsing on top of a self-hosted Jellyfin.
Two halves, built separately: **Reader** (iOS browse app) and **Writer** (uploader/ingest).
Design notes in `docs/`.

## Layout

```
build.sh  CLAUDE.md  docs/
jellypic/                        <- PROJECT_DIR
  jellypic.xcodeproj/
    project.pbxproj              hand-written, no XcodeGen/Tuist (zero deps)
    xcshareddata/xcschemes/      REQUIRED: xcodebuild -scheme needs a *shared* scheme
  jellypic/
    AppDelegate.swift  RootViewController.swift
    Info.plist  LaunchScreen.storyboard  Assets.xcassets/
```

`LaunchScreen.storyboard` is load-bearing, not cosmetic: without it iOS runs the app
letterboxed in a legacy-sized window on anything newer than an iPhone 8.

## Build

```sh
./build.sh                                   # sync + build on SERV2 -> ~/Desktop/jellypic.ipa
CONFIGURATION=Release ./build.sh             # release build
DEPLOYMENT_TARGET=15.0 ./build.sh            # raise the floor
SYNC=0 ./build.sh                            # build SERV2's copy as-is
BUILD_HOST= ./build.sh                       # build on this machine (CI runner)
```

Every setting is an env var: `PROJECT_NAME SCHEME CONFIGURATION DEPLOYMENT_TARGET
ARCHS SDK SIGN_IDENTITY DEVELOPER_DIR REMOTE_BASE OUTPUT_IPA BUILD_HOST BUILD_PASS
SYNC LOCAL_PROJECT_DIR`. `BUILD_HOST=` (empty) switches from ssh to a local build —
that is the CI path.

**This repo is the source of truth. SERV2 is only a build slave**, synced by rsync on
every run. Never edit on SERV2: it is not under git and the next build overwrites it.

**No credentials in tracked files.** `BUILD_PASS` comes from the environment, or from
`.env.local` (gitignored, `chmod 600`, sourced automatically by `build.sh`). The script
refuses to run rather than fall back to a default. `sshpass` is invoked as
`-eSSHPASS` — attached, never `-p`, which would expose the password in `ps` output.

## CI

`.github/workflows/build.yml`, one job on `macos-26` (Xcode 26.6, arm64):

| Entry point | Result |
|---|---|
| push to `main` | ad-hoc signed, automatic |
| manual, any branch | ad-hoc signed — dispatch on a PR's head branch to build that PR |
| manual on `main` + `sign: true` | same build, re-signed with the Apple certificate |

**The build is identical in all three cases; signing is a single trailing step.**
The certificate is therefore exposed to exactly one step, and the signed IPA comes
from the very binary verified in the step above it. Never move signing earlier or
split it across steps.

CI reuses `build.sh` with `BUILD_HOST=` and `REMOTE_BASE=$GITHUB_WORKSPACE` — the
same script as local development, no duplicated build logic.

**No third-party actions.** Importing a signing certificate through unaudited
third-party code is not acceptable; the keychain work is plain `security` calls.
Only `actions/checkout` and `actions/upload-artifact` (first-party) are allowed.

Secrets: `APPLE_CERT_P12_BASE64`, `APPLE_CERT_PASSWORD`,
`APPLE_PROVISIONING_PROFILE_BASE64`. Entitlements, team id and bundle id are read
out of the provisioning profile itself, so they cannot drift from it.

## Toolchain reality

| | value |
|---|---|
| Build machines | SERV2 + this Mac, both **macOS 11** |
| Xcode | **13.2.1**, SDK ceiling **iOS 15.2** |
| Deployment floor | **iOS 12.0** (iPhone 5s, test device) |
| Daily devices | iOS 15, 18, soon 26 |

Xcode 26 requires macOS 15+, so **CI is the only route to a modern SDK**. Until then
no API above iOS 15 exists, whatever device the app runs on.

Deployment-target floors, verified 2026-09-16: Xcode 13 → iOS 9 · Xcode 26 → **iOS 12
still allowed** (type it manually, the UI only offers 15+) · Xcode 27 → **iOS 15, below
is rejected outright**. So the 12.0 floor survives the move to Xcode 26 and only dies
at Xcode 27 — by which point the 5s is out of scope anyway.

No Swift-runtime patching here (unlike the iOS 6 apps in `~/Documents/ios6-app/`):
no `-toolchain`, no dylib swap, no `vtool -set-version-min`. The Swift ABI ships in
the OS since iOS 12.2; below that Xcode embeds the runtime itself.

## Legacy plumbing

The iOS 12 floor is a **test-device concession**, not an architecture. Keep everything
it forces on us in named, swappable seams so the migration is a delete, not a rewrite.

**Mark every such site with `// LEGACY(ios12):` + the version that frees it.** One
`grep -rn "LEGACY(ios12)"` must return the entire migration surface. No exceptions.

What the floor actually costs, and where it must stay contained:

| Constraint | Freed at | Containment rule |
|---|---|---|
| No `async/await` (Swift Concurrency back-deploys only to 13) | iOS 13 | All completion handlers live behind the `JellyfinAPI` protocol. Call sites never see a closure-based API — swapping in an `async` impl must touch one file. **This is the main irritant; guard it hardest.** |
| No SwiftUI | iOS 13 | UIKit only. Not pure debt: see below. |
| No SwiftData | iOS 17 | Core Data behind a `PhotoStore` protocol. |
| No `.navigationTransition(.zoom)` | iOS 18 | Hand-rolled `UIViewControllerAnimatedTransitioning`, one file. |

**Not** legacy debt, do not "fix" these on migration:
- **`UICollectionView` for the grid** is the correct permanent choice — `LazyVGrid`
  degrades past ~10k items, and this library is meant to exceed that.
- **`UIScrollView` in a pinch-zoom view** — SwiftUI still has no native equivalent;
  Photos itself does this.
- **`URLCache` / `NSCache`** — fully available on iOS 12, zero compromise.

Availability policy: the SDK ceiling makes it *impossible* to reference an iOS 16+ API
today, so there is no risk of accidental use. When the SDK rises, add capability behind
`if #available(iOS 17/18)` — **do not raise the floor to get a feature.** The floor
moves only when a toolchain forces it.

## Migration checklist

1. **CI on Xcode 26** — `BUILD_HOST= DEVELOPER_DIR=…/Xcode-26.app/… ./build.sh`.
   Keep `DEPLOYMENT_TARGET=12.0`. Nothing in the legacy table changes yet; the win is
   SDK 26, so `if #available` enhancements become possible for the iOS 18/26 devices.
   Expect the legacy (non-Liquid-Glass) appearance on iOS 26 — that is the SDK link
   version talking, and is fine for a sideload.
2. **Xcode 27 forces the floor to 15.0** — the 5s drops out. Now `grep LEGACY(ios12)`
   and clear it: async/await client, SwiftData or keep Core Data, native transitions.
3. Keep the grid and the zoom scroll view. They were never the compromise.

## Conventions

**No comments in the Xcode project.** Not in the Swift sources, not in `Info.plist`,
not in the storyboards. No doc comments, no `///`, no section banners, no
explanatory prose. Code must read on its own; if it cannot, rename things or split
the function.

The single exception is `// LEGACY(ios12):` markers — they are load-bearing, since
`grep -rn "LEGACY(ios12)"` is the migration surface. Keep them to one line and put
the reasoning in `docs/`.

Anything worth remembering goes in `docs/` as a reference, not in the code. Project
rationale lives in `docs/03-xcode-project.md`. `build.sh` is exempt: it is tooling,
not the app, and stays documented inline.

**Commits carry no co-author trailer.** No `Co-Authored-By:`, no "Generated with"
footer, no tool attribution of any kind. Commit messages are the change and its
reason, nothing else.

- Zero third-party dependencies. `URLSession`, `URLCache`, `NSCache`, Core Data, UIKit.
- Jellyfin auth header (10.11+): `Authorization: MediaBrowser Token="…", Client="…",
  DeviceId="…", Version="…"`. `X-Emby-*` is legacy and can be disabled server-side.
- Sort photos on `PremiereDate`, never `DateCreated` — see `docs/` for why.
- Logout must `POST /Sessions/Logout` before wiping local state.
