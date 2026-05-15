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

Create a notarytool keychain profile once:

```bash
xcrun notarytool store-credentials calshot-notary \
  --apple-id "APPLE_ID_EMAIL" \
  --team-id "C2N7W5247T" \
  --password "APP_SPECIFIC_PASSWORD"
```

Then build, submit, staple, and verify:

```bash
CALSHOT_NOTARY_PROFILE=calshot-notary ./script/build_dmg.sh --notarize
```

The notarized artifact is named:

```text
dist/CalShot-<version>-<build>-notarized.dmg
```

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
```

Before publishing, confirm:

- the DMG is notarized and stapled;
- `spctl` accepts the DMG;
- the app launches from the mounted DMG after drag-installing to `/Applications`;
- Calendar and Accessibility prompts refer to the distributed app bundle;
- the review window still opens for an image drop, a selected-text hotkey, and an Outlook `.eml` drop.
