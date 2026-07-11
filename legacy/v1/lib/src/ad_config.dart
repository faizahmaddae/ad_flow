// Copyright 2024 - AdMob Integration Package
// Production-ready AdMob configuration for Flutter

import 'dart:io';

import 'package:flutter/foundation.dart'
    show TargetPlatform, kReleaseMode, visibleForTesting;
import 'ad_flow_logger.dart';

// ============================================================
// PLATFORM DETECTION (testable)
// ============================================================

/// Testable platform detection for ad_flow.
///
/// Consolidates `dart:io` `Platform.isAndroid`/`Platform.isIOS` checks
/// behind an overridable interface, enabling unit tests to simulate
/// either platform.
///
/// ```dart
/// // In test setUp:
/// AdFlowPlatform.platformOverride = TargetPlatform.android;
/// // In test tearDown:
/// AdFlowPlatform.reset();
/// ```
class AdFlowPlatform {
  AdFlowPlatform._();

  /// Override for platform detection in unit tests.
  @visibleForTesting
  static TargetPlatform? platformOverride;

  /// Whether the current platform is Android (testable).
  static bool get isAndroid =>
      platformOverride == TargetPlatform.android ||
      (platformOverride == null && Platform.isAndroid);

  /// Whether the current platform is iOS (testable).
  static bool get isIOS =>
      platformOverride == TargetPlatform.iOS ||
      (platformOverride == null && Platform.isIOS);

  /// Resets the platform override.
  @visibleForTesting
  static void reset() => platformOverride = null;
}

// ============================================================
// GOOGLE TEST AD UNIT IDs (for development/testing)
// ============================================================

/// Google's official test ad unit IDs for development.
///
/// These IDs are provided by Google and should ONLY be used during development.
/// Using test IDs in production can result in ad serving being disabled.
///
/// See: https://developers.google.com/admob/android/test-ads
class TestAdUnitIds {
  TestAdUnitIds._();

  /// Helper to get platform-specific ad unit ID
  static String _getPlatformId(String androidId, String iosId) {
    if (AdFlowPlatform.isAndroid) return androidId;
    if (AdFlowPlatform.isIOS) return iosId;
    // Return empty string for unsupported platforms (web, desktop)
    // to avoid crashes during testing or multi-platform development
    return '';
  }

  /// Test banner ad unit ID
  static String get banner => _getPlatformId(
    'ca-app-pub-3940256099942544/6300978111',
    'ca-app-pub-3940256099942544/2435281174',
  );

  /// Test interstitial ad unit ID
  static String get interstitial => _getPlatformId(
    'ca-app-pub-3940256099942544/1033173712',
    'ca-app-pub-3940256099942544/4411468910',
  );

  /// Test app open ad unit ID
  static String get appOpen => _getPlatformId(
    'ca-app-pub-3940256099942544/9257395921',
    'ca-app-pub-3940256099942544/5575463023',
  );

  /// Test native ad unit ID
  static String get native => _getPlatformId(
    'ca-app-pub-3940256099942544/2247696110',
    'ca-app-pub-3940256099942544/3986624511',
  );

  /// Test rewarded ad unit ID
  static String get rewarded => _getPlatformId(
    'ca-app-pub-3940256099942544/5224354917',
    'ca-app-pub-3940256099942544/1712485313',
  );

  /// Test rewarded interstitial ad unit ID
  static String get rewardedInterstitial => _getPlatformId(
    'ca-app-pub-3940256099942544/5354046379',
    'ca-app-pub-3940256099942544/6978759866',
  );
}

// ============================================================
// USER CONFIGURATION CLASS
// ============================================================

/// Configuration for ad_flow package.
///
/// Create an instance and pass to [AdFlow.instance.initialize()]:
/// ```dart
/// final config = AdFlowConfig(
///   androidBannerAdUnitId: 'ca-app-pub-xxx/xxx',
///   iosBannerAdUnitId: 'ca-app-pub-xxx/xxx',
///   androidInterstitialAdUnitId: 'ca-app-pub-xxx/xxx',
///   iosInterstitialAdUnitId: 'ca-app-pub-xxx/xxx',
///   // ... other IDs
/// );
///
/// await AdFlow.instance.initialize(config: config);
/// ```
///
/// For testing, use [AdFlowConfig.testMode()] which uses Google's test IDs.
class AdFlowConfig {
  /// Android banner ad unit ID from AdMob console
  final String? androidBannerAdUnitId;

