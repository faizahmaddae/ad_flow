# ad_flow - AI Coding Agent Instructions

## Project Overview
Flutter package (v1.3.7) for AdMob integration with GDPR/ATT compliance. Provides banner, interstitial, rewarded, app open, and native ads with consent management via Google's UMP SDK and iOS ATT (App Tracking Transparency).

**Package Type:** Pure Dart package - no native plugin code (relies on `google_mobile_ads`, `app_tracking_transparency`, `shared_preferences`).

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

**Memory Optimization:** Managers only instantiated when accessed → only dispose managers that were actually used.

### Key Files & Responsibilities
| File | Purpose | Key APIs |
|------|---------|----------|
| [lib/ad_flow.dart](lib/ad_flow.dart) | Barrel exports (public API surface) | All public classes/functions |
| [lib/src/ad_service.dart](lib/src/ad_service.dart) | `AdFlow` singleton, initialization orchestration | `initialize()`, `initializeWithExplainer()`, `reset()` |
| [lib/src/ad_config.dart](lib/src/ad_config.dart) | Configuration + test IDs | `AdFlowConfig`, `TestAdUnitIds`, `AdFlowConfig.current` |
| [lib/src/consent_manager.dart](lib/src/consent_manager.dart) | iOS ATT → UMP consent flow (strictly sequential) | `gatherConsent()`, `canRequestAds`, `canShowAds` |
| [lib/src/ads_enabled_manager.dart](lib/src/ads_enabled_manager.dart) | "Remove Ads" IAP feature via SharedPreferences | `enableAds()`, `disableAds()`, `isEnabled` |
| [lib/src/mediation_helper.dart](lib/src/mediation_helper.dart) | Forward consent to mediation networks (Unity, AppLovin, etc.) | `registerAdapter()`, `forwardConsent()` |
| [lib/src/app_lifecycle_reactor.dart](lib/src/app_lifecycle_reactor.dart) | WidgetsBindingObserver for app open ads on resume | `startListening()`, `maxForegroundAdsPerSession` |
| [lib/src/easy_banner_widget.dart](lib/src/easy_banner_widget.dart) | Self-contained widget pattern reference | `EasyBannerWidget` |
| [lib/src/native_ad_widget.dart](lib/src/native_ad_widget.dart) | Native ad widgets (manager-based & self-contained) | `NativeAdWidget`, `EasyNativeAdWidget` |
| [doc/NATIVE_ADS_SETUP.md](doc/NATIVE_ADS_SETUP.md) | Platform-specific native ad factory setup (Kotlin/Swift) | Factory registration patterns |
| [doc/MEDIATION_SETUP.md](doc/MEDIATION_SETUP.md) | AdMob mediation integration guide (Unity, AppLovin) | Step-by-step setup, API reference |

### Initialization Order (critical)
1. `AdsEnabledManager.initialize()` → loads persisted remove-ads state from SharedPreferences
2. `MediationHelper` → register adapters BEFORE init (optional, for mediation networks)
3. `ConsentManager.gatherConsent()` → **iOS ATT prompt first** (if iOS), then UMP consent form
4. `MediationHelper.forwardConsent()` → auto-called if adapters registered
5. `MobileAds.instance.initialize()` → only if `canRequestAds` is true
6. Preload ads based on `AdFlowConfig` flags (interstitial, rewarded, app open)

## Development Workflow

### Running & Testing
```bash
# Run example app (2 variants: with/without explainer)
cd example && flutter pub get && flutter run

# Unit tests (all)
flutter test

# Single test file
flutter test test/ad_flow_test.dart

# Coverage (if needed)
flutter test --coverage
```

**Example App Structure:** [example/lib/main.dart](example/lib/main.dart) exports one of two examples:
- `example_with_explainer.dart` - Shows friendly dialog before ATT/UMP (recommended for GDPR)
- `example_without_explainer.dart` - Direct consent prompts

### Test Isolation Pattern (REQUIRED)
Every singleton has a `reset()` method. **Always call in `setUp()`** to prevent state leakage:
```dart
setUp(() async {
  SharedPreferences.setMockInitialValues({});
  await AdsEnabledManager.instance.reset();
  await AdFlow.instance.reset();
});
```

**Platform Testing Limitation:** `Platform.isAndroid/isIOS` cannot be mocked in pure Dart unit tests—use integration tests or acceptance of limited coverage for platform-specific paths. See [test/ad_config_test.dart](test/ad_config_test.dart) for examples of testing around this.

### Native Ads Setup
Requires platform-specific factory code (Kotlin/Swift). See [doc/NATIVE_ADS_SETUP.md](doc/NATIVE_ADS_SETUP.md) for complete setup guide including:
- Factory registration in MainActivity.kt (Android) and AppDelegate.swift (iOS)
- Layout XML templates (Android) and XIB files (iOS)
- Factory ID conventions: `'small'`, `'medium'`, `'large'`

