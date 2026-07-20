import '../core/ad_flow_error.dart';

/// Options applied to a single ad request.
///
/// Mirrors the useful subset of the plugin's `AdRequest` without exposing
/// plugin types above the seam.
class AdRequestOptions {
  /// Creates request options; all fields are optional.
  const AdRequestOptions({
    this.keywords,
    this.contentUrl,
    this.neighboringContentUrls,
    this.nonPersonalizedAds,
    this.extras,
    this.mediationExtras,
  });

  /// Targeting keywords.
  final List<String>? keywords;

  /// URL of the content the user is viewing, for targeting.
  final String? contentUrl;

  /// URLs of content adjacent to the ad, for brand safety.
  final List<String>? neighboringContentUrls;

  /// Request non-personalized ads only.
  final bool? nonPersonalizedAds;

  /// Extras for the AdMob adapter itself (e.g. `{'collapsible': 'bottom'}`
  /// is set by the seam for collapsible banners — do not set it here).
  /// Third-party mediation networks do NOT read this map; use
  /// [mediationExtras] for those.
  final Map<String, String>? extras;

  /// Per-network mediation extras, forwarded to the plugin's
  /// `AdRequest.mediationExtras` — see [MediationNetworkExtras].
  final List<MediationNetworkExtras>? mediationExtras;

