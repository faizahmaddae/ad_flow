# Native Ads with ad_flow (v2)

ad_flow supports both of the plugin's native-ad rendering paths:

| Path | Native code needed | When to use |
|------|--------------------|-------------|
| **Templates** (`NativeConfig.templateKind`) | none | Default. Google's small/medium templates, styled from Dart. |
| **Platform factories** (`NativeConfig.factoryId`) | yes (Kotlin/Swift) | Full custom layout control. |

Provide **exactly one** of `templateKind` or `factoryId`.

## Path A — templates (no native code)

```dart
final ads = await AdFlow.initialize(AdFlowConfig(
  nativeAd: const NativeConfig(
    adUnitId: PlatformAdUnitId(android: 'ca-app-pub-…/1', ios: 'ca-app-pub-…/2'),
    templateKind: NativeTemplateKind.medium, // or .small
  ),
));
```

```dart
class _MyScreenState extends State<MyScreen> {
  late final _native = ads.native(); // create ONCE, never inside build()

  @override
  Widget build(BuildContext context) =>
      AdFlowNativeAd(controller: _native, ownsController: true);
}
```

`AdFlowNativeAd` reserves the template's minimum height up front (small ≈ 90,
medium ≈ 320 logical px; override with `placeholderHeight`), loads through the
consent/config gate like every other format, and disposes the controller with
the widget when `ownsController` is true. Native ads never auto-refresh; call
`controller.reload()` if you want a new one.

## Path B — platform factories (custom layouts)

1. Implement a `NativeAdFactory` per layout on each platform and register it
   with the plugin under a **factory ID**. This is plain `google_mobile_ads`
   machinery — ad_flow adds nothing on the native side — so follow Google's
   guide, which includes complete Kotlin/Swift/XML examples:
   <https://developers.google.com/admob/flutter/native/platform-views>

   Registration happens in `MainActivity`/`AppDelegate`, e.g. (Android):

   ```kotlin
   GoogleMobileAdsPlugin.registerNativeAdFactory(
     flutterEngine, "myFactoryId", MyNativeAdFactory(context)
   )
   ```

2. Point the slot at the factory:

   ```dart
   nativeAd: const NativeConfig(
     adUnitId: PlatformAdUnitId(android: '…', ios: '…'),
     factoryId: 'myFactoryId',
     factoryExtras: {'accentColor': '#FF6B35'}, // optional, passed through
   ),
   ```

3. Host it exactly as in Path A (`AdFlowNativeAd`); pass `placeholderHeight`
   matching your layout (the default reservation for factory rendering is
   100 logical px).

## Policy notes (native ads have their own rules)

- The ad must be **clearly distinguishable** from your content: the AdChoices
  icon and the "Ad" attribution must remain visible and unobstructed (the
  templates handle this; factory layouts must).
- Render every asset the network marks required; do not alter or crop
  Google-served assets.
- Keep tap targets honest — no layouts that invite accidental clicks.

Full policy: <https://support.google.com/admob/answer/6329638>

## Diagnostics

- On a test device the **native ad validator** overlays the rendered ad and
  reports implementation issues.
- `controller.lastBlockReason` / `ads.onAdBlocked` answer "why isn't it
  showing"; `controller.response` reports which network filled it.
