import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/ad_flow_error.dart';
import 'ad_sdk.dart';
import 'ad_sdk_types.dart';

/// A fully controllable [AdSdk] test double.
///
/// - Every `load*` call records its arguments and returns a fresh fake
///   handle (also kept in the per-format list, e.g. [interstitials]) that
///   the test can drive: [FakeFullScreenAdHandle.simulateDismissed],
///   [FakeFullScreenAdHandle.simulateReward], …
/// - Failure knobs ([nextLoadError], [alwaysLoadError], [consentUpdateError],
///   [consentFormError]) make the corresponding calls throw.
/// - Consent state is plain mutable fields ([canRequestAdsResult],
///   [consentStatus], …).
/// - [emitAppForeground] drives [appForegroundEvents].
///
/// Event streams are synchronous broadcast streams: events are delivered
/// inline to already-subscribed listeners and dropped otherwise — subscribe
/// before driving.
class FakeAdSdk implements AdSdk {
  // ── Recorded calls ──────────────────────────────────────────────────────

  /// Number of [initialize] calls.
  int initializeCalls = 0;

  /// Every configuration passed to [updateRequestConfiguration], in order.
  /// Recorded on COMPLETION (after the hold/error knobs) — see
  /// [updateRequestConfigurationCalls] for dispatch counting.
  final List<AdRequestConfig> requestConfigs = [];

  /// Number of [updateRequestConfiguration] DISPATCHES (counted at entry,
  /// before the hold/error knobs) — lets a test assert the ADR-028 rule that
  /// no config call may even be dispatched while `initialize` is in flight.
  int updateRequestConfigurationCalls = 0;

  /// Every consent info update request, in order.
  final List<ConsentUpdateCall> consentUpdateCalls = [];

  /// Number of [loadAndShowConsentFormIfRequired] calls.
  int loadAndShowConsentFormCalls = 0;

  /// Number of [showPrivacyOptionsForm] calls.
  int showPrivacyOptionsFormCalls = 0;

  /// Number of [resetConsent] calls.
  int resetConsentCalls = 0;

  /// Number of [openAdInspector] calls.
  int adInspectorCalls = 0;

  /// Number of [requestTrackingAuthorization] calls.
  int requestTrackingAuthorizationCalls = 0;

  /// Every load in order, as `'<format>:<adUnitId>'` entries.
  final List<String> loadLog = [];

  /// Fake handles created by [loadInterstitial], in order.
  final List<FakeFullScreenAdHandle> interstitials = [];

  /// Fake handles created by [loadRewarded], in order.
  final List<FakeFullScreenAdHandle> rewardeds = [];

  /// Fake handles created by [loadRewardedInterstitial], in order.
  final List<FakeFullScreenAdHandle> rewardedInterstitials = [];

  /// Fake handles created by [loadAppOpen], in order.
  final List<FakeFullScreenAdHandle> appOpens = [];

  /// Fake handles created by [loadBanner], in order.
  final List<FakeBannerHandle> banners = [];

  /// Fake handles created by [loadNative], in order.
  final List<FakeNativeHandle> natives = [];

  /// Every [BannerLoadSpec] passed to [loadBanner], in order.
  final List<BannerLoadSpec> bannerSpecs = [];

  /// Every [NativeLoadSpec] passed to [loadNative], in order.
  final List<NativeLoadSpec> nativeSpecs = [];

  /// The [AdRequestOptions] of every full-screen load (interstitial,
  /// rewarded, rewarded interstitial, app open), in order.
  final List<AdRequestOptions> fullScreenRequests = [];

  /// The `ssv` argument of every [loadRewarded] call, in order.
  final List<ServerSideVerification?> rewardedSsvs = [];

  /// The `ssv` argument of every [loadRewardedInterstitial] call, in order.
  final List<ServerSideVerification?> rewardedInterstitialSsvs = [];

  // ── Behavior knobs ──────────────────────────────────────────────────────

  /// If set, the next `load*` call throws this and the knob clears.
  AdFlowError? nextLoadError;

  /// While set, every `load*` call throws this.
  AdFlowError? alwaysLoadError;

