import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'ad_sdk_types.dart';

/// A loaded full-screen ad (interstitial, rewarded, rewarded interstitial or
/// app open), ready to be shown once.
///
/// Handles are **single-use**: after [AdDismissedEvent] or
/// [AdFailedToShowEvent] the owner must [dispose] the handle and load the
/// next one.
abstract interface class FullScreenAdHandle {
  /// The ad unit this ad was loaded for.
  String get adUnitId;

  /// Which network filled this ad (mediation observability), or null when
  /// the SDK reported nothing.
  AdResponseSummary? get response;

  /// Show/dismiss/impression/click events for this ad.
  Stream<FullScreenAdEvent> get contentEvents;

  /// Impression-level revenue events (allowlisted accounts only).
  Stream<AdPaidEvent> get paidEvents;

  /// Shows the ad. Show failures are reported via [contentEvents] as
  /// [AdFailedToShowEvent], mirroring the underlying SDK.
  ///
  /// [onUserEarnedReward] is required by rewarded and rewarded interstitial
  /// ads and ignored by the other formats.
  Future<void> show({OnUserEarnedReward? onUserEarnedReward});

  /// Releases the underlying platform ad.
  Future<void> dispose();
}

/// A loaded interstitial ad.
abstract interface class InterstitialHandle implements FullScreenAdHandle {}

/// A loaded rewarded ad.
abstract interface class RewardedHandle implements FullScreenAdHandle {
  /// Applies (or replaces) server-side verification options on this
  /// already-loaded ad — call any time before `show()`.
  ///
  /// Real apps set the SSV `userId` after login and per-show `customData`
  /// (which mission/level earned the reward), long after the ad preloaded
  /// (2026-07 audit). Throws an `AdFlowError` on failure — a caller granting
  /// high-value rewards must know its verification payload did not attach.
  Future<void> updateServerSideVerification(ServerSideVerification ssv);
}

/// A loaded rewarded interstitial ad.
///
/// Policy: callers must present an intro screen with clear reward messaging
/// and a skip option *before* showing this ad.
abstract interface class RewardedInterstitialHandle
    implements FullScreenAdHandle {
  /// Applies (or replaces) server-side verification options on this
  /// already-loaded ad — see [RewardedHandle.updateServerSideVerification].
  Future<void> updateServerSideVerification(ServerSideVerification ssv);
}

/// A loaded app open ad.
///
/// Policy: warm-start only; a loaded ad expires 4 hours after load — the
/// owner tracks load time and discards stale handles.
abstract interface class AppOpenHandle implements FullScreenAdHandle {}

/// A loaded view-based ad (banner or native), hosted in the widget tree.
abstract interface class ViewAdHandle {
  /// The ad unit this ad was loaded for.
  String get adUnitId;

  /// Which network filled this ad (mediation observability), or null when
  /// the SDK reported nothing. Refreshed by AdMob's server-side auto-refresh
  /// as the winning source changes.
  AdResponseSummary? get response;

  /// Open/close/impression/click events for this ad.
  Stream<ViewAdEvent> get events;

  /// Impression-level revenue events (allowlisted accounts only).
  Stream<AdPaidEvent> get paidEvents;

  /// Builds the widget that renders this ad (an `AdWidget` in production,
  /// a plain placeholder in tests). Host it exactly once.
  Widget buildWidget();

  /// Releases the underlying platform ad.
  Future<void> dispose();
}

/// A loaded banner ad.
abstract interface class BannerHandle implements ViewAdHandle {
  /// The resolved on-screen size, known once loaded.
  ///
  /// Shorthand for `dimensions.value`.
  AdDimensions get size;

  /// Reactive view of [size].
  ///
  /// AdMob's server-side auto-refresh replaces the creative in place, and an
  /// inline adaptive replacement can legitimately resolve to a DIFFERENT
  /// height — the hosting widget sizes its box from the handle, so it must be
  /// told or the new creative renders clipped/letterboxed in the old box
  /// (2026-07 audit). Fixed and anchored sizes never change after load.
  ValueListenable<AdDimensions> get dimensions;

  /// Whether the loaded ad is a collapsible banner.
  bool get isCollapsible;
}

/// A loaded native ad.
abstract interface class NativeHandle implements ViewAdHandle {}