  static bool _listEq<T>(List<T>? a, List<T>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _mapEq(Map<String, String>? a, Map<String, String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  // Value equality: per-slot configs embed request options, and the
  // widget-first ad widgets compare configs in didUpdateWidget — identity
  // comparison would re-mint a controller (and re-request an ad) on every
  // rebuild that passes a non-const inline config.
  @override
  bool operator ==(Object other) =>
      other is AdRequestOptions &&
      _listEq(other.keywords, keywords) &&
      other.contentUrl == contentUrl &&
      _listEq(other.neighboringContentUrls, neighboringContentUrls) &&
      other.nonPersonalizedAds == nonPersonalizedAds &&
      _mapEq(other.extras, extras) &&
      _listEq(other.mediationExtras, mediationExtras);

  @override
  int get hashCode => Object.hash(
    keywords?.length,
    contentUrl,
    neighboringContentUrls?.length,
    nonPersonalizedAds,
    extras?.length,
    mediationExtras?.length,
  );
}

/// Extras for ONE third-party mediation network on an ad request, mapped to
/// the plugin's `MediationExtras` mechanism (4.0).
///
/// The plugin instantiates [androidClassName] / [iosClassName] via
/// reflection on the platform side — they must name a platform class
/// implementing the plugin's `FlutterMediationExtras` (Android) /
/// `FLTMediationExtras` (iOS) contract, typically provided by the network's
/// `gma_mediation_<network>` adapter package. [extras] is handed to that
/// class to build the network-specific extras object.
///
/// This carries request-level extras only. Network privacy signals (Unity's
/// MetaData consent calls, AppLovin's US-state flag, Meta's Limited Data
/// Use) are separate per-network APIs — see `doc/MEDIATION_SETUP.md` for
/// what remains the integrator's responsibility.
class MediationNetworkExtras {
  /// Creates extras for one network.
  ///
  /// The platform side instantiates [androidClassName] / [iosClassName] by
  /// REFLECTION, so a typo or empty name is a silent no-op at request time
  /// (the extras never reach the network). The asserts catch the empty case
  /// in debug; keep the names in sync with your `gma_mediation_<network>`
  /// adapter package — see doc/MEDIATION_SETUP.md.
  const MediationNetworkExtras({
    required this.androidClassName,
    required this.iosClassName,
    this.extras = const {},
  }) : assert(androidClassName != '', 'androidClassName must not be empty'),
       assert(iosClassName != '', 'iosClassName must not be empty');

  /// Fully-qualified Android class implementing `FlutterMediationExtras`.
  final String androidClassName;

  /// iOS class conforming to `FLTMediationExtras`.
  final String iosClassName;

  /// The values handed to that class.
  final Map<String, Object?> extras;

  @override
  bool operator ==(Object other) {
    if (other is! MediationNetworkExtras) return false;
    if (other.androidClassName != androidClassName ||
        other.iosClassName != iosClassName ||
        other.extras.length != extras.length) {
      return false;
    }
    for (final entry in extras.entries) {
      if (other.extras[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(androidClassName, iosClassName, extras.length);
}

/// Maximum ad content rating, per AdMob's rating scale.
enum MaxContentRating {
  /// General audiences.
  g,

  /// Parental guidance.
  pg,

  /// Teen.
  t,

  /// Mature audiences.
  ma,
}

/// Global request configuration applied once via
/// [MobileAds.updateRequestConfiguration]'s seam equivalent.
class AdRequestConfig {
  /// Creates a request configuration; all fields are optional.
  const AdRequestConfig({
    this.testDeviceIds,
    this.maxAdContentRating,
    this.tagForChildDirectedTreatment,
    this.tagForUnderAgeOfConsent,
  });

  /// Device IDs that should always receive test ads.
  final List<String>? testDeviceIds;

  /// Maximum content rating of served ads.
  final MaxContentRating? maxAdContentRating;

  /// COPPA tag; `null` means unspecified.
  final bool? tagForChildDirectedTreatment;

  /// Tag users below the age of consent; `null` means unspecified.
  final bool? tagForUnderAgeOfConsent;
}

/// Precision of the revenue value reported in an [AdPaidEvent].
enum AdRevenuePrecision {
  /// Unknown precision.
  unknown,

  /// Estimated from aggregated data.
  estimated,

  /// Publisher-provided value (e.g. manual CPMs in mediation).
  publisherProvided,

  /// The precise value paid for this ad.
  precise,
}

/// A compact, plugin-free summary of the SDK's `ResponseInfo` — which
/// network actually filled the ad (2026-07 audit).
///
/// This is the mediation observability surface: without it there is no way
/// to attribute revenue or diagnose fill per ad source through ad_flow.
/// Available on every handle (`handle.response`) and every controller
/// (`controller.response`) once loaded; the winning source also rides along
/// on [AdPaidEvent.adSourceName] for impression-level revenue attribution.
class AdResponseSummary {
  /// Creates a response summary.
  const AdResponseSummary({
    this.responseId,
    this.mediationAdapterClassName,
    this.adSourceName,
    this.adSourceInstanceName,
  });

  /// AdMob's response identifier (correlate with AdMob console logs).
  final String? responseId;

  /// Class name of the mediation adapter that loaded the ad.
  final String? mediationAdapterClassName;

  /// Display name of the winning ad source (e.g. `AdMob Network`, a
  /// mediation partner).
  final String? adSourceName;

  /// The winning ad source instance name from the mediation waterfall.
  final String? adSourceInstanceName;

  @override
  bool operator ==(Object other) =>
      other is AdResponseSummary &&
      other.responseId == responseId &&
      other.mediationAdapterClassName == mediationAdapterClassName &&
      other.adSourceName == adSourceName &&
      other.adSourceInstanceName == adSourceInstanceName;

  @override
  int get hashCode => Object.hash(
    responseId,
    mediationAdapterClassName,
    adSourceName,
    adSourceInstanceName,
  );

  @override
  String toString() =>
      'AdResponseSummary(source: $adSourceName/$adSourceInstanceName, '
      'adapter: $mediationAdapterClassName, id: $responseId)';
}

/// Impression-level revenue reported by the SDK (allowlisted accounts only).
class AdPaidEvent {
  /// Creates a paid event.
  const AdPaidEvent({
    required this.adUnitId,
    required this.valueMicros,
    required this.currencyCode,
    required this.precision,
    this.slot,
    this.adSourceName,
  });

  /// The ad unit that earned the revenue.
  final String adUnitId;

  /// Revenue in micro-units of [currencyCode].
  final double valueMicros;

  /// ISO 4217 currency code.
  final String currencyCode;

  /// How precise [valueMicros] is.
  final AdRevenuePrecision precision;

  /// Which ad_flow slot earned it (`'banner'`, `'interstitial'`, …) — set by
  /// the controller that owns the placement, so one `onPaidEvent` listener
  /// can log per-format revenue (e.g. a Firebase `ad_impression` event)
  /// without juggling ad unit IDs (2026-07 audit).
  final String? slot;

  /// The winning mediation ad source, when known — see
  /// [AdResponseSummary.adSourceName].
  final String? adSourceName;

  /// This event tagged with the ad_flow [slot] that earned it.
  AdPaidEvent taggedWithSlot(String slot) => AdPaidEvent(
    adUnitId: adUnitId,
    valueMicros: valueMicros,
    currencyCode: currencyCode,
    precision: precision,
    slot: slot,
    adSourceName: adSourceName,
  );

  @override
  bool operator ==(Object other) =>
      other is AdPaidEvent &&
      other.adUnitId == adUnitId &&
      other.valueMicros == valueMicros &&
      other.currencyCode == currencyCode &&
      other.precision == precision &&
      other.slot == slot &&
      other.adSourceName == adSourceName;

  @override
  int get hashCode => Object.hash(
    adUnitId,
    valueMicros,
    currencyCode,
    precision,
    slot,
    adSourceName,
  );
}

/// Server-side verification options for (rewarded) ads with high-value
/// rewards — echoed back in AdMob's server-to-server reward callback.
class ServerSideVerification {
  /// Creates SSV options.
  const ServerSideVerification({this.userId, this.customData});

  /// The user to credit in the SSV callback.
  final String? userId;

  /// Opaque data echoed back in the SSV callback.
  final String? customData;
}

/// A reward earned from a rewarded or rewarded interstitial ad.
class RewardEarned {
  /// Creates a reward of [amount] units of [type].
  const RewardEarned({required this.amount, required this.type});

  /// Number of reward units earned.
  final num amount;

  /// Reward type as configured in the AdMob console.
  final String type;

  @override
  bool operator ==(Object other) =>
      other is RewardEarned && other.amount == amount && other.type == type;

  @override
  int get hashCode => Object.hash(amount, type);
}

/// Callback invoked when the user earns a reward.
typedef OnUserEarnedReward = void Function(RewardEarned reward);

/// Events emitted by a full-screen ad handle between `show()` and disposal.
sealed class FullScreenAdEvent {
  const FullScreenAdEvent();
}

/// The ad showed full-screen content.
class AdShowedEvent extends FullScreenAdEvent {
  /// Const instance.
  const AdShowedEvent();
}

/// The ad was dismissed by the user. The handle is now single-use spent:
/// dispose it and load the next one.
class AdDismissedEvent extends FullScreenAdEvent {
  /// Const instance.
  const AdDismissedEvent();
}

/// The ad failed to show full-screen content.
class AdFailedToShowEvent extends FullScreenAdEvent {
  /// Wraps the show [error].
  const AdFailedToShowEvent(this.error);

  /// Why the show failed.
  final AdFlowError error;
}

/// An impression was recorded for the ad.
class AdImpressionEvent extends FullScreenAdEvent {
  /// Const instance.
  const AdImpressionEvent();
}

/// The user clicked the ad.
class AdClickedEvent extends FullScreenAdEvent {
  /// Const instance.
  const AdClickedEvent();
}

/// Events emitted by banner and native (view-based) ad handles.
enum ViewAdEvent {
  /// The ad opened an overlay (e.g. a browser).
  opened,

  /// The opened overlay was closed.
  closed,

  /// An impression was recorded.
  impression,

  /// The user clicked the ad.
  clicked,
}

/// Screen orientation used when resolving adaptive banner sizes.
enum AdOrientation {
  /// Portrait.
  portrait,

  /// Landscape.
  landscape,
}

/// Fixed (non-adaptive) IAB banner sizes.
enum FixedBannerSize {
  /// 320x50.
  banner,

  /// 320x100.
  largeBanner,

  /// 300x250.
  mediumRectangle,

  /// 468x60.
  fullBanner,

  /// 728x90.
  leaderboard,
}

/// How a banner should be sized.
sealed class BannerSizeSpec {
  const BannerSizeSpec();
}

/// Anchored adaptive banner (the recommended default).
///
/// Resolved via `AdSize.getLargeAnchoredAdaptiveBannerAdSize` (or the
/// `WithOrientation` variant when [orientation] is set).
class AnchoredAdaptiveSizeSpec extends BannerSizeSpec {
  /// Creates a spec for an anchored adaptive banner of [width] logical px.
  const AnchoredAdaptiveSizeSpec({required this.width, this.orientation});

  /// Available width in logical pixels (truncated screen width, typically).
  final int width;

  /// Lock the size to an orientation instead of the current one.
  final AdOrientation? orientation;
}

/// Inline adaptive banner (for placement within scrolling content).
class InlineAdaptiveSizeSpec extends BannerSizeSpec {
  /// Creates a spec for an inline adaptive banner of [width] logical px.
  const InlineAdaptiveSizeSpec({
    required this.width,
    this.maxHeight,
    this.orientation,
  });

  /// Available width in logical pixels.
  final int width;

  /// Optional maximum height in logical pixels.
  final int? maxHeight;

  /// Lock the size to an orientation instead of the current one.
  final AdOrientation? orientation;
}

/// A fixed IAB banner size.
class FixedSizeSpec extends BannerSizeSpec {
  /// Creates a spec for the given fixed [size].
  const FixedSizeSpec(this.size);

  /// Which fixed size to request.
  final FixedBannerSize size;
}

/// Where a collapsible banner anchors while expanded.
enum CollapsiblePlacement {
  /// Expanded ad anchors to the top of the screen.
  top,

  /// Expanded ad anchors to the bottom of the screen.
  bottom,
}

/// Everything the seam needs to load one banner.
class BannerLoadSpec {
  /// Creates a banner load spec.
  const BannerLoadSpec({
    required this.adUnitId,
    required this.size,
    this.collapsible,
    this.request = const AdRequestOptions(),
  });

  /// The banner ad unit.
  final String adUnitId;

  /// How to size the banner.
  final BannerSizeSpec size;

  /// Request a collapsible banner anchored at the given placement.
  /// Google demand only; auto-refresh does not re-request collapsible ads.
  final CollapsiblePlacement? collapsible;

  /// Per-request options.
  final AdRequestOptions request;
}

/// Built-in native ad template types (Dart-only rendering).
enum NativeTemplateKind {
  /// Small template (minimum ~320x90).
  small,

  /// Medium template (minimum ~320x320).
  medium,
}

/// Everything the seam needs to load one native ad.
///
/// Exactly one of [templateKind] (Dart template rendering) or [factoryId]
/// (a platform-registered `NativeAdFactory`) must be provided.
class NativeLoadSpec {
  /// Creates a native load spec.
  const NativeLoadSpec({
    required this.adUnitId,
    this.templateKind,
    this.factoryId,
    this.factoryExtras,
    this.request = const AdRequestOptions(),
  }) : assert(
         (templateKind != null) ^ (factoryId != null),
         'Provide exactly one of templateKind or factoryId.',
       );

  /// The native ad unit.
  final String adUnitId;

  /// Render with a built-in template of this kind.
  final NativeTemplateKind? templateKind;

  /// Render with the platform-registered factory of this id.
  final String? factoryId;

  /// Options passed through to a platform factory.
  final Map<String, Object>? factoryExtras;

  /// Per-request options.
  final AdRequestOptions request;
}

/// The on-screen size of a loaded view-based ad, in logical pixels.
class AdDimensions {
  /// Creates dimensions of [width] x [height].
  const AdDimensions({required this.width, required this.height});

  /// Width in logical pixels.
  final double width;

  /// Height in logical pixels.
  final double height;

  @override
  bool operator ==(Object other) =>
      other is AdDimensions && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'AdDimensions($width x $height)';
}

/// Emitted when the app returns to the foreground (warm start).
///
/// Backed by the plugin's `AppStateEventNotifier.appStateStream` — the only
/// correct foreground signal (iOS `inactive` is NOT backgrounding).
class AppForegroundEvent {
  /// Const instance.
  const AppForegroundEvent();
}

/// Result of opening the Ad Inspector.
class AdInspectorResult {
  /// Creates a result; [error] is null on success.
  const AdInspectorResult({this.error});

  /// The failure, if the inspector could not open or errored.
  final AdFlowError? error;

  /// Whether the inspector opened and closed without error.
  bool get isSuccess => error == null;
}

/// UMP consent status, mirrored above the seam.
enum AdConsentStatus {
  /// Consent status is unknown (info update has not run).
  unknown,

  /// Consent is required but not yet obtained.
  required,

  /// Consent is not required (e.g. user outside EEA/UK/CH).
  notRequired,

  /// Consent has been obtained.
  obtained,
}

/// Whether a privacy-options entry point must be surfaced in the app.
enum PrivacyOptionsRequirement {
  /// Unknown (info update has not run).
  unknown,

  /// A persistent "Manage consent" control is required.
  required,

  /// No privacy-options entry point is required.
  notRequired,
}

/// iOS App Tracking Transparency authorization status, mirrored above the
/// seam. Only iOS 14+ ever reports the first four; every other platform (and
/// older iOS) reports [notSupported].
enum AttStatus {
  /// The user has not yet been shown the system tracking prompt — the only
  /// state in which requesting authorization shows the dialog.
  notDetermined,

  /// Tracking is restricted at the device level; the prompt cannot be shown.
  restricted,

  /// The user denied tracking authorization.
  denied,

  /// The user authorized tracking.
  authorized,

  /// Not iOS (or below iOS 14) — ATT does not apply.
  notSupported,
}

/// Debug geography override for UMP testing.
enum ConsentDebugGeography {
  /// No override.
  disabled,

  /// Behave as if the device is in the EEA.
  eea,

  /// Behave as if the device is in a regulated US state.
  regulatedUsState,

  /// Behave as if the device is in an unregulated region.
  other,
}

/// Debug settings for UMP consent testing. Remove before release.
class ConsentDebugOptions {
  /// Creates debug options.
  const ConsentDebugOptions({
    this.geography = ConsentDebugGeography.disabled,
    this.testIdentifiers = const [],
  });

  /// Simulated geography.
  final ConsentDebugGeography geography;

  /// Hashed test device identifiers (printed to the console on first run).
  final List<String> testIdentifiers;
}
