# CalShot Agent Notes

## Project Shape
- CalShot is a native macOS menu-bar agent app built from `project.yml` with XcodeGen.
- `project.yml` is authoritative. `CalShot.xcodeproj/` is generated locally and should remain untracked.
- This project needs local macOS/Xcode validation. Do not treat Codex cloud/container runs as sufficient for GUI behavior.

## Build And Test
- Bundle Chrono after dependency changes: `script/bundle_chrono.sh`
- Generate the Xcode project: `xcodegen generate`
- Run tests: `xcodebuild test -scheme CalShot`
- Build and launch the staged app bundle: `./script/build_and_run.sh --verify`
- Working app bundles are staged in `dev/` after local builds, with the default debug app at `dev/CalShot.app`.
- Generate deterministic OCR smoke images: `./script/generate_smoke_images.sh`
- Run the realistic OCR smoke suite through the real app bundle: `./script/smoke_images.sh`
- Launch one smoke image through the real app bundle: `./script/build_and_run.sh --image build/SmokeImages/01_university_seminar_flyer.png`
- Build a distributable DMG: `./script/build_dmg.sh`
- Build, notarize, staple, and verify a release DMG: `CALSHOT_NOTARY_PROFILE=<keychain-profile> ./script/build_dmg.sh --notarize`
- Distribution builds use bundle ID `com.jgassens.CalShot` and should be signed with a Developer ID Application certificate.

## Sparkle Versioning
- Before committing and pushing changes that may be released from `main`, increment `CFBundleVersion` in `project.yml`. Sparkle only treats a build as an update when the appcast build number is greater than the installed app's build number.
- Increment `CFBundleShortVersionString` for user-facing releases when appropriate; otherwise keep the marketing version stable and only bump `CFBundleVersion`.
- After changing either version, run `xcodegen generate` so `Resources/Info.plist` stays in sync with `project.yml`.
- For a release, build/notarize the DMG, run `script/generate_appcast.sh --artifact <dmg> --release-tag <tag>`, then upload both the DMG and `appcast.xml` to the matching GitHub Release.

## Product Rules
- Keep OCR and parsing local. Do not add cloud OCR, LLM calls, or telemetry.
- Network access is limited to resolving user-provided event links so shortened URLs can become direct Teams/Zoom/Meet/Webex links.
- Do not log full OCR text in release builds.
- Use EventKit write-only access and the default calendar only. Do not add a calendar picker unless full-access mode is explicitly accepted later.
- Menu-bar icon drag/drop is the first post-Phase 0+1 input surface; route it through the same OCR/review pipeline as Open Image and clipboard image.
- Keep shelf, hotkey capture, ScreenCaptureKit, and Duckling out until explicitly requested.
