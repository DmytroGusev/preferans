# Release Checklist

## Project

- Set `PRODUCT_BUNDLE_IDENTIFIER`
- Set `DEVELOPMENT_TEAM`
- Set version and build number
- Add all required App Icon images to `AppIcon.appiconset`
- Test on at least one real iPhone
- Archive successfully in Xcode

## Product

- Decide the exact Preferans variant and ruleset being shipped
- Remove mock multiplayer claims if real online play is not ready
- Finalize onboarding/help copy for players unfamiliar with the game

## App Store Connect

- Copy metadata from `Metadata.json`
- Fill in privacy answers using `PrivacyChecklist.md`
- Paste updated review notes from `ReviewNotes.md`
- Upload screenshots described in `ScreenshotPlan.md`
- Provide working support URL, marketing URL, and privacy policy URL

## Submission

- Verify GitHub Pages is enabled for `/docs` on the `main` branch
- Verify no placeholder URLs remain
- Verify no mock features are described as live features
- Verify the binary matches the listed privacy answers
