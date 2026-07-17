import '../core/ad_flow_error.dart';
import '../seam/ad_sdk_types.dart';
import 'ad_platform.dart';

/// A pair of per-platform ad unit IDs.
class PlatformAdUnitId {
  /// Creates a per-platform ad unit ID pair; leave a platform null if the
  /// app does not ship there.
  const PlatformAdUnitId({this.android, this.ios});

  /// The Android ad unit ID (`ca-app-pub-…`).
  final String? android;

  /// The iOS ad unit ID (`ca-app-pub-…`).
  final String? ios;

  /// The ID for [platform], or null if none was configured.
  String? resolve(AdPlatform platform) => switch (platform) {
    AdPlatform.android => android,
    AdPlatform.ios => ios,
  };

  @override
  bool operator ==(Object other) =>
      other is PlatformAdUnitId && other.android == android && other.ios == ios;

  @override
  int get hashCode => Object.hash(android, ios);
}

/// Limits how often full-screen ads in a slot may show.
class FrequencyCap {
  /// Creates a frequency cap.
  const FrequencyCap({
    this.maxPerSession,
    this.maxPerHour,
    this.minGap = Duration.zero,
  }) : assert(
         maxPerSession == null || maxPerSession >= 0,
         'maxPerSession must be >= 0',
       ),
       assert(maxPerHour == null || maxPerHour >= 0, 'maxPerHour must be >= 0');

  /// Maximum impressions per app session (null = unlimited).
  final int? maxPerSession;

  /// Maximum impressions per rolling hour (null = unlimited).
  final int? maxPerHour;

  /// Minimum gap between two impressions.
  final Duration minGap;

  @override
  bool operator ==(Object other) =>
      other is FrequencyCap &&
      other.maxPerSession == maxPerSession &&
      other.maxPerHour == maxPerHour &&
      other.minGap == minGap;

  @override
  int get hashCode => Object.hash(maxPerSession, maxPerHour, minGap);
}

/// Tuning for load-failure retries (consumed by `RetryPolicy`).
///
/// Defaults port v1's battle-tested timing (3 attempts, 5s base, 5min
/// cooldown) onto exponential backoff with jitter (ADR-008).
class RetryConfig {
  /// Creates retry tuning.
  const RetryConfig({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(seconds: 5),
    this.maxDelay = const Duration(minutes: 1),
    this.cooldown = const Duration(minutes: 5),
    this.jitterFactor = 0.25,
  }) : assert(maxAttempts >= 0, 'maxAttempts must be >= 0'),
       assert(
         jitterFactor >= 0 && jitterFactor <= 1,
         'jitterFactor must be within [0, 1]',
       );

  /// Total load attempts before entering [cooldown]. 0 disables retries.
  final int maxAttempts;

  /// Delay before the first retry; doubles each attempt.
  final Duration baseDelay;

  /// Upper bound for a single backoff delay.
  final Duration maxDelay;

  /// How long to wait after [maxAttempts] failures before auto re-arming.
  final Duration cooldown;

  /// Random jitter applied to each delay, as a fraction of the delay
  /// (0.25 = ±25%). Prevents lockstep retries across slots.
  final double jitterFactor;

  @override
  bool operator ==(Object other) =>
      other is RetryConfig &&
      other.maxAttempts == maxAttempts &&
      other.baseDelay == baseDelay &&
      other.maxDelay == maxDelay &&
      other.cooldown == cooldown &&
      other.jitterFactor == jitterFactor;

  @override
  int get hashCode =>
      Object.hash(maxAttempts, baseDelay, maxDelay, cooldown, jitterFactor);
}

/// Copy for the mandatory rewarded-interstitial intro screen
/// (reward disclosure + skip option — an AdMob policy requirement).
class RewardIntroContent {
  /// Creates intro-screen copy; defaults are generic English strings —
  /// override them with app-specific, localized text.
  const RewardIntroContent({
    this.title = 'Earn a reward',
    this.message = 'Watch a short ad to earn your reward.',
    this.continueLabel = 'Watch ad',
    this.skipLabel = 'No thanks',
  });

  /// Headline.
  final String title;

  /// Body text; must make the reward clear.
  final String message;

  /// Label of the button that proceeds to the ad.
  final String continueLabel;

  /// Label of the skip option (mandatory — never remove it).
  final String skipLabel;
}

/// How a banner slot is sized.
enum BannerKind {
  /// Anchored adaptive (the recommended, revenue-optimized default).
  anchoredAdaptive,

  /// Inline adaptive, for banners inside scrolling content.
  inlineAdaptive,

