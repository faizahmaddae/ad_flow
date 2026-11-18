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
    required bool consentFastPathEligible,
    RewardedIntroPresenter? rewardedIntroPresenter,
  }) : _config = config,
       _sdk = sdk,
       _consent = consentGateway,
       _ownsConsent = ownsConsent,
       _platform = platform,
       _consentFastPathEligible = consentFastPathEligible,
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
      consentGeneration: () => _consentGeneration,
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
          'rewardedIntroPresenter: RewardedIntroScreen.presenter(navigatorKey).',
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
  /// The optional priming ("explainer") parameters are all opt-in — pass
  /// none and UMP's own flow runs unchanged:
  ///
  /// - [attExplainer] — the app's ATT primer shown before Apple's system
  ///   tracking prompt (client-driven ATT, iOS). The tracking question always
  ///   comes **after** the GDPR flow, and is not asked of a user who has just
  ///   refused GDPR purpose 1 (ADR-082 — the pre-5.5.0 ATT-first order got
  ///   apps rejected under App Store Guideline 5.1.1(iv)). Pass none to let
  ///   UMP drive ATT from the IDFA message configured in the AdMob console —
  ///   the simplest compliant setup. Do not use both.
  /// - [attExplainerContent] — the copy for the ATT presenter (localize by
  ///   overriding).
  ///
  /// These apply only to a gateway this facade creates. If you inject your
  /// own [consent], construct it with these options yourself.
  ///
  /// Mediation networks that do not read the IAB TCF string themselves need
  /// their own privacy flags: set them before calling [initialize], and again
  /// from [onConsentChanged] (see doc/MEDIATION_SETUP.md).
  static Future<AdFlow> initialize(
    AdFlowConfig config, {
    AdSdk? sdk,
    ConsentGateway? consent,
    KeyValueStore? store,
    AdPlatform? platform,
    RewardedIntroPresenter? rewardedIntroPresenter,
    ConsentDebugOptions? consentDebug,
    AttExplainerPresenter? attExplainer,
    AttExplainerContent attExplainerContent = const AttExplainerContent(),
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
            attExplainer: attExplainer,
            attExplainerContent: attExplainerContent,
          ),
      // Only dispose a consent gateway this facade created itself — an
      // injected one may be shared/reused by the caller beyond dispose().
      ownsConsent: consent == null,
      platform: platform ?? currentAdPlatform(),
      store: store ?? SharedPrefsKeyValueStore(),
      // The cached-consent fast path (ADR-072) is engaged only when this facade
      // owns the DEFAULT UmpConsentGateway (so it knows the info update is
      // dispatched synchronously at startup) and no client-driven ATT primer is
      // configured (so serving on cached consent can never precede a required
      // ATT decision). Anything else falls back to the full-flow wait: always
      // correct, just not fast.
      consentFastPathEligible: consent == null && attExplainer == null,
      rewardedIntroPresenter: rewardedIntroPresenter,
    );
    // IDEMPOTENT (ADR-044): a second initialize() replaces the first graph
    // instead of leaving it running. Apps DO re-initialize — on login/logout,
    // on a config change, on a debug hot restart — and every call builds a
    // whole new graph. Without this the previous one stayed fully alive: still
    // subscribed to the foreground stream, still preloading, still able to
    // show ads, and coordinating through its OWN separate
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

  /// Whether the cached-consent startup fast path may engage (ADR-072): the
  /// facade owns the default gateway (info update dispatched synchronously at
  /// startup) and there is no client-driven ATT adopter. See [_settleConsent].
  final bool _consentFastPathEligible;

  /// Set true when the cached-consent fast path is actually ACCEPTED (a load was
  /// permitted under cached consent while this launch's flow was still running),
  /// so [_runConsent]'s completion can reconcile that inventory: on a downgrade
  /// it invalidates the consent generation BEFORE re-checking, catching a load
  /// still in flight (which `recheckGate` cannot touch while `AdLoading`) and a
  /// show waiting at an async boundary (5.2.2 addendum to ADR-072).
  bool _consentFastPathServed = false;
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

  /// Whether a failed/absent request configuration must BLOCK loads: exactly
  /// when it carries policy-critical fields (child-directed / under-age tags,
  /// a content rating, test devices). A config with none of them loses
  /// nothing by loading without it.
  bool get _configFailurePolicyIsClosed =>
      _config.requestConfigIsPolicySensitive;

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
    if (_requestConfigApplied) return true;
    // Fail-open must NOT mean "serve while Mobile Ads init is still running"
    // (5.1.2). A request dispatched now would race the native init — an
    // untagged/untest-flagged first request, or worse the ADR-028
    // platform-thread deadlock window. While the REAL initialize() future is in
    // flight, block regardless of the config's sensitivity; the load re-checks
    // on its short gate backoff and recovers the moment init completes and
    // config applies (see the init-completion hook in _initializeAndConfigure).
    // Only once init has genuinely completed — so config was ATTEMPTED and
    // failed for real, not merely deferred — may a config with nothing
    // policy-critical in it fail open.
    if (_initInFlight != null && !_initDone) return false;
    return !_configFailurePolicyIsClosed;
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
          .updateRequestConfiguration(requestConfigFrom(_config))
          .timeout(_initTimeout);
      _requestConfigApplied = true;
      // Config is in place — possibly LATE (init completed after the first
      // frame, so loads were blocked on requestConfigNotApplied). Promptly
      // re-drive every controller now, so a blocked slot recovers at once
      // instead of waiting out its gate-recheck backoff (mirrors enableAds();
      // an AdLoading controller's recheck is a harmless no-op). (5.1.2)
      if (!_disposed) _recheckAll();
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
            'are ${_configFailurePolicyIsClosed ? "BLOCKED until it succeeds, because it carries policy-critical fields" : "proceeding without it"})',
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
  /// dispose) can DROP their live ads — nothing else ever re-checks a mounted
  /// view ad's permission (2026-07 audit). Controllers deregister themselves
  /// on dispose.
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
    // A privacy-options change / re-run / reset makes every ad requested under
    // the old answer stale: bump the consent generation, then re-evaluate every
    // controller against the fresh gate. recheckGate drops a no-longer-permitted
    // ad AND drops-and-reloads any warm ad whose generation is now stale (its
    // impression/measurement would reflect the old choice); a load in flight
    // drops itself on completion; a full-screen ad on screen is not
    // interrupted. One path, permission and consent-staleness together.
    _consentGeneration++;
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

  /// Bumped on every consent MUTATION (privacy-options change, re-run, reset)
  /// so an ad requested under the OLD answer is recognised as stale and
  /// dropped-and-reloaded (see [AdGate.consentGeneration]).
  int _consentGeneration = 0;

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
  /// A fire-and-forget hook, e.g. for forwarding consent to mediation networks
  /// that do not read the IAB TCF string themselves: read the UMP-written
  /// state (`IABTCF_*` / `IABGPP_*` keys) and call the partner SDK's own
  /// privacy APIs — Google does NOT propagate consent to such networks. Nothing
  /// waits for it, and it is assignable only after `initialize` returns, so set
  /// anything a partner needs before its adapter initializes BEFORE calling
  /// [initialize] (see doc/MEDIATION_SETUP.md).
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
      // CACHED-CONSENT FAST PATH (ADR-072; Google UMP guidance). A returning
      // user whose PREVIOUS session already made `canRequestAds()` true should
      // not lose ad serving just because THIS launch's consent-info update is
      // slow. When eligible ([_consentFastPathEligible]) the default gateway has
      // already dispatched this launch's `requestConsentInfoUpdate`
      // synchronously at startup (and no ATT decision is being bypassed), so a
      // cached `canRequestAds() == true` means we may serve NOW — the gate's own
      // live `canRequestAds()` read (next step) still confirms it, the slow
      // flow keeps running and publishes its final result, and a downgrade
      // drops stale inventory (see [_runConsent]). A first-install user (cached
      // false) falls through and waits for the flow to settle.
      if (_consentFastPathEligible) {
        try {
          if (await _sdk.canRequestAds()) {
            // Fast path ACCEPTED. Publish the live cached answer — `canRequestAds`
            // is the documented reactive consent value, so it must reflect that
            // we are serving now (the flow later reconciles it to its final
            // value). And record that inventory may now be requested under
            // cached consent, so a later downgrade invalidates it ([_runConsent]).
            _consentFastPathServed = true;
            if (!_disposed) _canRequestAdsNotifier.value = true;
            return;
          }
        } catch (_) {
          // Indeterminate — do not fast-path; join the full flow instead.
        }
        if (_disposed || _consentOpen) return;
      }
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
  /// This resolves the consent RESULT only — init runs in parallel ([_start]).
  /// The `canRequestAds` notifier updates here.
  Future<bool> _runConsent(ConsentDebugOptions? debug) {
    _consentRetryArmed = false;
    final run = _consent.ensureCanRequestAds(debug: debug);
    final published = run.then((open) {
      _consentOpen = open;
      if (!_disposed) {
        _canRequestAdsNotifier.value = open;
        // The initial/retry settle must NOT bump the consent generation: the
        // cached-consent fast path (ADR-072) may have a load in flight, and
        // bumping it as the flow settles to the SAME answer would invalidate
        // that perfectly good ad and force a wasteful reload. A real later
        // consent MUTATION invalidates inventory via _afterConsentMutation, and
        // a downgrade here is handled just below.
        _dispatchConsentChanged();
        // Reconcile the fast path (ADR-072 / 5.2.2). If a returning user was
        // served on cached consent but THIS launch's flow concluded ads may NOT
        // be requested (consent lapsed and a now-required form was declined),
        // the inventory it loaded — or is still loading, or preparing to show —
        // is stale-consent and must go. Nothing else bumped the generation, so
        // bump it HERE, before _recheckAll: an already-loaded
        // ad is dropped by recheckGate's live check, but a load still in flight
        // (recheckGate no-ops on AdLoading) and a show waiting at an async
        // boundary are caught ONLY by the generation — the completing load's
        // own generation check and the final show-dispatch guard both reject a
        // now-stale generation. A no-op when the fast path was never accepted.
        final servedOnCachedConsent = _consentFastPathServed;
        _consentFastPathServed = false;
        if (!open && servedOnCachedConsent) _consentGeneration++;
        if (!open && _consentFastPathEligible) _recheckAll();
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
    // Consent (UMP) is independent of the Ads SDK, so the two run in parallel
    // (init sends no ad request); request configuration follows init
    // (ADR-028/032).
    _consentDebug = debug;
    final consent = _runConsent(debug);
    // Kicks init synchronously (so `_initInFlight` is set before any load
    // reaches the gate), then awaits it below.
    final init = _initializeAndConfigure();
    // The app-open slot preloads AT ONCE, not after consent: its launch moment
    // (`showAtLaunch`, while the loading screen is up) is only seconds long.
    // Safe — every load still waits for init + request configuration and for
    // consent (a returning user's cached consent opens the gate early, a first
    // install's flow is joined).
    _appOpen?.start();
    await init;

    // Gate ad loads on consent.
    final canRequestAds = await consent;

    // Since startup runs in the background (ADR-032), the app may have called
    // dispose() while we were awaiting — don't start a manager or kick
    // preloads on a torn-down graph.
    if (_disposed) return canRequestAds;

    // The controllers gate every load themselves, so starting them with a
    // closed gate is safe — they simply stay idle / blocked until it opens.
    unawaited(_interstitial?.load());
    unawaited(_rewarded?.load());
    unawaited(_rewardedInterstitial?.load());
    return canRequestAds;
  }

  /// Initializes the Ads SDK, then applies request configuration.
  ///
  /// The init→config ORDERING is load-bearing (ADR-027/028): the plugin
  /// dispatches `MobileAds#initialize` to a background thread, but services
  /// `updateRequestConfiguration` synchronously on the platform thread; if the
  /// latter runs before the native Ads (Play Services Dynamite) module has
  /// bootstrapped, it races init's background bootstrap of the same singleton
  /// into a platform-thread deadlock. So config keys off the ACTUAL init
  /// completion (`_initDone`), not a bounded wait — if init lands late, the
  /// completion hook applies config then.
  Future<void> _initializeAndConfigure() async {
    Future<void>? init;
    try {
      init = _sdk.initialize();
    } catch (_) {
      // A synchronously-throwing seam: no init future. The config attempt
      // refuses to dispatch (never safe); loads degrade per the config policy.
    }
    if (init != null) {
      final tracked = init.catchError((Object _) {});
      _initInFlight = tracked;
      unawaited(
        tracked.whenComplete(() {
          _initDone = true;
          if (_disposed || _requestConfigApplied) return;
          // Init actually completed: apply request configuration NOW. Earlier
          // attempts returned "not applied" only because init was in flight
          // (ADR-028) — a defer, not a failure to rate-limit — so bypass the
          // retry-arm cooldown and kick an attempt directly. A blocked slot
          // then recovers promptly (the apply calls _recheckAll on success). If
          // an attempt is already in flight it is awaiting this same init future
          // and will apply config itself. (5.1.2)
          if (_configAttemptInFlight == null) unawaited(_runConfigAttempt());
        }),
      );
      try {
        await tracked.timeout(_initTimeout);
      } catch (_) {
        // Init is merely slow — carry on; the hook above finishes the job.
      }
    }
    if (_initDone) await _settleRequestConfig();
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
    if (_disposed) return; // inert after dispose, like every other public call
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
    if (_disposed) return; // inert after dispose, like every other public call
    _adsEnabled.value = false;
    _recheckAll();
  }

  /// The interstitial slot, or null when it is not configured for this
  /// platform (6.0: one nullable getter per slot — `ads.interstitial?.show()`).
  InterstitialAdController? get interstitial => _interstitial;

  /// The rewarded slot, or null when it is not configured for this platform.
  RewardedAdController? get rewarded => _rewarded;

  /// The rewarded interstitial slot, or null when it is not configured for
  /// this platform.
  RewardedInterstitialAdController? get rewardedInterstitial =>
      _rewardedInterstitial;

  /// The app open slot (its manager; the controller is `appOpen?.controller`),
  /// or null when it is not configured for this platform.
  AppOpenAdManager? get appOpen => _appOpen;

  /// Creates a fresh banner controller (one per placement; give it to an
  /// `AdFlowBanner` with `ownsController: true`). [override] replaces the
  /// global banner config for this placement.
  ///
  /// Throws an [AdFlowError] (`invalidConfig`) when there is no banner config
  /// or the slot has no ad unit ID for this platform. `AdFlowBanner(adFlow:)`
  /// renders nothing in that case instead (ADR-085).
  BannerAdController banner([BannerConfig? override]) {
    final config = override ?? _config.banner;
    if (config == null) {
      throw AdFlowError(
        AdFlowErrorKind.invalidConfig,
        'No banner config: pass one to banner() or configure '
        'AdFlowConfig.banner.',
      );
    }
    // In test mode the sample unit must match THIS placement's kind (an
    // adaptive slot served from Google's fixed-size sample unit gets a
    // creative that cannot fill it — issue #15), so resolve from the
    // override's kind, not the global config's.
    final adUnitId = resolveAdUnitId(
      configured: config.adUnitId,
      testIds: TestAdUnitIds.forBannerKind(config.kind),
      platform: _platform,
      testAds: _config.usesTestAds,
    );
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
      heightMemory: _bannerHeights,
    );
    _mintedViewControllers.add(controller);
    return controller;
  }

  /// Shared by every banner this graph mints, so a banner mounted on a new
  /// screen reserves the height earlier banners of its width rendered at,
  /// instead of growing from the 50dp floor each time (ADR-079).
  final BannerHeightMemory _bannerHeights = BannerHeightMemory();

  /// Creates a fresh native controller (one per placement; give it to an
  /// `AdFlowNativeAd` with `ownsController: true`). [override] replaces
  /// the global native config for this placement.
  ///
  /// Throws an [AdFlowError] (`invalidConfig`) when there is no native config
  /// or the slot has no ad unit ID for this platform. `AdFlowNativeAd(adFlow:)`
  /// renders nothing in that case instead (ADR-085).
  NativeAdController native([NativeConfig? override]) {
    final config = override ?? _config.nativeAd;
    if (config == null) {
      throw AdFlowError(
        AdFlowErrorKind.invalidConfig,
        'No native config: pass one to native() or configure '
        'AdFlowConfig.nativeAd.',
      );
    }
    final adUnitId = resolveAdUnitId(
      configured: config.adUnitId,
      testIds: TestAdUnitIds.native,
      platform: _platform,
      testAds: _config.usesTestAds,
    );
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