  /// If set, every `load*` call awaits this before proceeding — leave it
  /// incomplete to keep a load in flight (e.g. to dispose mid-load).
  Completer<void>? loadHold;

  /// If set, [initialize] awaits this before completing — leave it
  /// incomplete to simulate a native SDK init call that never calls back.
  Completer<void>? initializeHold;

  /// If set, [updateRequestConfiguration] awaits this before recording —
  /// leave it incomplete to simulate a config call that hangs.
  Completer<void>? updateRequestConfigurationHold;

  /// If set, [updateRequestConfiguration] throws this instead of recording.
  AdFlowError? updateRequestConfigurationError;

  /// If set (and the load carries a non-null `ssv`), [loadRewarded] /
  /// [loadRewardedInterstitial] throw this instead of returning a handle —
  /// mirrors the real seam FAILING a load whose server-side verification
  /// could not be attached (4.0 audit; `AdFlowErrorKind.ssv`).
  Object? ssvAttachError;

  /// If set, [requestConsentInfoUpdate] throws this.
  AdFlowError? consentUpdateError;

  /// If set, [requestConsentInfoUpdate] awaits this before completing —
  /// leave it incomplete to simulate a hanging network call.
  Completer<void>? consentUpdateHold;

  /// If set, [loadAndShowConsentFormIfRequired] throws this.
  AdFlowError? consentFormError;

  /// If set, [showPrivacyOptionsForm] throws this.
  AdFlowError? privacyOptionsFormError;

  /// Value returned by [canRequestAds].
  bool canRequestAdsResult = false;

  /// If set, [canRequestAds] throws this instead of returning — models the
  /// production gateway's final `canRequestAds()` (which is outside its
  /// try/catch) failing, so a background `_start` can reject.
  AdFlowError? canRequestAdsError;

  /// Value returned by [getConsentStatus].
  AdConsentStatus consentStatus = AdConsentStatus.unknown;

  /// Value returned by [isConsentFormAvailable].
  bool consentFormAvailable = false;

  /// Value returned by [getPrivacyOptionsRequirementStatus].
  PrivacyOptionsRequirement privacyOptionsRequirement =
      PrivacyOptionsRequirement.notRequired;

  /// Result returned by [openAdInspector].
  AdInspectorResult inspectorResult = const AdInspectorResult();

  /// Value returned by [getTrackingAuthorizationStatus] (the current ATT
  /// status). Defaults to [AttStatus.notSupported] so tests that do not
  /// exercise ATT behave as if off iOS.
  AttStatus attStatus = AttStatus.notSupported;

  /// Value [requestTrackingAuthorization] resolves to (the post-prompt
  /// status). The call also updates [attStatus] to this, mirroring the real
  /// SDK transitioning out of [AttStatus.notDetermined].
  AttStatus attRequestResult = AttStatus.authorized;

  /// Invoked by [loadAndShowConsentFormIfRequired] (when it does not throw);
  /// use it to flip [canRequestAdsResult]/[consentStatus] the way a real
  /// form dismissal would.
  void Function()? onConsentFormShown;

  /// Invoked when [showPrivacyOptionsForm] runs (after the error knob) —
  /// mutate consent state here to simulate the user changing (or
  /// withdrawing) consent in the privacy-options form.
  void Function()? onPrivacyOptionsFormShown;

  /// Invoked by [requestConsentInfoUpdate] when it does NOT throw. Use it to
  /// flip [canRequestAdsResult] the way a real UMP info update does once the
  /// network is reachable — e.g. to model an offline launch (set
  /// [consentUpdateError], leave [canRequestAdsResult] false) that later
  /// recovers (clear the error, set this to open the gate).
  void Function()? onConsentInfoUpdate;

  /// When true, any `load*` while [canRequestAdsResult] is false throws a
  /// [StateError] — a tripwire for the "consent gates every load" invariant.
  /// Off by default so seam-level tests can exercise loads in isolation.
  bool enforceConsentGate = false;

  /// Default size given to loaded fake banners.
  AdDimensions bannerSize = const AdDimensions(width: 320, height: 50);

  /// Whether loaded fake banners report themselves collapsible.
  bool bannerIsCollapsible = false;

