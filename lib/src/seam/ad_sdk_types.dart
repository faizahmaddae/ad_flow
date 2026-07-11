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
  });

  /// Targeting keywords.
  final List<String>? keywords;

  /// URL of the content the user is viewing, for targeting.
  final String? contentUrl;

  /// URLs of content adjacent to the ad, for brand safety.
  final List<String>? neighboringContentUrls;

  /// Request non-personalized ads only.
  final bool? nonPersonalizedAds;

  /// Network-specific extras (e.g. `{'collapsible': 'bottom'}` is set by the
  /// seam itself for collapsible banners — do not set it here).
  final Map<String, String>? extras;
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

/// Impression-level revenue reported by the SDK (allowlisted accounts only).
class AdPaidEvent {
  /// Creates a paid event.
  const AdPaidEvent({
    required this.adUnitId,
    required this.valueMicros,
    required this.currencyCode,
    required this.precision,
  });

  /// The ad unit that earned the revenue.
  final String adUnitId;

  /// Revenue in micro-units of [currencyCode].
  final double valueMicros;

  /// ISO 4217 currency code.
  final String currencyCode;

  /// How precise [valueMicros] is.
  final AdRevenuePrecision precision;

  @override
  bool operator ==(Object other) =>
      other is AdPaidEvent &&
      other.adUnitId == adUnitId &&
      other.valueMicros == valueMicros &&
      other.currencyCode == currencyCode &&
      other.precision == precision;

  @override
  int get hashCode =>
      Object.hash(adUnitId, valueMicros, currencyCode, precision);
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
