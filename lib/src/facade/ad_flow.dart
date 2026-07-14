import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/ad_flow_config.dart';
import '../config/ad_platform.dart';
import '../consent/consent_gateway.dart';
import '../consent/explainer_content.dart';
import '../controllers/app_open_ad_controller.dart';
import '../controllers/banner_ad_controller.dart';
import '../controllers/interstitial_ad_controller.dart';
import '../controllers/native_ad_controller.dart';
import '../controllers/rewarded_ad_controller.dart';
import '../controllers/rewarded_interstitial_ad_controller.dart';
import '../core/ad_flow_error.dart';
import '../lifecycle/app_open_ad_manager.dart';
import '../policy/ad_gate.dart';
import '../policy/frequency_cap_policy.dart';
import '../policy/full_screen_ad_coordinator.dart';
import '../policy/key_value_store.dart';
import '../policy/retry_policy.dart';
import '../seam/ad_sdk.dart';
import '../seam/ad_sdk_types.dart';
import '../seam/gma_ad_sdk.dart';

/// The composition root and ergonomic entry point of ad_flow.
///
/// [initialize] builds the whole graph (seam → consent → policies →
/// controllers → lifecycle), initializes the SDK (concurrently with
/// consent gathering) then applies request configuration, and preloads
/// every configured full-screen format once the consent gate is open. All
/// collaborators are injectable — tests build their own `AdFlow` over a
/// `FakeAdSdk` (ADR-004: no static state beyond the optional [instance]
/// convenience pointer).
class AdFlow {
  AdFlow._({
    required AdFlowConfig config,
    required AdSdk sdk,
    required ConsentGateway consentGateway,
    required bool ownsConsent,
    required AdPlatform platform,
    required KeyValueStore store,
    RewardedIntroPresenter? rewardedIntroPresenter,
  }) : _config = config,
       _sdk = sdk,
       _consent = consentGateway,
       _ownsConsent = ownsConsent,
       _platform = platform,
       _coordinator = FullScreenAdCoordinator(),
       _retry = RetryPolicy(config.retry) {
    _caps = StoredFrequencyCapPolicy(
      store: store,
      slotCaps: {
        if (config.interstitial != null)
          InterstitialAdController.slotName: config.interstitial!.cap,
        if (config.appOpen != null)
          AppOpenAdController.slotName: config.appOpen!.cap,
      },
      globalCap: config.globalFrequencyCap,
    );
    _gate = AdGate(
      canRequestAds: _sdk.canRequestAds,
      isEnabled: () => _adsEnabled.value,
      caps: _caps,
      coordinator: _coordinator,
    );

    final interstitialId = config.interstitialAdUnitId(_platform);
    if (interstitialId != null) {
      _interstitial = InterstitialAdController(
        sdk: _sdk,
        gate: _gate,
        caps: _caps,
        coordinator: _coordinator,
        config: config.interstitial!,
        adUnitId: interstitialId,
        retry: _retry,
        onPaid: _dispatchPaid,
      );
    }

    final rewardedId = config.rewardedAdUnitId(_platform);
    if (rewardedId != null) {
      _rewarded = RewardedAdController(
        sdk: _sdk,
        gate: _gate,
        caps: _caps,
        coordinator: _coordinator,
        config: config.rewarded!,
        adUnitId: rewardedId,
        retry: _retry,
        onPaid: _dispatchPaid,
      );
    }

    final rewardedInterstitialId = config.rewardedInterstitialAdUnitId(
      _platform,
    );
    if (rewardedInterstitialId != null) {
      if (rewardedIntroPresenter == null) {
        throw const AdFlowError(
          AdFlowErrorKind.invalidConfig,
          'rewardedInterstitial is configured but no rewardedIntroPresenter '
          'was provided. Pass e.g. '
          '(content) => RewardedIntroScreen.show(navigatorKey.currentContext!, content).',
        );
      }
      _rewardedInterstitial = RewardedInterstitialAdController(
        sdk: _sdk,
        gate: _gate,
        caps: _caps,
        coordinator: _coordinator,
        config: config.rewardedInterstitial!,
        adUnitId: rewardedInterstitialId,
        showIntro: rewardedIntroPresenter,
        retry: _retry,
        onPaid: _dispatchPaid,
      );
    }

    final appOpenId = config.appOpenAdUnitId(_platform);
    if (appOpenId != null) {
      final appOpenController = AppOpenAdController(
        sdk: _sdk,
        gate: _gate,
        caps: _caps,
        coordinator: _coordinator,
        config: config.appOpen!,
        adUnitId: appOpenId,
        retry: _retry,
        onPaid: _dispatchPaid,
      );
      _appOpenController = appOpenController;
      _appOpen = AppOpenAdManager(
        controller: appOpenController,
        sdk: _sdk,
        config: config.appOpen!,
        coordinator: _coordinator,
      );
    }
  }