  final _appForeground = StreamController<AppForegroundEvent>.broadcast(
    sync: true,
  );

  /// Whether anyone is currently subscribed to [appForegroundEvents] — lets a
  /// test detect an app-open manager that (re)subscribed, e.g. after a
  /// dispose-during-startup.
  bool get hasForegroundListener => _appForeground.hasListener;

  /// Emits one [AppForegroundEvent] on [appForegroundEvents].
  void emitAppForeground() => _appForeground.add(const AppForegroundEvent());

  /// Closes the streams this fake owns.
  Future<void> dispose() async {
    await _appForeground.close();
  }

  Future<void> _checkLoadAllowed(String format, String adUnitId) async {
    if (enforceConsentGate && !canRequestAdsResult) {
      throw StateError(
        'Invariant violation: load $format:$adUnitId requested while '
        'canRequestAds() is false.',
      );
    }
    final hold = loadHold;
    if (hold != null) await hold.future;
    final error = nextLoadError ?? alwaysLoadError;
    if (error != null) {
      nextLoadError = null;
      throw error;
    }
  }

  Future<FakeFullScreenAdHandle> _loadFullScreen(
    String format,
    String adUnitId,
    List<FakeFullScreenAdHandle> into, {
    AdRequestOptions options = const AdRequestOptions(),
  }) async {
    await _checkLoadAllowed(format, adUnitId);
    loadLog.add('$format:$adUnitId');
    fullScreenRequests.add(options);
    final handle = FakeFullScreenAdHandle(adUnitId);
    into.add(handle);
    return handle;
  }

  /// Number of [disableMediationInitialization] calls.
  int disableMediationInitializationCalls = 0;

  /// Whether [disableMediationInitialization] was called before the first
  /// [initialize] — the only ordering in which the real plugin honours it.
  bool? mediationInitDisabledBeforeInitialize;

  /// If set, [disableMediationInitialization] throws this — models a mediation
  /// deferral that could not be applied (4.1 audit).
  Object? disableMediationInitializationError;

  @override
  Future<void> disableMediationInitialization() async {
    disableMediationInitializationCalls++;
    mediationInitDisabledBeforeInitialize ??= initializeCalls == 0;
    final error = disableMediationInitializationError;
    if (error != null) throw error;
  }

  @override
  Future<void> initialize() async {
    initializeCalls++;
    final hold = initializeHold;
    if (hold != null) await hold.future;
  }

  @override
  Future<void> updateRequestConfiguration(AdRequestConfig config) async {
    updateRequestConfigurationCalls++;
    final hold = updateRequestConfigurationHold;
    if (hold != null) await hold.future;
    final error = updateRequestConfigurationError;
    if (error != null) throw error;
    requestConfigs.add(config);
  }

  @override
  Future<InterstitialHandle> loadInterstitial(
    String adUnitId,
    AdRequestOptions options,
  ) async => _loadFullScreen(
    'interstitial',
    adUnitId,
    interstitials,
    options: options,
  );

  @override
  Future<RewardedHandle> loadRewarded(
    String adUnitId,
    AdRequestOptions options, {
    ServerSideVerification? ssv,
  }) async {
    final handle = await _loadFullScreen(
      'rewarded',
      adUnitId,
      rewardeds,
      options: options,
    );
    rewardedSsvs.add(ssv);
    final ssvError = ssvAttachError;
    if (ssv != null && ssvError != null) {
      // Mirrors the real seam: the un-verifiable ad is released and the load
      // FAILS — never a ready ad that silently lost its SSV payload.
      rewardeds.remove(handle);
      unawaited(handle.dispose());
      throw ssvError;
    }
    return handle;
  }

  @override
  Future<RewardedInterstitialHandle> loadRewardedInterstitial(
    String adUnitId,
    AdRequestOptions options, {
    ServerSideVerification? ssv,
  }) async {
    final handle = await _loadFullScreen(
      'rewarded_interstitial',
      adUnitId,
      rewardedInterstitials,
      options: options,
    );
    rewardedInterstitialSsvs.add(ssv);
    final ssvError = ssvAttachError;
    if (ssv != null && ssvError != null) {
      rewardedInterstitials.remove(handle);
      unawaited(handle.dispose());
      throw ssvError;
    }
    return handle;
  }