/// The seam between ad_flow and `google_mobile_ads` — the ONLY door to the
/// plugin.
///
/// Everything above this interface is plugin-agnostic and fully testable
/// with `FakeAdSdk`; `GmaAdSdk` maps it onto the real plugin (legacy or
/// Next-Gen native SDK alike).
///
/// All `load*` methods complete with a handle on success and throw an
/// `AdFlowError` (kind `loadFailed`) on failure.
abstract interface class AdSdk {
  /// Initializes the underlying Mobile Ads SDK.
  ///
  /// Safe to run in parallel with consent gathering — initialization sends
  /// no ad request. Completes when the SDK reports ready (or its internal
  /// timeout elapses).
  Future<void> initialize();

  /// Applies global request configuration (test devices, content rating,
  /// COPPA/underage tags).
  Future<void> updateRequestConfiguration(AdRequestConfig config);

  /// Loads an interstitial ad.
  Future<InterstitialHandle> loadInterstitial(
    String adUnitId,
    AdRequestOptions options,
  );

  /// Loads a rewarded ad. [ssv] configures server-side reward verification.
  Future<RewardedHandle> loadRewarded(
    String adUnitId,
    AdRequestOptions options, {
    ServerSideVerification? ssv,
  });

  /// Loads a rewarded interstitial ad. [ssv] configures server-side reward
  /// verification.
  Future<RewardedInterstitialHandle> loadRewardedInterstitial(
    String adUnitId,
    AdRequestOptions options, {
    ServerSideVerification? ssv,
  });

  /// Loads an app open ad.
  Future<AppOpenHandle> loadAppOpen(String adUnitId, AdRequestOptions options);

  /// Loads a banner ad per [spec].
  Future<BannerHandle> loadBanner(BannerLoadSpec spec);

  /// Loads a native ad per [spec].
  Future<NativeHandle> loadNative(NativeLoadSpec spec);

  /// Emits every time the app returns to the foreground (warm start).
  ///
  /// Backed by `AppStateEventNotifier.appStateStream`; never hand-roll
  /// lifecycle detection off `didChangeAppLifecycleState`.
  Stream<AppForegroundEvent> get appForegroundEvents;

  /// Opens the Ad Inspector debug overlay.
  Future<AdInspectorResult> openAdInspector();

  // ── UMP consent primitives ────────────────────────────────────────────
  // Raw one-call wrappers; `ConsentGateway` composes them into the gate.

  /// Refreshes UMP consent info. Call once every app launch.
  ///
  /// Throws an `AdFlowError` (kind `consent`) on failure.
  Future<void> requestConsentInfoUpdate({
    bool? tagForUnderAgeOfConsent,
    ConsentDebugOptions? debug,
  });

  /// Whether ads may be requested. THE gate: no `load*` call is allowed
  /// until this is true.
  Future<bool> canRequestAds();

  /// Current consent status.
  Future<AdConsentStatus> getConsentStatus();

  /// Whether a consent form is available to show.
  Future<bool> isConsentFormAvailable();

  /// Whether the app must surface a privacy-options entry point.
  Future<PrivacyOptionsRequirement> getPrivacyOptionsRequirementStatus();

  /// Loads and shows the consent form if consent is required; completes when
  /// dismissed. Throws an `AdFlowError` (kind `consent`) on form error.
  Future<void> loadAndShowConsentFormIfRequired();

  /// Shows the privacy-options form (the "Manage consent" surface).
  /// Throws an `AdFlowError` (kind `consent`) on form error.
  Future<void> showPrivacyOptionsForm();

  /// Resets UMP consent state. Testing only — never call in production.
  Future<void> resetConsent();

  // ── ATT (iOS App Tracking Transparency) ───────────────────────────────
  // Used only by the opt-in client-driven ATT flow. On Android and any
  // non-iOS platform both methods resolve to [AttStatus.notSupported].

  /// The current ATT authorization status. Android/others →
  /// [AttStatus.notSupported].
  Future<AttStatus> getTrackingAuthorizationStatus();

  /// Shows the iOS system tracking prompt (only when the current status is
  /// [AttStatus.notDetermined]) and resolves to the resulting status. A
  /// no-op returning [AttStatus.notSupported] off iOS.
  Future<AttStatus> requestTrackingAuthorization();
}