  /// iOS banner ad unit ID from AdMob console
  final String? iosBannerAdUnitId;

  /// Android interstitial ad unit ID from AdMob console
  final String? androidInterstitialAdUnitId;

  /// iOS interstitial ad unit ID from AdMob console
  final String? iosInterstitialAdUnitId;

  /// Android app open ad unit ID from AdMob console
  final String? androidAppOpenAdUnitId;

  /// iOS app open ad unit ID from AdMob console
  final String? iosAppOpenAdUnitId;

  /// Android native ad unit ID from AdMob console
  final String? androidNativeAdUnitId;

  /// iOS native ad unit ID from AdMob console
  final String? iosNativeAdUnitId;

  /// Android rewarded ad unit ID from AdMob console
  final String? androidRewardedAdUnitId;

  /// iOS rewarded ad unit ID from AdMob console
  final String? iosRewardedAdUnitId;

  /// Test device IDs for ad testing (get from logcat/console)
  final List<String> testDeviceIds;

  /// Enable consent debug mode (for testing GDPR in non-EU regions)
  final bool enableConsentDebug;

  /// Tag for under age of consent (COPPA compliance)
  final bool tagForUnderAgeOfConsent;

  /// Maximum duration to cache app open ads (Google recommends 4 hours)
  final Duration appOpenAdMaxCacheDuration;

  /// Minimum interval between interstitial ads
  final Duration minInterstitialInterval;

  /// Maximum number of load failures before entering cooldown.
  ///
  /// Each failed load counts as one attempt. With the default of 3,
  /// the ad loads once initially, then retries twice more (3 total
  /// attempts) before entering the cooldown period defined by
  /// [retryCooldownAfterMaxAttempts]. Set to 0 to disable retries.
  final int maxLoadRetries;

  /// Delay between load retries
  final Duration retryDelay;

  /// iOS only: Skip GDPR consent UI if ATT was denied.
  ///
  /// When `true` and the user selects "Ask App Not to Track" in the ATT prompt,
  /// the GDPR/TCF consent dialog will be skipped entirely on iOS.
  /// This prevents Apple App Store review rejections (Guideline 5.1.1)
  /// for showing personalized ad consent after ATT denial.
  ///
  /// Default is `true` for compliance with Apple guidelines.
  /// Set to `false` only if you need to show the consent form for legal reasons.
  final bool skipGdprConsentIfAttDenied;

  /// Whether rewarded ads should ignore the "Remove Ads" setting.
  ///
  /// When `true` (default), rewarded ads will still be available even when
  /// the user has purchased "Remove Ads". This is the expected behavior for
  /// most apps since users typically still want access to optional rewards.
  ///
  /// Set to `false` if you want rewarded ads to also be disabled when
  /// the user purchases "Remove Ads".
  final bool rewardedAdsIgnoreRemoveAds;

  /// HTTP timeout for ad requests in milliseconds.
  ///
  /// Longer timeouts improve fill rates but may delay the UI.
  /// Default is 30 seconds (30000ms).
  final int httpTimeoutMillis;

  /// Cooldown period after max retries are exhausted.
  ///
  /// After an ad fails to load [maxLoadRetries] times, the manager will
  /// wait this duration before allowing new load attempts. This prevents
  /// rapid-fire failed requests that could trigger AdMob rate limiting.
  ///
  /// Default is 5 minutes.
  final Duration retryCooldownAfterMaxAttempts;

  /// Maximum ad content rating for all ad requests.
  ///
  /// Use [MaxAdContentRating] constants to restrict ad content:
  /// - `MaxAdContentRating.g` — General audiences
  /// - `MaxAdContentRating.pg` — Parental guidance
  /// - `MaxAdContentRating.t` — Teen
  /// - `MaxAdContentRating.ma` — Mature audiences
  ///
  /// Default: `null` (no restriction).
  final String? maxAdContentRating;

  // ============================================================
  // INITIALIZATION TIMEOUTS
  // ============================================================

  /// Timeout for cold-start app open ad loading.
  ///
  /// If the app open ad doesn't load within this time on cold start,
  /// the app proceeds without showing it. The ad continues loading in background
  /// for future use.
  ///
  /// Default: 3 seconds. Set to `null` to wait indefinitely (not recommended).
  final Duration? coldStartAdTimeout;