  @override
  Future<AppOpenHandle> loadAppOpen(
    String adUnitId,
    AdRequestOptions options,
  ) async => _loadFullScreen('app_open', adUnitId, appOpens, options: options);

  @override
  Future<BannerHandle> loadBanner(BannerLoadSpec spec) async {
    await _checkLoadAllowed('banner', spec.adUnitId);
    loadLog.add('banner:${spec.adUnitId}');
    bannerSpecs.add(spec);
    final handle = FakeBannerHandle(
      spec.adUnitId,
      size: bannerSize,
      isCollapsible: bannerIsCollapsible,
    );
    banners.add(handle);
    return handle;
  }

  @override
  Future<NativeHandle> loadNative(NativeLoadSpec spec) async {
    await _checkLoadAllowed('native', spec.adUnitId);
    loadLog.add('native:${spec.adUnitId}');
    nativeSpecs.add(spec);
    final handle = FakeNativeHandle(spec.adUnitId);
    natives.add(handle);
    return handle;
  }

  @override
  Stream<AppForegroundEvent> get appForegroundEvents => _appForeground.stream;

  @override
  Future<AdInspectorResult> openAdInspector() async {
    adInspectorCalls++;
    return inspectorResult;
  }

  @override
  Future<void> requestConsentInfoUpdate({
    bool? tagForUnderAgeOfConsent,
    ConsentDebugOptions? debug,
  }) async {
    consentUpdateCalls.add(
      ConsentUpdateCall(
        tagForUnderAgeOfConsent: tagForUnderAgeOfConsent,
        debug: debug,
      ),
    );
    final hold = consentUpdateHold;
    if (hold != null) await hold.future;
    final error = consentUpdateError;
    if (error != null) throw error;
    onConsentInfoUpdate?.call();
  }

  @override
  Future<bool> canRequestAds() async {
    final error = canRequestAdsError;
    if (error != null) throw error;
    return canRequestAdsResult;
  }

  @override
  Future<AdConsentStatus> getConsentStatus() async => consentStatus;

  @override
  Future<bool> isConsentFormAvailable() async => consentFormAvailable;

  @override
  Future<PrivacyOptionsRequirement>
  getPrivacyOptionsRequirementStatus() async => privacyOptionsRequirement;

  @override
  Future<void> loadAndShowConsentFormIfRequired() async {
    loadAndShowConsentFormCalls++;
    final error = consentFormError;
    if (error != null) throw error;
    onConsentFormShown?.call();
  }

  @override
  Future<void> showPrivacyOptionsForm() async {
    showPrivacyOptionsFormCalls++;
    final error = privacyOptionsFormError;
    if (error != null) throw error;
    onPrivacyOptionsFormShown?.call();
  }

  @override
  Future<void> resetConsent() async {
    resetConsentCalls++;
  }

  @override
  Future<AttStatus> getTrackingAuthorizationStatus() async => attStatus;

  @override
  Future<AttStatus> requestTrackingAuthorization() async {
    requestTrackingAuthorizationCalls++;
    return attStatus = attRequestResult;
  }
}

/// One recorded [FakeAdSdk.requestConsentInfoUpdate] call.
class ConsentUpdateCall {
  /// Creates a record of the call's arguments.
  const ConsentUpdateCall({this.tagForUnderAgeOfConsent, this.debug});

  /// The `tagForUnderAgeOfConsent` argument.
  final bool? tagForUnderAgeOfConsent;

  /// The `debug` argument.
  final ConsentDebugOptions? debug;
}

