# ad_flow

Easy, policy-compliant AdMob integration for Flutter — banner, interstitial,
rewarded, rewarded interstitial, native and app open ads, with UMP consent,
frequency capping, retry with backoff, and revenue callbacks built in.

[![pub package](https://img.shields.io/pub/v/ad_flow.svg)](https://pub.dev/packages/ad_flow)
[![google_mobile_ads](https://img.shields.io/badge/google__mobile__ads-9.x-green.svg)](https://pub.dev/packages/google_mobile_ads)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

v2 is a ground-up rewrite on `google_mobile_ads ^9.0.0`. Coming from 1.x?
Read [MIGRATION](MIGRATION.md).

**What you get for free:**

- **Consent first, always.** No ad loads before the UMP gate opens
  (GDPR/EEA form, ATT coordination, privacy-options entry point).
- **Policy-safe defaults.** App open only on warm starts with the 4-hour
  expiry; interstitials frequency-capped and action-paced; the rewarded
  interstitial intro/skip screen is mandatory by construction; banners
  reserve their height so layouts never shift.
- **Revenue-minded plumbing.** Every full-screen format keeps one ad warm
  (load → show → reload on dismiss); failed loads retry with exponential
  backoff + jitter and re-arm after a cooldown; `onPaidEvent` reports
  impression-level revenue.
- **Testable.** Everything runs behind an `AdSdk` seam;
  `package:ad_flow/ad_flow_testing.dart` ships `FakeAdSdk` so you can unit
  test your integration without a device.

---

## 1. Install

```yaml
dependencies:
  ad_flow: ^2.0.0
```

Requirements (from `google_mobile_ads` 9.x): Flutter ≥ 3.38.1, Dart ≥ 3.10,
iOS 13+, Android `minSdk 24` / `compileSdk 36`.

## 2. Platform setup

### app-ads.txt — do not skip this

Since January 2025 AdMob **requires a verified `app-ads.txt`** for full ad
serving. Publish one at `https://your-developer-domain/app-ads.txt` with the
line AdMob gives you, and verify it in the AdMob console — otherwise your
apps silently under-serve.

### Android

`android/app/src/main/AndroidManifest.xml`, inside `<application>`:

```xml
<meta-data
    android:name="com.google.android.gms.ads.APPLICATION_ID"
    android:value="ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY"/>
```

### iOS

`ios/Runner/Info.plist`:

```xml
<key>GADApplicationIdentifier</key>
<string>ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY</string>
<key>NSUserTrackingUsageDescription</key>
<string>This identifier will be used to deliver personalized ads to you.</string>
```

Recent Flutter templates are already scene-based; if you maintain a custom
`AppDelegate`, adopt the `UISceneDelegate` lifecycle (required by the v9
plugin).

The application ID **cannot** be set from Dart — `AdFlowConfig` carries ad
*unit* IDs only.

## 3. Initialize

```dart
final navigatorKey = GlobalKey<NavigatorState>();

// During development: Google's sample ads for every format.
final ads = await AdFlow.initialize(
  AdFlowConfig.test(),
  rewardedIntroPresenter: (content) =>
      RewardedIntroScreen.show(navigatorKey.currentContext!, content),
);
```

Production config — only configured slots ever load:

```dart
final ads = await AdFlow.initialize(
  AdFlowConfig(
    banner: const BannerConfig(
      adUnitId: PlatformAdUnitId(android: 'ca-app-pub-…/1', ios: 'ca-app-pub-…/2'),
    ),
    interstitial: const InterstitialConfig(
      adUnitId: PlatformAdUnitId(android: 'ca-app-pub-…/3'),
      cap: FrequencyCap(minGap: Duration(seconds: 30), maxPerHour: 6),
      minActionsBetween: 2,
    ),
    rewarded: const RewardedConfig(adUnitId: PlatformAdUnitId(android: 'ca-app-pub-…/4')),
    appOpen: const AppOpenConfig(adUnitId: PlatformAdUnitId(android: 'ca-app-pub-…/5')),
    globalFrequencyCap: const FrequencyCap(minGap: Duration(seconds: 15)),
    testDeviceIds: ['YOUR-HASHED-DEVICE-ID'],
  ),
);
```

`initialize` builds the whole graph synchronously and **returns immediately** —
consent gathering, the Ads SDK init and request configuration all run in the
**background**. Nothing loads before the consent gate opens (invariant 1), so
it is safe to render at once; the app-open manager starts and every configured
full-screen format preloads once the gate resolves.

**Never block your first frame on `AdFlow.initialize()`.** Render your real UI
immediately; ads, consent and ATT appear over it:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final ads = await AdFlow.initialize(myConfig, /* presenters… */);
  runApp(MyApp(ads: ads)); // the await resolves instantly — never a network wait
}
```

The `await` completes on the next microtask (graph construction only), so the
first frame is never delayed by consent/network. If you genuinely need to know
when the consent gate has resolved, `await ads.whenReady` (`Future<bool>` = the
gate result) — but it is **not** required for normal use, and you should not
gate UI on it. Do **not** wrap your app in a `FutureBuilder<AdFlow>` that shows
a spinner until consent finishes (that was v1's splash-hang pain on weak
connections). See [example/lib/main.dart](example/lib/main.dart).

Set `testMode: true` (or use `AdFlowConfig.test()`) during development —
it swaps every **configured** slot to Google's sample IDs. Never ship it.

## 4. Formats

### Banner

```dart
class _MyScreenState extends State<MyScreen> {
  // Create the controller ONCE, as a field — never inside build().
  late final _banner = ads.banner();

  @override
  Widget build(BuildContext context) => Scaffold(
        bottomNavigationBar: SafeArea(
          child: AdFlowBanner(controller: _banner, ownsController: true),
        ),
        // ...
      );
}
```

> **Never create ad controllers inside `build()`.** Each `ads.banner()` /
> `ads.native()` call mints a fresh controller and starts a new ad load, so
> building one in `build()` restarts the load — and blanks the ad — on every
> rebuild (e.g. every `setState`). Hoist each to a `late final` `State`
> field and reference the field, as above.

Anchored adaptive by default (Google's revenue recommendation); the widget
reserves its height from the first frame so content never shifts under a
loading ad. Inline adaptive, fixed sizes and collapsible banners are
configured via `BannerConfig(kind:, fixedSize:, collapsible:)`. Refresh is
client-driven every `minRefresh` (≥ 60s recommended, values under 30s are
clamped).

Adaptive banners have no pure-width height formula — Google documents
50–90dp depending on device and width. `AdFlowBanner` reserves a
device-height-aware estimate (15% of screen height, clamped to that
50–90dp range) rather than a flat guess, but if you already know the real
height for a placement (e.g. from a previous load), pass it explicitly via
`placeholderHeight` to eliminate any residual shift entirely.

### Interstitial

```dart
// At natural break points (level end, screen change):
ads.interstitial.recordUserAction();
await ads.interstitial.show();
```

Preloaded at init and after every dismissal. `show()` is a no-op (returns
false) while consent is closed, a cap is active, another full-screen ad is
visible, or — once you start calling `recordUserAction()` — fewer than
`minActionsBetween` actions happened since the last interstitial.

### Rewarded

```dart
await ads.rewarded.show(onReward: (reward) {
  wallet.add(reward.amount); // fires at most once per ad
});
```

High-value rewards: set `RewardedConfig.ssv` for server-side verification.

### Rewarded interstitial

```dart
await ads.rewardedInterstitial.show(onReward: grantReward);
```

AdMob policy requires an intro screen with clear reward messaging and a
skip option before the ad plays. ad_flow enforces this by construction:
the `rewardedIntroPresenter` you pass to `initialize` runs first, and the
ad shows only if the user didn't skip. `RewardedIntroScreen.show` is the
ready-made presenter; customize copy via `RewardedInterstitialConfig.intro`.

### Native

```dart
// Create the controller ONCE, as a State field (never inside build()):
late final _nativeAd = ads.native();

// ...then in build():
AdFlowNativeAd(controller: _nativeAd, ownsController: true)
```

Template rendering (`NativeConfig(templateKind: NativeTemplateKind.small | .medium)`)
needs no native code. For fully custom layouts register a platform
`NativeAdFactory` (see the [official guide](https://developers.google.com/admob/flutter/native/platforms))
and use `NativeConfig(factoryId: 'yourFactoryId')`.

### App open

Nothing to call. The `AppOpenAdManager` (started by `initialize`) shows a
preloaded ad when the app returns to the foreground — never on cold launch,
never over another full-screen ad, never past the 4-hour expiry (stale ads
are discarded and reloaded). To show on cold start from a dedicated splash
gate, set `AppOpenConfig(showOnColdStart: true)`.

## 5. Consent & privacy

UMP runs inside `initialize`. GDPR requires a persistent "Manage consent"
entry point when applicable:

```dart
PrivacyOptionsButton(consent: ads.consent) // renders nothing when not required
```

Consent failures never throw from `initialize` — the flow degrades to the
SDK's own `canRequestAds()` answer and surfaces the failure on
`ads.consent.lastError`.

### ATT (iOS App Tracking Transparency) — two modes

- **UMP-driven (default).** Pass no `attExplainer`. On iOS, UMP drives the
  ATT explainer and system prompt for you — configure the IDFA message in
  AdMob's *Privacy & messaging*. `ad_flow` makes no ATT calls itself.
- **Client-driven (opt-in, like v1).** Pass an `attExplainer` (below). Then
  `ad_flow` runs your own ATT primer → a short delay (200 ms, Apple's
  guidance) → Apple's system prompt, **before** the GDPR flow. In this mode
  do **not** also configure the UMP IDFA message in the AdMob console — that
  would double-prompt.

Either way, add `NSUserTrackingUsageDescription` to `Info.plist`.

### Consent & ATT explainers (priming)

Opt-in priming screens — the v2 equivalent of v1's `initializeWithExplainer`,
decoupled from `BuildContext` via the same presenter pattern as the
rewarded-interstitial intro. Show your own localizable screen explaining what
the next system dialog will ask; the real UMP form / ATT prompt always
follows. The consent primer appears **only when a form will actually show**
(non-EEA users never see it). Everything is additive — pass nothing and
behaviour is exactly as before.

```dart
final navigatorKey = GlobalKey<NavigatorState>();
// ...MaterialApp(navigatorKey: navigatorKey, ...)

final ads = await AdFlow.initialize(
  myConfig,
  // iOS: your ATT primer → 200 ms → Apple's system prompt, before GDPR.
  attExplainer: (content) async {
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await AttExplainerScreen.show(context, content);
  },
  // Shown before the GDPR form (EEA only).
  consentExplainer: (content) async {
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await ConsentExplainerScreen.show(context, content);
  },
  // Optional: localize / customize the copy.
  // attExplainerContent: const AttExplainerContent(title: 'Autoriser le suivi ?'),
);
```

`AttExplainerScreen` and `ConsentExplainerScreen` are ready-made; pass your
own presenter to use custom UI, keeping it context-safe (the package never
holds a `BuildContext` — the callback resolves it). `skipConsentPrimerIfAttDenied`
(default true) skips the optional consent *primer* when the user just denied
ATT. It never suppresses the GDPR form itself: a required consent form
(EEA/UK/CH) is always shown, because ATT (Apple) and GDPR (EU) are independent
regimes — denying tracking does not satisfy GDPR consent.

Testing EEA behavior:

```dart
await AdFlow.initialize(config, consentDebug: const ConsentDebugOptions(
  geography: ConsentDebugGeography.eea,
  testIdentifiers: ['YOUR-HASHED-DEVICE-ID'],
));
```

## 6. Remove-Ads, revenue, inspector

```dart
ads.disableAds();   // user bought Remove-Ads: every load/show is blocked
ads.enableAds();
ads.adsEnabled;     // ValueListenable<bool> — hide ad widgets reactively

ads.onPaidEvent = (e) =>
    analytics.logAdRevenue(e.valueMicros / 1e6, e.currencyCode);

await ads.openAdInspector(); // debug overlay on a test device
```

## 7. Testing your integration

```dart
import 'package:ad_flow/ad_flow_testing.dart';

final sdk = FakeAdSdk()..canRequestAdsResult = true;
final ads = await AdFlow.initialize(
  config,
  sdk: sdk,
  store: InMemoryKeyValueStore(),
  platform: AdPlatform.android,
);
await ads.interstitial.show();
sdk.interstitials.single.simulateDismissed(); // drive SDK behavior
```

## 8. Next-Gen SDK (experimental, Android-only)

The v9 plugin can swap its native Android dependency to Google's Next-Gen
GMA SDK at build time — same Dart API, no code changes:

```sh
flutter build apk --dart-define=USE_NEXT_GEN_SDK=true
```

iOS ignores the flag. It is experimental in Flutter; keep it off in
production until Google declares Flutter support GA.

## 9. Mediation

Add the official `gma_mediation_*` adapter packages to your app, register
the partners in AdMob's *Privacy & messaging* for consent forwarding, and —
on iOS — add the partners' `SKAdNetworkItems` to `Info.plist`. Mediation
needs no ad_flow changes; adapters raise fill and eCPM transparently.

## 10. Policy compliance checklist

- [ ] `app-ads.txt` published and verified (required since Jan 2025)
- [ ] Production ad unit IDs only in `AdFlowConfig`; `testMode` off
- [ ] Never click your own live ads; use test ads / registered test devices
- [ ] Interstitials only at natural breaks (`recordUserAction` pacing on)
- [ ] Banners not flush against tappable controls
- [ ] App open not combined with a banner on the same surface
- [ ] Privacy-options button reachable (e.g. in settings)
- [ ] Rewarded interstitial intro copy states the reward clearly
- [ ] iOS: IDFA message configured in AdMob console

## License

MIT — see [LICENSE](LICENSE).