  /// Sentinel value used by [copyWith] to distinguish between "not provided"
  /// and an explicit `null`. Allows callers to null-out nullable fields:
  /// ```dart
  /// config.copyWith(coldStartAdTimeout: null) // actually sets it to null
  /// ```
  static const _sentinel = Object();

  /// Creates a custom ad configuration.
  ///
  /// At minimum, provide your ad unit IDs for production use.
  const AdFlowConfig({
    this.androidBannerAdUnitId,
    this.iosBannerAdUnitId,
    this.androidInterstitialAdUnitId,
    this.iosInterstitialAdUnitId,
    this.androidAppOpenAdUnitId,
    this.iosAppOpenAdUnitId,
    this.androidNativeAdUnitId,
    this.iosNativeAdUnitId,
    this.androidRewardedAdUnitId,
    this.iosRewardedAdUnitId,
    this.testDeviceIds = const [],
    this.enableConsentDebug = false,
    this.tagForUnderAgeOfConsent = false,
    this.appOpenAdMaxCacheDuration = const Duration(hours: 4),
    this.minInterstitialInterval = const Duration(seconds: 30),
    this.maxLoadRetries = 3,
    this.retryDelay = const Duration(seconds: 5),
    this.skipGdprConsentIfAttDenied = true,
    this.rewardedAdsIgnoreRemoveAds = true,
    this.httpTimeoutMillis = 30000,
    this.retryCooldownAfterMaxAttempts = const Duration(minutes: 5),
    this.maxAdContentRating,
    this.coldStartAdTimeout = const Duration(seconds: 3),
  });

  /// Creates a test configuration using Google's official test ad unit IDs.
  ///
  /// Use this during development to avoid invalid traffic.
  /// ```dart
  /// await AdFlow.instance.initialize(
  ///   config: AdFlowConfig.testMode(),
  /// );
  /// ```
  factory AdFlowConfig.testMode({
    List<String> testDeviceIds = const [],
    bool enableConsentDebug = true,
    Duration? coldStartAdTimeout = const Duration(seconds: 3),
  }) {
    return AdFlowConfig(
      androidBannerAdUnitId: TestAdUnitIds.banner,
      iosBannerAdUnitId: TestAdUnitIds.banner,
      androidInterstitialAdUnitId: TestAdUnitIds.interstitial,
      iosInterstitialAdUnitId: TestAdUnitIds.interstitial,
      androidAppOpenAdUnitId: TestAdUnitIds.appOpen,
      iosAppOpenAdUnitId: TestAdUnitIds.appOpen,
      androidNativeAdUnitId: TestAdUnitIds.native,
      iosNativeAdUnitId: TestAdUnitIds.native,
      androidRewardedAdUnitId: TestAdUnitIds.rewarded,
      iosRewardedAdUnitId: TestAdUnitIds.rewarded,
      testDeviceIds: testDeviceIds,
      enableConsentDebug: enableConsentDebug,
      coldStartAdTimeout: coldStartAdTimeout,
    );
  }