/// A drivable fake full-screen ad handle.
///
/// Implements every full-screen handle interface so one fake serves all
/// four formats.
class FakeFullScreenAdHandle
    implements
        InterstitialHandle,
        RewardedHandle,
        RewardedInterstitialHandle,
        AppOpenHandle {
  /// Creates a fake handle for [adUnitId].
  FakeFullScreenAdHandle(this.adUnitId);

  @override
  final String adUnitId;

  final _content = StreamController<FullScreenAdEvent>.broadcast(sync: true);
  final _paid = StreamController<AdPaidEvent>.broadcast(sync: true);

  /// Number of [show] calls (an SDK-faithful controller never exceeds 1).
  int showCalls = 0;

  /// The reward callback passed to the most recent [show].
  OnUserEarnedReward? lastOnUserEarnedReward;

  /// Whether [dispose] has been called.
  bool disposed = false;

  /// If set, [show] emits [AdFailedToShowEvent] with this error instead of
  /// [AdShowedEvent].
  AdFlowError? showError;

  /// If set, [show] throws this instead of completing normally — simulates
  /// the real plugin's `Ad.show()` Future *rejecting* (ad already
  /// released, channel error, mediation failure), which the documented
  /// [AdSdk.show] contract says should never happen (failures are meant to
  /// arrive via [AdFailedToShowEvent] on [contentEvents] instead) but a
  /// real implementation can still violate. Controllers must be robust to
  /// this regardless of what the contract promises.
  Object? showRejectsWith;

  /// Whether [show] automatically emits [AdShowedEvent] (default true). Turn
  /// off to drive the showed event manually.
  bool autoEmitShowed = true;

  /// Whether [simulateDismissed] has fired — the ad's lifecycle has ended,
  /// matching the real SDK's single-use ad instances.
  bool _dismissed = false;

  /// What [response] reports (settable to simulate mediation fill info).
  AdResponseSummary? responseSummary;

  @override
  AdResponseSummary? get response => responseSummary;

  /// SSV payloads applied via [updateServerSideVerification], in order.
  final List<ServerSideVerification> ssvUpdates = [];

  /// If set, [updateServerSideVerification] throws this.
  Object? ssvUpdateError;

  @override
  Future<void> updateServerSideVerification(ServerSideVerification ssv) async {
    final error = ssvUpdateError;
    if (error != null) throw error;
    ssvUpdates.add(ssv);
  }

  @override
  Stream<FullScreenAdEvent> get contentEvents => _content.stream;

  @override
  Stream<AdPaidEvent> get paidEvents => _paid.stream;

  @override
  Future<void> show({OnUserEarnedReward? onUserEarnedReward}) async {
    showCalls++;
    lastOnUserEarnedReward = onUserEarnedReward;
    final rejectsWith = showRejectsWith;
    if (rejectsWith != null) throw rejectsWith;
    if (showCalls > 1) {
      // A real single-use ad instance can't be shown a second time — fail
      // the way the SDK would (via the event stream, matching the
      // documented AdSdk.show contract) instead of silently succeeding
      // again. Catches a controller bug that reaches a double-show
      // through a path review finding #10's own repro didn't cover.
      _content.add(
        const AdFailedToShowEvent(
          AdFlowError(AdFlowErrorKind.showFailed, 'Ad already used'),
        ),
      );
      return;
    }
    final error = showError;
    if (error != null) {
      _content.add(AdFailedToShowEvent(error));
      return;
    }
    if (autoEmitShowed) _content.add(const AdShowedEvent());
  }

  /// Emits [AdShowedEvent] (for tests with [autoEmitShowed] off).
  void simulateShowed() => _content.add(const AdShowedEvent());

  /// Emits [AdDismissedEvent]. Throws [StateError] if [show] was never
  /// called — the real SDK never dismisses an ad that was never shown.
  void simulateDismissed() {
    if (showCalls == 0) {
      throw StateError(
        'simulateDismissed called before show() — an ad can only be '
        'dismissed after it was shown.',
      );
    }
    _dismissed = true;
    _content.add(const AdDismissedEvent());
  }

  /// Emits [AdImpressionEvent].
  /// Emits [AdFailedToShowEvent] directly — e.g. a mid-display failure
  /// AFTER the ad already showed (use [showError] for one that fails the
  /// show dispatch itself).
  void simulateShowFailed(AdFlowError error) =>
      _content.add(AdFailedToShowEvent(error));

  void simulateImpression() => _content.add(const AdImpressionEvent());

  /// Emits [AdClickedEvent].
  void simulateClicked() => _content.add(const AdClickedEvent());

  /// Invokes the reward callback captured by [show]. Throws [StateError]
  /// if the ad has already been dismissed — a reward can't arrive after
  /// the ad's lifecycle has ended.
  void simulateReward(RewardEarned reward) {
    if (_dismissed) {
      throw StateError(
        'simulateReward called after simulateDismissed — a reward cannot '
        'arrive once the ad has already been dismissed.',
      );
    }
    lastOnUserEarnedReward?.call(reward);
  }

  /// Emits a paid event.
  void simulatePaid(AdPaidEvent event) => _paid.add(event);

  @override
  Future<void> dispose() async {
    disposed = true;
    // Escape any in-flight synchronous event dispatch before closing —
    // controllers legitimately dispose a handle from its own dismiss event.
    await Future<void>.delayed(Duration.zero);
    await _content.close();
    await _paid.close();
  }
}

