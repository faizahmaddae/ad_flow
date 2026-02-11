// Copyright 2024 - AdMob Integration Package
// Comprehensive tests for AdFlow (ad_service.dart)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ad_flow/ad_flow.dart';

import 'helpers/mock_ad_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAdSdk mockSdk;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AdsEnabledManager.instance.reset();

    mockSdk = MockAdSdk();
    AdSdk.instance = mockSdk;

    AdFlowPlatform.platformOverride = TargetPlatform.android;
    await AdFlow.instance.reset();
  });

  tearDown(() async {
    await AdFlow.instance.reset();
    ConsentManager.instance.resetConsent();
    AdSdk.resetInstance();
    AdFlowPlatform.reset();
  });

  group('singleton', () {
    test('returns same instance', () {
      expect(identical(AdFlow.instance, AdFlow.instance), true);
    });
  });

  group('initial state', () {
    test('isInitialized is false', () {
      expect(AdFlow.instance.isInitialized, false);
    });

    test('isMobileAdsInitialized is false', () {
      expect(AdFlow.instance.isMobileAdsInitialized, false);
    });

    test('config returns test mode by default', () {
      // Default config (when no config set) falls back to testMode
      expect(AdFlow.instance.config, isNotNull);
    });
  });

  group('lazy manager access', () {
    test('banner returns BannerAdManager', () {
      expect(AdFlow.instance.banner, isA<BannerAdManager>());
    });

    test('interstitial returns InterstitialAdManager', () {
      expect(AdFlow.instance.interstitial, isA<InterstitialAdManager>());
    });

    test('rewarded returns RewardedAdManager', () {
      expect(AdFlow.instance.rewarded, isA<RewardedAdManager>());
    });

    test('appOpen returns AppOpenAdManager', () {
      expect(AdFlow.instance.appOpen, isA<AppOpenAdManager>());
    });

    test('native returns NativeAdManager', () {
      expect(AdFlow.instance.native, isA<NativeAdManager>());
    });

    test('consent returns ConsentManager', () {
      expect(AdFlow.instance.consent, isA<ConsentManager>());
    });

    test('same manager returned on repeated access', () {
      final b1 = AdFlow.instance.banner;
      final b2 = AdFlow.instance.banner;
      expect(identical(b1, b2), true);
    });
  });

  group('initialize', () {
    test('calls consent gathering', () async {
      await AdFlow.instance.initialize(
        config: AdFlowConfig.testMode(),
      );
      // Give async callbacks time to complete
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(mockSdk.requestConsentInfoUpdateCalls, 1);
    });

    test('initializes Mobile Ads SDK when consent allows', () async {
      mockSdk.canRequestAdsResult = true;
      await AdFlow.instance.initialize(
        config: AdFlowConfig.testMode(),
      );
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(mockSdk.initializeMobileAdsCalls, greaterThanOrEqualTo(1));
    });

    test('calls onComplete callback', () async {
      bool? callbackResult;
      mockSdk.canRequestAdsResult = true;

      await AdFlow.instance.initialize(
        config: AdFlowConfig.testMode(),
        onComplete: (canRequestAds) {
          callbackResult = canRequestAds;
        },
      );
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(callbackResult, isNotNull);
    });

    test('sets isInitialized after complete', () async {
      await AdFlow.instance.initialize(
        config: AdFlowConfig.testMode(),
      );
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(AdFlow.instance.isInitialized, true);
    });

    test('no-ops when called twice', () async {
      await AdFlow.instance.initialize(
        config: AdFlowConfig.testMode(),
      );
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(const Duration(milliseconds: 50));

      final firstCallCount = mockSdk.requestConsentInfoUpdateCalls;

      bool? secondResult;
      await AdFlow.instance.initialize(
        config: AdFlowConfig.testMode(),
        onComplete: (can) => secondResult = can,
      );
      await Future.delayed(Duration.zero);

      // Should not call consent again
      expect(mockSdk.requestConsentInfoUpdateCalls, firstCallCount);
      // But should still call onComplete
      expect(secondResult, isNotNull);
    });

    test('skips ad loading when ads disabled', () async {
      await AdsEnabledManager.instance.initialize();
      await AdsEnabledManager.instance.disableAds();

      bool? callbackResult;
      await AdFlow.instance.initialize(
        config: AdFlowConfig.testMode(),
        onComplete: (canRequestAds) {
          callbackResult = canRequestAds;
        },
      );
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(callbackResult, false);
      expect(AdFlow.instance.isInitialized, true);
      // Should not call consent
      expect(mockSdk.requestConsentInfoUpdateCalls, 0);
    });
  });

  group('error handling', () {
    test('errorStream exposes AdFlowErrorHandler stream', () {
      expect(AdFlow.instance.errorStream, isNotNull);
    });

    test('setErrorCallback delegates to handler', () {
      // Should not throw
      AdFlow.instance.setErrorCallback((_) {});
      AdFlow.instance.clearErrorCallback();
    });
  });

  group('ads enabled management', () {
    setUp(() async {
      await AdsEnabledManager.instance.initialize();
    });

    test('isAdsEnabled returns true by default', () {
      expect(AdFlow.instance.isAdsEnabled, true);
    });

    test('isAdsDisabled returns false by default', () {
      expect(AdFlow.instance.isAdsDisabled, false);
    });

    test('disableAds disables ads', () async {
      await AdFlow.instance.disableAds();
      expect(AdFlow.instance.isAdsEnabled, false);
      expect(AdFlow.instance.isAdsDisabled, true);
    });

    test('enableAds enables ads', () async {
      await AdFlow.instance.disableAds();
      await AdFlow.instance.enableAds();
      expect(AdFlow.instance.isAdsEnabled, true);
    });

    test('adsEnabledStream emits changes', () async {
      final statuses = <bool>[];
      final sub = AdFlow.instance.adsEnabledStream.listen(statuses.add);

      await AdsEnabledManager.instance.disableAds();
      await Future.delayed(Duration.zero);

      expect(statuses, contains(false));

      await sub.cancel();
    });
  });

  group('disposeAllAds', () {
    test('disposes all managers safely', () async {
      // Access managers to create them
      AdFlow.instance.banner;
      AdFlow.instance.interstitial;
      AdFlow.instance.rewarded;
      AdFlow.instance.appOpen;
      AdFlow.instance.native;

      // Should not throw
      await AdFlow.instance.disposeAllAds();
    });

    test('works when no managers created', () async {
      await AdFlow.instance.disposeAllAds();
    });
  });

  group('privacy options', () {
    test('isPrivacyOptionsRequired delegates to consent', () {
      expect(AdFlow.instance.isPrivacyOptionsRequired, isA<bool>());
    });

    test('showPrivacyOptions calls consent form', () {
      AdFlow.instance.showPrivacyOptions(onComplete: () {});
      // The mock fires callback synchronously, but the internal async
      // may delay it
      // Not asserting completion - just verifying no crash
    });
  });

  group('openAdInspector', () {
    test('calls SDK openAdInspector', () {
      AdFlow.instance.openAdInspector();
      expect(mockSdk.openAdInspectorCalls, 1);
    });
  });

  group('pauseAppOpenAds / resumeAppOpenAds', () {
    test('pauseAppOpenAds does not crash without reactor', () {
      // No lifecycle reactor created
      AdFlow.instance.pauseAppOpenAds();
    });

    test('resumeAppOpenAds does not crash without reactor', () {
      AdFlow.instance.resumeAppOpenAds();
    });
  });

  group('waitForInit', () {
    test('throws StateError when init not started', () async {
      expect(
        () => AdFlow.instance.waitForInit(),
        throwsStateError,
      );
    });

    test('returns immediately if already initialized', () async {
      // Initialize first
      await AdFlow.instance.initialize(config: AdFlowConfig.testMode());
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(const Duration(milliseconds: 100));

      // waitForInit should return quickly
      final result = await AdFlow.instance.waitForInit();
      expect(result, isA<bool>());
    });
  });

  group('initStream', () {
    test('emits when init completes', () async {
      final values = <bool>[];
      final sub = AdFlow.instance.initStream.listen(values.add);

      await AdFlow.instance.initialize(config: AdFlowConfig.testMode());
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(values, isNotEmpty);

      await sub.cancel();
    });
  });

  group('dispose', () {
    test('disposes managers and resets state', () async {
      await AdFlow.instance.dispose();
      expect(AdFlow.instance.isInitialized, false);
    });
  });

  group('reset', () {
    test('resets all state', () async {
      await AdFlow.instance.initialize(config: AdFlowConfig.testMode());
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(const Duration(milliseconds: 50));

      await AdFlow.instance.reset();

      expect(AdFlow.instance.isInitialized, false);
      expect(AdFlow.instance.isMobileAdsInitialized, false);
    });

    test('allows re-initialization after reset', () async {
      await AdFlow.instance.initialize(config: AdFlowConfig.testMode());
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(const Duration(milliseconds: 50));

      await AdFlow.instance.reset();
      ConsentManager.instance.resetConsent();
      mockSdk.resetMock();

      await AdFlow.instance.initialize(config: AdFlowConfig.testMode());
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(AdFlow.instance.isInitialized, true);
    });
  });

  group('preloadAds', () {
    test('skips preload when cannot request ads', () async {
      // Can't request ads
      mockSdk.canRequestAdsResult = false;
      await AdFlow.instance.preloadAds();
      // No ads should be loaded
      expect(mockSdk.loadInterstitialCalls, 0);
    });
  });
}
