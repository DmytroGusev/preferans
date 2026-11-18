# Google Ads install attribution for Preferans iOS

Scope: measure acquisition campaigns for Preferans, not serve in-game ads.
Keep Firebase's existing opt-in, no-IDFA setup and do not add AdMob, ATT,
remarketing, user-provided data measurement or advertising identifiers.

## Ready before an Ads account exists

- Preferans's dedicated GA4 property is `561600345`; Firebase project
  `guru-preferans-20261030`; iOS bundle `com.mixandmatch.preferans`; App Store ID
  `6763581975`. Do not link a different Guru of Cards property.
- The SDK emits the built-in iOS `first_open` key event after analytics opt-in.
  A previous simulator QA run received it in GA4. Do not create a second event
  for the same first open or send simulated conversions to Google Ads.
- The signed build 34 contains the dedicated Firebase configuration. The IPA
  guard verified its signature, all eight collection defaults off, and no
  ATT/IDFA symbols, tracking declarations or advertising-framework links.
- Keep the QA environment separate from live campaign reporting. A TestFlight
  first open tests the event path, not attribution to a paid App Store install.

## After the owner has an Ads account

1. Identify the individual Google Ads customer ID for Preferans. Use a Google
   Ads admin and GA4 editor/admin. Do not link a multi-client manager account
   by default; its clients may gain access to shared data.
2. In the Preferans GA4 property, use Admin > Product links > Google Ads links.
   Turn **Enable Personalized Advertising** off before linking. Keep Google
   Signals, remarketing audiences and user-provided data off; do not change
   settings in other properties or create a campaign.
3. In that Google Ads customer account, create/import the conversion action
   for Preferans iOS's existing Firebase/GA4 `first_open` only. Check that no
   duplicate first-open conversion is counted. A custom SKAdNetwork value
   schema is not part of this installs-only setup.
4. Check the resulting data flow and disclosures before spending. Apple privacy
   postbacks and modeled conversions have limits; app analytics for players who
   decline are not collected. The app denies ad storage, ad user data, and
   ad personalization; this can limit click-ID keyed export and bidding.
   Only a live, separately approved campaign against the released app can
   verify campaign-attributed installs. Do not enable identifiable advertising
   export if reporting is sparse.

No account was linked, no conversion was imported and no spend was authorized.
On 16 November 2026 the GA4 link list had zero completed or pending links.

References: [Google Ads links](https://support.google.com/analytics/answer/9379420),
[mobile app conversions](https://support.google.com/google-ads/answer/16056245),
[Firebase key events](https://support.google.com/analytics/answer/13128484),
[consent effects](https://support.google.com/google-ads/answer/13802165).