  /// A fixed IAB size (see [BannerConfig.fixedSize]).
  fixed,
}

/// Configuration for the banner slot.
class BannerConfig {
  /// Creates banner configuration.
  const BannerConfig({
    required this.adUnitId,
    this.kind = BannerKind.anchoredAdaptive,
    this.fixedSize = FixedBannerSize.banner,
    this.maxInlineHeight,
    this.collapsible,
    this.minRefresh,
  });

  /// Per-platform banner ad unit IDs.
  final PlatformAdUnitId adUnitId;

  /// Sizing strategy. Prefer [BannerKind.anchoredAdaptive] over fixed sizes.
  final BannerKind kind;

  /// The size used when [kind] is [BannerKind.fixed].
  final FixedBannerSize fixedSize;

  /// Height cap for [BannerKind.inlineAdaptive] banners.
  final int? maxInlineHeight;

  /// Request collapsible banners anchored at this placement (Google demand
  /// only; auto-refresh does not re-request collapsible ads).
  final CollapsiblePlacement? collapsible;

  /// Opt-in **client-side** refresh interval. **Null (the default) means no
  /// client-side refresh at all** — no timer runs (ADR-041).
  ///
  /// Leave this null unless you know you need it. AdMob already refreshes
  /// banner ad units **server-side**, configured per ad unit in the AdMob
  /// console and **on by default**. A client-side timer on top of that is a
  /// second, unsynchronised refresh loop for the same placement: up to 2x the
  /// ad requests, for no extra revenue. Configure the refresh rate in the
  /// console instead.
  ///
  /// Set it only when the console refresh is deliberately off and you want the
  /// client to drive it. Values below 30s are clamped by the banner controller
  /// (Duration comparisons are not allowed in const asserts, so this cannot be
  /// a constructor assert); AdMob's own guidance is 60s or more.
  ///
  /// When set, a refresh never blanks the slot: the current ad keeps rendering
  /// until its replacement has actually loaded (ADR-041).
  final Duration? minRefresh;
}

/// Configuration for the interstitial slot.
class InterstitialConfig {
  /// Creates interstitial configuration.
  const InterstitialConfig({
    required this.adUnitId,
    this.cap = const FrequencyCap(minGap: Duration(seconds: 30)),
    this.minActionsBetween = 2,
    this.maxAdAge = const Duration(minutes: 55),
  }) : assert(minActionsBetween >= 0, 'minActionsBetween must be >= 0');

  /// Per-platform interstitial ad unit IDs.
  final PlatformAdUnitId adUnitId;

  /// Per-slot frequency cap (v1 default: 30s minimum gap).
  final FrequencyCap cap;

  /// Minimum user actions between two interstitials (AdMob guidance:
  /// at most one ad per two user actions).
  final int minActionsBetween;

  /// How long a preloaded ad stays showable before it is proactively
  /// discarded and replaced (null = never).
  ///
  /// Google documents full-screen ads as expiring **after one hour**: a
  /// stale ad shown late may fail to display — or display but not count —
  /// so a long session's warm ad could silently waste its natural break.
  /// The 55-minute default replaces it just inside the documented window
  /// (2026-07 audit).
  final Duration? maxAdAge;
}

/// Configuration for the rewarded slot.
class RewardedConfig {
  /// Creates rewarded configuration.
  const RewardedConfig({
    required this.adUnitId,
    this.cap = const FrequencyCap(),
    this.ssv,
    this.maxAdAge = const Duration(minutes: 55),
  });

  /// Per-platform rewarded ad unit IDs.
  final PlatformAdUnitId adUnitId;

  /// Per-slot frequency cap. **Unlimited by default**, and deliberately so: a
  /// rewarded ad is one the user explicitly asked for, in exchange for
  /// something. Capping it means refusing a user who tapped "watch an ad for
  /// 100 coins" — they get no ad and no reward. Set a cap only if you have a
  /// specific abuse to prevent.
  ///
  /// This slot is exempt from [AdFlowConfig.globalFrequencyCap] (ADR-039):
  /// the global cap paces **involuntary** ads and must never swallow a
  /// user-initiated one.
  final FrequencyCap cap;

  /// Server-side verification for high-value rewards.
  final ServerSideVerification? ssv;

  /// How long a preloaded ad stays showable before it is proactively
  /// discarded and replaced (null = never) — see
  /// [InterstitialConfig.maxAdAge].
  final Duration? maxAdAge;
}

/// Configuration for the rewarded interstitial slot.
class RewardedInterstitialConfig {
  /// Creates rewarded interstitial configuration.
  const RewardedInterstitialConfig({
    required this.adUnitId,
    this.cap = const FrequencyCap(),
    this.intro = const RewardIntroContent(),
    this.ssv,
    this.maxAdAge = const Duration(minutes: 55),
  });

