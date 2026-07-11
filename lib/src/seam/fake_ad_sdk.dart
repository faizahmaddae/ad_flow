import 'dart:async';

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
  final List<AdRequestConfig> requestConfigs = [];

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

  // ── Behavior knobs ──────────────────────────────────────────────────────

  /// If set, the next `load*` call throws this and the knob clears.
  AdFlowError? nextLoadError;

  /// While set, every `load*` call throws this.
  AdFlowError? alwaysLoadError;

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

  /// Value returned by [getConsentStatus].
  AdConsentStatus consentStatus = AdConsentStatus.unknown;

  /// Value returned by [isConsentFormAvailable].
  bool consentFormAvailable = false;

  /// Value returned by [getPrivacyOptionsRequirementStatus].
  PrivacyOptionsRequirement privacyOptionsRequirement =
      PrivacyOptionsRequirement.notRequired;

  /// Result returned by [openAdInspector].
  AdInspectorResult inspectorResult = const AdInspectorResult();

  /// Invoked by [loadAndShowConsentFormIfRequired] (when it does not throw);
  /// use it to flip [canRequestAdsResult]/[consentStatus] the way a real
  /// form dismissal would.
  void Function()? onConsentFormShown;

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

  /// Emits one [AppForegroundEvent] on [appForegroundEvents].
  void emitAppForeground() => _appForeground.add(const AppForegroundEvent());

  /// Closes the streams this fake owns.
  Future<void> dispose() async {
    await _appForeground.close();
  }

  void _checkLoadAllowed(String format, String adUnitId) {
    if (enforceConsentGate && !canRequestAdsResult) {
      throw StateError(
        'Invariant violation: load $format:$adUnitId requested while '
        'canRequestAds() is false.',
      );
    }
    final error = nextLoadError ?? alwaysLoadError;
    if (error != null) {
      nextLoadError = null;
      throw error;
    }
  }

  FakeFullScreenAdHandle _loadFullScreen(
    String format,
    String adUnitId,
    List<FakeFullScreenAdHandle> into,
  ) {
    _checkLoadAllowed(format, adUnitId);
    loadLog.add('$format:$adUnitId');
    final handle = FakeFullScreenAdHandle(adUnitId);
    into.add(handle);
    return handle;
  }

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<void> updateRequestConfiguration(AdRequestConfig config) async {
    requestConfigs.add(config);
  }

  @override
  Future<InterstitialHandle> loadInterstitial(
    String adUnitId,
    AdRequestOptions options,
  ) async => _loadFullScreen('interstitial', adUnitId, interstitials);

  @override
  Future<RewardedHandle> loadRewarded(
    String adUnitId,
    AdRequestOptions options,
  ) async => _loadFullScreen('rewarded', adUnitId, rewardeds);

  @override
  Future<RewardedInterstitialHandle> loadRewardedInterstitial(
    String adUnitId,
    AdRequestOptions options,
  ) async => _loadFullScreen(
    'rewarded_interstitial',
    adUnitId,
    rewardedInterstitials,
  );

  @override
  Future<AppOpenHandle> loadAppOpen(
    String adUnitId,
    AdRequestOptions options,
  ) async => _loadFullScreen('app_open', adUnitId, appOpens);

  @override
  Future<BannerHandle> loadBanner(BannerLoadSpec spec) async {
    _checkLoadAllowed('banner', spec.adUnitId);
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
    _checkLoadAllowed('native', spec.adUnitId);
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
  }

  @override
  Future<bool> canRequestAds() async => canRequestAdsResult;

  @override
  Future<AdConsentStatus> getConsentStatus() async => consentStatus;

  @override
  Future<bool> isConsentFormAvailable() async => consentFormAvailable;

  @override
  Future<PrivacyOptionsRequirement> getPrivacyOptionsRequirementStatus() async =>
      privacyOptionsRequirement;

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
  }

  @override
  Future<void> resetConsent() async {
    resetConsentCalls++;
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

  /// Whether [show] automatically emits [AdShowedEvent] (default true). Turn
  /// off to drive the showed event manually.
  bool autoEmitShowed = true;

  @override
  Stream<FullScreenAdEvent> get contentEvents => _content.stream;

  @override
  Stream<AdPaidEvent> get paidEvents => _paid.stream;

  @override
  Future<void> show({OnUserEarnedReward? onUserEarnedReward}) async {
    showCalls++;
    lastOnUserEarnedReward = onUserEarnedReward;
    final error = showError;
    if (error != null) {
      _content.add(AdFailedToShowEvent(error));
      return;
    }
    if (autoEmitShowed) _content.add(const AdShowedEvent());
  }

  /// Emits [AdShowedEvent] (for tests with [autoEmitShowed] off).
  void simulateShowed() => _content.add(const AdShowedEvent());

  /// Emits [AdDismissedEvent].
  void simulateDismissed() => _content.add(const AdDismissedEvent());

  /// Emits [AdImpressionEvent].
  void simulateImpression() => _content.add(const AdImpressionEvent());

  /// Emits [AdClickedEvent].
  void simulateClicked() => _content.add(const AdClickedEvent());

  /// Invokes the reward callback captured by [show].
  void simulateReward(RewardEarned reward) =>
      lastOnUserEarnedReward?.call(reward);

  /// Emits a paid event.
  void simulatePaid(AdPaidEvent event) => _paid.add(event);

  @override
  Future<void> dispose() async {
    disposed = true;
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
    this.size = const AdDimensions(width: 320, height: 50),
    this.isCollapsible = false,
  });

  @override
  final String adUnitId;

  @override
  final AdDimensions size;

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
