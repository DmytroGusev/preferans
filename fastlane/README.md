# Fastlane Screenshots

This folder is prepared for uploading screenshots to App Store Connect with Fastlane.

Manual upload is still the simplest path:

1. Open App Store Connect.
2. Open the Preferans app version.
3. Go to the iPhone 6.5-inch screenshot slot.
4. Upload the PNG files from `AppStore/Screenshots/iPhone-6.5`.

Automatic upload requires Fastlane plus Apple authentication:

```sh
ASC_ISSUER_ID="YOUR-ISSUER-ID" fastlane ios upload_screenshots
```

The lane is configured for:

- Bundle ID: `com.mixandmatch.preferans`
- Key ID: `BQR53J468H`
- Key path: `/Users/dmytrogusev/Downloads/AuthKey_BQR53J468H.p8`

The lane uses `force: true` and disables precheck so screenshot uploads work in non-interactive API-key mode.