/// A drivable fake banner handle. [buildWidget] returns a [SizedBox] of
/// [size] so widget tests can pump it without platform views.
class FakeBannerHandle implements BannerHandle {
  /// Creates a fake banner handle.
  FakeBannerHandle(
    this.adUnitId, {
    AdDimensions size = const AdDimensions(width: 320, height: 50),
    this.isCollapsible = false,
  }) : _dimensions = ValueNotifier(size);

  @override
  final String adUnitId;

  final ValueNotifier<AdDimensions> _dimensions;

  @override
  AdDimensions get size => _dimensions.value;

  @override
  ValueListenable<AdDimensions> get dimensions => _dimensions;

  /// Simulates the platform resolving a new size for the SAME live ad —
  /// what an AdMob server-side auto-refresh of an inline adaptive banner
  /// does (the real seam updates the handle and notifies listeners).
  void simulateResize(AdDimensions size) => _dimensions.value = size;

  /// What [response] reports (settable to simulate mediation fill info).
  AdResponseSummary? responseSummary;

  @override
  AdResponseSummary? get response => responseSummary;

  @override
  final bool isCollapsible;

  final _events = StreamController<ViewAdEvent>.broadcast(sync: true);
  final _paid = StreamController<AdPaidEvent>.broadcast(sync: true);

  /// Whether [dispose] has been called.
  bool disposed = false;

  /// Number of [buildWidget] calls.
  int buildWidgetCalls = 0;

  @override
  Stream<ViewAdEvent> get events => _events.stream;

  @override
  Stream<AdPaidEvent> get paidEvents => _paid.stream;

  @override
  Widget buildWidget() {
    buildWidgetCalls++;
    return SizedBox(width: size.width, height: size.height);
  }

  /// Emits a view-ad event.
  void simulateEvent(ViewAdEvent event) => _events.add(event);

  /// Emits a paid event.
  void simulatePaid(AdPaidEvent event) => _paid.add(event);

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
    await _paid.close();
  }
}

/// A drivable fake native handle. [buildWidget] returns a fixed-size
/// [SizedBox] so widget tests can pump it without platform views.
class FakeNativeHandle implements NativeHandle {
  /// Creates a fake native handle.
  FakeNativeHandle(this.adUnitId);

  @override
  final String adUnitId;

  /// What [response] reports (settable to simulate mediation fill info).
  AdResponseSummary? responseSummary;

  @override
  AdResponseSummary? get response => responseSummary;

  final _events = StreamController<ViewAdEvent>.broadcast(sync: true);
  final _paid = StreamController<AdPaidEvent>.broadcast(sync: true);

  /// Whether [dispose] has been called.
  bool disposed = false;

  /// Number of [buildWidget] calls.
  int buildWidgetCalls = 0;

  @override
  Stream<ViewAdEvent> get events => _events.stream;

  @override
  Stream<AdPaidEvent> get paidEvents => _paid.stream;

  @override
  Widget buildWidget() {
    buildWidgetCalls++;
    return const SizedBox(width: 320, height: 90);
  }

  /// Emits a view-ad event.
  void simulateEvent(ViewAdEvent event) => _events.add(event);

  /// Emits a paid event.
  void simulatePaid(AdPaidEvent event) => _paid.add(event);

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
    await _paid.close();
  }
}
