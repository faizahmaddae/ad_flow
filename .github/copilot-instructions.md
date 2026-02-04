# ad_flow - AI Coding Agent Instructions

## Project Overview
Flutter package for AdMob integration with GDPR/ATT compliance. **Pure Dart package**—no native plugin code (delegates to `google_mobile_ads`, `app_tracking_transparency`, `shared_preferences`). Supports banner, interstitial, rewarded, native, and app open ads with built-in consent management and mediation helper.

## Architecture Philosophy

### Singleton Entry Point with Lazy Initialization
`AdFlow.instance` is the single entry point, with **lazy-initialized** managers created only when accessed:
```dart
AdFlow.instance.banner       // BannerAdManager (created on first access)
AdFlow.instance.interstitial // InterstitialAdManager
AdFlow.instance.rewarded     // RewardedAdManager
AdFlow.instance.appOpen      // AppOpenAdManager (4-hour cache expiry)
AdFlow.instance.native       // NativeAdManager
AdFlow.instance.consent      // ConsentManager (separate singleton)

// Non-blocking init support (v1.3.14+)
AdFlow.instance.initStream   // Stream<bool> - emits when init completes
AdFlow.instance.waitForInit() // Future<bool> - waits for init with optional timeout
AdFlow.instance.isInitialized // bool - check if already initialized
```

**Why lazy?** Users who only need banners won't waste memory on interstitial/rewarded managers. Performance-first design.

### Key Files & Responsibilities
| File | Purpose | Critical Details |
|------|---------|------------------|
| `lib/ad_flow.dart` | **Barrel export**—add ALL new public APIs here | Re-exports from `src/`, plus commonly used `google_mobile_ads` types |
| `lib/src/ad_service.dart` | `AdFlow` singleton orchestrator | `initialize()`, `initializeWithExplainer()`, manager lifecycle |
| `lib/src/ad_config.dart` | Configuration classes | `AdFlowConfig`, `TestAdUnitIds`, platform helpers, cache durations |
| `lib/src/consent_manager.dart` | Consent flow controller | **Sequential**: iOS ATT → UMP SDK → `canRequestAds` flag |
| `lib/src/ads_enabled_manager.dart` | "Remove Ads" IAP state | SharedPreferences persistence, reactive listeners |
| `lib/src/mediation_helper.dart` | Third-party adapter registry | Forwards consent to Unity/AppLovin/Meta adapters |
| `lib/src/ad_error_handler.dart` | Centralized error stream | `AdFlowError` with `AdErrorType` enum, broadcast stream |

### Initialization Order (STRICTLY SEQUENTIAL)
**Critical:** Never parallelize steps 1-5. Consent dialogs must appear sequentially per platform UX guidelines.
```
1. AdsEnabledManager.initialize()     → Load "remove ads" state from prefs
2. MediationHelper.registerXxx()      → Register adapters BEFORE consent
3. ConsentManager.gatherConsent()     → iOS ATT first, THEN UMP (never parallel!)
4. MediationHelper.forwardConsent()   → Auto-called if adapters registered
5. MobileAds.instance.initialize()    → Only if canRequestAds == true
6. Preload ads per AdFlowConfig flags → Auto-load if enabled in config
```

**Non-Blocking Mode (v1.3.14+):** The same sequence runs in background—call `initialize()` without `await`. Reactive widgets (`EasyBannerAd`, `EasyNativeAd`) auto-load when ready via `initStream`. For fullscreen ads, use `await waitForInit()`.

**Gotcha:** Calling `initialize()` multiple times per session is a no-op (checks `_isInitialized`). "Remove Ads" must be disabled **before** init to skip ad preloading.

## Development Workflow

### Running & Testing
```bash
cd example && flutter run              # Run example app (exports from main.dart)
flutter test                           # All unit tests
flutter test test/ad_flow_test.dart    # Single test file
flutter analyze                        # Lint checks (uses analysis_options.yaml)
dart format lib test                   # Format code
```

### Test Isolation (MANDATORY)
Every singleton has `reset()`. **Always** call in `setUp()` to avoid test pollution:
```dart
setUp(() async {
  SharedPreferences.setMockInitialValues({}); // Mock prefs FIRST
  await AdsEnabledManager.instance.reset();
  await AdFlow.instance.reset();
});
```

**Platform Limitation:** `Platform.isAndroid/isIOS` cannot be mocked in unit tests. Skip platform-specific logic in pure unit tests, or use widget tests with device targeting.

### Example App Structure
```
example/lib/main.dart                   → Export switcher (change active example here)
example/lib/example_with_explainer.dart → Recommended: shows dialog before consent
example/lib/example_without_explainer.dart → Direct consent (no explainer)
```
Toggle by commenting/uncommenting exports in `main.dart`.