  /// Creates a copy of this config with the given fields replaced.
  ///
  /// Nullable fields (ad unit IDs, [coldStartAdTimeout], [maxAdContentRating])
  /// can be explicitly set to `null` to clear them:
  /// ```dart
  /// final cleared = config.copyWith(coldStartAdTimeout: null); // now null
  /// ```
  ///
  /// Non-nullable fields retain their current value when omitted.
  AdFlowConfig copyWith({
    Object? androidBannerAdUnitId = _sentinel,
    Object? iosBannerAdUnitId = _sentinel,
    Object? androidInterstitialAdUnitId = _sentinel,
    Object? iosInterstitialAdUnitId = _sentinel,
    Object? androidAppOpenAdUnitId = _sentinel,
    Object? iosAppOpenAdUnitId = _sentinel,
    Object? androidNativeAdUnitId = _sentinel,
    Object? iosNativeAdUnitId = _sentinel,
    Object? androidRewardedAdUnitId = _sentinel,
    Object? iosRewardedAdUnitId = _sentinel,
    List<String>? testDeviceIds,
    bool? enableConsentDebug,
    bool? tagForUnderAgeOfConsent,
    Duration? appOpenAdMaxCacheDuration,
    Duration? minInterstitialInterval,
    int? maxLoadRetries,
    Duration? retryDelay,
    bool? skipGdprConsentIfAttDenied,
    bool? rewardedAdsIgnoreRemoveAds,
    int? httpTimeoutMillis,
    Duration? retryCooldownAfterMaxAttempts,
    Object? maxAdContentRating = _sentinel,
    Object? coldStartAdTimeout = _sentinel,
  }) {
    return AdFlowConfig(
      androidBannerAdUnitId: identical(androidBannerAdUnitId, _sentinel)
          ? this.androidBannerAdUnitId
          : androidBannerAdUnitId as String?,
      iosBannerAdUnitId: identical(iosBannerAdUnitId, _sentinel)
          ? this.iosBannerAdUnitId
          : iosBannerAdUnitId as String?,
      androidInterstitialAdUnitId:
          identical(androidInterstitialAdUnitId, _sentinel)
          ? this.androidInterstitialAdUnitId
          : androidInterstitialAdUnitId as String?,
      iosInterstitialAdUnitId: identical(iosInterstitialAdUnitId, _sentinel)
          ? this.iosInterstitialAdUnitId
          : iosInterstitialAdUnitId as String?,
      androidAppOpenAdUnitId: identical(androidAppOpenAdUnitId, _sentinel)
          ? this.androidAppOpenAdUnitId
          : androidAppOpenAdUnitId as String?,
      iosAppOpenAdUnitId: identical(iosAppOpenAdUnitId, _sentinel)
          ? this.iosAppOpenAdUnitId
          : iosAppOpenAdUnitId as String?,
      androidNativeAdUnitId: identical(androidNativeAdUnitId, _sentinel)
          ? this.androidNativeAdUnitId
          : androidNativeAdUnitId as String?,
      iosNativeAdUnitId: identical(iosNativeAdUnitId, _sentinel)
          ? this.iosNativeAdUnitId
          : iosNativeAdUnitId as String?,
      androidRewardedAdUnitId: identical(androidRewardedAdUnitId, _sentinel)
          ? this.androidRewardedAdUnitId
          : androidRewardedAdUnitId as String?,
      iosRewardedAdUnitId: identical(iosRewardedAdUnitId, _sentinel)
          ? this.iosRewardedAdUnitId
          : iosRewardedAdUnitId as String?,
      testDeviceIds: testDeviceIds ?? this.testDeviceIds,
      enableConsentDebug: enableConsentDebug ?? this.enableConsentDebug,
      tagForUnderAgeOfConsent:
          tagForUnderAgeOfConsent ?? this.tagForUnderAgeOfConsent,
      appOpenAdMaxCacheDuration:
          appOpenAdMaxCacheDuration ?? this.appOpenAdMaxCacheDuration,
      minInterstitialInterval:
          minInterstitialInterval ?? this.minInterstitialInterval,
      maxLoadRetries: maxLoadRetries ?? this.maxLoadRetries,
      retryDelay: retryDelay ?? this.retryDelay,
      skipGdprConsentIfAttDenied:
          skipGdprConsentIfAttDenied ?? this.skipGdprConsentIfAttDenied,
      rewardedAdsIgnoreRemoveAds:
          rewardedAdsIgnoreRemoveAds ?? this.rewardedAdsIgnoreRemoveAds,
      httpTimeoutMillis: httpTimeoutMillis ?? this.httpTimeoutMillis,
      retryCooldownAfterMaxAttempts:
          retryCooldownAfterMaxAttempts ?? this.retryCooldownAfterMaxAttempts,
      maxAdContentRating: identical(maxAdContentRating, _sentinel)
          ? this.maxAdContentRating
          : maxAdContentRating as String?,
      coldStartAdTimeout: identical(coldStartAdTimeout, _sentinel)
          ? this.coldStartAdTimeout
          : coldStartAdTimeout as Duration?,
    );
  }

  // ============================================================
  // Platform-specific Ad Unit ID Getters
  // ============================================================

  /// Helper to get platform-specific ad unit ID with fallback to test ID
  String _getPlatformAdUnitId(
    String? androidId,
    String? iosId,
    String fallback,
  ) {
    if (AdFlowPlatform.isAndroid) return androidId ?? fallback;
    if (AdFlowPlatform.isIOS) return iosId ?? fallback;
    // Return fallback for unsupported platforms (web, desktop)
    return fallback;
  }

  /// Get banner ad unit ID for current platform
  String get bannerAdUnitId => _getPlatformAdUnitId(
    androidBannerAdUnitId,
    iosBannerAdUnitId,
    TestAdUnitIds.banner,
  );