  /// Builds the graph and starts ad_flow.
  ///
  /// SDK initialization and consent gathering run in parallel (init sends
  /// no ad request); request configuration is applied after init completes
  /// (ADR-028); nothing loads before the consent gate is open.
  /// [sdk], [consent], [store] and [platform] are injectable for tests.
  /// [rewardedIntroPresenter] is required when the rewarded interstitial
  /// slot is configured. [consentDebug] passes UMP debug geography —
  /// remove before release.
  ///
  /// The optional priming ("explainer") parameters restore v1's
  /// `initializeWithExplainer` in the v2 presenter style — all opt-in and
  /// additive (pass none and behaviour is exactly as before):
  ///
  /// - [attExplainer] — the app's ATT primer shown before Apple's system
  ///   tracking prompt (client-driven ATT, iOS). Supplying it also opts into
  ///   running ATT *before* the GDPR flow. In this mode do **not** also
  ///   configure the UMP IDFA message in the AdMob console (avoids a double
  ///   prompt).
  /// - [consentExplainer] — the app's consent primer shown before the UMP
  ///   GDPR form, only when a form will actually appear.
  /// - [consentExplainerContent] / [attExplainerContent] — the copy for the
  ///   presenters (localize by overriding).
  /// - [skipConsentPrimerIfAttDenied] — skip the optional consent *primer*
  ///   (not the form) when the user just denied ATT (default true). A required
  ///   GDPR form always shows regardless — ATT and GDPR are independent
  ///   regimes (ADR-031).
  ///
  /// These apply only to a gateway this facade creates. If you inject your
  /// own [consent], construct it with these options yourself.
  static Future<AdFlow> initialize(
    AdFlowConfig config, {
    AdSdk? sdk,
    ConsentGateway? consent,
    KeyValueStore? store,
    AdPlatform? platform,
    RewardedIntroPresenter? rewardedIntroPresenter,
    ConsentDebugOptions? consentDebug,
    ConsentExplainerPresenter? consentExplainer,
    AttExplainerPresenter? attExplainer,
    ConsentExplainerContent consentExplainerContent =
        const ConsentExplainerContent(),
    AttExplainerContent attExplainerContent = const AttExplainerContent(),
    bool skipConsentPrimerIfAttDenied = true,
  }) async {
    final resolvedSdk = sdk ?? GmaAdSdk();
    final flow = AdFlow._(
      config: config,
      sdk: resolvedSdk,
      consentGateway:
          consent ??
          UmpConsentGateway(
            resolvedSdk,
            tagForUnderAgeOfConsent: config.tagForUnderAgeOfConsent,
            consentExplainer: consentExplainer,
            attExplainer: attExplainer,
            consentExplainerContent: consentExplainerContent,
            attExplainerContent: attExplainerContent,
            skipConsentPrimerIfAttDenied: skipConsentPrimerIfAttDenied,
          ),
      // Only dispose a consent gateway this facade created itself — an
      // injected one may be shared/reused by the caller beyond dispose().
      ownsConsent: consent == null,
      platform: platform ?? currentAdPlatform(),
      store: store ?? SharedPrefsKeyValueStore(),
      rewardedIntroPresenter: rewardedIntroPresenter,
    );
    await flow._start(consentDebug);
    _instance = flow;
    return flow;
  }

  static AdFlow? _instance;

  /// Convenience pointer to the most recently initialized instance —
  /// a thin alias, never required (inject the instance itself instead
  /// where possible).
  static AdFlow get instance {
    final instance = _instance;
    if (instance == null) {
      throw StateError('AdFlow.instance read before AdFlow.initialize().');
    }
    return instance;
  }

  final AdFlowConfig _config;
  final AdSdk _sdk;
  final ConsentGateway _consent;
  final bool _ownsConsent;
  final AdPlatform _platform;
  final FullScreenAdCoordinator _coordinator;
  final RetryPolicy _retry;
  late final StoredFrequencyCapPolicy _caps;
  late final AdGate _gate;