  /// Per-platform rewarded interstitial ad unit IDs.
  final PlatformAdUnitId adUnitId;

  /// Per-slot frequency cap. Unlimited by default — see [RewardedConfig.cap].
  /// The user reaches this ad only by tapping "continue" on the mandatory
  /// intro screen, so it too is exempt from
  /// [AdFlowConfig.globalFrequencyCap] (ADR-039).
  final FrequencyCap cap;

  /// Copy for the mandatory intro/skip screen shown before the ad.
  final RewardIntroContent intro;

  /// Server-side verification for high-value rewards.
  final ServerSideVerification? ssv;

  /// How long a preloaded ad stays showable before it is proactively
  /// discarded and replaced (null = never) — see
  /// [InterstitialConfig.maxAdAge].
  final Duration? maxAdAge;
}

/// Configuration for the native slot.
///
/// Provide exactly one of [templateKind] (Dart template rendering, the
/// simple path) or [factoryId] (a platform-registered `NativeAdFactory`).
class NativeConfig {
  /// Creates native configuration.
  const NativeConfig({
    required this.adUnitId,
    this.templateKind,
    this.factoryId,
    this.factoryExtras,
  }) : assert(
         (templateKind != null) ^ (factoryId != null),
         'Provide exactly one of templateKind or factoryId.',
       );

  /// Per-platform native ad unit IDs.
  final PlatformAdUnitId adUnitId;

  /// Render with a built-in template of this kind.
  final NativeTemplateKind? templateKind;

  /// Render with the platform-registered factory of this id.
  final String? factoryId;

  /// Options passed through to a platform factory.
  final Map<String, Object>? factoryExtras;
}

/// Configuration for the app open slot.
class AppOpenConfig {
  /// Creates app open configuration.
  const AppOpenConfig({
    required this.adUnitId,
    this.cap = const FrequencyCap(minGap: Duration(minutes: 4)),
    this.expiry = const Duration(hours: 4),
  });

  /// Per-platform app open ad unit IDs.
  final PlatformAdUnitId adUnitId;

  /// Per-slot frequency cap.
  final FrequencyCap cap;

  /// Loaded ads older than this are discarded and reloaded
  /// (Google mandates 4 hours).
  final Duration expiry;
}

// 3.0: `showOnColdStart` (deprecated + ignored since 2.1.0/ADR-043) is
// REMOVED. It never could show an ad on a cold launch — no foreground event
// exists for one — and the first warm return shows by default.

/// Google's official sample ad unit IDs (safe to click; used by
/// [AdFlowConfig.test] and whenever [AdFlowConfig.testMode] is on).
abstract final class TestAdUnitIds {
  /// Sample banner IDs.
  static const banner = PlatformAdUnitId(
    android: 'ca-app-pub-3940256099942544/6300978111',
    ios: 'ca-app-pub-3940256099942544/2435281174',
  );

  /// Sample interstitial IDs.
  static const interstitial = PlatformAdUnitId(
    android: 'ca-app-pub-3940256099942544/1033173712',
    ios: 'ca-app-pub-3940256099942544/4411468910',
  );

  /// Sample rewarded IDs.
  static const rewarded = PlatformAdUnitId(
    android: 'ca-app-pub-3940256099942544/5224354917',
    ios: 'ca-app-pub-3940256099942544/1712485313',
  );

  /// Sample rewarded interstitial IDs.
  static const rewardedInterstitial = PlatformAdUnitId(
    android: 'ca-app-pub-3940256099942544/5354046379',
    ios: 'ca-app-pub-3940256099942544/6978759866',
  );

  /// Sample native (advanced) IDs.
  static const native = PlatformAdUnitId(
    android: 'ca-app-pub-3940256099942544/2247696110',
    ios: 'ca-app-pub-3940256099942544/3986624511',
  );

  /// Sample app open IDs.
  static const appOpen = PlatformAdUnitId(
    android: 'ca-app-pub-3940256099942544/9257395921',
    ios: 'ca-app-pub-3940256099942544/5575463023',
  );
}

