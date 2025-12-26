// Copyright 2024 - AdMob Integration Package
// Unit tests for AdFlowConfig

import 'package:flutter_test/flutter_test.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  group('AdFlowConfig', () {
    group('constructor', () {
      test('creates config with default values', () {
        const config = AdFlowConfig();

        expect(config.androidBannerAdUnitId, isNull);
        expect(config.iosBannerAdUnitId, isNull);
        expect(config.testDeviceIds, isEmpty);
        expect(config.enableConsentDebug, false);
        expect(config.tagForUnderAgeOfConsent, false);
        expect(config.appOpenAdMaxCacheDuration, const Duration(hours: 4));
        expect(config.minInterstitialInterval, const Duration(seconds: 30));
        expect(config.maxLoadRetries, 3);
        expect(config.retryDelay, const Duration(seconds: 5));
      });

      test('creates config with custom values', () {
        const config = AdFlowConfig(
          androidBannerAdUnitId: 'android-banner-id',
          iosBannerAdUnitId: 'ios-banner-id',
          androidInterstitialAdUnitId: 'android-interstitial-id',
          iosInterstitialAdUnitId: 'ios-interstitial-id',
          testDeviceIds: ['device1', 'device2'],
          enableConsentDebug: true,
          tagForUnderAgeOfConsent: true,
          appOpenAdMaxCacheDuration: Duration(hours: 2),
          minInterstitialInterval: Duration(seconds: 60),
          maxLoadRetries: 5,
          retryDelay: Duration(seconds: 10),
        );

        expect(config.androidBannerAdUnitId, 'android-banner-id');
        expect(config.iosBannerAdUnitId, 'ios-banner-id');
        expect(config.androidInterstitialAdUnitId, 'android-interstitial-id');
        expect(config.iosInterstitialAdUnitId, 'ios-interstitial-id');
        expect(config.testDeviceIds, ['device1', 'device2']);
        expect(config.enableConsentDebug, true);
        expect(config.tagForUnderAgeOfConsent, true);
        expect(config.appOpenAdMaxCacheDuration, const Duration(hours: 2));
        expect(config.minInterstitialInterval, const Duration(seconds: 60));
        expect(config.maxLoadRetries, 5);
        expect(config.retryDelay, const Duration(seconds: 10));
      });
    });

    // Note: testMode factory tests are skipped because they call TestAdUnitIds
    // which uses Platform.isAndroid/isIOS, unavailable in unit tests.
    // These would work in integration tests on actual devices.

    group('duration configurations', () {
      test('appOpenAdMaxCacheDuration defaults to 4 hours', () {
        const config = AdFlowConfig();
        expect(config.appOpenAdMaxCacheDuration.inHours, 4);
      });

      test('minInterstitialInterval defaults to 30 seconds', () {
        const config = AdFlowConfig();
        expect(config.minInterstitialInterval.inSeconds, 30);
      });

      test('retryDelay defaults to 5 seconds', () {
        const config = AdFlowConfig();
        expect(config.retryDelay.inSeconds, 5);
      });

      test('custom durations are preserved', () {
        const config = AdFlowConfig(
          appOpenAdMaxCacheDuration: Duration(hours: 1),
          minInterstitialInterval: Duration(minutes: 2),
          retryDelay: Duration(seconds: 15),
        );

        expect(config.appOpenAdMaxCacheDuration.inHours, 1);
        expect(config.minInterstitialInterval.inMinutes, 2);
        expect(config.retryDelay.inSeconds, 15);
      });
    });
  });

  group('AdConfig static proxy', () {
    setUp(() {
      // Reset to default state (using plain config instead of testMode)
      AdFlowConfig.setCurrent(const AdFlowConfig());
    });

    test('setConfig updates the static configuration', () {
      const customConfig = AdFlowConfig(
        maxLoadRetries: 10,
        minInterstitialInterval: Duration(minutes: 5),
      );

      AdFlowConfig.setCurrent(customConfig);

      expect(AdFlowConfig.current.maxLoadRetries, 10);
      expect(
        AdFlowConfig.current.minInterstitialInterval,
        const Duration(minutes: 5),
      );
    });

    test('enableConsentDebug defaults to false', () {
      AdFlowConfig.setCurrent(const AdFlowConfig());

      expect(AdFlowConfig.current.enableConsentDebug, false);
    });

    test('appOpenAdMaxCacheDuration proxies correctly', () {
      const config = AdFlowConfig(
        appOpenAdMaxCacheDuration: Duration(hours: 2),
      );
      AdFlowConfig.setCurrent(config);

      expect(
        AdFlowConfig.current.appOpenAdMaxCacheDuration,
        const Duration(hours: 2),
      );
    });

    test('minInterstitialInterval proxies correctly', () {
      const config = AdFlowConfig(
        minInterstitialInterval: Duration(seconds: 45),
      );
      AdFlowConfig.setCurrent(config);

      expect(
        AdFlowConfig.current.minInterstitialInterval,
        const Duration(seconds: 45),
      );
    });

    test('testDeviceIds proxies correctly', () {
      const config = AdFlowConfig(testDeviceIds: ['device-a', 'device-b']);
      AdFlowConfig.setCurrent(config);

      expect(AdFlowConfig.current.testDeviceIds, ['device-a', 'device-b']);
      expect(AdFlowConfig.current.testDeviceIds, ['device-a', 'device-b']);
    });
  });

  group('CollapsibleBannerPlacement', () {
    test('top placement has correct value', () {
      expect(CollapsibleBannerPlacement.top.value, 'top');
    });

    test('bottom placement has correct value', () {
      expect(CollapsibleBannerPlacement.bottom.value, 'bottom');
    });
  });
}
