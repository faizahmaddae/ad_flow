# ad_flow example

Demonstrates every ad_flow format — anchored adaptive banner, interstitial
(with user-action pacing), rewarded, rewarded interstitial (with the mandatory
intro/skip screen), native (medium template), app open (warm returns, plus the
cold-launch ad on the startup screen) — and the privacy-options entry point,
the Remove-Ads toggle, paid-event logging and the Ad Inspector.

The config lists Google's sample ad units where your IDs would go. Debug runs
serve test ads automatically (no `testMode` needed).

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
(see the package README, *Next-Gen SDK*).