## Code Patterns

### Ad Widget Types (Two Approaches)
**Self-contained widgets** (handle own lifecycle, auto-check `AdsEnabledManager`):
- `EasyBannerAd()` - Adaptive banners, collapsible support, auto-dispose
- `EasyNativeAd()` - Native ads with customizable UI
- Use case: Drop-in widgets for quick integration

**Manager-based widgets** (pre-loaded manager passed in):
- `NativeAdWidget(manager: myNativeManager)` - Receives pre-loaded manager
- Use case: More control over loading timing, custom retry logic

All widgets return `SizedBox.shrink()` if `AdsEnabledManager.isDisabled`.

### Ad Manager Contract (all `*_ad_manager.dart`)
Every manager implements:
```dart
// State getters
bool get isLoaded;
bool get isLoading;
bool get isShowing;      // fullscreen ads only (interstitial/rewarded/app open)
bool get canShowAd;      // cooldown check (interstitial only)

// Core methods
Future<void> loadAd();   // MUST check AdsEnabledManager.isDisabled first
Future<void> showAd();   // MUST check AdsEnabledManager.isDisabled first (fullscreen only)
void dispose();

// Reactive updates (status listeners)
void addStatusListener(VoidCallback);
void removeStatusListener(VoidCallback);
void _notifyStatusListeners();  // Private, call after ANY state change
```

**Reference implementation:** [interstitial_ad_manager.dart](lib/src/interstitial_ad_manager.dart)

### Error Handling (Centralized Stream)
All ad errors flow through `AdFlowErrorHandler` singleton:
```dart
// Option 1: Stream (for multiple listeners)
AdFlow.instance.errorStream.listen((AdFlowError e) {
  print('${e.type.name}: ${e.message} (code: ${e.code})');
  analytics.log('ad_error', {'type': e.type.name});
});

// Option 2: Callback (simpler for single handler)
AdFlow.instance.setErrorCallback((error) => showSnackbar(error.message));
```

**Error types** (`AdErrorType` enum): `load`, `show`, `consent`, `initialization`

### Widget Lifecycle Pattern (Self-Contained Widgets)
Standard pattern for `EasyBannerAd`, `EasyNativeAd`:
```dart
@override
void initState() {
  super.initState();
  _adsEnabled = AdsEnabledManager.instance.isEnabled;
  
  // Load AFTER first frame (ensures context ready)
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_adsEnabled && !_isDisposed) _tryLoadAd();
  });
  
  // Listen for "Remove Ads" state changes
  AdsEnabledManager.instance.addListener(_onAdsEnabledChanged);
  
  // Listen for AdFlow initialization (non-blocking init support)
  _initSubscription = AdFlow.instance.initStream.listen(_onAdFlowInitialized);
}

void _onAdFlowInitialized(bool canRequestAds) {
  if (_isDisposed || !mounted || !canRequestAds) return;
  if (_adsEnabled && !_isLoaded) _loadAd();
}

void _tryLoadAd() {
  if (AdFlow.instance.isInitialized) {
    _loadAd();
  }
  // If not initialized, _onAdFlowInitialized will be called when ready
}

@override
void dispose() {
  _isDisposed = true; // Set flag FIRST
  _initSubscription?.cancel();  // Cancel stream subscription
  AdsEnabledManager.instance.removeListener(_onAdsEnabledChanged);
  _manager.dispose();
  super.dispose();
}
```

**Key:** Check `_isDisposed` in callbacks to prevent post-dispose setState calls.

### Non-Blocking Initialization Pattern
For apps that need instant startup:
```dart
// main.dart - NO await, app starts immediately
void main() {
  runApp(MyApp());
}

// In first page's initState
WidgetsBinding.instance.addPostFrameCallback((_) {
  AdFlow.instance.initializeWithExplainer(context: context);  // Fire-and-forget
});

// Reactive widgets (EasyBannerAd, EasyNativeAd) auto-load when ready
// For fullscreen ads, use waitForInit():
final ready = await AdFlow.instance.waitForInit();
if (ready) await AdFlow.instance.interstitial.showAd();
```

