// Copyright 2024 - AdMob Integration Package
// Thin abstraction layer over Google Mobile Ads SDK for testability

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';

/// Abstraction layer over Google Mobile Ads SDK and related platform APIs.
///
/// Production code uses [AdSdk.instance] which delegates to real SDK calls.
/// Tests override [AdSdk.instance] with a subclass to control SDK behavior
/// without platform channel dependencies.
///
/// Example usage in tests:
/// ```dart
/// setUp(() {
///   AdSdk.instance = MockAdSdk();
/// });
/// tearDown(() {
///   AdSdk.resetInstance();
/// });
/// ```
class AdSdk {
  /// Singleton instance, overridable for testing.
  static AdSdk _instance = AdSdk();
  static AdSdk get instance => _instance;

  /// Set a custom instance for testing.
  @visibleForTesting
  static set instance(AdSdk sdk) => _instance = sdk;

  /// Reset to default instance.
  @visibleForTesting
  static void resetInstance() => _instance = AdSdk();

  // ══════════════════════════════════════════════════════════════════════════
  // INTERSTITIAL ADS
  // ══════════════════════════════════════════════════════════════════════════

  /// Loads an interstitial ad via the SDK.
  Future<void> loadInterstitialAd({
    required String adUnitId,
    required AdRequest request,
    required void Function(InterstitialAd ad) onLoaded,
    required void Function(LoadAdError error) onFailed,
  }) {
    return InterstitialAd.load(
      adUnitId: adUnitId,
      request: request,
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: onFailed,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // REWARDED ADS
  // ══════════════════════════════════════════════════════════════════════════

  /// Loads a rewarded ad via the SDK.
  Future<void> loadRewardedAd({
    required String adUnitId,
    required AdRequest request,
    required void Function(RewardedAd ad) onLoaded,
    required void Function(LoadAdError error) onFailed,
  }) {
    return RewardedAd.load(
      adUnitId: adUnitId,
      request: request,
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: onFailed,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // APP OPEN ADS
  // ══════════════════════════════════════════════════════════════════════════

  /// Loads an app open ad via the SDK.
  Future<void> loadAppOpenAd({
    required String adUnitId,
    required AdRequest request,
    required void Function(AppOpenAd ad) onLoaded,
    required void Function(LoadAdError error) onFailed,
  }) {
    return AppOpenAd.load(
      adUnitId: adUnitId,
      request: request,
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: onLoaded,
        onAdFailedToLoad: onFailed,
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BANNER ADS
  // ══════════════════════════════════════════════════════════════════════════

  /// Creates and loads a banner ad.
  ///
  /// The [onAdLoaded] callback receives the ad to store.
  /// The [onAdFailedToLoad] callback receives the ad and error for cleanup.
  Future<void> loadBannerAd({
    required String adUnitId,
    required AdSize size,
    required AdRequest request,
    required void Function(BannerAd ad) onAdLoaded,
    required void Function(BannerAd ad, LoadAdError error) onAdFailedToLoad,
    void Function(BannerAd ad)? onAdOpened,
    void Function(BannerAd ad)? onAdClosed,
    void Function(BannerAd ad)? onAdClicked,
    void Function(BannerAd ad)? onAdImpression,
  }) async {
    final ad = BannerAd(
      adUnitId: adUnitId,
      size: size,
      request: request,
      listener: BannerAdListener(
        onAdLoaded: (Ad a) => onAdLoaded(a as BannerAd),
        onAdFailedToLoad: (Ad a, LoadAdError e) =>
            onAdFailedToLoad(a as BannerAd, e),
        onAdOpened: onAdOpened != null
            ? (Ad a) => onAdOpened(a as BannerAd)
            : null,
        onAdClosed: onAdClosed != null
            ? (Ad a) => onAdClosed(a as BannerAd)
            : null,
        onAdClicked: onAdClicked != null
            ? (Ad a) => onAdClicked(a as BannerAd)
            : null,
        onAdImpression: onAdImpression != null
            ? (Ad a) => onAdImpression(a as BannerAd)
            : null,
      ),
    );
    await ad.load();
  }

  /// Gets the adaptive banner ad size for the current orientation.
  Future<AdSize?> getAdaptiveBannerSize(int width) {
    return AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NATIVE ADS
  // ══════════════════════════════════════════════════════════════════════════

  /// Creates and loads a native ad.
  Future<void> loadNativeAd({
    required String adUnitId,
    required String factoryId,
    required AdRequest request,
    required void Function(NativeAd ad) onAdLoaded,
    required void Function(NativeAd ad, LoadAdError error) onAdFailedToLoad,
    void Function(NativeAd ad)? onAdOpened,
    void Function(NativeAd ad)? onAdClosed,
    void Function(NativeAd ad)? onAdClicked,
    void Function(NativeAd ad)? onAdImpression,
  }) async {
    final ad = NativeAd(
      adUnitId: adUnitId,
      factoryId: factoryId,
      request: request,
      listener: NativeAdListener(
        onAdLoaded: (Ad a) => onAdLoaded(a as NativeAd),
        onAdFailedToLoad: (Ad a, LoadAdError e) =>
            onAdFailedToLoad(a as NativeAd, e),
        onAdOpened: onAdOpened != null
            ? (Ad a) => onAdOpened(a as NativeAd)
            : null,
        onAdClosed: onAdClosed != null
            ? (Ad a) => onAdClosed(a as NativeAd)
            : null,
        onAdClicked: onAdClicked != null
            ? (Ad a) => onAdClicked(a as NativeAd)
            : null,
        onAdImpression: onAdImpression != null
            ? (Ad a) => onAdImpression(a as NativeAd)
            : null,
      ),
    );
    await ad.load();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CONSENT MANAGEMENT
  // ══════════════════════════════════════════════════════════════════════════

  /// Requests consent info update from UMP SDK.
  void requestConsentInfoUpdate(
    ConsentRequestParameters params,
    VoidCallback onSuccess,
    void Function(FormError error) onFailure,
  ) {
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      onSuccess,
      onFailure,
    );
  }

  /// Loads and shows consent form if required.
  void loadAndShowConsentFormIfRequired(
    void Function(FormError? error) onComplete,
  ) {
    ConsentForm.loadAndShowConsentFormIfRequired(onComplete);
  }

  /// Shows the privacy options form.
  void showPrivacyOptionsForm(void Function(FormError? error) onComplete) {
    ConsentForm.showPrivacyOptionsForm(onComplete);
  }

  /// Whether ads can be requested based on consent.
  Future<bool> canRequestAds() {
    return ConsentInformation.instance.canRequestAds();
  }

  /// Gets the current consent status.
  Future<ConsentStatus> getConsentStatus() {
    return ConsentInformation.instance.getConsentStatus();
  }

  /// Whether the consent form is available.
  Future<bool> isConsentFormAvailable() {
    return ConsentInformation.instance.isConsentFormAvailable();
  }

  /// Gets the privacy options requirement status.
  Future<PrivacyOptionsRequirementStatus> getPrivacyOptionsRequirementStatus() {
    return ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
  }

  /// Resets consent information (testing only).
  void resetConsentInfo() {
    ConsentInformation.instance.reset();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MOBILE ADS SDK
  // ══════════════════════════════════════════════════════════════════════════

  /// Initializes the Mobile Ads SDK.
  Future<InitializationStatus> initializeMobileAds() {
    return MobileAds.instance.initialize();
  }

  /// Updates the request configuration.
  Future<void> updateRequestConfiguration(RequestConfiguration config) {
    return MobileAds.instance.updateRequestConfiguration(config);
  }

  /// Opens the Ad Inspector (debug tool).
  void openAdInspector(void Function(dynamic error) onComplete) {
    MobileAds.instance.openAdInspector(onComplete);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // APP TRACKING TRANSPARENCY (iOS)
  // ══════════════════════════════════════════════════════════════════════════

  /// Gets the current ATT tracking authorization status.
  Future<TrackingStatus> getTrackingAuthorizationStatus() {
    return AppTrackingTransparency.trackingAuthorizationStatus;
  }

  /// Requests ATT tracking authorization.
  Future<TrackingStatus> requestTrackingAuthorization() {
    return AppTrackingTransparency.requestTrackingAuthorization();
  }
}
