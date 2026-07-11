# ad_flow example

Demonstrates every ad_flow v2 format using **Google's official test ads**
(`AdFlowConfig.test()`): anchored adaptive banner, interstitial (with
user-action pacing), rewarded, rewarded interstitial (with the mandatory
intro/skip screen), native (medium template), app open (warm starts only),
plus the privacy-options entry point, Remove-Ads toggle, paid-event
logging and the Ad Inspector.

## Run

```sh
flutter run
```

The AdMob **application IDs** in `android/app/src/main/AndroidManifest.xml`
(`com.google.android.gms.ads.APPLICATION_ID`) and `ios/Runner/Info.plist`
(`GADApplicationIdentifier`) are Google's sample IDs — replace them with
your own for a real app. They cannot be set from Dart.

## Next-Gen SDK variant (experimental, Android-only)

The plugin can swap the native Android dependency to the Next-Gen GMA SDK
at build time. Same Dart code, no changes:

```sh
flutter build apk --dart-define=USE_NEXT_GEN_SDK=true
```

iOS ignores the flag. Keep it off in production until Flutter support is GA
(see DECISIONS ADR-010).
