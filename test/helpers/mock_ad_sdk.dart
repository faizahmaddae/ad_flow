// Copyright 2024 - AdMob Integration Package
// Mock AdSdk for unit testing
//
// Extends AdSdk and overrides all methods to provide controllable
// test behavior. Instead of calling real platform channels,
// callbacks are triggered directly with fake ad objects.

import 'dart:async';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:ad_flow/src/ad_sdk.dart';

import 'fake_ads.dart';

/// Configurable mock SDK for unit tests.
///
/// Usage:
/// ```dart
/// final mockSdk = MockAdSdk();
/// AdSdk.instance = mockSdk;
///
/// // Configure behavior
/// mockSdk.interstitialAdToReturn = FakeInterstitialAd();
/// mockSdk.canRequestAdsResult = true;
///
/// // Run code under test
/// await manager.loadAd();
/// ```
class MockAdSdk extends AdSdk {
  // ── Consent Configuration ──
  bool canRequestAdsResult = true;
  ConsentStatus consentStatusResult = ConsentStatus.obtained;
  bool isConsentFormAvailableResult = true;
  PrivacyOptionsRequirementStatus privacyOptionsRequirementStatusResult =
      PrivacyOptionsRequirementStatus.notRequired;
  TrackingStatus trackingAuthorizationStatusResult =
      TrackingStatus.notDetermined;
  TrackingStatus requestTrackingResult = TrackingStatus.authorized;

  /// If non-null, requestConsentInfoUpdate will call onFailure with this error.
  FormError? consentUpdateError;

  /// If non-null, loadAndShowConsentFormIfRequired will call onComplete with this error.
  FormError? consentFormError;

  /// If non-null, showPrivacyOptionsForm will call onComplete with this error.
  FormError? privacyOptionsFormError;

  // ── Ad Loading Configuration ──
  FakeInterstitialAd? interstitialAdToReturn;
  LoadAdError? interstitialLoadError;

  FakeRewardedAd? rewardedAdToReturn;
  LoadAdError? rewardedLoadError;

  FakeAppOpenAd? appOpenAdToReturn;
  LoadAdError? appOpenLoadError;

  FakeBannerAd? bannerAdToReturn;
  LoadAdError? bannerLoadError;

  FakeNativeAd? nativeAdToReturn;
  LoadAdError? nativeLoadError;

  AdSize? adaptiveBannerSizeResult;
  bool returnNullAdaptiveSize = false;

  // ── Mobile Ads SDK ──
  bool initializeMobileAdsResult = true;
  bool initializeMobileAdsThrows = false;
  int initializeMobileAdsCalls = 0;
  Duration? mobileAdsInitDelay;
  Exception? mobileAdsInitError;
  int updateRequestConfigCalls = 0;
  int openAdInspectorCalls = 0;
  dynamic openAdInspectorError;
  RequestConfiguration? lastRequestConfig;

  // ── Call Tracking ──
  int loadInterstitialCalls = 0;
  int loadRewardedCalls = 0;
  int loadAppOpenCalls = 0;
  int loadBannerCalls = 0;
  int loadNativeCalls = 0;
  int requestConsentInfoUpdateCalls = 0;
  int loadAndShowConsentFormCalls = 0;
  int showPrivacyOptionsFormCalls = 0;
  int canRequestAdsCalls = 0;
  int getConsentStatusCalls = 0;
  int isConsentFormAvailableCalls = 0;
  int getPrivacyOptionsRequirementStatusCalls = 0;
  int resetConsentInfoCalls = 0;
  int getTrackingAuthorizationStatusCalls = 0;
  int requestTrackingAuthorizationCalls = 0;

  // Last captured parameters
  String? lastAdUnitId;
  AdRequest? lastAdRequest;
  String? lastFactoryId;

