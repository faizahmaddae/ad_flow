// Copyright 2024 - AdMob Integration Package
// Unit tests for AdFlow singleton

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdFlow', () {
    setUp(() async {
      // Reset SharedPreferences mock before each test
      SharedPreferences.setMockInitialValues({});
      // Reset the singleton states
      await AdsEnabledManager.instance.reset();
      await AdFlow.instance.reset();
    });

    group('singleton pattern', () {
      test('instance returns the same object', () {
        final instance1 = AdFlow.instance;
        final instance2 = AdFlow.instance;

        expect(identical(instance1, instance2), true);
      });
    });

    group('initial state after reset', () {
      test('isInitialized is false', () {
        expect(AdFlow.instance.isInitialized, false);
      });

      test('isMobileAdsInitialized is false', () {
        expect(AdFlow.instance.isMobileAdsInitialized, false);
      });

      // Note: config getter calls AdFlowConfig.testMode() which uses
      // Platform.isAndroid/isIOS - cannot be tested in unit tests
    });

    group('lazy initialization of managers', () {
      test('banner manager is created on first access', () {
        final banner = AdFlow.instance.banner;
        expect(banner, isNotNull);
        expect(banner, isA<BannerAdManager>());
      });

      test('interstitial manager is created on first access', () {
        final interstitial = AdFlow.instance.interstitial;
        expect(interstitial, isNotNull);
        expect(interstitial, isA<InterstitialAdManager>());
      });

      test('appOpen manager is created on first access', () {
        final appOpen = AdFlow.instance.appOpen;
        expect(appOpen, isNotNull);
        expect(appOpen, isA<AppOpenAdManager>());
      });

      test('native manager is created on first access', () {
        final native = AdFlow.instance.native;
        expect(native, isNotNull);
        expect(native, isA<NativeAdManager>());
      });

      test('rewarded manager is created on first access', () {
        final rewarded = AdFlow.instance.rewarded;
        expect(rewarded, isNotNull);
        expect(rewarded, isA<RewardedAdManager>());
      });

      test('same manager instance returned on subsequent access', () {
        final banner1 = AdFlow.instance.banner;
        final banner2 = AdFlow.instance.banner;
        expect(identical(banner1, banner2), true);
      });
    });

    group('consent manager access', () {
      test('consent returns ConsentManager singleton', () {
        final consent = AdFlow.instance.consent;
        expect(consent, ConsentManager.instance);
      });
    });

    group('ads enabled state', () {
      test('isAdsEnabled defaults to true', () async {
        await AdsEnabledManager.instance.initialize();
        expect(AdFlow.instance.isAdsEnabled, true);
      });

      test('isAdsDisabled is inverse of isAdsEnabled', () async {
        await AdsEnabledManager.instance.initialize();
        expect(AdFlow.instance.isAdsDisabled, false);
      });

      test('disableAds sets isAdsEnabled to false', () async {
        await AdsEnabledManager.instance.initialize();
        await AdFlow.instance.disableAds();
        expect(AdFlow.instance.isAdsEnabled, false);
        expect(AdFlow.instance.isAdsDisabled, true);
      });

      test('enableAds restores isAdsEnabled to true', () async {
        await AdsEnabledManager.instance.initialize();
        await AdFlow.instance.disableAds();
        await AdFlow.instance.enableAds();
        expect(AdFlow.instance.isAdsEnabled, true);
      });

      test('adsEnabledStream emits changes', () async {
        await AdsEnabledManager.instance.initialize();

        final stream = AdFlow.instance.adsEnabledStream;
        final emissions = <bool>[];
        final subscription = stream.listen(emissions.add);

        await AdFlow.instance.disableAds();
        await AdFlow.instance.enableAds();

        // Allow stream to emit
        await Future.delayed(const Duration(milliseconds: 50));

        subscription.cancel();
        expect(emissions.contains(false), true);
        expect(emissions.contains(true), true);
      });
    });

    group('reset', () {
      test('reset clears isInitialized', () async {
        // Access managers to create them
        AdFlow.instance.banner;
        AdFlow.instance.interstitial;

        await AdFlow.instance.reset();
        expect(AdFlow.instance.isInitialized, false);
      });

      test('reset clears isMobileAdsInitialized', () async {
        await AdFlow.instance.reset();
        expect(AdFlow.instance.isMobileAdsInitialized, false);
      });

      // Note: config getter calls AdFlowConfig.testMode() which uses
      // Platform.isAndroid/isIOS - cannot be tested in unit tests

      test('reset allows managers to be recreated', () async {
        final banner1 = AdFlow.instance.banner;
        await AdFlow.instance.reset();
        final banner2 = AdFlow.instance.banner;

        // After reset, a new instance should be created
        expect(identical(banner1, banner2), false);
      });

      test('reset can be called multiple times safely', () async {
        await AdFlow.instance.reset();
        await AdFlow.instance.reset();
        await AdFlow.instance.reset();
        // No exception should be thrown
        expect(AdFlow.instance.isInitialized, false);
      });
    });

    group('dispose', () {
      test('dispose sets isInitialized to false', () async {
        // Access a manager first
        AdFlow.instance.banner;
        await AdFlow.instance.dispose();
        expect(AdFlow.instance.isInitialized, false);
      });

      test('dispose can be called safely', () async {
        await AdFlow.instance.dispose();
        // No exception should be thrown
      });

      test('dispose can be called multiple times', () async {
        await AdFlow.instance.dispose();
        await AdFlow.instance.dispose();
        // No exception should be thrown
      });
    });

    group('disposeAllAds', () {
      test(
        'disposeAllAds can be called without managers initialized',
        () async {
          await AdFlow.instance.disposeAllAds();
          // No exception should be thrown
        },
      );

      test('disposeAllAds can be called with managers initialized', () async {
        // Create all managers
        AdFlow.instance.banner;
        AdFlow.instance.interstitial;
        AdFlow.instance.appOpen;
        AdFlow.instance.native;
        AdFlow.instance.rewarded;

        await AdFlow.instance.disposeAllAds();
        // No exception should be thrown
      });
    });

    group('lifecycleReactor', () {
      test('lifecycleReactor is null before initialization', () {
        expect(AdFlow.instance.lifecycleReactor, isNull);
      });
    });

    group('app open ad controls', () {
      test('pauseAppOpenAds can be called safely before init', () {
        AdFlow.instance.pauseAppOpenAds();
        // No exception should be thrown
      });

      test('resumeAppOpenAds can be called safely before init', () {
        AdFlow.instance.resumeAppOpenAds();
        // No exception should be thrown
      });
    });
  });
}