/// Immutable top-level configuration for ad_flow.
///
/// Note: the AdMob **application ID** cannot be set at runtime — it lives in
/// `AndroidManifest.xml` (`com.google.android.gms.ads.APPLICATION_ID`) and
/// `Info.plist` (`GADApplicationIdentifier`). This config carries ad *unit*
/// IDs only.
class AdFlowConfig {
  /// Creates a configuration. Formats without config never load.
  const AdFlowConfig({
    this.banner,
    this.interstitial,
    this.rewarded,
    this.rewardedInterstitial,
    this.nativeAd,
    this.appOpen,
    this.globalFrequencyCap = const FrequencyCap(
      maxPerSession: 100,
      minGap: Duration(seconds: 15),
    ),
    this.retry = const RetryConfig(),
    this.testMode = false,
    this.testDeviceIds = const [],
    this.maxAdContentRating,
    this.tagForUnderAgeOfConsent,
    this.tagForChildDirectedTreatment,
  });

  /// Validates the configuration, throwing an
  /// [AdFlowError] (kind `invalidConfig`) on the first nonsensical value.
  ///
  /// Called automatically by `AdFlow.initialize` — failing at init is
  /// discoverable; a blank/empty ad unit ID silently producing no-fill
  /// forever is not (2026-07 audit). Durations cannot be compared in const
  /// constructor asserts (`const_eval_type_num`), so this is where their
  /// sanity checks live.
  void validate() {
    void check(bool ok, String message) {
      if (!ok) throw AdFlowError(AdFlowErrorKind.invalidConfig, message);
    }

    void checkUnitId(PlatformAdUnitId id, String slot) {
      check(
        id.android != null || id.ios != null,
        '$slot.adUnitId has no platform IDs — configure android and/or ios, '
        'or leave the slot null.',
      );
      check(
        id.android == null || id.android!.trim().isNotEmpty,
        '$slot.adUnitId.android is an empty string.',
      );
      check(
        id.ios == null || id.ios!.trim().isNotEmpty,
        '$slot.adUnitId.ios is an empty string.',
      );
    }

    void checkCap(FrequencyCap cap, String name) {
      check(cap.minGap >= Duration.zero, '$name.minGap is negative.');
    }

    void checkAge(Duration? age, String name) {
      check(age == null || age > Duration.zero, '$name must be positive.');
    }

    final banner = this.banner;
    if (banner != null) {
      checkUnitId(banner.adUnitId, 'banner');
      check(
        banner.maxInlineHeight == null || banner.maxInlineHeight! > 0,
        'banner.maxInlineHeight must be positive.',
      );
      check(
        banner.minRefresh == null || banner.minRefresh! > Duration.zero,
        'banner.minRefresh must be positive (or null to disable).',
      );
    }
    final interstitial = this.interstitial;
    if (interstitial != null) {
      checkUnitId(interstitial.adUnitId, 'interstitial');
      checkCap(interstitial.cap, 'interstitial.cap');
      checkAge(interstitial.maxAdAge, 'interstitial.maxAdAge');
    }
    final rewarded = this.rewarded;
    if (rewarded != null) {
      checkUnitId(rewarded.adUnitId, 'rewarded');
      checkCap(rewarded.cap, 'rewarded.cap');
      checkAge(rewarded.maxAdAge, 'rewarded.maxAdAge');
    }
    final rewardedInterstitial = this.rewardedInterstitial;
    if (rewardedInterstitial != null) {
      checkUnitId(rewardedInterstitial.adUnitId, 'rewardedInterstitial');
      checkCap(rewardedInterstitial.cap, 'rewardedInterstitial.cap');
      checkAge(rewardedInterstitial.maxAdAge, 'rewardedInterstitial.maxAdAge');
    }
    final nativeAd = this.nativeAd;
    if (nativeAd != null) checkUnitId(nativeAd.adUnitId, 'nativeAd');
    final appOpen = this.appOpen;
    if (appOpen != null) {
      checkUnitId(appOpen.adUnitId, 'appOpen');
      checkCap(appOpen.cap, 'appOpen.cap');
      check(appOpen.expiry > Duration.zero, 'appOpen.expiry must be positive.');
    }
    checkCap(globalFrequencyCap, 'globalFrequencyCap');
    check(retry.baseDelay > Duration.zero, 'retry.baseDelay must be positive.');
    check(
      retry.maxDelay >= retry.baseDelay,
      'retry.maxDelay must be >= retry.baseDelay.',
    );
    check(retry.cooldown >= Duration.zero, 'retry.cooldown is negative.');
    for (final id in testDeviceIds) {
      check(id.trim().isNotEmpty, 'testDeviceIds contains an empty string.');
    }
  }

