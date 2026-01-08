# ad_flow - AI Coding Agent Instructions

## Project Overview
Flutter package for AdMob integration with GDPR/ATT compliance. Pure Dart wrapper—no native plugin code (relies on `google_mobile_ads`, `app_tracking_transparency`, `shared_preferences`).

## Architecture

### Singleton Entry Point
`AdFlow.instance` with **lazy-initialized** managers (created on first access only):
```dart
AdFlow.instance.banner       // BannerAdManager
AdFlow.instance.interstitial // InterstitialAdManager  
AdFlow.instance.rewarded     // RewardedAdManager
AdFlow.instance.appOpen      // AppOpenAdManager
AdFlow.instance.native       // NativeAdManager
AdFlow.instance.consent      // ConsentManager (separate singleton)
```

### Key Files
| File | Purpose |
|------|---------|
| `lib/ad_flow.dart` | Barrel exports—**add all new public APIs here** |
| `lib/src/ad_service.dart` | `AdFlow` singleton, `initialize()`, `initializeWithExplainer()` |
| `lib/src/ad_config.dart` | `AdFlowConfig`, `TestAdUnitIds`, platform-specific ID helpers |
| `lib/src/consent_manager.dart` | iOS ATT → UMP consent flow (**strictly sequential**) |
| `lib/src/ads_enabled_manager.dart` | "Remove Ads" feature via SharedPreferences |
| `lib/src/mediation_helper.dart` | Forward consent to Unity/AppLovin/Meta/etc |

### Initialization Order (CRITICAL)
```
1. AdsEnabledManager.initialize()     → Load remove-ads state from prefs
2. MediationHelper.registerXxx()      → BEFORE init if using mediation
3. ConsentManager.gatherConsent()     → iOS ATT first, then UMP (sequential!)
4. MediationHelper.forwardConsent()   → Auto-called if adapters registered
5. MobileAds.instance.initialize()    → Only if canRequestAds == true
6. Preload ads per AdFlowConfig flags
```

## Development Workflow
```bash
cd example && flutter run              # Run example app
flutter test                           # All unit tests
flutter test test/ad_flow_test.dart    # Single test file
flutter analyze                        # Lint checks
```

### Test Isolation (MANDATORY)
Every singleton has `reset()`. **Always** call in `setUp()`:
```dart
setUp(() async {
  SharedPreferences.setMockInitialValues({});
  await AdsEnabledManager.instance.reset();
  await AdFlow.instance.reset();
});
```
**Limitation:** `Platform.isAndroid/isIOS` cannot be mocked—skip platform-specific tests in unit tests.

## Code Patterns

### Ad Widget Types
- **Self-contained:** `EasyBannerAd`, `EasyNativeAd` → handle own lifecycle, auto-check `AdsEnabledManager`
- **Manager-based:** `NativeAdWidget(manager: ...)` → receives pre-loaded manager

All widgets return `SizedBox.shrink()` if ads disabled.

### Ad Manager Contract (all `*_ad_manager.dart`)
```dart
// Required state getters
bool get isLoaded;
bool get isLoading;
bool get isShowing;      // fullscreen ads only
bool get canShowAd;      // cooldown check for interstitials

// Required methods
Future<void> loadAd();   // Check AdsEnabledManager.isDisabled first
Future<void> showAd();   // Check AdsEnabledManager.isDisabled first (fullscreen only)
void dispose();

// Reactive updates
void addStatusListener(VoidCallback);
void removeStatusListener(VoidCallback);
void _notifyStatusListeners();          // Private, call after state changes
```
Reference: `lib/src/interstitial_ad_manager.dart`

### Error Handling
Central stream via `AdFlowErrorHandler` singleton:
```dart
AdFlow.instance.errorStream.listen((AdFlowError e) => log(e.message));
// Alternatively:
AdFlow.instance.setErrorCallback((error) => analytics.log(error));
```

## Critical Rules
1. **Never** call `initialize()` more than once per session—check `_isInitialized` early
2. **Disable ads BEFORE init**—`onComplete` callback runs AFTER preloading
3. Dispose managers **only if accessed** (lazy init: check `if (_xxxManager != null)`)
4. Keep consent flows **sequential** (ATT → UMP → MobileAds.init)—never parallelize dialogs
5. Register mediation adapters **BEFORE** `initialize()`
6. App Open ads expire after 4 hours (`appOpenAdMaxCacheDuration`)
7. **Always** export new public APIs from `lib/ad_flow.dart` barrel file

## Adding New Ad Types
1. Create `lib/src/xxx_ad_manager.dart`:
   - Follow `InterstitialAdManager` pattern (status listeners, state getters, retry logic)
   - Check `AdsEnabledManager.isDisabled` at start of `loadAd()`/`showAd()`
   - Use `AdFlowErrorHandler.instance.reportError()` for error reporting
2. Add lazy getter in `lib/src/ad_service.dart`:
   ```dart
   XxxAdManager? _xxxAdManager;
   XxxAdManager get xxx => _xxxAdManager ??= XxxAdManager();
   ```
3. Export from `lib/ad_flow.dart`
4. Update `disposeAllAds()`: `await _xxxAdManager?.dispose();`
5. Update `reset()`: `_xxxAdManager = null;`
6. Write tests with singleton reset in `setUp()`

## Widget Lifecycle Pattern
Self-contained widgets like `EasyBannerAd` follow this pattern:
```dart
@override
void initState() {
  _adsEnabled = AdsEnabledManager.instance.isEnabled;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_adsEnabled) _loadAd();
  });
  AdsEnabledManager.instance.addListener(_onAdsEnabledChanged);
}

@override
void dispose() {
  AdsEnabledManager.instance.removeListener(_onAdsEnabledChanged);
  _bannerManager.dispose();
}
```