  // ══════════════════════════════════════════════════════════════════════════
  // INTERSTITIAL ADS
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Future<void> loadInterstitialAd({
    required String adUnitId,
    required AdRequest request,
    required void Function(InterstitialAd ad) onLoaded,
    required void Function(LoadAdError error) onFailed,
  }) async {
    loadInterstitialCalls++;
    lastAdUnitId = adUnitId;
    lastAdRequest = request;

    if (interstitialLoadError != null) {
      onFailed(interstitialLoadError!);
    } else {
      final ad = interstitialAdToReturn ?? FakeInterstitialAd();
      onLoaded(ad);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // REWARDED ADS
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Future<void> loadRewardedAd({
    required String adUnitId,
    required AdRequest request,
    required void Function(RewardedAd ad) onLoaded,
    required void Function(LoadAdError error) onFailed,
  }) async {
    loadRewardedCalls++;
    lastAdUnitId = adUnitId;
    lastAdRequest = request;

    if (rewardedLoadError != null) {
      onFailed(rewardedLoadError!);
    } else {
      final ad = rewardedAdToReturn ?? FakeRewardedAd();
      onLoaded(ad);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // APP OPEN ADS
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Future<void> loadAppOpenAd({
    required String adUnitId,
    required AdRequest request,
    required void Function(AppOpenAd ad) onLoaded,
    required void Function(LoadAdError error) onFailed,
  }) async {
    loadAppOpenCalls++;
    lastAdUnitId = adUnitId;
    lastAdRequest = request;

    if (appOpenLoadError != null) {
      onFailed(appOpenLoadError!);
    } else {
      final ad = appOpenAdToReturn ?? FakeAppOpenAd();
      onLoaded(ad);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BANNER ADS
  // ══════════════════════════════════════════════════════════════════════════

  @override
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
    loadBannerCalls++;
    lastAdUnitId = adUnitId;
    lastAdRequest = request;

    final ad = bannerAdToReturn ?? FakeBannerAd();
    if (bannerLoadError != null) {
      onAdFailedToLoad(ad, bannerLoadError!);
    } else {
      onAdLoaded(ad);
    }
  }

  @override
  Future<AdSize?> getAdaptiveBannerSize(int width) async {
    if (returnNullAdaptiveSize) return null;
    return adaptiveBannerSizeResult ?? AdSize.banner;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NATIVE ADS
  // ══════════════════════════════════════════════════════════════════════════

  @override
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
    loadNativeCalls++;
    lastAdUnitId = adUnitId;
    lastAdRequest = request;
    lastFactoryId = factoryId;

    final ad = nativeAdToReturn ?? FakeNativeAd();
    if (nativeLoadError != null) {
      onAdFailedToLoad(ad, nativeLoadError!);
    } else {
      onAdLoaded(ad);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CONSENT
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void requestConsentInfoUpdate(
    ConsentRequestParameters params,
    VoidCallback onSuccess,
    void Function(FormError error) onFailure,
  ) {
    requestConsentInfoUpdateCalls++;

    if (consentUpdateError != null) {
      onFailure(consentUpdateError!);
    } else {
      onSuccess();
    }
  }

  @override
  void loadAndShowConsentFormIfRequired(
    void Function(FormError? error) onComplete,
  ) {
    loadAndShowConsentFormCalls++;
    onComplete(consentFormError);
  }

  @override
  void showPrivacyOptionsForm(
    void Function(FormError? error) onComplete,
  ) {
    showPrivacyOptionsFormCalls++;
    onComplete(privacyOptionsFormError);
  }

  @override
  Future<bool> canRequestAds() async {
    canRequestAdsCalls++;
    return canRequestAdsResult;
  }

  @override
  Future<ConsentStatus> getConsentStatus() async {
    getConsentStatusCalls++;
    return consentStatusResult;
  }

  @override
  Future<bool> isConsentFormAvailable() async {
    isConsentFormAvailableCalls++;
    return isConsentFormAvailableResult;
  }

  @override
  Future<PrivacyOptionsRequirementStatus>
      getPrivacyOptionsRequirementStatus() async {
    getPrivacyOptionsRequirementStatusCalls++;
    return privacyOptionsRequirementStatusResult;
  }

  @override
  void resetConsentInfo() {
    resetConsentInfoCalls++;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MOBILE ADS SDK
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Future<InitializationStatus> initializeMobileAds() async {
    initializeMobileAdsCalls++;
    if (mobileAdsInitDelay != null) {
      await Future.delayed(mobileAdsInitDelay!);
    }
    if (mobileAdsInitError != null) {
      throw mobileAdsInitError!;
    }
    if (initializeMobileAdsThrows) {
      throw Exception('Mock SDK init failure');
    }
    return FakeInitializationStatus();
  }

  @override
  Future<void> updateRequestConfiguration(RequestConfiguration config) async {
    updateRequestConfigCalls++;
    lastRequestConfig = config;
  }

  @override
  void openAdInspector(void Function(dynamic error) onComplete) {
    openAdInspectorCalls++;
    onComplete(openAdInspectorError);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // APP TRACKING TRANSPARENCY
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Future<TrackingStatus> getTrackingAuthorizationStatus() async {
    getTrackingAuthorizationStatusCalls++;
    return trackingAuthorizationStatusResult;
  }

  @override
  Future<TrackingStatus> requestTrackingAuthorization() async {
    requestTrackingAuthorizationCalls++;
    return requestTrackingResult;
  }

  /// Reset all mock state.
  void resetMock() {
    canRequestAdsResult = true;
    consentStatusResult = ConsentStatus.obtained;
    isConsentFormAvailableResult = true;
    privacyOptionsRequirementStatusResult =
        PrivacyOptionsRequirementStatus.notRequired;
    trackingAuthorizationStatusResult = TrackingStatus.notDetermined;
    requestTrackingResult = TrackingStatus.authorized;
    consentUpdateError = null;
    consentFormError = null;
    privacyOptionsFormError = null;

    interstitialAdToReturn = null;
    interstitialLoadError = null;
    rewardedAdToReturn = null;
    rewardedLoadError = null;
    appOpenAdToReturn = null;
    appOpenLoadError = null;
    bannerAdToReturn = null;
    bannerLoadError = null;
    nativeAdToReturn = null;
    nativeLoadError = null;
    adaptiveBannerSizeResult = null;
    returnNullAdaptiveSize = false;

    initializeMobileAdsResult = true;
    initializeMobileAdsThrows = false;
    initializeMobileAdsCalls = 0;
    mobileAdsInitDelay = null;
    mobileAdsInitError = null;
    updateRequestConfigCalls = 0;
    openAdInspectorCalls = 0;
    openAdInspectorError = null;
    lastRequestConfig = null;

    loadInterstitialCalls = 0;
    loadRewardedCalls = 0;
    loadAppOpenCalls = 0;
    loadBannerCalls = 0;
    loadNativeCalls = 0;
    requestConsentInfoUpdateCalls = 0;
    loadAndShowConsentFormCalls = 0;
    showPrivacyOptionsFormCalls = 0;
    canRequestAdsCalls = 0;
    getConsentStatusCalls = 0;
    isConsentFormAvailableCalls = 0;
    getPrivacyOptionsRequirementStatusCalls = 0;
    resetConsentInfoCalls = 0;
    getTrackingAuthorizationStatusCalls = 0;
    requestTrackingAuthorizationCalls = 0;

    lastAdUnitId = null;
    lastAdRequest = null;
    lastFactoryId = null;
  }
}
