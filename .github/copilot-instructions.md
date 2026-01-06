# ad_flow - AI Coding Agent Instructions

## Project Overview
Flutter package (v1.3.9) for AdMob integration with GDPR/ATT compliance. Pure Dart—no native plugin code (relies on `google_mobile_ads`, `app_tracking_transparency`, `shared_preferences`).

## Architecture

### Entry Point
`AdFlow.instance` singleton with **lazy-initialized** managers (created on first access only):
```dart
AdFlow.instance.banner       // BannerAdManager
AdFlow.instance.interstitial // InterstitialAdManager  
AdFlow.instance.rewarded     // RewardedAdManager
AdFlow.instance.appOpen      // AppOpenAdManager
AdFlow.instance.native       // NativeAdManager
AdFlow.instance.consent      // ConsentManager
```

### Key Files
| File | Purpose |
|------|---------|
| [lib/ad_flow.dart](lib/ad_flow.dart) | Barrel exports—add new public APIs here |
| [lib/src/ad_service.dart](lib/src/ad_service.dart) | `AdFlow` singleton, `initialize()`, `initializeWithExplainer()` |
| [lib/src/ad_config.dart](lib/src/ad_config.dart) | `AdFlowConfig`, `TestAdUnitIds`, platform ID helpers |
| [lib/src/consent_manager.dart](lib/src/consent_manager.dart) | iOS ATT → UMP consent flow (strictly sequential) |
| [lib/src/ads_enabled_manager.dart](lib/src/ads_enabled_manager.dart) | "Remove Ads" feature via SharedPreferences |
| [lib/src/mediation_helper.dart](lib/src/mediation_helper.dart) | Forward consent to Unity/AppLovin/etc |
| [doc/NATIVE_ADS_SETUP.md](doc/NATIVE_ADS_SETUP.md) | Platform factory code (Kotlin/Swift) |
| [doc/MEDIATION_SETUP.md](doc/MEDIATION_SETUP.md) | Mediation integration guide |

### Initialization Order (critical)
1. `AdsEnabledManager.initialize()` → load remove-ads state
2. `MediationHelper.registerXxxWithCallbacks()` → BEFORE init (optional)
3. `ConsentManager.gatherConsent()` → iOS ATT first, then UMP
4. `MediationHelper.forwardConsent()` → auto-called if adapters registered
5. `MobileAds.instance.initialize()` → only if `canRequestAds`
6. Preload ads per `AdFlowConfig` flags

## Development Workflow

```bash
cd example && flutter run          # Example app (with/without explainer variants)
flutter test                       # All unit tests
flutter test test/ad_flow_test.dart # Single test file
```

### Test Isolation (REQUIRED)
Every singleton has `reset()`. Always call in `setUp()`:
```dart
setUp(() async {
  SharedPreferences.setMockInitialValues({});
  await AdsEnabledManager.instance.reset();
  await AdFlow.instance.reset();
});
```

**Platform Limitation:** `Platform.isAndroid/isIOS` cannot be mocked in pure Dart unit tests.

## Code Patterns

### Ad Widget Pattern
All widgets check `AdsEnabledManager` first, return `SizedBox.shrink()` if disabled:
- **Self-contained:** `EasyBannerAd`, `EasyNativeAd` (handle own lifecycle)
- **Manager-based:** `NativeAdWidget(manager: ...)` (receives pre-loaded manager)

### Ad Manager Contract
Each `*_ad_manager.dart` follows:
- `loadAd()`/`showAd()` → checks `AdsEnabledManager.isDisabled` first
- State: `isLoaded`, `isLoading`, `isShowing`, `canShowAd`
- Reactive: `addStatusListener()`/`removeStatusListener()`
- Retry with exponential backoff (`AdFlowConfig.maxLoadRetries`)
- Cooldown: `minInterstitialInterval` (default 30s)

### Error Handling
```dart
AdFlow.instance.errorStream.listen((AdFlowError e) => debugPrint(e.message));
```

## Critical Rules
1. **Never** call `initialize()` more than once per session
2. **Disable ads BEFORE init**—`onComplete` runs AFTER preloading
3. Dispose managers **only if accessed** (lazy init saves memory)
4. Keep consent flows **sequential** (ATT → UMP → MobileAds.init)
5. Register mediation adapters BEFORE `initialize()`
6. App Open ads expire after 4 hours (`appOpenAdMaxCacheDuration`)
7. Add new exports to [lib/ad_flow.dart](lib/ad_flow.dart) barrel

## Adding New Ad Types
1. Create manager in `lib/src/*_ad_manager.dart` following [interstitial_ad_manager.dart](lib/src/interstitial_ad_manager.dart):
   - Status listeners, state getters, consent/enabled checks, retry logic
2. Add lazy getter in [ad_service.dart](lib/src/ad_service.dart)
3. Export from [lib/ad_flow.dart](lib/ad_flow.dart)
4. Add to `disposeAllAds()` and `reset()` (dispose only if `_field != null`)
5. Write tests with singleton reset in `setUp()`