  /// A configuration that serves Google's official test ads for every
  /// format. Use during development; never ship it.
  factory AdFlowConfig.test({
    FrequencyCap? globalFrequencyCap,
    RetryConfig? retry,
  }) => AdFlowConfig(
    banner: const BannerConfig(adUnitId: TestAdUnitIds.banner),
    interstitial: const InterstitialConfig(
      adUnitId: TestAdUnitIds.interstitial,
    ),
    rewarded: const RewardedConfig(adUnitId: TestAdUnitIds.rewarded),
    rewardedInterstitial: const RewardedInterstitialConfig(
      adUnitId: TestAdUnitIds.rewardedInterstitial,
    ),
    nativeAd: const NativeConfig(
      adUnitId: TestAdUnitIds.native,
      templateKind: NativeTemplateKind.medium,
    ),
    appOpen: const AppOpenConfig(adUnitId: TestAdUnitIds.appOpen),
    globalFrequencyCap:
        globalFrequencyCap ??
        const FrequencyCap(maxPerSession: 100, minGap: Duration(seconds: 15)),
    retry: retry ?? const RetryConfig(),
    testMode: true,
  );

  /// Banner slot config, or null to disable banners.
  final BannerConfig? banner;

  /// Interstitial slot config, or null to disable interstitials.
  final InterstitialConfig? interstitial;

  /// Rewarded slot config, or null to disable rewarded ads.
  final RewardedConfig? rewarded;

  /// Rewarded interstitial slot config, or null to disable the format.
  final RewardedInterstitialConfig? rewardedInterstitial;

  /// Native slot config, or null to disable native ads.
  final NativeConfig? nativeAd;

  /// App open slot config, or null to disable app open ads.
  final AppOpenConfig? appOpen;

  /// Cross-format cap: no two full-screen ads back to back.
  final FrequencyCap globalFrequencyCap;

  /// Load-retry tuning shared by all slots.
  final RetryConfig retry;

  /// When true, every slot serves Google's sample test IDs regardless of
  /// the configured IDs. **Explicit flag — never derived from resolved IDs**
  /// (v1's derivation produced false positives, ADR-012).
  final bool testMode;

  /// Devices that always receive test ads (with real IDs).
  final List<String> testDeviceIds;

  /// Maximum content rating of served ads.
  final MaxContentRating? maxAdContentRating;

  /// Tag users below the age of consent; null = unspecified.
  final bool? tagForUnderAgeOfConsent;

  /// COPPA tag; null = unspecified.
  final bool? tagForChildDirectedTreatment;

  /// The banner ad unit ID to actually request for [platform]
  /// (the test ID when [testMode] is on), or null if the slot is off.
  String? bannerAdUnitId(AdPlatform platform) =>
      _effective(banner?.adUnitId, TestAdUnitIds.banner, platform);

  /// Effective interstitial ad unit ID for [platform]; see [bannerAdUnitId].
  String? interstitialAdUnitId(AdPlatform platform) =>
      _effective(interstitial?.adUnitId, TestAdUnitIds.interstitial, platform);

  /// Effective rewarded ad unit ID for [platform]; see [bannerAdUnitId].
  String? rewardedAdUnitId(AdPlatform platform) =>
      _effective(rewarded?.adUnitId, TestAdUnitIds.rewarded, platform);

  /// Effective rewarded interstitial ad unit ID for [platform];
  /// see [bannerAdUnitId].
  String? rewardedInterstitialAdUnitId(AdPlatform platform) => _effective(
    rewardedInterstitial?.adUnitId,
    TestAdUnitIds.rewardedInterstitial,
    platform,
  );

  /// Effective native ad unit ID for [platform]; see [bannerAdUnitId].
  String? nativeAdUnitId(AdPlatform platform) =>
      _effective(nativeAd?.adUnitId, TestAdUnitIds.native, platform);

  /// Effective app open ad unit ID for [platform]; see [bannerAdUnitId].
  String? appOpenAdUnitId(AdPlatform platform) =>
      _effective(appOpen?.adUnitId, TestAdUnitIds.appOpen, platform);

  /// The request configuration to push to the SDK at initialization.
  AdRequestConfig toRequestConfig() => AdRequestConfig(
    testDeviceIds: testDeviceIds.isEmpty ? null : testDeviceIds,
    maxAdContentRating: maxAdContentRating,
    tagForChildDirectedTreatment: tagForChildDirectedTreatment,
    tagForUnderAgeOfConsent: tagForUnderAgeOfConsent,
  );

  /// Test-mode substitution: a configured slot resolves to the sample ID
  /// while [testMode] is on. An unconfigured slot stays null — it never
  /// loads, so it must not resolve to anything (v1 bug, ADR-012).
  String? _effective(
    PlatformAdUnitId? configured,
    PlatformAdUnitId testIds,
    AdPlatform platform,
  ) {
    if (configured == null) return null;
    return (testMode ? testIds : configured).resolve(platform);
  }
}
