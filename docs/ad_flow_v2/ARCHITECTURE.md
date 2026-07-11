# ARCHITECTURE — ad_flow v2

The target design. Follow it unless you find a concrete reason not to — if you deviate, record why in `DECISIONS.md`. The Dart below is a **contract sketch**: the *shape* (layers, responsibilities, method signatures) is the contract; exact names/param lists may be refined during implementation, but changes to the public contract must be reflected here and in `MIGRATION.md`.

## Design principles
Dependency injection over global state · one reactive primitive (`ValueListenable`) · each layer testable behind an interface · policy-compliant, revenue-optimized defaults · the SDK seam hides whether legacy or Next-Gen native code runs.

## Layer map (bottom-up — also the build order)

```
┌─ widgets ────────────────  AdFlowBanner, AdFlowNativeAd, PrivacyOptionsButton
├─ facade ─────────────────  AdFlow (composition root + ergonomic API)
├─ lifecycle ──────────────  AppOpenAdManager (AppStateEventNotifier)
├─ controllers ────────────  Banner / Interstitial / Rewarded / RewardedInterstitial / Native / AppOpen
├─ policies (cross-cutting)  RetryPolicy · FrequencyCapPolicy · AdGate · FullScreenAdCoordinator
├─ consent ────────────────  ConsentGateway (wraps UMP)
├─ config ─────────────────  AdFlowConfig + per-format configs
└─ seam ───────────────────  AdSdk  (GmaAdSdk real · FakeAdSdk test)   ← the ONLY import of google_mobile_ads
```

**Dependency rule:** a layer may depend only on the layers below it, through their interfaces. Widgets and the facade may touch `google_mobile_ads` types only where a real `AdWidget`/`AdSize` is unavoidable; everything else goes through the seam.

## Suggested file layout

```
lib/
  ad_flow.dart                      # barrel: exports public API only
  src/
    seam/ad_sdk.dart                # AdSdk interface
    seam/gma_ad_sdk.dart            # real impl (imports google_mobile_ads)
    config/ad_flow_config.dart      # AdFlowConfig + per-format configs
    config/ad_platform.dart         # injectable platform + id resolution
    consent/consent_gateway.dart
    policy/retry_policy.dart
    policy/frequency_cap_policy.dart
    policy/ad_gate.dart
    policy/full_screen_ad_coordinator.dart
    policy/key_value_store.dart      # interface + shared_prefs impl + in-memory fake
    core/ad_load_state.dart          # sealed state
    core/ad_controller.dart          # AdController + FullScreenAdController contracts
    controllers/banner_ad_controller.dart
    controllers/interstitial_ad_controller.dart
    controllers/rewarded_ad_controller.dart
    controllers/rewarded_interstitial_ad_controller.dart
    controllers/native_ad_controller.dart
    controllers/app_open_ad_controller.dart
    lifecycle/app_open_ad_manager.dart
    facade/ad_flow.dart
    widgets/ad_flow_banner.dart
    widgets/ad_flow_native_ad.dart
    widgets/privacy_options_button.dart
    widgets/rewarded_intro_screen.dart   # mandatory intro/skip for rewarded interstitial
test/  (mirror src/, using FakeAdSdk + fakes)
example/  (all formats + a --dart-define=USE_NEXT_GEN_SDK=true variant)
```

---

## Contract sketch (Dart)

### Sealed load state
```dart
sealed class AdLoadState {
  const AdLoadState();
}
class AdIdle     extends AdLoadState { const AdIdle(); }
class AdLoading  extends AdLoadState { const AdLoading(); }
class AdLoaded   extends AdLoadState { const AdLoaded(); }
class AdShowing  extends AdLoadState { const AdShowing(); }
class AdFailed   extends AdLoadState { final AdFlowError error; const AdFailed(this.error); }
```

