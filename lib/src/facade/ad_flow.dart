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
import '../core/ad_block_reason.dart';
import '../core/ad_controller.dart';
import '../core/ad_flow_error.dart';
import '../core/callback_guard.dart';
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
    Future<void> Function()? consentForwarder,
  }) : _config = config,
       _sdk = sdk,
       _consent = consentGateway,
       _ownsConsent = ownsConsent,
       _platform = platform,
       _consentForwarder = consentForwarder,
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
      // The global cap paces INVOLUNTARY interruptions. Classic rewarded is
      // exempt: it is reached only by an explicit "watch an ad for a reward"
      // tap, and refusing that tap means no ad, no reward, no explanation
      // (ADR-039). The rewarded INTERSTITIAL is NOT exempt (4.0, revising
      // ADR-039): its intro appears at an app-chosen transition the user did
      // not ask for — the intro itself is the interruption the global cap
      // exists to pace — and since the whole sequence is now preflighted
      // BEFORE the intro (atomic reservation), a capped sequence simply never
      // starts; the user is never promised an ad and then refused one.
      // Impressions of BOTH rewarded formats are still recorded globally, so
      // an interstitial cannot fire straight after either.
      globalCapExemptSlots: const {RewardedAdController.slotName},
    );
    _gate = AdGate(
      canRequestAds: _sdk.canRequestAds,
      // `!_disposed` first: widget-owned banner/native controllers minted via
      // [banner]/[native] outlive this graph's dispose() (ADR-044 replaces
      // the graph; widgets dispose their controllers on their own schedule).
      // A dead graph's gate must refuse every load, or those leftovers would
      // keep serving ads wired to disposed collaborators (2026-07 audit).
      isEnabled: () => !_disposed && _adsEnabled.value,
      settleRequestConfig: _settleRequestConfig,
      settleConsent: _settleConsent,
      settleConsentForwarding: _settleConsentForwarding,
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
        onBlocked: _dispatchBlocked,
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
        onBlocked: _dispatchBlocked,
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
        onBlocked: _dispatchBlocked,
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
        onBlocked: _dispatchBlocked,
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
  /// [forwardConsent] is the **fail-closed consent-forwarding barrier**: an
  /// async callback that pushes the user's consent to mediation networks
  /// which do NOT read the IAB TCF string themselves (Unity's MetaData calls,
  /// AppLovin's US-state flag, Meta's Limited Data Use — read the `IABTCF_*` /
  /// `IABGPP_*` keys and call the partner SDK). It runs after consent settles,
  /// and every MEDIATION-CAPABLE ad load *waits* for it to SUCCEED before the
  /// request goes out — unlike the fire-and-forget [onConsentChanged] field
  /// (assignable only *after* `initialize` returns, so it can miss the initial
  /// flow). Fail-CLOSED by default ([AdFlowConfig.mediationConsentPolicy]): a
  /// failed/timed-out forward BLOCKS the load
  /// ([AdBlockReason.consentNotForwarded]) and is retried in the background —
  /// the slot recovers when forwarding succeeds — rather than quietly sending
  /// an unsignalled request. It never blocks UI ([whenReady] resolves on
  /// consent alone), and it re-establishes on every consent change before the
  /// next request, not only at startup. See doc/MEDIATION_SETUP.md and
  /// [AdFlowConfig.deferMediationInit].
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
    Future<void> Function()? forwardConsent,
  }) async {
    // Fail fast on nonsense (empty ad unit strings, negative durations) —
    // discoverable at init, instead of silent no-fill in production
    // (2026-07 audit). Throws AdFlowError(invalidConfig); initialize stays
    // async, so this surfaces as a rejected Future.
    config.validate();
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
      consentForwarder: forwardConsent,
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

  /// Backs [canRequestAds]; refreshed after every consent flow completion
  /// and every consent mutation through [consent].
  final ValueNotifier<bool> _canRequestAdsNotifier = ValueNotifier(false);

  /// LIVE consent answer, reactive (3.0): whether ads may currently be
  /// requested.
  ///
  /// Unlike [whenReady] — a one-shot snapshot of the FIRST consent flow —
  /// this follows later changes too: an ADR-035 retry that succeeds once the
  /// network returns flips it true; a withdrawal in the privacy-options form
  /// flips it false. Use it to show/hide consent-dependent UI reactively.
  ValueListenable<bool> get canRequestAds => _canRequestAdsNotifier;

  /// Re-reads the SDK's consent answer into [canRequestAds] (best-effort).
  void _refreshCanRequestAds() {
    unawaited(
      _sdk
          .canRequestAds()
          .then((value) {
            if (!_disposed) _canRequestAdsNotifier.value = value;
          })
          .catchError((Object _) {}),
    );
  }

  // ── Request configuration, and its retry (4.0 audit) ─────────────────────
  //
  // `updateRequestConfiguration` is a PROCESS like consent, not a one-shot:
  // its failure/timeout must be retryable and — when the config carries
  // policy-critical fields — must fail CLOSED for ad loading rather than
  // silently degrade (a child-directed app sending untagged requests, a
  // registered test device receiving live ads). The old design released a
  // one-shot gate in a `finally`, so any failure meant every session load
  // went out unconfigured, invisibly, forever.
  //
  // Ordering is load-bearing (ADR-028): the plugin services
  // `updateRequestConfiguration` synchronously on the platform thread and it
  // races a still-running background `initialize()` bootstrap into a
  // platform-thread deadlock — so an apply attempt NEVER dispatches while
  // init is genuinely in flight, not even after our bounded wait timed out.

  /// The ACTUAL native init completion (error-contained), regardless of the
  /// bounded wait in [_start] timing out.
  Future<void>? _initInFlight;
  bool _initDone = false;

  /// FACT: `updateRequestConfiguration` has been applied successfully.
  bool _requestConfigApplied = false;
  Future<void>? _configAttemptInFlight;
  bool _configRetryArmed = true;
  Timer? _configRetryTimer;

  /// Whether a failed/absent request configuration must BLOCK loads.
  bool get _configFailurePolicyIsClosed =>
      switch (_config.requestConfigPolicy) {
        RequestConfigFailurePolicy.failClosed => true,
        RequestConfigFailurePolicy.failOpen => false,
        RequestConfigFailurePolicy.auto =>
          _config.requestConfigIsPolicySensitive,
      };

  /// Awaited by `AdGate.canLoad` before every load: joins the in-flight
  /// bounded apply attempt (or starts one, rate-limited), then answers
  /// whether loads may proceed with respect to request configuration.
  Future<bool> _settleRequestConfig() async {
    if (_disposed) return false;
    if (_requestConfigApplied) return true;
    final inFlight = _configAttemptInFlight;
    if (inFlight != null) {
      await inFlight;
    } else if (_configRetryArmed) {
      await _runConfigAttempt();
    }
    return _requestConfigApplied || !_configFailurePolicyIsClosed;
  }

  /// Runs one bounded apply attempt, published on [_configAttemptInFlight]
  /// so concurrent gate checks join it instead of stacking channel calls.
  Future<void> _runConfigAttempt() {
    _configRetryArmed = false;
    final attempt = _applyRequestConfigOnce();
    _configAttemptInFlight = attempt;
    return attempt.whenComplete(() {
      if (identical(_configAttemptInFlight, attempt)) {
        _configAttemptInFlight = null;
      }
      if (_disposed || _requestConfigApplied) return;
      _configRetryTimer?.cancel();
      _configRetryTimer = Timer(
        _consentRetryInterval,
        () => _configRetryArmed = true,
      );
    });
  }

  /// How long one apply attempt waits for a still-pending init before
  /// answering "not applied yet". Short by design: a normally-pending init
  /// (~1s on a warm device) is joined inline — the ADR-033 first-frame load
  /// then proceeds with config applied, no backoff detour — while a genuinely
  /// hung init fails attempts FAST into a visible AdBlocked instead of
  /// parking every gate pass for the full init timeout.
  static const _configInitJoinBound = Duration(seconds: 2);

  Future<void> _applyRequestConfigOnce() async {
    // ADR-028: never dispatch while native init is in flight — the plugin
    // services updateRequestConfiguration synchronously on the platform
    // thread and it races a live init bootstrap into a deadlock. If init has
    // not completed, join it briefly; past the bound, report not-applied and
    // let the init-completion hook / retry machinery finish the job.
    if (!_initDone) {
      final init = _initInFlight;
      if (init == null) return;
      try {
        await init.timeout(_configInitJoinBound);
      } catch (_) {
        return;
      }
    }
    if (_disposed || _requestConfigApplied) return;
    try {
      await _sdk
          .updateRequestConfiguration(_config.toRequestConfig())
          .timeout(_initTimeout);
      _requestConfigApplied = true;
    } catch (error, stack) {
      // Contained and REPORTED — a silent config loss is the failure mode
      // this machinery exists to remove.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'ad_flow',
          context: ErrorDescription(
            'while applying the ad request configuration (will retry; loads '
            'are ${_configFailurePolicyIsClosed ? "BLOCKED until it succeeds" : "proceeding without it"} per RequestConfigFailurePolicy)',
          ),
        ),
      );
    }
  }

  InterstitialAdController? _interstitial;
  RewardedAdController? _rewarded;
  RewardedInterstitialAdController? _rewardedInterstitial;
  AppOpenAdController? _appOpenController;
  AppOpenAdManager? _appOpen;
  bool _disposed = false;
  late final Future<bool> _ready;

  /// Widget-owned banner/native controllers minted via [banner]/[native],
  /// tracked so gate-relevant changes (Remove-Ads, consent mutations,
  /// dispose) can DROP their live ads — with `minRefresh` off by default
  /// (ADR-041) nothing else ever re-checks a mounted view ad's permission
  /// (2026-07 audit). Controllers deregister themselves on dispose.
  final Set<AdController> _mintedViewControllers = {};

  /// Re-evaluates every controller's permission — see
  /// [AdController.recheckGate].
  void _recheckAll() {
    unawaited(_interstitial?.recheckGate());
    unawaited(_rewarded?.recheckGate());
    unawaited(_rewardedInterstitial?.recheckGate());
    unawaited(_appOpenController?.recheckGate());
    // Copy: a controller disposed mid-iteration mutates the set.
    for (final controller in List.of(_mintedViewControllers)) {
      unawaited(controller.recheckGate());
    }
  }

  /// Called by the [consent] wrapper after any consent-mutating call
  /// completes (a privacy-options form the user may have used to withdraw,
  /// an app-driven `ensureCanRequestAds`, a test `reset`) so ads that are no
  /// longer permitted come down and newly-permitted slots load (2026-07
  /// audit; a withdrawal used to be entirely unobservable — nothing dropped
  /// a mounted banner, while AdMob's server-side auto-refresh kept
  /// requesting ads for it).
  void _afterConsentMutation() {
    if (_disposed) return;
    _refreshCanRequestAds();
    _dispatchConsentChanged();
    // A privacy-options change / re-run / reset makes any prior forward stale.
    // Invalidate it so the forwarding barrier re-establishes BEFORE the next
    // newly-permitted load (the same fail-closed ordering as the first load,
    // not only at startup — 4.1 release gate). `_recheckAll` then drives the
    // reloads that hit the gate and re-forward.
    _invalidateConsentForwarding();
    _recheckAll();
  }

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

  // ── Consent forwarding barrier (fail-closed by default; 4.1 release gate) ──
  //
  // A mediation network that does not read the IAB TCF/GPP string itself needs
  // its per-network privacy signal (Unity MetaData, AppLovin US flag, Meta
  // LDU) set BEFORE it fills an ad request. `forwardConsent` is that signal.
  //
  // The gate treats this like request configuration: a MEDIATION-CAPABLE load
  // waits for forwarding to SUCCEED, and — fail-CLOSED by default — is
  // BLOCKED ([AdBlockReason.consentNotForwarded]) if it has not, rather than
  // quietly sending an unsignalled request. The forwarder is retried in the
  // background and every gate re-check re-joins it, so a blocked slot recovers
  // the moment forwarding succeeds. `MediationConsentFailurePolicy.failOpen`
  // is the explicit, unsafe opt-out. UI never blocks — only the ad request.

  /// The app-supplied consent-forwarding barrier (null = not opted in).
  final Future<void> Function()? _consentForwarder;

  /// Bounds one forwarding attempt so a slow/broken forwarder fails the
  /// attempt (→ blocked + retried under fail-closed) rather than parking the
  /// gate. Consistent with [_settleRequestConfig] and non-blocking init.
  static const _forwardConsentTimeout = Duration(seconds: 15);

  /// FACT: forwarding has completed successfully for the current consent
  /// generation.
  bool _consentForwarded = false;
  Future<void>? _forwardAttemptInFlight;
  bool _forwardRetryArmed = true;
  Timer? _forwardRetryTimer;

  /// Bumped on every consent MUTATION so an in-flight forward that started
  /// under the OLD consent state cannot mark the NEW state as forwarded
  /// (latest-value-wins across a mutation during forwarding).
  int _consentGeneration = 0;

  /// True once [AdSdk.disableMediationInitialization] has succeeded (or was
  /// not requested), so the retry loop stops.
  bool _deferMediationDone = false;

  /// True once a requested [AdFlowConfig.deferMediationInit] has DEFINITIVELY
  /// failed (all attempts exhausted). Unrecoverable — the plugin no-ops the
  /// deferral once `initialize()` has run — so under fail-closed this keeps
  /// mediation-capable loads blocked (the requested ordering is lost).
  bool _mediationDeferralFailed = false;

  /// Completes when the deferral has SETTLED (succeeded or definitively
  /// failed) in [_start]. The forwarding barrier awaits it so a load can
  /// never slip through WHILE the deferral is still in flight and then have
  /// it fail — the guarantee is structural, not timing-dependent. An
  /// already-complete future when deferral was not requested. Bounded by the
  /// init timeout on the barrier side, so it never parks a load forever.
  final Completer<void> _deferMediationSettled = Completer<void>();

  /// Whether the publisher opted into strict mediation consent ordering.
  bool get _mediationConsentRequired =>
      _consentForwarder != null || _config.deferMediationInit;

  /// Whether a failed/incomplete forwarding-or-deferral must BLOCK
  /// mediation-capable loads (the default) vs. serve anyway (explicit unsafe).
  bool get _mediationConsentFailClosed =>
      _config.mediationConsentPolicy ==
      MediationConsentFailurePolicy.failClosed;

  /// Awaited by `AdGate.loadBlockReason` AFTER the consent gate opens, before
  /// a mediation-capable request. Answers whether the load may proceed with
  /// respect to consent forwarding / mediation-init deferral.
  Future<bool> _settleConsentForwarding() async {
    if (!_mediationConsentRequired) return true; // non-adopter: no barrier
    if (_disposed) return false;
    // If deferral was requested, WAIT for it to settle before deciding — a
    // load must never slip through while the deferral is still in flight and
    // then have it fail (a structural guarantee, not a timing assumption).
    // Bounded so a hung startup never parks the load forever.
    if (_config.deferMediationInit && !_deferMediationSettled.isCompleted) {
      try {
        await _deferMediationSettled.future.timeout(_initTimeout);
      } catch (_) {
        // Still not settled — treat as not-yet-safe: fail-closed blocks,
        // fail-open proceeds; either way the next gate re-check re-evaluates.
        return !_mediationConsentFailClosed;
      }
      if (_disposed) return false;
    }
    // Deferral is an init-time, one-shot call — a definitive failure cannot be
    // retried. The strict ordering the publisher asked for is permanently
    // lost, so under fail-closed we refuse mediation-capable loads.
    if (_mediationDeferralFailed) return !_mediationConsentFailClosed;
    if (_consentForwarder == null) return true; // deferral ok, no forwarder
    if (_consentForwarded) return true; // already forwarded this generation
    final inFlight = _forwardAttemptInFlight;
    if (inFlight != null) {
      await inFlight;
    } else if (_forwardRetryArmed) {
      await _runForwardAttempt();
    }
    return _consentForwarded || !_mediationConsentFailClosed;
  }

  /// Runs one bounded forwarding attempt, published on [_forwardAttemptInFlight]
  /// so concurrent gate checks join it instead of stacking forwarder calls.
  Future<void> _runForwardAttempt() {
    _forwardRetryArmed = false;
    final attempt = _forwardConsentOnce(_consentGeneration);
    _forwardAttemptInFlight = attempt;
    return attempt.whenComplete(() {
      if (identical(_forwardAttemptInFlight, attempt)) {
        _forwardAttemptInFlight = null;
      }
      if (_disposed || _consentForwarded) return;
      // Re-arm after a cooldown so a still-failing forwarder keeps being
      // retried (at a sane rate) and a blocked slot recovers on its own.
      _forwardRetryTimer?.cancel();
      _forwardRetryTimer = Timer(
        _consentRetryInterval,
        () => _forwardRetryArmed = true,
      );
    });
  }

  /// Runs the forwarder once, bounded and error-contained. On success marks
  /// [_consentForwarded] — but only if [generation] still matches, so a
  /// forward that raced a consent mutation cannot mark the new state forwarded.
  Future<void> _forwardConsentOnce(int generation) async {
    final forwarder = _consentForwarder;
    if (forwarder == null || _disposed) return;
    try {
      await Future<void>.sync(forwarder).timeout(_forwardConsentTimeout);
      if (!_disposed && generation == _consentGeneration) {
        _consentForwarded = true;
      }
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'ad_flow',
          context: ErrorDescription(
            'while forwarding consent to mediation networks (will retry; '
            'mediation-capable loads are '
            '${_mediationConsentFailClosed ? "BLOCKED until it succeeds" : "proceeding without it"} '
            'per MediationConsentFailurePolicy)',
          ),
        ),
      );
    }
  }

  /// Invalidates a completed forward so the barrier re-runs it before the next
  /// mediation-capable load — after a consent MUTATION (withdrawal/change) the
  /// forwarded signal is stale. Bumps the generation so an in-flight forward
  /// from the old state cannot mark the new one forwarded.
  ///
  /// Deliberately does NOT null [_forwardAttemptInFlight]: an in-flight
  /// attempt is left in place so a post-mutation load JOINS it rather than
  /// launching a second, concurrent invocation of the app's `forwardConsent`
  /// callback (release-gate review: repeated mutations during a slow forwarder
  /// otherwise stacked overlapping calls). The stale attempt completes without
  /// marking the new generation forwarded (the generation guard), so the load
  /// still blocks fail-closed and a fresh, correctly-generationed forward runs
  /// next — at most one `forwardConsent` call is ever in flight.
  void _invalidateConsentForwarding() {
    _consentGeneration++;
    _consentForwarded = false;
    _forwardRetryArmed = true;
  }

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

  /// Completes when the FIRST background consent flow has resolved — its
  /// value is whether ads could be requested at that moment.
  ///
  /// **Not required for normal use.** [initialize] returns before this
  /// completes, and the app should render immediately; ads only ever load
  /// after the gate opens (invariant 1). Await this only if you genuinely
  /// need to block on the consent result. It never throws.
  ///
  /// **A one-shot snapshot, not live state**: a failed flow that the ADR-035
  /// retry later recovers, or a consent withdrawal in the privacy-options
  /// form, does NOT change what this already completed with. For the current
  /// answer ask [consent] (`lastError`, or re-run `ensureCanRequestAds`).
  Future<bool> get whenReady => _ready;

  /// Impression-level revenue callback for every format (allowlisted
  /// AdMob accounts only). Assignable at any time.
  void Function(AdPaidEvent event)? onPaidEvent;

  void _dispatchPaid(AdPaidEvent event) => onPaidEvent?.call(event);

  /// Called (isolated) after every consent flow or consent mutation
  /// completes: the initial background flow, an ADR-035 retry that finally
  /// succeeds, a privacy-options form the user may have used to change or
  /// withdraw consent, and a test reset (4.0).
  ///
  /// This is the hook for forwarding consent to mediation networks that do
  /// not read the IAB TCF string themselves: read the UMP-written state
  /// (`IABTCF_*` / `IABGPP_*` keys in the platform's default preferences)
  /// and call the partner SDK's own privacy APIs here — Google explicitly
  /// does NOT propagate consent to such networks automatically. See
  /// doc/MEDIATION_SETUP.md, and [AdFlowConfig.deferMediationInit] for
  /// partners that need their flags before their SDK spins up.
  void Function()? onConsentChanged;

  void _dispatchConsentChanged() {
    final onChanged = onConsentChanged;
    if (onChanged == null) return;
    guardedCallback(onChanged, debugName: 'onConsentChanged');
  }

  /// Called whenever a load or show is REFUSED, with the slot name and the
  /// reason (ADR-045). Assignable at any time.
  ///
  /// This is the answer to "why aren't my ads showing?". A refused load leaves
  /// the controller at `AdIdle` — identical to "nothing requested yet" — so
  /// consent never gathered, Remove-Ads still on, and a frequency cap quietly
  /// doing its job all looked the same, and the package logs nothing
  /// (`avoid_print` is on). Wire this to your logger during a rollout:
  ///
  /// ```dart
  /// ads.onAdBlocked = (slot, reason) => log.info('ad_flow: \$slot blocked: \${reason.name}');
  /// ```
  ///
  /// A per-slot snapshot is also available as `controller.lastBlockReason`.
  /// Most reasons are NORMAL (a cap doing its job, a user who skipped the
  /// rewarded intro) — this is a diagnostic, not an error channel.
  void Function(String slot, AdBlockReason reason)? onAdBlocked;

  void _dispatchBlocked(String slot, AdBlockReason reason) =>
      onAdBlocked?.call(slot, reason);

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

  /// Runs one consent attempt.
  ///
  /// Consent forwarding is deliberately NOT folded into this chain (4.1
  /// release gate): it is a separate gate barrier ([_settleConsentForwarding])
  /// that only the MEDIATION-CAPABLE load path awaits, so (a) `whenReady` and
  /// the consent notifier resolve on consent alone — forwarding never delays
  /// UI — and (b) forwarding runs lazily, once, before the first PERMITTED
  /// load, and is fail-CLOSED there rather than degrade-open here.
  Future<bool> _runConsent(ConsentDebugOptions? debug) {
    _consentRetryArmed = false;
    final run = _consent.ensureCanRequestAds(debug: debug);
    final published = run.then((open) {
      _consentOpen = open;
      if (!_disposed) {
        _canRequestAdsNotifier.value = open;
        // A completed consent flow (initial, or a retry that finally resolved)
        // is a forwarding point: invalidate any prior forward so the barrier
        // re-runs it against the fresh state, and fire the observability hook.
        _invalidateConsentForwarding();
        _dispatchConsentChanged();
      }
      return open;
    });
    _consentInFlight = published;
    return published.whenComplete(() {
      if (identical(_consentInFlight, published)) _consentInFlight = null;
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
    _consentDebug = debug;
    final consent = _runConsent(debug);

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
    //
    // 4.0 hardening: the config attempt keys off the ACTUAL init completion
    // (`_initDone`), not our bounded wait below — the old code dispatched
    // config right after the 30s wait timed out, which is exactly when the
    // native init may still be mid-bootstrap, quietly re-opening the ADR-028
    // race on the slowest devices. If init lands later, the completion hook
    // below applies the configuration then.
    // Opt-in mediation-init deferral (4.0): must precede initialize() (the
    // plugin no-ops it afterwards). Best-effort — a failure only means
    // adapters auto-init as usual — but REPORTED, not swallowed (4.1): this
    // is a policy-ORDERING primitive, so a lost guarantee (a partner adapter
    // now spins up before its consent flags are forwarded) must be visible,
    // matching the request-config "no silent config loss" contract.
    if (_config.deferMediationInit) {
      // Retry the deferral a few times BEFORE init — it must land before
      // initialize(), which the plugin no-ops it after, so there is no second
      // chance later. A definitive failure sets _mediationDeferralFailed, and
      // under the fail-closed policy the gate then blocks mediation-capable
      // loads: the strict ordering the publisher explicitly requested could
      // not be honoured, and quietly requesting anyway is the exact risk this
      // opt-in exists to prevent (4.1 release gate).
      Object? deferError;
      StackTrace? deferStack;
      for (var attempt = 0; attempt < 3 && !_deferMediationDone; attempt++) {
        try {
          await _sdk.disableMediationInitialization();
          _deferMediationDone = true;
        } catch (error, stack) {
          deferError = error;
          deferStack = stack;
        }
      }
      if (!_deferMediationDone) {
        _mediationDeferralFailed = true;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: deferError ?? StateError('deferMediationInit failed'),
            stack: deferStack,
            library: 'ad_flow',
            context: ErrorDescription(
              'while deferring mediation adapter initialization '
              '(deferMediationInit); the requested ordering could not be '
              'established. Mediation-capable loads are '
              '${_mediationConsentFailClosed ? "BLOCKED (MediationConsentFailurePolicy.failClosed)" : "proceeding (MediationConsentFailurePolicy.failOpen)"} '
              '— a partner needing pre-init privacy flags may not have '
              'received them before its SDK started',
            ),
          ),
        );
      }
    }
    // Deferral has now settled (succeeded, definitively failed, or was never
    // requested): release the barrier's wait so loads can decide.
    if (!_deferMediationSettled.isCompleted) _deferMediationSettled.complete();

    Future<void>? init;
    try {
      init = _sdk.initialize();
    } catch (_) {
      // A synchronously-throwing seam: no init future at all. The config
      // attempt will refuse to dispatch (never safe), and loads degrade per
      // the RequestConfigFailurePolicy.
    }
    if (init != null) {
      final tracked = init.catchError((Object _) {});
      _initInFlight = tracked;
      unawaited(
        tracked.whenComplete(() {
          _initDone = true;
          // Late init (past the bounded wait): apply the configuration now —
          // fail-open sessions get it from this point on; fail-closed slots
          // unblock on their next gate re-check.
          if (!_disposed && !_requestConfigApplied) {
            unawaited(_settleRequestConfig());
          }
        }),
      );
      try {
        await tracked.timeout(_initTimeout);
      } catch (_) {
        // Init is merely slow — carry on; the hook above finishes the job.
      }
    }

    // Apply request configuration (first attempt; retried on failure, and
    // every gate check joins/re-kicks it). Still UNCONDITIONAL with respect
    // to the consent *result* (review finding #5): it sends no ad request,
    // and test-device/COPPA/rating settings must reach the SDK regardless of
    // how consent resolves. Skipped while init is still pending — the
    // completion hook above owns the late apply, and waiting a second
    // 30s bound here would double the worst-case `whenReady` for nothing.
    if (_initDone) await _settleRequestConfig();

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
  ///
  /// Returned through a thin wrapper: after any consent-MUTATING call
  /// completes ([ConsentGateway.showPrivacyOptions],
  /// [ConsentGateway.ensureCanRequestAds], [ConsentGateway.reset]), the
  /// graph re-checks every controller so a withdrawal drops live/warm ads
  /// and a newly-opened gate loads idle slots (2026-07 audit). Use this —
  /// not a directly-constructed gateway — for the `PrivacyOptionsButton`.
  ConsentGateway get consent => _consentView;
  late final ConsentGateway _consentView = _GraphAwareConsentGateway(
    _consent,
    this,
  );

  /// Whether ads are enabled (Remove-Ads state). Reactive for widgets.
  ValueListenable<bool> get adsEnabled => _adsEnabled;

  /// Re-enables ad loading after [disableAds] and re-warms inventory at
  /// once (no gate-recheck backoff wait).
  void enableAds() {
    _adsEnabled.value = true;
    _recheckAll();
  }

  /// Blocks every future ad load/show (e.g. the user bought Remove-Ads) and
  /// DROPS every live/warm ad, including mounted banner/native ads minted
  /// via [banner]/[native] (their widgets fall back to the placeholder;
  /// also hide them via [adsEnabled] for a clean layout). Before this
  /// dropped live ads, a Remove-Ads purchaser kept seeing — and AdMob kept
  /// server-side refreshing — the already-mounted banner (2026-07 audit).
  void disableAds() {
    _adsEnabled.value = false;
    _recheckAll();
  }

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

  // ── Null-safe slot access ─────────────────────────────────────────────
  //
  // The throwing getters above fail fast on a MISCONFIGURATION. But a slot
  // can be absent by DESIGN — most commonly an ad unit configured for one
  // platform only — and shared cross-platform code should degrade, not
  // crash, on the platform without it (2026-07 audit).

  /// The interstitial controller, or null when the slot is not configured
  /// for this platform.
  InterstitialAdController? get interstitialOrNull => _interstitial;

  /// The rewarded controller, or null when the slot is not configured for
  /// this platform.
  RewardedAdController? get rewardedOrNull => _rewarded;

  /// The rewarded interstitial controller, or null when the slot is not
  /// configured for this platform.
  RewardedInterstitialAdController? get rewardedInterstitialOrNull =>
      _rewardedInterstitial;

  /// The app open manager, or null when the slot is not configured for this
  /// platform.
  AppOpenAdManager? get appOpenOrNull => _appOpen;

  /// The app open controller, or null when the slot is not configured for
  /// this platform.
  AppOpenAdController? get appOpenControllerOrNull => _appOpenController;

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
    late final BannerAdController controller;
    controller = BannerAdController(
      sdk: _sdk,
      gate: _gate,
      config: config,
      adUnitId: adUnitId,
      coordinator: _coordinator,
      retry: RetryPolicy(_config.retry),
      onPaid: _dispatchPaid,
      onBlocked: _dispatchBlocked,
      onDisposed: () => _mintedViewControllers.remove(controller),
    );
    _mintedViewControllers.add(controller);
    return controller;
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
    late final NativeAdController controller;
    controller = NativeAdController(
      sdk: _sdk,
      gate: _gate,
      config: config,
      adUnitId: adUnitId,
      coordinator: _coordinator,
      retry: RetryPolicy(_config.retry),
      onPaid: _dispatchPaid,
      onBlocked: _dispatchBlocked,
      onDisposed: () => _mintedViewControllers.remove(controller),
    );
    _mintedViewControllers.add(controller);
    return controller;
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
  /// [banner]/[native] are owned by their widgets and disposed there — but
  /// their ads are DROPPED here (the dead graph's gate refuses everything
  /// from now on), so a leftover widget shows its placeholder rather than an
  /// ad served through disposed collaborators (2026-07 audit).
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // With _disposed set, the gate reads closed: this drop-recheck brings
    // down every minted view controller's live ad. Runs before the owned
    // controllers are disposed below (their own dispose is the stronger
    // teardown; the recheck they get is a harmless no-op afterwards).
    _recheckAll();
    _consentRetryTimer?.cancel();
    _consentRetryTimer = null;
    _configRetryTimer?.cancel();
    _configRetryTimer = null;
    _forwardRetryTimer?.cancel();
    _forwardRetryTimer = null;
    // Release any load parked on the deferral-settled barrier (a mid-startup
    // dispose); _settleConsentForwarding then answers false on the disposed
    // graph and the controllers bail on their own _disposed guard.
    if (!_deferMediationSettled.isCompleted) _deferMediationSettled.complete();
    // Loads parked in a joined config attempt resolve when that bounded
    // attempt does; _settleRequestConfig answers false on a disposed graph
    // and the controllers bail on their own _disposed guard.
    _appOpen?.dispose();
    _interstitial?.dispose();
    _rewarded?.dispose();
    _rewardedInterstitial?.dispose();
    _appOpenController?.dispose();
    _coordinator.dispose();
    _adsEnabled.dispose();
    _canRequestAdsNotifier.dispose();
    if (_ownsConsent) _consent.dispose();
    if (identical(_instance, this)) _instance = null;
  }
}

