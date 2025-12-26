# ad_flow - AI Coding Agent Instructions

## Project Overview
A Flutter package for AdMob integration with GDPR/ATT compliance. Provides banner, interstitial, rewarded, app open, and native ads with built-in consent management via Google's UMP SDK.

## Architecture

### Singleton & Lazy Initialization
Entry point: `AdFlow.instance`. Ad managers are **lazily initialized** (created only on first access):
```dart
AdFlow.instance.banner       // BannerAdManager
AdFlow.instance.interstitial // InterstitialAdManager
AdFlow.instance.rewarded     // RewardedAdManager  
AdFlow.instance.appOpen      // AppOpenAdManager
AdFlow.instance.native       // NativeAdManager
AdFlow.instance.consent      // ConsentManager (always available)
```

### Key Files
- [lib/ad_flow.dart](lib/ad_flow.dart) - Barrel exports (public API)
- [lib/src/ad_service.dart](lib/src/ad_service.dart) - `AdFlow` singleton, `initialize()`, `reset()`, preloading
- [lib/src/ad_config.dart](lib/src/ad_config.dart) - `AdFlowConfig`, `TestAdUnitIds` (Google test IDs)
- [lib/src/ad_error_handler.dart](lib/src/ad_error_handler.dart) - `AdFlowError`, `AdFlowErrorHandler` with stream
- [lib/src/consent_manager.dart](lib/src/consent_manager.dart) - iOS ATT → UMP consent (strictly sequential)
- [lib/src/ads_enabled_manager.dart](lib/src/ads_enabled_manager.dart) - "Remove Ads" via SharedPreferences
- [lib/src/easy_banner_widget.dart](lib/src/easy_banner_widget.dart) - Self-contained widget pattern reference

### Initialization Flow (order matters)
1. `AdsEnabledManager.initialize()` - loads persisted remove-ads state
2. `ConsentManager.gatherConsent()` - iOS ATT first (if iOS), then UMP form
3. `MobileAds.instance.initialize()` - only if `canRequestAds` is true
4. Preload ads based on `AdFlowConfig` flags

## Development Workflow

### Running Example/Tests
```bash
cd example && flutter pub get && flutter run  # Example app
flutter test                                   # All unit tests
```

### Test Isolation Pattern
Every singleton has a `reset()` method. **Required** in `setUp()`:
```dart
setUp(() async {
  SharedPreferences.setMockInitialValues({});
  await AdsEnabledManager.instance.reset();
  await AdFlow.instance.reset();
});
```
**Note:** `Platform.isAndroid/isIOS` cannot be tested in pure Dart unit tests - these paths require integration tests or platform mocking.

## Code Conventions

### Configuration
Use `AdFlowConfig.testMode()` during development:
```dart
await AdFlow.instance.initialize(config: AdFlowConfig.testMode());
```

### Widget Pattern (ads-enabled check)
All ad widgets must respect `AdsEnabledManager`. See [easy_banner_widget.dart](lib/src/easy_banner_widget.dart#L40-L45):
```dart
if (AdsEnabledManager.instance.isDisabled) return SizedBox.shrink();
```

### Ad Manager Pattern
Each manager follows this contract (see [interstitial_ad_manager.dart](lib/src/interstitial_ad_manager.dart)):
- `loadAd()` - with retry + exponential backoff
- `isLoaded`, `isLoading`, `isShowing` - state getters
- `addStatusListener()`/`removeStatusListener()` - reactive updates
- `dispose()` - cleanup; call **only if manager was accessed**
- Cooldown: `canShowAd` checks `minInterstitialInterval` from config

### Error Handling
Subscribe to centralized stream (see [ad_error_handler.dart](lib/src/ad_error_handler.dart)):
```dart
AdFlow.instance.errorStream.listen((AdFlowError error) {
  // error.type (AdErrorType enum), error.code, error.message
});
```

### Consent Variants
- `gatherConsent()` - direct system prompts
- `gatherConsentWithExplainer()` - shows friendly dialog first (needs `BuildContext`)

## Platform Setup (when modifying example/)
- **Android:** App ID in `android/app/src/main/AndroidManifest.xml` (`com.google.android.gms.ads.APPLICATION_ID`)
- **iOS:** `GADApplicationIdentifier` + `NSUserTrackingUsageDescription` + SKAdNetwork IDs in `ios/Runner/Info.plist`

## Critical Rules
1. **Never** call `AdFlow.instance.initialize()` more than once per app session
2. **Always** check `consent.canRequestAds` before loading ads
3. Use `Platform.isAndroid/isIOS` for platform-specific ad unit IDs in production `AdFlowConfig`
4. Dispose managers **only if accessed** (lazy initialization saves memory)
5. Keep consent flows **strictly sequential** to prevent popup stacking
