# 14. Getting a build onto TestFlight

The runbook for the one-time Apple setup behind `workflow_dispatch` with
`sign` + `testflight`. **Why** the pipeline is shaped this way is
`03-xcode-project.md` §5.6; this file is only the *how*, and it is written to be
re-followed from scratch after a certificate expires.

Two facts fixed on 2026-09-28, both worth stating because they were assumptions
before: the Apple Developer Program membership **is** paid and active, and the
`APPLE_PROVISIONING_PROFILE_BASE64` secret **was empty**, so the `sign` branch
had never once executed. Nothing here is undoing an earlier attempt.

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
secret*. (`gh` is not installed on this machine, so this is the web UI.)

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
/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' /tmp/p.plist
/usr/libexec/PlistBuddy -c 'Print :Entitlements:keychain-access-groups' /tmp/p.plist
```

If `ProvisionedDevices` prints, the profile is Development or Ad Hoc. The last
two lines must both show `TEAMID.com.rousseaddict.jellypic` — that is what keeps
the keychain working under the store signature, and its absence is how
`-34018` came back the first time (see `03-xcode-project.md` §5.1).

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

**Not yet measured, as of 2026-09-28: none of this has executed.** The most
likely first failure is the spelling of the altool flags. The man page gives
`--api-key` / `--api-issuer` and documents `--upload-app -f` as an alias of
`--upload-package`; other sources use `--apiKey` / `--apiIssuer`. If the upload
step fails on an unrecognised option, that is the line, and it is a one-word fix.

## 6. Every submission after the first

- `CFBundleVersion` is stamped from `github.run_number`, so build numbers take
  care of themselves. The `1` in the tracked `Info.plist` only ever applies to a
  local SERV2 build.
- `CFBundleShortVersionString` is **not** stamped. It stays `1.0` in
  `Info.plist` until a release deliberately changes it.
- `ITSAppUsesNonExemptEncryption = false` is in the bundle, so no export
  compliance questionnaire appears per upload.
