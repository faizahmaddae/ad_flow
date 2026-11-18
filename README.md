# ad_flow

AdMob for Flutter with the policy work done for you — banner, interstitial,
rewarded, rewarded interstitial, native and app open ads, with UMP consent,
iOS ATT in the order App Review expects, frequency caps, retries and revenue
callbacks built in. (The defaults encode AdMob's published policies; your
placements, content and console setup still decide final compliance.)

[![pub package](https://img.shields.io/pub/v/ad_flow.svg)](https://pub.dev/packages/ad_flow)
[![google_mobile_ads](https://img.shields.io/badge/google__mobile__ads-9.x-green.svg)](https://pub.dev/packages/google_mobile_ads)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Built on `google_mobile_ads ^9.2.0` (Android + iOS). Upgrading? Read
[MIGRATION](MIGRATION.md).

- **Consent first.** No ad request before the UMP gate opens and the request
  configuration is applied. GDPR form first, Apple's tracking question last.
- **One line per placement.** `await ads.interstitial?.show()` returns when the
  ad has closed; `AdFlowBanner(adFlow: ads)` reserves its height and owns its
  ad; test ads are automatic in debug builds.
- **Policy-aware defaults.** Interstitials capped and action-paced; app open on
  warm returns (cold launch on request) with the 4-hour expiry; the rewarded
  interstitial intro/skip screen is mandatory by construction.
- **Testable.** `package:ad_flow/ad_flow_testing.dart` ships `FakeAdSdk`.

**Contents:** [Install](#1-install) · [Platform setup](#2-platform-setup) ·
[Quick start](#3-quick-start) · [Formats](#4-formats) ·
[Consent & privacy](#5-consent--privacy) ·
[Remove-Ads & diagnostics](#6-remove-ads-revenue-diagnostics) ·
[Testing](#7-testing) · [Mediation](#8-mediation) ·
[Policy checklist](#9-policy-checklist)

### Set up with AI (copy-paste)

Paste into your assistant (Claude Code, Cursor, …) **inside your project**:

```
Integrate (or upgrade to) the ad_flow Flutter package, version ^6.0.0. Do not guess its API.

1. First read ad_flow's README and MIGRATION.md and its public API
   (package:ad_flow/ad_flow.dart in the pub cache). Use only symbols that exist there.
2. Find every existing ad integration: google_mobile_ads code, an older ad_flow, and any
   wrapper code of mine around it (waiting for an ad to close, mirrored frequency caps,
   privacy-options mirrors, a custom consent/ATT gateway, a launch-ad wait). Show me the list.
3. Replace it with ad_flow 6: non-blocking AdFlow.initialize (never gate the first frame on
   it), AdFlowBanner(adFlow: ads, safeArea: true), `await ads.interstitial?.show()` (returns
   when the ad closes), `ads.interstitial?.canShow`, `ads.appOpen?.showAtLaunch()` from the
   loading screen, test ads left automatic (no testMode), PrivacyOptionsButton in settings.
   Delete the wrapper code ad_flow now covers.
4. Platform setup: Android APPLICATION_ID meta-data; iOS GADApplicationIdentifier,
   NSUserTrackingUsageDescription, SKAdNetworkItems. Remind me to verify app-ads.txt.
5. Ask me for formats and ad unit IDs; keep my existing IDs and caps.
6. Verify: flutter analyze clean, the app builds; tell me every behaviour change.
```

---

## 1. Install

```yaml
dependencies:
  ad_flow: ^6.0.0
```

Requirements (from `google_mobile_ads` 9.2): Flutter ≥ 3.38.1, Dart ≥ 3.10,
iOS 13+, Android `minSdk 24` / `compileSdk 36`. Your Flutter version may
require more (Flutter 3.47 itself needs iOS 15).

**Upgrading an iOS app?** If `pod install` fails with a "higher minimum iOS
deployment version" message, your `ios/Podfile.lock` still pins the old Google
Mobile Ads SDK: run `cd ios && pod update Google-Mobile-Ads-SDK
google_mobile_ads` once and commit the lock.

## 2. Platform setup

### app-ads.txt — do not skip this

AdMob **requires a verified `app-ads.txt`** for full ad serving. Publish one at
`https://your-developer-domain/app-ads.txt` with the line AdMob gives you and
verify it in the AdMob console — otherwise your apps silently under-serve.

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
<key>SKAdNetworkItems</key>
<array>
  <dict>
    <key>SKAdNetworkIdentifier</key>
    <string>cstr6suwn9.skadnetwork</string>  <!-- Google; copy the full list -->
  </dict>
</array>
```

Copy the full, current `SKAdNetworkItems` list from
[Google's iOS quick start](https://developers.google.com/admob/ios/quick-start#update_your_infoplist)
(plus one entry per mediation network): without it iOS cannot attribute
installs for users who did not allow tracking — most users — and your iOS
eCPM drops with no error anywhere. `NSUserTrackingUsageDescription` is
required whenever ATT is asked (iOS terminates the app without it). A custom
`AppDelegate` must adopt the `UISceneDelegate` lifecycle (plugin v9).

The application ID cannot be set from Dart — `AdFlowConfig` carries ad *unit*
IDs only.

## 3. Quick start

```dart
import 'package:ad_flow/ad_flow.dart';
import 'package:flutter/material.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Returns on the next microtask: consent, ATT and SDK init run in the
  // background. Never hold your first frame (or a splash) on it.
  final ads = await AdFlow.initialize(
    const AdFlowConfig(
      banner: BannerConfig(
        adUnitId: PlatformAdUnitId(android: 'ca-app-pub-…/…', ios: 'ca-app-pub-…/…'),
      ),
      interstitial: InterstitialConfig(
        adUnitId: PlatformAdUnitId(android: 'ca-app-pub-…/…', ios: 'ca-app-pub-…/…'),
      ),
    ),
  );
  runApp(MaterialApp(
    navigatorKey: navigatorKey,
    home: Scaffold(
      body: const Placeholder(),
      bottomNavigationBar: AdFlowBanner(adFlow: ads, safeArea: true),
    ),
  ));
}
```

**Test ads are automatic.** While `AdFlowConfig.testMode` is left out, debug
builds serve Google's test ads and release builds serve your IDs, so a
development run never puts your own impressions on live inventory. Test ads
stand in only on the platforms a slot has IDs for, so debug and release agree
on which slots exist. Set `testMode: true` or `false` to force either; with
`testMode: true` a slot may leave its IDs out (`PlatformAdUnitId()`).

The [example](example/lib/main.dart) uses every format.

## 4. Formats

Each full-screen slot is `null` when it is not configured for this platform,
so shared code just uses `?.`. Banner and native placements are widgets, so
they need an ID for the running platform: `AdFlowBanner(adFlow: ads)` and
`AdFlowNativeAd(adFlow: ads)` throw `invalidConfig` where their slot has none.

### Banner

```dart
AdFlowBanner(adFlow: ads, safeArea: true)                 // global banner config
AdFlowBanner(adFlow: ads, config: BannerConfig(adUnitId: …)) // per placement
```

The widget creates and owns its ad, reserves its height before the ad loads
(no layout jump), follows rotation, and collapses to nothing when ads are
disabled. `safeArea: true` keeps a bottom banner clear of the home indicator —
and the inset collapses with the banner. AdMob refreshes banners server-side
(set the rate per ad unit in the console).

| Banner | Height on a phone | Set in `BannerConfig` |
| --- | --- | --- |
| Anchored adaptive, large *(default)* | ~100–150dp, full width | — |
| Anchored adaptive, classic | ~60dp, full width | `anchoredSize: AnchoredBannerSize.classic` |
| Inline adaptive (in scrolling content) | per creative, cap with `maxInlineHeight` | `kind: BannerKind.inlineAdaptive` |
| Fixed IAB size | exact (320×50, 300×250, …) | `kind: BannerKind.fixed, fixedSize: …` |

`backgroundColor:` paints an opaque colour **behind** the slot, for creatives
narrower than an adaptive slot. `placeholderHeight:` overrides the height
reserved before the first ad. Collapsible banners:
`collapsible: CollapsiblePlacement.bottom`.

### Interstitial

```dart
// At a natural break (level end, screen change):
ads.interstitial?.recordUserAction();
final result = await ads.interstitial?.show(); // returns when the ad CLOSES
startNextLevel();
```

`show()` returns an `AdShowResult`: `shown`, or why nothing was shown
(`blockReason`: not ready yet, a frequency cap, consent, Remove-Ads…), or the
SDK `error`. It is preloaded at start and after every close.

`ads.interstitial?.canShow` answers "would `show()` show an ad now?"
synchronously — use it to decide whether to pause for a break, instead of
mirroring the caps yourself. `InterstitialConfig.cap` (default: 30s gap) and
`minActionsBetween` (default 2, active once you call `recordUserAction`) pace
it; `AdFlowConfig.globalFrequencyCap` keeps any two full-screen ads apart.

### Rewarded

```dart
final result = await ads.rewarded?.show(onReward: (reward) {
  wallet.add(reward.amount); // at most once per ad
});
// result?.reward is the same reward, after the ad closed.
```

Rewarded ads are uncapped by default and exempt from the global cap — the user
asked for them. For valuable rewards, verify on your server:
`RewardedConfig(ssv: ServerSideVerification(userId: …))`.

### Rewarded interstitial

```dart
await AdFlow.initialize(
  config,
  rewardedIntroPresenter: RewardedIntroScreen.presenter(navigatorKey),
);
await ads.rewardedInterstitial?.show(onReward: grantReward);
```

AdMob requires an intro screen with the reward and a skip option before the ad;
ad_flow shows it first, always. Copy: `RewardedInterstitialConfig.intro`.

### Native

```dart
AdFlowNativeAd(adFlow: ads)
```

`NativeConfig(templateKind: NativeTemplateKind.small | .medium)` needs no
native code; `factoryId:` uses a platform `NativeAdFactory` —
[doc/NATIVE_ADS_SETUP.md](doc/NATIVE_ADS_SETUP.md). Native ads expire after
55 minutes and reload. A card you wrap around the ad stays visible after
Remove-Ads unless you hide it with `ads.adsEnabled`.

### App open

On a **warm return** (the user comes back to the app) a preloaded ad shows by
itself — never over another full-screen ad, never right after another ad
closes, never on the return from a banner the user tapped, never past the
4-hour expiry.

At **cold launch**, ask for it from your loading screen:

```dart
// Waits up to 3 s for the ad, shows it, returns when it closes.
await ads.appOpen?.showAtLaunch();
navigator.pushReplacement(homeRoute);
```

It returns at once when no consent is stored on the device yet (an EEA user's
first launch, before the GDPR form) or ads are disabled, and it takes the launch
moment only once per process. `AppOpenConfig(showOnResume: false)` makes the
slot launch-only.

## 5. Consent & privacy

`initialize` runs UMP every launch: the consent info update, the GDPR form
where required (EEA, UK, Switzerland), then — on iOS — Apple's tracking
question. **The tracking question always comes last**: App Review rejects an
app whose user answers it and is then shown a consent form asking them to agree
to tracking (Guideline 5.1.1(iv)).

- **ATT, UMP-driven (recommended).** Configure the IDFA message in the AdMob
  console (*Privacy & messaging*). UMP shows it after the GDPR message. No code.
- **ATT, your own primer.** Pass `attExplainer:
  AttExplainerScreen.presenter(navigatorKey)`. ad_flow asks after the GDPR
  flow, never after a GDPR refusal, and never before the form on an offline
  launch. Do not also configure the console IDFA message.
- **Consent primer** (optional, EEA only): `consentExplainer:
  ConsentExplainerScreen.presenter(navigatorKey)`, shown before the form only
  when a form will appear. Localize with `consentExplainerContent` /
  `attExplainerContent`.

Show the privacy-options entry point where users can find it (e.g. Settings);
it appears only when UMP requires it:

```dart
PrivacyOptionsButton(consent: ads.consent)
// or: ads.consent.privacyOptionsRequired (ValueListenable) +
//     ads.consent.showPrivacyOptions()
```

A consent change drops ads loaded under the old answer and reloads them.
Consent failures never throw: an offline launch keeps cached consent, reports
`ads.consent.lastError`, and retries when the network returns.

Children / content: `tagForChildDirectedTreatment`, `tagForUnderAgeOfConsent`
and `maxAdContentRating` on `AdFlowConfig` (no request goes out until they are
applied). Test EEA behaviour with `consentDebug: ConsentDebugOptions(geography:
ConsentDebugGeography.eea, testIdentifiers: ['HASHED-ID'])` — debug only.

## 6. Remove-Ads, revenue, diagnostics

```dart
ads.disableAds();  // Remove-Ads bought (or a remote kill switch): live ads are
                   // dropped, banners/natives collapse, nothing loads
ads.enableAds();
ads.adsEnabled;    // ValueListenable<bool>
ads.canRequestAds; // ValueListenable<bool>: the live consent answer

ads.onPaidEvent = (e) => analytics.logAdImpression(
  value: e.valueMicros / 1e6,
  currency: e.currencyCode,
  adFormat: e.slot,         // 'banner', 'interstitial', …
  adSource: e.adSourceName, // winning mediation network, when known
);

// "Why aren't my ads showing?"
ads.onAdBlocked = (slot, reason) => log.info('ad_flow: $slot — ${reason.name}');
await ads.openAdInspector(); // debug overlay on a test device
```

A refused load is a state of its own (`AdBlocked(reason)`), so a
`ValueListenableBuilder` on a slot's `state` can show it. Most reasons are
normal — a cap doing its job, a user skipping a rewarded intro.

## 7. Testing

```dart
import 'package:ad_flow/ad_flow_testing.dart';

final sdk = FakeAdSdk()..canRequestAdsResult = true;
final ads = await AdFlow.initialize(
  config,
  sdk: sdk,
  store: InMemoryKeyValueStore(),
  platform: AdPlatform.android,
);
await ads.whenReady;     // initialize() returns before consent resolves
await pumpEventQueue();  // let the preloads land

final result = ads.interstitial!.show();
await pumpEventQueue();
sdk.interstitials.single.simulateDismissed();
expect((await result).shown, isTrue);
```

`FakeAdSdk` also models offline consent (`consentUpdateError`), no-fill
(`alwaysLoadError`), hung loads (`loadHold`), and `enforceConsentGate = true`,
which throws if anything requests an ad before consent allows it.

## 8. Mediation

Add the `gma_mediation_*` adapters you use and their partners in the AdMob
console; UMP collects consent for them. Partners that need their own privacy
calls are yours to wire: see [doc/MEDIATION_SETUP.md](doc/MEDIATION_SETUP.md).

Next-Gen SDK (Android, experimental in the plugin): build with
`--dart-define=USE_NEXT_GEN_SDK=true`; ad_flow's API is the same either way.

## 9. Policy checklist

- [ ] `app-ads.txt` published and verified
- [ ] Production ad unit IDs only in `AdFlowConfig`; never click your own live ads
- [ ] Interstitials only at natural breaks (call `recordUserAction`)
- [ ] Banners not flush against tappable controls
- [ ] Privacy-options entry point reachable (e.g. Settings)
- [ ] Rewarded interstitial intro states the reward clearly
- [ ] iOS: `NSUserTrackingUsageDescription` and `SKAdNetworkItems` in `Info.plist`
- [ ] iOS ATT: UMP-driven (console IDFA message) **or** `attExplainer`, never both
- [ ] iOS: nothing of your own asks for tracking before the GDPR form

## License

MIT — see [LICENSE](LICENSE).