  final ValueNotifier<bool> _adsEnabled = ValueNotifier(true);

  InterstitialAdController? _interstitial;
  RewardedAdController? _rewarded;
  RewardedInterstitialAdController? _rewardedInterstitial;
  AppOpenAdController? _appOpenController;
  AppOpenAdManager? _appOpen;
  bool _disposed = false;

  /// Impression-level revenue callback for every format (allowlisted
  /// AdMob accounts only). Assignable at any time.
  void Function(AdPaidEvent event)? onPaidEvent;

  void _dispatchPaid(AdPaidEvent event) => onPaidEvent?.call(event);

  /// Bounds [AdSdk.initialize] the same way [UmpConsentGateway] bounds its
  /// own network-bound step. RESEARCH.md documents the native SDK's own
  /// init call as completing "on init or a 30s timeout," but that is the
  /// native SDK's promise, not ours — so [_start] wraps it defensively so a
  /// merely-slow (rather than frozen) init can't hang every caller's
  /// `FutureBuilder`-gated UI forever.
  ///
  /// Note: the far worse "whole app frozen at
  /// `ChimeraMobileAdsSettingManagerCreatorImpl`, isolate dead, this
  /// timeout never even fires" hang originally blamed on the native SDK
  /// (ADR-027 and its addenda) turned out to be a real ad_flow bug, now
  /// fixed by the call ORDERING in [_start] — see ADR-028. This timeout
  /// remains as belt-and-suspenders for a genuinely slow init.
  static const _initTimeout = Duration(seconds: 30);

  Future<void> _start(ConsentDebugOptions? debug) async {
    // Consent (UMP) is independent of the Ads SDK and safe to run in
    // parallel with everything below.
    final consent = _consent.ensureCanRequestAds(debug: debug);

    // Initialize the Ads SDK FIRST, and let it finish, BEFORE touching the
    // request configuration. This ordering is load-bearing, not cosmetic:
    //
    // In the google_mobile_ads plugin, `MobileAds#initialize` is dispatched
    // to a background thread on the native side (FlutterMobileAdsWrapper
    // runs `MobileAds.initialize()` inside `new Thread(...)`), so it never
    // blocks the platform thread. `MobileAds#updateRequestConfiguration`,
    // by contrast, is handled *synchronously on the platform thread* inside
    // the plugin's `onMethodCall` — and it calls both
    // `MobileAds.getRequestConfiguration()` and `setRequestConfiguration()`.
    // If those run before the native Ads (Play Services Dynamite) module has
    // finished bootstrapping, they force that bootstrap to happen
    // synchronously on the platform thread — and, worse, race the background
    // init that is bootstrapping the very same singleton. On a cold device
    // that race deadlocks the platform thread, which freezes the entire
    // Flutter engine (and the Dart isolate with it) hard enough that no
    // Dart-side timeout can recover — the exact "wedged at
    // ChimeraMobileAdsSettingManagerCreatorImpl" hang triaged in ADR-027.
    // Awaiting init first means the module is already loaded, so applying
    // the request configuration is a cheap, safe platform-thread call.
    //
    // `catchError` keeps a failed/slow init from bricking the app; loads
    // retry independently.
    await _sdk.initialize().timeout(_initTimeout).catchError((Object _) {});

    // Now that the Ads SDK is initialized, apply request configuration.
    // This still runs UNCONDITIONALLY (not gated on the consent *result*):
    // it sends no ad request, and controllers loading ads later must have
    // testDeviceIds/tagForChildDirectedTreatment/maxAdContentRating/
    // tagForUnderAgeOfConsent applied regardless of how or when consent
    // resolves (review finding #5: otherwise a registered test device gets
    // live ads, and a child-directed app serves untagged/wrongly-rated
    // ads). Guarded so a native failure here can't brick startup either.
    await _sdk
        .updateRequestConfiguration(_config.toRequestConfig())
        .catchError((Object _) {});

    // Gate ad loads on consent (init already awaited above).
    await consent;

    // The manager and controllers gate every load themselves, so starting
    // them with a closed gate is safe — they simply stay idle.
    _appOpen?.start();
    unawaited(_interstitial?.load());
    unawaited(_rewarded?.load());
    unawaited(_rewardedInterstitial?.load());
  }

