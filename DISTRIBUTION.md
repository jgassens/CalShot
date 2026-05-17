# CalShot Distribution

CalShot ships as a direct-distribution macOS app. The repository keeps
`project.yml` authoritative and generates `CalShot.xcodeproj` locally.

## Bundle Identity

- App bundle ID: `com.jgassens.CalShot`
- Minimum macOS: 14.0
- App type: menu-bar agent (`LSUIElement=true`)
- Signing entitlement highlights:
  - App Sandbox
  - user-selected read-only file access
  - Calendars access
  - outbound network client access for resolving user-provided meeting links
  - Sparkle sandbox installer mach lookup exceptions
- Sparkle feed URL:
  `https://github.com/jgassens/CalShot/releases/latest/download/appcast.xml`

Changing from older local builds with `com.local.CalShot` means macOS may ask
for Calendar or Accessibility permission again. That is expected because macOS
treats the distributed app as a different bundle.

## Build A Local DMG

```bash
./script/build_dmg.sh
```

The script:

1. Regenerates the Xcode project.
2. Runs the test suite.
3. Builds a Release archive.
4. Signs with a Developer ID Application identity when available.
5. Verifies bundle resources, Info.plist keys, entitlements, and code signing.
6. Packages `CalShot.app` plus an `/Applications` symlink into `dist/`.
7. Writes a `.sha256` sidecar for the DMG.

Default signing identity:

```text
Developer ID Application: JEREMIAH JOSEPH GASSENSMITH (C2N7W5247T)
```

Override it when needed:

```bash
CALSHOT_SIGNING_IDENTITY="Developer ID Application: Name (TEAMID)" ./script/build_dmg.sh
```

## Notarize

Create a `notarytool` keychain profile once. Prefer an App Store Connect API key
because it can be scoped and reused without storing an Apple ID password:

```bash
xcrun notarytool store-credentials calshot-notary \
  --key /path/to/AuthKey_KEYID.p8 \
  --key-id "KEYID" \
  --issuer "ISSUER_UUID"
```

If you deliberately use an Apple ID app-specific password instead, use:

```bash
xcrun notarytool store-credentials calshot-notary \
  --apple-id "APPLE_ID_EMAIL" \
  --team-id "C2N7W5247T" \
  --password "APP_SPECIFIC_PASSWORD"
```

Do not commit `.p8` files or local `.notary/` folders to this repository.

Then build, submit, staple, and verify:

```bash
CALSHOT_NOTARY_PROFILE=calshot-notary ./script/build_dmg.sh --notarize
```

The notarized artifact is named:

```text
dist/CalShot-<version>-<build>-notarized.dmg
```

## Sparkle Appcast

CalShot uses Sparkle 2 for direct-distribution updates. The private EdDSA key is
stored in the local login keychain under the account `com.jgassens.CalShot`.
Only the public key is committed in `project.yml`.

The appcast is expected to be uploaded as a GitHub Release asset named
`appcast.xml`. The installed app always checks GitHub's latest-release download
URL, while each appcast item points to the exact release tag that hosts that
version's DMG.

Generate or refresh the appcast after building the notarized DMG:

```bash
CALSHOT_NOTARY_PROFILE=calshot-notary ./script/build_dmg.sh --notarize
./script/generate_appcast.sh \
  --artifact dist/CalShot-<version>-<build>-notarized.dmg \
  --release-tag v<version>
```

Optional release notes can be attached to the same appcast item:

```bash
./script/generate_appcast.sh \
  --artifact dist/CalShot-<version>-<build>-notarized.dmg \
  --release-tag v<version> \
  --release-notes RELEASE_NOTES.md
```

For CI, export the Sparkle private key once and store the resulting text as a
GitHub secret named `CALSHOT_SPARKLE_PRIVATE_KEY`:

```bash
/path/to/Sparkle/bin/generate_keys --account com.jgassens.CalShot -x /private/tmp/calshot-sparkle-private-key.txt
```

Do not commit the exported private key. `script/generate_appcast.sh` will pass
`CALSHOT_SPARKLE_PRIVATE_KEY` to Sparkle through stdin when it is set.

## Local-Only Unsigned DMG

For quick packaging checks on a machine without a Developer ID certificate:

```bash
./script/build_dmg.sh --unsigned
```

Do not distribute unsigned artifacts.

## Release Checklist

```bash
script/bundle_chrono.sh
xcodegen generate
xcodebuild test -scheme CalShot
./script/build_dmg.sh --notarize
./script/generate_appcast.sh --artifact dist/CalShot-<version>-<build>-notarized.dmg --release-tag v<version>
```

Before publishing, confirm:

- the DMG is notarized and stapled;
- `spctl` accepts the DMG;
- `appcast.xml` is generated and signed by Sparkle;
- the GitHub Release contains both the DMG and `appcast.xml`;
- the app launches from the mounted DMG after drag-installing to `/Applications`;
- Calendar and Accessibility prompts refer to the distributed app bundle;
- the review window still opens for an image drop, a selected-text hotkey, and an Outlook `.eml` drop.