/// Thin [ConsentGateway] wrapper the facade hands out via [AdFlow.consent]:
/// after any consent-MUTATING call completes it re-checks every controller,
/// so a consent withdrawal in the privacy-options form drops live/warm ads
/// and a newly-opened gate loads idle slots (2026-07 audit). Read-only
/// members delegate untouched.
class _GraphAwareConsentGateway implements ConsentGateway {
  _GraphAwareConsentGateway(this._inner, this._owner);

  final ConsentGateway _inner;
  final AdFlow _owner;

  @override
  Future<bool> ensureCanRequestAds({ConsentDebugOptions? debug}) async {
    try {
      return await _inner.ensureCanRequestAds(debug: debug);
    } finally {
      _owner._afterConsentMutation();
    }
  }

  @override
  bool get isPrivacyOptionsRequired => _inner.isPrivacyOptionsRequired;

  @override
  ValueListenable<bool> get privacyOptionsRequired =>
      _inner.privacyOptionsRequired;

  @override
  AdFlowError? get lastError => _inner.lastError;

  @override
  Future<void> showPrivacyOptions() async {
    try {
      // Rethrows on failure, per the ConsentGateway contract — but the
      // recheck runs either way (the form may have committed a change
      // before erroring).
      await _inner.showPrivacyOptions();
    } finally {
      _owner._afterConsentMutation();
    }
  }

  @override
  Future<void> reset() async {
    try {
      await _inner.reset();
    } finally {
      _owner._afterConsentMutation();
    }
  }

  @override
  void dispose() => _inner.dispose();
}