### SDK seam — the only door to google_mobile_ads
```dart
/// Wraps every google_mobile_ads call so the rest of the package is testable
/// and agnostic to legacy vs Next-Gen native SDK.
abstract interface class AdSdk {
  Future<void> initialize();
  Future<void> updateRequestConfiguration(AdRequestConfig config);

  // Full-screen loads return a handle the controller drives.
  Future<InterstitialHandle> loadInterstitial(String adUnitId, AdRequestOptions o);
  Future<RewardedHandle> loadRewarded(String adUnitId, AdRequestOptions o);
  Future<RewardedInterstitialHandle> loadRewardedInterstitial(String adUnitId, AdRequestOptions o);
  Future<AppOpenHandle> loadAppOpen(String adUnitId, AdRequestOptions o);

  // Banner/native return the plugin object because a real AdWidget must host it.
  Future<BannerHandle> loadBanner(BannerLoadSpec spec);
  Future<NativeHandle> loadNative(NativeLoadSpec spec);

  Stream<AppForegroundEvent> get appForegroundEvents; // wraps AppStateEventNotifier
  Future<AdInspectorResult> openAdInspector();
}
```
Each `*Handle` exposes `show({onUserEarnedReward})` where relevant, a `fullScreenContentEvents` stream (showed/dismissed/failed/impression/clicked), `onPaidEvent`, and `dispose()`. `GmaAdSdk` maps these onto the real plugin callbacks; `FakeAdSdk` drives them synchronously in tests.

### Config (injected, immutable)
```dart
class AdFlowConfig {
  const AdFlowConfig({
    required this.appId,             // per-platform AdMob app id (or null → set in manifest/plist)
    this.banner, this.interstitial, this.rewarded,
    this.rewardedInterstitial, this.nativeAd, this.appOpen,
    this.globalFrequencyCap = const FrequencyCap(maxPerSession: 100, minGap: Duration(seconds: 15)),
    this.retry = const RetryConfig(),
    this.testMode = false,           // explicit — NOT derived from resolved ids
    this.testDeviceIds = const [],
    this.maxAdContentRating,
    this.tagForUnderAgeOfConsent,
    this.tagForChildDirectedTreatment,
  });
  factory AdFlowConfig.test({ ... }) // uses Google sample ids, testMode: true
  // ... copyWith
}

class BannerConfig { final PlatformAdUnitId adUnitId; final BannerType type; /* adaptive|inline|collapsible|fixed */ final Duration minRefresh; ... }
class InterstitialConfig { final PlatformAdUnitId adUnitId; final FrequencyCap cap; final int minActionsBetween; ... }
class RewardedConfig { final PlatformAdUnitId adUnitId; final ServerSideVerification? ssv; ... }
class RewardedInterstitialConfig { final PlatformAdUnitId adUnitId; final RewardIntroContent intro; final ServerSideVerification? ssv; ... }
class NativeConfig { final PlatformAdUnitId adUnitId; final NativeStyleSpec style; /* template or factoryId */ ... }
class AppOpenConfig { final PlatformAdUnitId adUnitId; final FrequencyCap cap; final Duration expiry = const Duration(hours: 4); final bool showOnColdStart = false; ... }

class PlatformAdUnitId { final String? android; final String? ios; String? resolve(AdPlatform p); }
class FrequencyCap { final int maxPerSession; final Duration minGap; final int? maxPerHour; }
```

### Consent
```dart
abstract interface class ConsentGateway {
  /// Runs requestConsentInfoUpdate + loadAndShowConsentFormIfRequired,
  /// coordinates ATT, and resolves to whether ads may be requested.
  Future<bool> ensureCanRequestAds({ConsentDebugOptions? debug});
  bool get isPrivacyOptionsRequired;
  Future<void> showPrivacyOptions();
  Future<void> reset(); // testing only
}
```
Wrap UMP's callback API into these Futures **once**; internal timeouts; never leak `Completer` juggling to callers.