## Code Patterns

### 1. Ad Widget Pattern
All ad widgets must check `AdsEnabledManager` and return empty widget if disabled. See [easy_banner_widget.dart](lib/src/easy_banner_widget.dart):
```dart
_adsEnabled = AdsEnabledManager.instance.isEnabled;
if (!_adsEnabled) return SizedBox.shrink();
```

**Two Widget Approaches:**
- **Manager-based**: Widget receives pre-loaded manager (e.g., `NativeAdWidget(manager: _nativeManager)`)
- **Self-contained**: Widget handles own lifecycle (e.g., `EasyBannerWidget(adUnitId: '...')`)

### 2. Ad Manager Contract
Each manager in `lib/src/*_ad_manager.dart` follows:
- `loadAd()` / `showAd()` → checks `AdsEnabledManager.isDisabled` first, then consent
- Retry with exponential backoff on load failures (configurable via `AdFlowConfig.maxLoadRetries`)
- State getters: `isLoaded`, `isLoading`, `isShowing`
- Reactive updates: `addStatusListener()` / `removeStatusListener()`
- Cleanup: `dispose()` → call **only if manager was accessed** (lazy init optimization)
- Cooldown enforcement: `canShowAd` → respects `minInterstitialInterval` from config (default 30s)

### 3. Error Handling
Subscribe to centralized error stream in [ad_error_handler.dart](lib/src/ad_error_handler.dart):
```dart
AdFlow.instance.errorStream.listen((AdFlowError error) {
  // error.type (AdErrorType enum), error.code, error.message
});
```

### 4. Consent Variants
- `gatherConsent()` → direct system prompts (ATT on iOS, then UMP)
- `gatherConsentWithExplainer(context)` → shows friendly dialog first (recommended for better UX)

**Localization:** [consent_explainer_localizations.dart](lib/src/consent_explainer_localizations.dart) provides translations in 8 languages (EN, ES, FR, DE, IT, PT, JA, ZH).

### 5. Mediation Support
Use [MediationHelper](lib/src/mediation_helper.dart) to forward consent to third-party ad networks. Register adapters BEFORE `AdFlow.initialize()`:
```dart
import 'package:gma_mediation_unity/gma_mediation_unity.dart';
import 'package:gma_mediation_applovin/gma_mediation_applovin.dart';

// Create instances and register Unity Ads
final unity = GmaMediationUnity();
MediationHelper.registerUnityWithCallbacks(
  setGDPRConsent: unity.setGDPRConsent,
  setCCPAConsent: unity.setCCPAConsent,
);

// Create instance and register AppLovin
final applovin = GmaMediationApplovin();
MediationHelper.registerApplovinWithCallbacks(
  setHasUserConsent: applovin.setHasUserConsent,
  setDoNotSell: applovin.setDoNotSell,
);

await AdFlow.instance.initialize(...); // Consent auto-forwarded
```

Mediation adapters are **optional** — only add the dependencies you need in pubspec.yaml.

## Critical Rules
1. **Never** call `AdFlow.instance.initialize()` more than once per session
2. **Always** check `consent.canRequestAds` before loading ads
3. Dispose managers **only if accessed** (lazy init saves memory)
4. Keep consent flows **strictly sequential** to prevent popup stacking (iOS ATT → UMP → MobileAds.initialize)
5. Add new exports to [lib/ad_flow.dart](lib/ad_flow.dart) barrel file
6. **Disable ads BEFORE initialization**—`onComplete` runs AFTER preloading:
```dart
// ✅ Correct: disable before init, or use conditional flags
await AdFlow.instance.disableAds();
await AdFlow.instance.initializeWithExplainer(preloadAppOpen: true);
```
7. **App Open Ad Caching:** Ads expire after 4 hours (configurable via `appOpenAdMaxCacheDuration`); reload before showing if expired
8. **Mediation consent:** Register adapters BEFORE `AdFlow.initialize()` — consent is forwarded automatically during init

## Adding New Ad Types
1. Create manager class following [interstitial_ad_manager.dart](lib/src/interstitial_ad_manager.dart) pattern:
   - Singleton with private constructor + static instance
   - Lazy ad loading with retry logic
   - Status listeners for reactive UI updates
   - State getters (`isLoaded`, `isLoading`, `isShowing`)
   - Consent + `AdsEnabledManager` checks in `loadAd()`/`showAd()`
2. Add lazy getter in [ad_service.dart](lib/src/ad_service.dart) (lines 208-225)
3. Export from [lib/ad_flow.dart](lib/ad_flow.dart) barrel file
4. Include in `disposeAllAds()` and `reset()` methods (dispose only if `_managerField != null`)
5. Write tests following [test/ad_flow_test.dart](test/ad_flow_test.dart) patterns (singleton reset in `setUp()`)
