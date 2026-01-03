# ad_flow - AI Coding Agent Instructions

## Project Overview
Flutter package for AdMob integration with GDPR/ATT compliance. Provides banner, interstitial, rewarded, app open, and native ads with consent management via Google's UMP SDK.

## Architecture

### Entry Point & Lazy Managers
`AdFlow.instance` is the singleton entry point. Ad managers are **lazily initialized** (created only on first access):
```dart
AdFlow.instance.banner       // BannerAdManager
AdFlow.instance.interstitial // InterstitialAdManager
AdFlow.instance.rewarded     // RewardedAdManager
AdFlow.instance.appOpen      // AppOpenAdManager
AdFlow.instance.native       // NativeAdManager
AdFlow.instance.consent      // ConsentManager (always available)
```

### Key Files
| File | Purpose |
|------|---------|
| [lib/ad_flow.dart](lib/ad_flow.dart) | Barrel exports (public API surface) |
| [lib/src/ad_service.dart](lib/src/ad_service.dart) | `AdFlow` singleton, `initialize()`, `reset()`, preloading |
| [lib/src/ad_config.dart](lib/src/ad_config.dart) | `AdFlowConfig` + `TestAdUnitIds` with Google test IDs |
| [lib/src/consent_manager.dart](lib/src/consent_manager.dart) | iOS ATT → UMP consent flow (strictly sequential) |
| [lib/src/ads_enabled_manager.dart](lib/src/ads_enabled_manager.dart) | "Remove Ads" via SharedPreferences |
| [lib/src/easy_banner_widget.dart](lib/src/easy_banner_widget.dart) | Reference for self-contained widget pattern |

### Initialization Order (critical)
1. `AdsEnabledManager.initialize()` → loads persisted remove-ads state
2. `ConsentManager.gatherConsent()` → iOS ATT first (if iOS), then UMP form
3. `MobileAds.instance.initialize()` → only if `canRequestAds` is true
4. Preload ads based on `AdFlowConfig` flags

## Development Workflow

```bash
cd example && flutter pub get && flutter run  # Run example app
flutter test                                   # All unit tests
flutter test test/ad_flow_test.dart            # Single test file
```

### Test Isolation Pattern (Required)
Every singleton has a `reset()` method. **Always call in `setUp()`**:
```dart
setUp(() async {
  SharedPreferences.setMockInitialValues({});
  await AdsEnabledManager.instance.reset();
  await AdFlow.instance.reset();
});
```

**Limitation:** `Platform.isAndroid/isIOS` cannot be mocked in pure Dart unit tests—use integration tests for platform-specific paths.

## Code Patterns

### 1. Ad Widget Pattern
All ad widgets must check `AdsEnabledManager` and return empty widget if disabled. See [easy_banner_widget.dart](lib/src/easy_banner_widget.dart):
```dart
_adsEnabled = AdsEnabledManager.instance.isEnabled;
if (!_adsEnabled) return SizedBox.shrink();
```

### 2. Ad Manager Contract
Each manager in `lib/src/*_ad_manager.dart` follows:
- `loadAd()` / `showAd()` → checks `AdsEnabledManager.isDisabled` first, then consent
- Retry with exponential backoff on load failures
- `isLoaded`, `isLoading`, `isShowing` → state getters
- `addStatusListener()` / `removeStatusListener()` → reactive updates
- `dispose()` → cleanup; call **only if manager was accessed**
- `canShowAd` → respects `minInterstitialInterval` cooldown from config

### 3. Error Handling
Subscribe to centralized error stream in [ad_error_handler.dart](lib/src/ad_error_handler.dart):
```dart
AdFlow.instance.errorStream.listen((AdFlowError error) {
  // error.type (AdErrorType enum), error.code, error.message
});
```

### 4. Consent Variants
- `gatherConsent()` → direct system prompts
- `gatherConsentWithExplainer(context)` → shows friendly dialog first

## Critical Rules
1. **Never** call `AdFlow.instance.initialize()` more than once per session
2. **Always** check `consent.canRequestAds` before loading ads
3. Dispose managers **only if accessed** (lazy init saves memory)
4. Keep consent flows **strictly sequential** to prevent popup stacking
5. Add new exports to [lib/ad_flow.dart](lib/ad_flow.dart) barrel file
6. **Disable ads BEFORE initialization**—`onComplete` runs AFTER preloading:
```dart
// ✅ Correct: disable before init, or use conditional flags
await AdFlow.instance.disableAds();
await AdFlow.instance.initializeWithExplainer(preloadAppOpen: true);
```

## Adding New Ad Types
1. Create manager class following [interstitial_ad_manager.dart](lib/src/interstitial_ad_manager.dart)
2. Add lazy getter in [ad_service.dart](lib/src/ad_service.dart) (lines 208-225)
3. Export from [lib/ad_flow.dart](lib/ad_flow.dart) barrel file
4. Include in `disposeAllAds()` and `reset()` methods
5. Write tests following [test/ad_flow_test.dart](test/ad_flow_test.dart) patterns