### Policies
```dart
class RetryPolicy { // exponential backoff + jitter + max attempts + cooldown
  Duration nextDelay(int attempt);
  bool shouldRetry(int attempt);
  Duration get cooldown;
}

abstract interface class FrequencyCapPolicy {
  Future<bool> canShow(String slot);          // per-format + global
  Future<void> recordImpression(String slot);
}

abstract interface class KeyValueStore { // shared_preferences behind an interface
  Future<int?> getInt(String k); Future<void> setInt(String k, int v);
  Future<List<int>> getHistory(String k); Future<void> pushHistory(String k, int tsMillis);
}

class FullScreenAdCoordinator { // single source of truth: is a full-screen ad on screen?
  bool get isFullScreenAdVisible;
  void enter(); void exit();
  ValueListenable<bool> get visible;
}

class AdGate { // composed check used before every load AND show
  AdGate(this._consent, this._enabled, this._caps);
  Future<bool> canLoad(String slot);
  Future<bool> canShow(String slot);          // also checks coordinator for app-open
}
```

### Controllers
```dart
abstract interface class AdController {
  ValueListenable<AdLoadState> get state;
  Future<void> load();
  void dispose();
}

abstract interface class FullScreenAdController extends AdController {
  /// Loads if needed, checks AdGate, shows, records impression, reloads the next.
  Future<bool> show({OnUserEarnedReward? onReward});
}
```
Every concrete controller: consults `AdGate.canLoad` before loading; uses `RetryPolicy` on failure and auto-re-arms after cooldown; for full-screen, checks `AdGate.canShow`, records via `FrequencyCapPolicy`, disposes single-use handles, and **reloads the next on dismiss**. `RewardedInterstitialAdController.show` first presents `RewardedIntroScreen` (skip option) and only proceeds if not skipped.

### Lifecycle
```dart
class AppOpenAdManager {
  AppOpenAdManager(this._controller, this._sdk, this._gate, this._coordinator, this._config);
  void start();  // subscribes to sdk.appForegroundEvents
  void stop();
  // On foreground: if not cold-start-suppressed, ad is loaded & <4h old,
  // gate.canShow('app_open') is true, and no full-screen ad is visible → show.
}
```
Exactly one `AppOpenAdManager` exists (owned by the facade). No static signaling.

### Facade (composition root)
```dart
class AdFlow {
  AdFlow._(this._config, this._sdk, this._consent, /* ...policies, controllers... */);

  /// Builds the whole graph. Injectable seam/consent for tests.
  static Future<AdFlow> initialize(AdFlowConfig config, {AdSdk? sdk, ConsentGateway? consent});

  BannerAdController banner(BannerConfig? override);
  InterstitialAdController get interstitial;
  RewardedAdController get rewarded;
  RewardedInterstitialAdController get rewardedInterstitial;
  NativeAdController native(NativeConfig? override);
  AppOpenAdManager get appOpen;
  ConsentGateway get consent;

  void enableAds();  void disableAds();          // Remove-Ads
  set onPaidEvent(void Function(PaidEvent) cb);   // impression-level revenue
  Future<void> openAdInspector();
  void dispose();
}
```
A convenience singleton accessor (e.g. `AdFlow.instance` set after `initialize`) is allowed **only** as a thin pointer to an injectable instance — tests build their own `AdFlow` with a `FakeAdSdk`.

### Widgets
`AdFlowBanner` (loads via a `BannerAdController`, shows a placeholder of reserved height until loaded to avoid layout shift, hosts `AdWidget`, disposes on unmount), `AdFlowNativeAd` (template or factory), `PrivacyOptionsButton` (visible only when `consent.isPrivacyOptionsRequired`), `RewardedIntroScreen` (reward disclosure + skip).

---

## Key sequences

**Init:** `AdFlow.initialize(config)` → build graph → `consent.ensureCanRequestAds()` **and** (in parallel) `sdk.initialize()` → when gate true, `updateRequestConfiguration` → start `AppOpenAdManager` → preload configured formats. No `load()` before the gate is true.

**Full-screen load/show:** `controller.load()` (gate.canLoad → sdk.load → state=Loaded, keep warm) … later `controller.show()` (gate.canShow → sdk handle.show → state=Showing → coordinator.enter) → on dismiss (coordinator.exit, caps.recordImpression, dispose, reload next).

**App-open on foreground:** `sdk.appForegroundEvents` → `AppOpenAdManager` checks loaded & <4h & gate.canShow & !coordinator.isFullScreenAdVisible & !coldStartSuppressed → show.