  /// Get interstitial ad unit ID for current platform
  String get interstitialAdUnitId => _getPlatformAdUnitId(
    androidInterstitialAdUnitId,
    iosInterstitialAdUnitId,
    TestAdUnitIds.interstitial,
  );

  /// Get app open ad unit ID for current platform
  String get appOpenAdUnitId => _getPlatformAdUnitId(
    androidAppOpenAdUnitId,
    iosAppOpenAdUnitId,
    TestAdUnitIds.appOpen,
  );

  /// Get native ad unit ID for current platform
  String get nativeAdUnitId => _getPlatformAdUnitId(
    androidNativeAdUnitId,
    iosNativeAdUnitId,
    TestAdUnitIds.native,
  );

  /// Get rewarded ad unit ID for current platform
  String get rewardedAdUnitId => _getPlatformAdUnitId(
    androidRewardedAdUnitId,
    iosRewardedAdUnitId,
    TestAdUnitIds.rewarded,
  );

  /// Check if using test ad unit IDs (Google's test publisher ID)
  static const _testPublisherId = '3940256099942544';

  /// Whether any configured ad unit is using Google's test IDs
  bool get isUsingTestAds {
    return bannerAdUnitId.contains(_testPublisherId) ||
        interstitialAdUnitId.contains(_testPublisherId) ||
        appOpenAdUnitId.contains(_testPublisherId) ||
        nativeAdUnitId.contains(_testPublisherId) ||
        rewardedAdUnitId.contains(_testPublisherId);
  }

  // ============================================================
  // AD TYPE AVAILABILITY CHECKS
  // ============================================================

  /// Whether banner ads are configured with real (non-test) IDs
  bool get hasBannerConfigured =>
      (androidBannerAdUnitId != null || iosBannerAdUnitId != null) &&
      !bannerAdUnitId.contains(_testPublisherId);

  /// Whether interstitial ads are configured with real (non-test) IDs
  bool get hasInterstitialConfigured =>
      (androidInterstitialAdUnitId != null ||
          iosInterstitialAdUnitId != null) &&
      !interstitialAdUnitId.contains(_testPublisherId);

  /// Whether app open ads are configured with real (non-test) IDs
  bool get hasAppOpenConfigured =>
      (androidAppOpenAdUnitId != null || iosAppOpenAdUnitId != null) &&
      !appOpenAdUnitId.contains(_testPublisherId);

  /// Whether native ads are configured with real (non-test) IDs
  bool get hasNativeConfigured =>
      (androidNativeAdUnitId != null || iosNativeAdUnitId != null) &&
      !nativeAdUnitId.contains(_testPublisherId);

  /// Whether rewarded ads are configured with real (non-test) IDs
  bool get hasRewardedConfigured =>
      (androidRewardedAdUnitId != null || iosRewardedAdUnitId != null) &&
      !rewardedAdUnitId.contains(_testPublisherId);

  // ============================================================
  // STATIC ACCESSOR (for internal package use)
  // ============================================================

  static AdFlowConfig? _current;

  /// The current configuration set during initialization.
  ///
  /// Falls back to test mode if not set (safe default for development).
  /// This is used internally by ad managers.
  static AdFlowConfig get current {
    if (_current == null) {
      if (kReleaseMode) {
        throw StateError(
          'AdFlowConfig.current accessed before AdFlow.initialize(). '
          'Call AdFlow.instance.initialize() before using any ad managers.',
        );
      }
      adFlowLog(
        '\u26a0\ufe0f AdFlowConfig.current accessed before AdFlow.initialize(). '
        'Falling back to test mode \u2014 ensure this is intentional in production.',
      );
    }
    return _current ?? AdFlowConfig.testMode();
  }

  /// Sets the current configuration (called by AdFlow.initialize).
  static void setCurrent(AdFlowConfig config) {
    _current = config;
  }

  /// Resets the current configuration (for testing).
  static void resetCurrent() {
    _current = null;
  }
}

/// Collapsible banner placement options
enum CollapsibleBannerPlacement {
  /// Banner anchored to top of screen, expands downward
  top,

  /// Banner anchored to bottom of screen, expands upward
  bottom,
}

/// Extension to get placement value for AdRequest extras
extension CollapsibleBannerPlacementExtension on CollapsibleBannerPlacement {
  String get value {
    switch (this) {
      case CollapsibleBannerPlacement.top:
        return 'top';
      case CollapsibleBannerPlacement.bottom:
        return 'bottom';
    }
  }
}