## Critical Rules
1. **Never** call `initialize()` more than once per session—check `_isInitialized` early
2. **Disable ads BEFORE init**—`onComplete` callback runs AFTER preloading
3. Dispose managers **only if accessed** (lazy init: check `if (_xxxManager != null)`)
4. Keep consent flows **sequential** (ATT → UMP → MobileAds.init)—never parallelize dialogs
5. Register mediation adapters **BEFORE** `initialize()`
6. App Open ads expire after 4 hours (`appOpenAdMaxCacheDuration` in `AdFlowConfig`)
7. **Always** export new public APIs from `lib/ad_flow.dart` barrel file
8. Check `AdsEnabledManager.isDisabled` at start of `loadAd()`/`showAd()` in all managers
9. Call `_notifyStatusListeners()` after ANY state change in managers (enables reactive UI)
10. **Always cancel stream subscriptions** in widget `dispose()`—`initStream.listen()` without cancel causes memory leaks in navigable pages

## Adding New Ad Types
1. Create `lib/src/xxx_ad_manager.dart`:
   - Follow `InterstitialAdManager` pattern (status listeners, state getters, retry logic)
   - Check `AdsEnabledManager.isDisabled` at start of `loadAd()`/`showAd()`
   - Use `AdFlowErrorHandler.instance.reportError()` for error reporting
   - Add exponential backoff retry logic (see `_loadWithRetry()` pattern)
2. Add lazy getter in `lib/src/ad_service.dart`:
   ```dart
   XxxAdManager? _xxxAdManager;
   XxxAdManager get xxx => _xxxAdManager ??= XxxAdManager();
   ```
3. **Export from `lib/ad_flow.dart`** (this is critical!)
4. Update `disposeAllAds()`: `await _xxxAdManager?.dispose();`
5. Update `reset()`: `_xxxAdManager = null;`
6. Write tests with singleton reset in `setUp()`

## Mediation Integration
Register adapters **before** calling `initialize()`:
```dart
// In main.dart, before runApp()
final unity = GmaMediationUnity();
MediationHelper.registerUnityWithCallbacks(
  setGDPRConsent: unity.setGDPRConsent,
  setCCPAConsent: unity.setCCPAConsent,
);

// Then initialize AdFlow
await AdFlow.instance.initialize(...);
```

**Consent auto-forwarding:** If adapters are registered, `MediationHelper.forwardConsent()` is called automatically after UMP consent gathering. Manual forwarding:
```dart
await MediationHelper.forwardConsent(
  MediationConsentConfig(hasGdprConsent: true, ccpaOptOut: false)
);
```

## Common Gotchas
- **App Open ads expire:** Check `_isAdExpired()` before showing (4-hour cache limit)
- **Interstitial cooldown:** Use `minInterstitialInterval` (default 60s) to prevent ad spam
- **Adaptive banners:** Must get width from context—call `AdSize.getAnchoredAdaptiveBannerAdSize()` in build method
- **Collapsible banners:** Set `collapsiblePlacement` in `AdRequest.extras` (see `BannerAdManager.loadCollapsibleBanner()`)
- **Test mode:** Use `AdFlowConfig.testMode()` for development—uses Google test ad unit IDs
- **Consent required check:** `ConsentManager.isConsentFormAvailable` only returns `true` in GDPR regions
- **ATT denial handling:** If `TrackingStatus.denied`, can skip GDPR with `skipGdprConsentIfAttDenied: true` in `AdFlowConfig`
- **Slow network handling:** Smart timeouts are built-in (consent: 10s, SDK: 8s, cold-start ad: 3s) - dialogs always wait for user

## Initialization Timeouts
The package includes smart defaults to handle slow networks without breaking compliance:
```dart
AdFlowConfig(
  consentNetworkTimeout: Duration(seconds: 10), // Network request only, NOT dialogs
  sdkInitTimeout: Duration(seconds: 8),         // Retries in background if timeout
  coldStartAdTimeout: Duration(seconds: 3),     // App open ad on cold start
)
```
**Important:** Consent dialogs (ATT prompt, UMP form) are NEVER timed out—they wait for user interaction.

## Package Structure
- **Pure Dart package:** No native code—delegates to `google_mobile_ads` and `app_tracking_transparency` plugins
- **Platforms:** Android & iOS only (as per `pubspec.yaml`)
- **Dependencies:** 
  - `google_mobile_ads: ^7.0.0` (core ad functionality)
  - `app_tracking_transparency: ^2.0.6+1` (iOS ATT)
  - `shared_preferences: ^2.5.4` (persist "Remove Ads" state)
- **Optional:** Mediation adapters (Unity, AppLovin, Meta, etc.) are commented out in `pubspec.yaml`—users uncomment as needed

## Documentation References
- [Main README](README.md) - Setup, features, API examples
- [Mediation Setup](doc/MEDIATION_SETUP.md) - Unity Ads, AppLovin, Meta integration
- [Native Ads Setup](doc/NATIVE_ADS_SETUP.md) - Custom native ad layouts
- Example apps: `example/lib/example_with_explainer.dart` (recommended) & `example_without_explainer.dart`
