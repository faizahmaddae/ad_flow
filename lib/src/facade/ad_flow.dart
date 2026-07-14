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
/// controllers → lifecycle) synchronously and returns immediately; SDK init,
/// consent gathering, request configuration and full-screen preloads all run
/// in the background (**non-blocking**, ADR-032 — render your first frame at
/// once, await [whenReady] only if you must). All collaborators are
/// injectable — tests build their own `AdFlow` over a `FakeAdSdk` (ADR-004:
/// no static state beyond the optional [instance] convenience pointer).
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
        if (config.rewarded != null)
          RewardedAdController.slotName: config.rewarded!.cap,
        if (config.rewardedInterstitial != null)
          RewardedInterstitialAdController.slotName:
              config.rewardedInterstitial!.cap,
      },
      globalCap: config.globalFrequencyCap,
      // The global cap paces INVOLUNTARY ads (interstitial, app-open). The
      // rewarded formats are reached only by an explicit user action — a tap on
      // "watch an ad for a reward", and for the rewarded interstitial a tap on
      // the mandatory intro's continue button — so the global cap must never
      // block them: the user would get no ad, no reward and no explanation
      // (ADR-039). Their impressions are still RECORDED globally, so an
      // interstitial cannot fire straight after one.
      globalCapExemptSlots: const {
        RewardedAdController.slotName,
        RewardedInterstitialAdController.slotName,
      },
    );
    _gate = AdGate(
      canRequestAds: _sdk.canRequestAds,
      isEnabled: () => _adsEnabled.value,
      caps: _caps,
      coordinator: _coordinator,
      configReady: _configApplied.future,
      settleConsent: _settleConsent,
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

  /// Builds the graph and starts ad_flow — **non-blocking** (ADR-032).
  ///
  /// The returned `Future` completes on the next microtask, **before**
  /// consent resolves: graph construction is synchronous, and consent, SDK
  /// init and request configuration all run in the background. **Render your
  /// first frame immediately — never gate UI on this Future** (that was v1's
  /// splash hang). Await [whenReady] only if you genuinely need the consent
  /// result. Nothing loads before request configuration is applied AND the
  /// consent gate is open (ADR-028/ADR-033), so rendering at once is safe.
  ///
  /// SDK init and consent gathering run in parallel (init sends no ad
  /// request); request configuration is applied after init completes (ADR-028).
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
    // IDEMPOTENT (ADR-044): a second initialize() replaces the first graph
    // instead of leaving it running. Apps DO re-initialize — on login/logout,
    // on a config change, on a debug hot restart — and every call builds a
    // whole new graph. Without this the previous one stayed fully alive: still
    // subscribed to the foreground stream, still preloading and refreshing,
    // still able to show ads, and coordinating through its OWN separate
    // FullScreenAdCoordinator, so it could not even see the new graph's ads.
    // That is v1 trap #6 — two lifecycle reactors fighting — coming back in
    // through the front door.
    //
    // Torn down AFTER the new graph is constructed, so a throwing constructor
    // (e.g. a missing rewardedIntroPresenter) leaves the working graph intact.
    final previous = _instance;
    if (previous != null && !previous._disposed) previous.dispose();

    // NON-BLOCKING (ADR-032): the whole graph is built synchronously above.
    // Publish the instance pointer and kick consent + SDK init in the
    // BACKGROUND, then return immediately — the caller's first frame must
    // never wait on the network-bound consent flow (that was v1's splash-hang
    // pain). Nothing loads before the consent gate opens (invariant 1), so a
    // caller can render its UI at once; ads/consent/ATT arrive over it. Await
    // [whenReady] only if you genuinely need the consent result.
    //
    // The returned Future completes on the next microtask (before consent).
    // `initialize` stays `async` so a synchronous constructor failure (e.g. a
    // missing rewardedIntroPresenter) still surfaces as a rejected Future.
    _instance = flow;
    flow._begin(consentDebug);
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

  /// Completes once `updateRequestConfiguration` has been applied in [_start]
  /// (or on [dispose]). `AdGate.canLoad` awaits it so no ad request — preload
  /// or on-demand first-frame banner/native — can precede request
  /// configuration now that startup runs in the background (ADR-033).
  final Completer<void> _configApplied = Completer<void>();

  InterstitialAdController? _interstitial;
  RewardedAdController? _rewarded;
  RewardedInterstitialAdController? _rewardedInterstitial;
  AppOpenAdController? _appOpenController;
  AppOpenAdManager? _appOpen;
  bool _disposed = false;
  late final Future<bool> _ready;

  // ── Consent, and its retry ────────────────────────────────────────────────
  //
  // The consent flow is the single gate every ad load waits behind, and it is
  // network-bound — so on this package's target population (mostly weak, slow,
  // intermittent connections) it is also the thing most likely to fail. It
  // used to run EXACTLY ONCE per session: a launch in airplane mode, or on a
  // connection too slow for the 30s info-update timeout, left
  // `canRequestAds()` false with nothing to ever re-ask — so the app served
  // ZERO ads for the whole session, even after the network came back seconds
  // later. Nothing surfaced it, because a closed gate looks exactly like a
  // user who declined.
  //
  // The gate now routes every load through [_settleConsent], which joins the
  // in-flight attempt and re-attempts a FAILED one.
  ConsentDebugOptions? _consentDebug;
  Future<bool>? _consentInFlight;
  bool _consentOpen = false;
  bool _consentRetryArmed = true;
  Timer? _consentRetryTimer;

  /// Minimum spacing between two consent attempts, so the gate re-checks that
  /// several controllers make while offline coalesce into one UMP call.
  static const _consentRetryInterval = Duration(seconds: 10);

  /// Kicks the background startup ([_start]) exactly once and stores its
  /// result future for [whenReady]. Errors are captured here — a background
  /// startup failure must never become an unhandled async error or reach
  /// [whenReady] as a throw (`_start` already degrades internally; this is a
  /// last-resort net).
  void _begin(ConsentDebugOptions? debug) {
    _ready = _start(debug).catchError((Object _) => false);
  }

  /// Completes when the background consent flow has resolved — its value is
  /// whether ads may be requested (`canRequestAds()`).
  ///
  /// **Not required for normal use.** [initialize] returns before this
  /// completes, and the app should render immediately; ads only ever load
  /// after the gate opens (invariant 1). Await this only if you genuinely
  /// need to block on the consent result (e.g. a settings screen that must
  /// reflect the final consent state). It never throws.
  Future<bool> get whenReady => _ready;

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

  /// Awaited by [AdGate.canLoad] before it reads `canRequestAds()`.
  ///
  /// Joins the consent attempt that is already in flight (so a first-frame
  /// banner simply waits for consent to resolve, instead of reading a
  /// still-false answer and sleeping out a 5-minute cooldown), and RE-ATTEMPTS
  /// one that previously failed (so an offline launch recovers when the
  /// network returns).
  ///
  /// A user who merely DECLINED is a settled answer, not a failure: the flow
  /// completed and `lastError` is null, so it is never re-run — re-prompting
  /// them on a timer would be both hostile and a policy problem.
  Future<void> _settleConsent() async {
    if (_disposed || _consentOpen) return;

    final inFlight = _consentInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    // The last attempt finished without opening the gate. Only retry a genuine
    // FAILURE (network/timeout/platform error — surfaced on lastError), and at
    // most once per _consentRetryInterval so several controllers re-checking
    // the gate at once coalesce into a single UMP call.
    if (_consent.lastError == null || !_consentRetryArmed) return;
    await _runConsent(_consentDebug);
  }

  /// Runs one consent attempt, publishing it on [_consentInFlight] so
  /// concurrent [_settleConsent] callers join it rather than starting a second.
  Future<bool> _runConsent(ConsentDebugOptions? debug) {
    _consentRetryArmed = false;
    final run = _consent.ensureCanRequestAds(debug: debug);
    _consentInFlight = run;
    return run
        .then((open) {
          _consentOpen = open;
          return open;
        })
        .whenComplete(() {
          if (identical(_consentInFlight, run)) _consentInFlight = null;
          if (_disposed || _consentOpen) return;
          // Re-arm the retry after a cooldown, so a still-offline device keeps
          // trying (at a sane rate) rather than giving up for the session.
          _consentRetryTimer?.cancel();
          _consentRetryTimer = Timer(
            _consentRetryInterval,
            () => _consentRetryArmed = true,
          );
        });
  }

  Future<bool> _start(ConsentDebugOptions? debug) async {
    // Consent (UMP) is independent of the Ads SDK and safe to run in
    // parallel with everything below.
    //
    // This call is INSIDE the try below (not before it): AdGate.canLoad awaits
    // _configApplied, so any throw that escapes before the `finally` runs
    // would hang EVERY ad load in the app forever. An injected ConsentGateway
    // whose ensureCanRequestAds throws synchronously is enough to trigger it.
    final Future<bool> consent;

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
    //
    // Everything up to releasing the config gate runs in a try/finally: the
    // config gate (_configApplied) MUST be released no matter what, or every
    // ad load — which now awaits it in AdGate.canLoad (ADR-033) — would hang
    // forever on a startup hiccup (worst on weak internet). The timeouts bound
    // a *hung* init/config; the `finally` covers any *thrown* path.
    try {
      _consentDebug = debug;
      consent = _runConsent(debug);

      await _sdk.initialize().timeout(_initTimeout).catchError((Object _) {});

      // Now that the Ads SDK is initialized, apply request configuration.
      // This still runs UNCONDITIONALLY (not gated on the consent *result*):
      // it sends no ad request, and controllers loading ads later must have
      // testDeviceIds/tagForChildDirectedTreatment/maxAdContentRating/
      // tagForUnderAgeOfConsent applied regardless of how or when consent
      // resolves (review finding #5: otherwise a registered test device gets
      // live ads, and a child-directed app serves untagged/wrongly-rated
      // ads). Bounded by _initTimeout so a hung config call can't wedge loads.
      await _sdk
          .updateRequestConfiguration(_config.toRequestConfig())
          .timeout(_initTimeout)
          .catchError((Object _) {});
    } finally {
      // ALWAYS release the config gate — even if init/config threw, timed out,
      // or hung past the timeout. A failed/slow config setter must let loads
      // DEGRADE (proceed without config) rather than await forever; that is no
      // worse than not using ad_flow at all.
      if (!_configApplied.isCompleted) _configApplied.complete();
    }

    // Gate ad loads on consent (init already awaited above).
    final canRequestAds = await consent;

    // Since startup runs in the background (ADR-032), the app may have called
    // dispose() while we were awaiting consent — don't start a manager or kick
    // preloads on a torn-down graph.
    if (_disposed) return canRequestAds;

    // The manager and controllers gate every load themselves, so starting
    // them with a closed gate is safe — they simply stay idle.
    _appOpen?.start();
    unawaited(_interstitial?.load());
    unawaited(_rewarded?.load());
    unawaited(_rewardedInterstitial?.load());
    return canRequestAds;
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
      coordinator: _coordinator,
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
      coordinator: _coordinator,
      retry: RetryPolicy(_config.retry),
      onPaid: _dispatchPaid,
    );
  }

  /// Tells ad_flow that a **blocking** banner or native ad currently occupies
  /// the screen, so no app-open ad is shown over it (ADR-042).
  ///
  /// AdMob objects to an app-open ad covering content that is itself already
  /// showing an ad. ad_flow cannot decide this for you: whether a banner is
  /// "blocking" is a question about YOUR layout — a small anchored banner below
  /// the content usually is not; a large native card filling the screen is. So
  /// call this from the screens where it matters:
  ///
  /// ```dart
  /// @override
  /// void initState() {
  ///   super.initState();
  ///   ads.setBlockingViewAdVisible(true);
  /// }
  ///
  /// @override
  /// void dispose() {
  ///   ads.setBlockingViewAdVisible(false);
  ///   super.dispose();
  /// }
  /// ```
  ///
  /// ad_flow handles the *click* case for you already — returning from a banner
  /// or native ad the user tapped never shows an app-open ad. This flag is for
  /// the *placement* case, which only the app can know. Ad placement remains
  /// partly the integrator's responsibility.
  void setBlockingViewAdVisible(bool visible) =>
      _coordinator.blockingViewAdVisible = visible;

  /// Opens the Ad Inspector debug overlay.
  Future<AdInspectorResult> openAdInspector() => _sdk.openAdInspector();

  /// Tears down the whole graph. Banner/native controllers created via
  /// [banner]/[native] are owned by their widgets and disposed there.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _consentRetryTimer?.cancel();
    _consentRetryTimer = null;
    // Release any load parked in AdGate.canLoad awaiting config (a background
    // startup may not have applied it yet) — the controllers are disposed
    // below, so those loads then bail on their own _disposed guard instead of
    // waiting out the init timeout.
    if (!_configApplied.isCompleted) _configApplied.complete();
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
