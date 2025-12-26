// Copyright 2024 - AdMob Integration Package
// Production-ready AdMob configuration for Flutter

import 'dart:io';

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
    if (Platform.isAndroid) return androidId;
    if (Platform.isIOS) return iosId;
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
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

  /// Number of retries for failed ad loads
  final int maxLoadRetries;

  /// Delay between load retries
  final Duration retryDelay;

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
    if (Platform.isAndroid) return androidId ?? fallback;
    if (Platform.isIOS) return iosId ?? fallback;
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
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
        appOpenAdUnitId.contains(_testPublisherId);
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
  static AdFlowConfig get current => _current ?? AdFlowConfig.testMode();

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