  /// The consent gateway (privacy options, lastError, re-runs).
  ConsentGateway get consent => _consent;

  /// Whether ads are enabled (Remove-Ads state). Reactive for widgets.
  ValueListenable<bool> get adsEnabled => _adsEnabled;

  /// Re-enables ad loading after [disableAds].
  void enableAds() => _adsEnabled.value = true;

  /// Blocks every future ad load/show (e.g. the user bought Remove-Ads).
  /// Hide any mounted ad widgets in response to [adsEnabled].
  void disableAds() => _adsEnabled.value = false;

  T _require<T>(T? controller, String format) {
    final resolved = controller;
    if (resolved == null) {
      throw AdFlowError(
        AdFlowErrorKind.invalidConfig,
        'The $format slot is not configured for ${_platform.name} '
        '(missing config or platform ad unit ID).',
      );
    }
    return resolved;
  }

  /// The interstitial controller. Throws if the slot is unconfigured.
  InterstitialAdController get interstitial =>
      _require(_interstitial, 'interstitial');

  /// The rewarded controller. Throws if the slot is unconfigured.
  RewardedAdController get rewarded => _require(_rewarded, 'rewarded');

  /// The rewarded interstitial controller. Throws if the slot is
  /// unconfigured.
  RewardedInterstitialAdController get rewardedInterstitial =>
      _require(_rewardedInterstitial, 'rewardedInterstitial');

  /// The app open manager. Throws if the slot is unconfigured.
  AppOpenAdManager get appOpen => _require(_appOpen, 'appOpen');

  /// The app open controller (state inspection). Throws if unconfigured.
  AppOpenAdController get appOpenController =>
      _require(_appOpenController, 'appOpen');

  /// Creates a fresh banner controller (one per placement; give it to an
  /// `AdFlowBanner` with `ownsController: true`). [override] replaces the
  /// global banner config for this placement.
  BannerAdController banner([BannerConfig? override]) {
    final config = override ?? _config.banner;
    if (config == null) {
      throw AdFlowError(
        AdFlowErrorKind.invalidConfig,
        'No banner config: pass one to banner() or configure '
        'AdFlowConfig.banner.',
      );
    }
    final adUnitId = (_config.testMode ? TestAdUnitIds.banner : config.adUnitId)
        .resolve(_platform);
    if (adUnitId == null) {
      throw AdFlowError(
        AdFlowErrorKind.invalidConfig,
        'The banner slot has no ad unit ID for ${_platform.name}.',
      );
    }
    return BannerAdController(
      sdk: _sdk,
      gate: _gate,
      config: config,
      adUnitId: adUnitId,
      retry: RetryPolicy(_config.retry),
      onPaid: _dispatchPaid,
    );
  }

  /// Creates a fresh native controller (one per placement; give it to an
  /// `AdFlowNativeAd` with `ownsController: true`). [override] replaces
  /// the global native config for this placement.
  NativeAdController native([NativeConfig? override]) {
    final config = override ?? _config.nativeAd;
    if (config == null) {
      throw AdFlowError(
        AdFlowErrorKind.invalidConfig,
        'No native config: pass one to native() or configure '
        'AdFlowConfig.nativeAd.',
      );
    }
    final adUnitId = (_config.testMode ? TestAdUnitIds.native : config.adUnitId)
        .resolve(_platform);
    if (adUnitId == null) {
      throw AdFlowError(
        AdFlowErrorKind.invalidConfig,
        'The native slot has no ad unit ID for ${_platform.name}.',
      );
    }
    return NativeAdController(
      sdk: _sdk,
      gate: _gate,
      config: config,
      adUnitId: adUnitId,
      retry: RetryPolicy(_config.retry),
      onPaid: _dispatchPaid,
    );
  }

  /// Opens the Ad Inspector debug overlay.
  Future<AdInspectorResult> openAdInspector() => _sdk.openAdInspector();

  /// Tears down the whole graph. Banner/native controllers created via
  /// [banner]/[native] are owned by their widgets and disposed there.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _appOpen?.dispose();
    _interstitial?.dispose();
    _rewarded?.dispose();
    _rewardedInterstitial?.dispose();
    _appOpenController?.dispose();
    _coordinator.dispose();
    _adsEnabled.dispose();
    if (_ownsConsent) _consent.dispose();
    if (identical(_instance, this)) _instance = null;
  }
}
