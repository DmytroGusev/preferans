# Fastlane Screenshots

This folder is prepared for uploading screenshots to App Store Connect with Fastlane.

Manual upload is still the simplest path:

1. Open App Store Connect.
2. Open the Preferans app version.
3. Go to the iPhone 6.5-inch screenshot slot.
4. Upload the PNG files from `AppStore/Screenshots/iPhone-6.5`.

Automatic upload requires Fastlane plus Apple authentication:

```sh
brew install fastlane
fastlane ios upload_screenshots
```

If Apple ID login is blocked by 2FA/session issues, create an App Store Connect API key and configure Fastlane with that key before running the lane.

