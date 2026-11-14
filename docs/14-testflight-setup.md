# 14. Getting a build onto TestFlight

The runbook for the one-time Apple setup behind `workflow_dispatch` with
`sign` + `testflight`. **Why** the pipeline is shaped this way is
`03-xcode-project.md` §5.6; this file is only the *how*, and it is written to be
re-followed from scratch after a certificate expires.

Two facts fixed on 2026-09-28, both worth stating because they were assumptions
before: the Apple Developer Program membership **is** paid and active, and the
`APPLE_PROVISIONING_PROFILE_BASE64` secret **was empty**, so the `sign` branch
had never once executed. Nothing here is undoing an earlier attempt.

**Executed since.** Store signing ran on 2026-11-10 (run #11), and the first upload
reached TestFlight on 2026-11-11 (run #15, build 1.0 (15), deployment target 15.0).
§5 records what each run measured. The certificate and the profile expire in
November 2027, which is when this runbook is next followed from the top.

**Internal TestFlight testers go through no review at all.** No demo server, no
screenshots, no privacy policy URL — none of the App Store metadata backlog
blocks it. That is the reason to do this before the rest of that backlog: it is
the first path that puts the app on the iOS 15/18/26 devices, which ad-hoc
signing can never reach. External testers need Beta App Review, and that brings
the demo server back.

## 1. Apple side, in this order

At `developer.apple.com/account` → Certificates, Identifiers & Profiles.

### 1.1 App ID

*Identifiers* → `+` → App IDs → App. Description is free text; the Bundle ID
must be **explicit** (not wildcard) and exactly `com.rousseaddict.jellypic`.

**Check nothing in the capability list.** `UIBackgroundModes: fetch` is not a
capability — it needs no entitlement and no App ID configuration. The keychain
access group the app depends on is derived from the App ID automatically; it is
not something to enable.

### 1.2 Distribution certificate

A certificate signing request first. *Keychain Access* → menu **Keychain
Access → Certificate Assistant → Request a Certificate From a Certificate
Authority** → email, any common name, **Saved to disk**. This writes a
`.certSigningRequest` *and* puts the matching private key in the login keychain.
The two halves only ever meet again in step 1.2's export, which is what makes
the trap below possible.

*Certificates* → `+` → **Apple Distribution** → upload the CSR → download the
`.cer` → double-click it to install.

Export: Keychain Access → the **My Certificates** tab → right-click
`Apple Distribution: …` → *Export* → `.p12`, with a password.

> **Export from *Certificates* instead of *My Certificates* and the `.p12` has
> no private key.** Nothing complains: `security import` succeeds,
> `find-identity` then returns nothing, and the job fails much later with
> "No Apple Distribution identity in the imported .p12". If that message appears,
> this is almost always why.

### 1.3 Provisioning profile

*Profiles* → `+` → **Distribution / App Store Connect** → the App ID from 1.1 →
the certificate from 1.2 → download the `.mobileprovision`.

It must be an App Store profile. An Ad Hoc one is the natural mistake here,
since Ad Hoc is what the sideload path has always used, and it signs perfectly
before being rejected at upload. §3 catches it locally.

### 1.4 App record

`appstoreconnect.apple.com` → *Apps* → `+` → New App. iOS, name ≤ 30 characters,
the bundle ID from 1.1, any SKU.

This step is web only: the App Store Connect API refuses to create an app record
(`POST /v1/apps`), whatever the key's role.

### 1.5 App Store Connect API key

ASC → **Users and Access → Integrations → App Store Connect API** → *Team
Keys* → `+` → access role **App Manager** → *Generate*.

- The **Issuer ID** is the UUID printed above the table, shared by all keys.
- The **Key ID** is in the key's row, 10 characters.
- The `.p8` **downloads exactly once.** Lose it and the only remedy is to
  revoke the key and make another.

An API key rather than an Apple ID with an app-specific password: it is
revocable on its own, scoped to a role, and carries no 2FA to work around.

## 2. The six secrets

`github.com/RousseAddict/jellypic/settings/secrets/actions` → *New repository
secret*, or `gh secret set NAME < file` from the repository.

| Secret | Value |
|---|---|
| `APPLE_CERT_P12_BASE64` | `base64 -i dist.p12 \| pbcopy` |
| `APPLE_CERT_PASSWORD` | the password typed during the 1.2 export |
| `APPLE_PROVISIONING_PROFILE_BASE64` | `base64 -i profile.mobileprovision \| pbcopy` |
| `ASC_API_KEY_ID` | the KEY ID column, 10 characters |
| `ASC_API_ISSUER_ID` | the UUID above the table |
| `ASC_API_KEY_P8_BASE64` | `base64 -i AuthKey_XXXXXXXXXX.p8 \| pbcopy` |

Team id and bundle id are deliberately **not** secrets: the workflow reads both
out of the profile, so they cannot drift from it.

## 3. Verify before pasting

The profile check is the same assertion the workflow makes, and running it here
turns a ten-minute round trip into a one-second one:

```sh
security cms -D -i profile.mobileprovision > /tmp/p.plist
/usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' /tmp/p.plist            # must FAIL
/usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' /tmp/p.plist   # must be false
/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' /tmp/p.plist   # TEAMID.com.rousseaddict.jellypic
```

If `ProvisionedDevices` prints, the profile is Development or Ad Hoc.

Do not expect `keychain-access-groups` to name the app. A profile lists what
the app *may* claim, so it always reads `TEAMID.*` (plus `com.apple.token` on
recent profiles). The signing step narrows it to `TEAMID.com.rousseaddict.jellypic`
before `codesign`, the way Xcode does. Signed verbatim, the wildcard risks a
rejection at upload and a keychain with no clear default group, the `-34018`
of `03-xcode-project.md` §5.1. The narrowed signature was accepted at upload
(run #15); what the wildcard would have done was never measured, and no longer
needs to be.

And that the `.p12` actually carries its key:

```sh
openssl pkcs12 -in dist.p12 -nocerts -nodes -legacy | grep -c 'PRIVATE KEY'   # must print 1
```

## 4. The openssl 3 trap

`openssl` on this machine is Homebrew's 3.6.3 at `/usr/local/bin`, not Apple's
LibreSSL. Building the `.p12` with `openssl pkcs12 -export` instead of Keychain
Access therefore defaults to AES-256-CBC with PBKDF2, which `security import`
can refuse. It needs `-legacy`, or explicitly
`-keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1`.

This is the reason §1.2 goes through Keychain Access: its export always produces
something `security` can read back, and the whole signing step runs on
`security`.

## 5. First run

Dispatch on `main` with **`sign` on and `testflight` off** first. That exercises
the certificate, the profile, the entitlements and the identity match, and
produces a signed IPA as an artifact — without consuming a build number or
putting anything in App Store Connect. Separating the two inputs exists for
precisely this run.

Then dispatch again with both on. `--validate-app` runs before `--upload-app`,
so a server-side rejection still costs nothing.

**What the first runs measured**, 2026-11-10 and 11:

| Run | Inputs | Result |
|---|---|---|
| #11 | `sign` | signed IPA; entitlements narrowed to the app, Distribution chain complete, `get-task-allow` false, `CFBundleVersion` 11 |
| #13 | `sign` + `testflight`, target 12.2 | refused at validation, nothing consumed: *ITMS-90068: iOS apps must target iOS version from 13 to 27.3* |
| #14 | target typed as `15` | the workflow's own minimum-version check failed: `15` against the binary's `15.0`. The check now compares major and minor |
| #15 | `sign` + `testflight`, target 15.0 | `VERIFY SUCCEEDED`, `UPLOAD SUCCEEDED`, build 1.0 (15) |

Three questions this settled:

- **The altool flags are `--api-key` / `--api-issuer` with `--upload-app`**, on
  Xcode 26.6. The camel-case spellings some sources give were never needed.
- **No secure timestamp is accepted.** `codesign` without `--timestamp=none` still
  signed with a plain `Signed Time`, not a `Timestamp`, and validation passed.
- **The store refuses a floor below 13**, and warns that 15.0 becomes the minimum in
  April 2027. Store builds therefore target 15.0, the `deployment_target` default;
  the 5s sideload stays at 12.2. See `18-app-store-submission.md` §5.

## 6. Every submission after the first

- `CFBundleVersion` is stamped from `github.run_number`, so build numbers take
  care of themselves. The `1` in the tracked `Info.plist` only ever applies to a
  local SERV2 build.
- `CFBundleShortVersionString` is **not** stamped. It stays `1.0` in
  `Info.plist` until a release deliberately changes it.
- `ITSAppUsesNonExemptEncryption = false` is in the bundle, so no export
  compliance questionnaire appears per upload.
- `deployment_target` stays at **15.0** for anything uploaded (§5).
- An internal group created with access to all builds receives each new build
  without a step in App Store Connect. A TestFlight build expires 90 days after
  upload.
