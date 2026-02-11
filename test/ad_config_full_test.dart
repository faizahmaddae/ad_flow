// Copyright 2024 - AdMob Integration Package
// Expanded tests for ad_config.dart - covers AdFlowPlatform, TestAdUnitIds,
// copyWith, testMode, isUsingTestAds, has*Configured getters

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  group('AdFlowPlatform', () {
    tearDown(() {
      AdFlowPlatform.reset();
    });

    test('isAndroid true when overridden to android', () {
      AdFlowPlatform.platformOverride = TargetPlatform.android;
      expect(AdFlowPlatform.isAndroid, true);
      expect(AdFlowPlatform.isIOS, false);
    });

    test('isIOS true when overridden to iOS', () {
      AdFlowPlatform.platformOverride = TargetPlatform.iOS;
      expect(AdFlowPlatform.isIOS, true);
      expect(AdFlowPlatform.isAndroid, false);
    });

    test('reset clears override', () {
      AdFlowPlatform.platformOverride = TargetPlatform.iOS;
      AdFlowPlatform.reset();
      expect(AdFlowPlatform.platformOverride, isNull);
    });

    test('non-mobile platform returns false for both', () {
      AdFlowPlatform.platformOverride = TargetPlatform.windows;
      expect(AdFlowPlatform.isAndroid, false);
      expect(AdFlowPlatform.isIOS, false);
    });
  });

  group('TestAdUnitIds', () {
    setUp(() {
      AdFlowPlatform.platformOverride = TargetPlatform.android;
    });

    tearDown(() {
      AdFlowPlatform.reset();
    });

    test('provides banner test ID for Android', () {
      AdFlowPlatform.platformOverride = TargetPlatform.android;
      expect(TestAdUnitIds.banner, contains('ca-app-pub'));
    });

    test('provides banner test ID for iOS', () {
      AdFlowPlatform.platformOverride = TargetPlatform.iOS;
      expect(TestAdUnitIds.banner, contains('ca-app-pub'));
    });

    test('provides interstitial test ID', () {
      expect(TestAdUnitIds.interstitial, contains('ca-app-pub'));
    });

    test('provides appOpen test ID', () {
      expect(TestAdUnitIds.appOpen, contains('ca-app-pub'));
    });

    test('provides native test ID', () {
      expect(TestAdUnitIds.native, contains('ca-app-pub'));
    });

    test('provides rewarded test ID', () {
      expect(TestAdUnitIds.rewarded, contains('ca-app-pub'));
    });

    test('provides rewardedInterstitial test ID', () {
      expect(TestAdUnitIds.rewardedInterstitial, contains('ca-app-pub'));
    });

    test('different IDs for different platforms', () {
      AdFlowPlatform.platformOverride = TargetPlatform.android;
      final androidId = TestAdUnitIds.banner;

      AdFlowPlatform.platformOverride = TargetPlatform.iOS;
      final iosId = TestAdUnitIds.banner;

      expect(androidId, isNot(equals(iosId)));
    });
  });

  group('AdFlowConfig.testMode', () {
    setUp(() {
      AdFlowPlatform.platformOverride = TargetPlatform.android;
    });

    tearDown(() {
      AdFlowPlatform.reset();
      AdFlowConfig.resetCurrent();
    });

    test('creates config with test ad unit IDs', () {
      final config = AdFlowConfig.testMode();
      expect(config.androidBannerAdUnitId, isNotNull);
      expect(config.androidInterstitialAdUnitId, isNotNull);
      expect(config.androidAppOpenAdUnitId, isNotNull);
      expect(config.androidNativeAdUnitId, isNotNull);
      expect(config.androidRewardedAdUnitId, isNotNull);
    });

    test('creates config with custom overrides', () {
      final config = AdFlowConfig.testMode(
        testDeviceIds: ['device1'],
        enableConsentDebug: true,
      );
      expect(config.testDeviceIds, ['device1']);
      expect(config.enableConsentDebug, true);
    });
  });

  group('AdFlowConfig.copyWith', () {
    setUp(() {
      AdFlowPlatform.platformOverride = TargetPlatform.android;
    });

    tearDown(() {
      AdFlowPlatform.reset();
    });

    test('creates copy with replaced values', () {
      const config = AdFlowConfig(
        androidBannerAdUnitId: 'original',
        maxLoadRetries: 3,
      );
      final copy = config.copyWith(
        androidBannerAdUnitId: 'replaced',
        maxLoadRetries: 5,
      );

      expect(copy.androidBannerAdUnitId, 'replaced');
      expect(copy.maxLoadRetries, 5);
    });

    test('preserves unmodified values', () {
      const config = AdFlowConfig(
        androidBannerAdUnitId: 'banner',
        maxLoadRetries: 3,
        minInterstitialInterval: Duration(seconds: 60),
      );
      final copy = config.copyWith(maxLoadRetries: 5);

      expect(copy.androidBannerAdUnitId, 'banner');
      expect(copy.minInterstitialInterval, const Duration(seconds: 60));
      expect(copy.maxLoadRetries, 5);
    });

    test('copies all fields when all specified', () {
      const config = AdFlowConfig();
      final copy = config.copyWith(
        androidBannerAdUnitId: 'ab',
        iosBannerAdUnitId: 'ib',
        androidInterstitialAdUnitId: 'ai',
        iosInterstitialAdUnitId: 'ii',
        androidAppOpenAdUnitId: 'ao',
        iosAppOpenAdUnitId: 'io',
        androidNativeAdUnitId: 'an',
        iosNativeAdUnitId: 'in_',
        androidRewardedAdUnitId: 'ar',
        iosRewardedAdUnitId: 'ir',
        testDeviceIds: ['d1'],
        enableConsentDebug: true,
        tagForUnderAgeOfConsent: true,
        appOpenAdMaxCacheDuration: const Duration(hours: 1),
        minInterstitialInterval: const Duration(seconds: 90),
        maxLoadRetries: 10,
        retryDelay: const Duration(seconds: 20),
      );

      expect(copy.androidBannerAdUnitId, 'ab');
      expect(copy.iosBannerAdUnitId, 'ib');
      expect(copy.androidInterstitialAdUnitId, 'ai');
      expect(copy.iosInterstitialAdUnitId, 'ii');
      expect(copy.androidAppOpenAdUnitId, 'ao');
      expect(copy.iosAppOpenAdUnitId, 'io');
      expect(copy.androidNativeAdUnitId, 'an');
      expect(copy.iosNativeAdUnitId, 'in_');
      expect(copy.androidRewardedAdUnitId, 'ar');
      expect(copy.iosRewardedAdUnitId, 'ir');
      expect(copy.testDeviceIds, ['d1']);
      expect(copy.enableConsentDebug, true);
      expect(copy.tagForUnderAgeOfConsent, true);
      expect(copy.appOpenAdMaxCacheDuration, const Duration(hours: 1));
      expect(copy.minInterstitialInterval, const Duration(seconds: 90));
      expect(copy.maxLoadRetries, 10);
      expect(copy.retryDelay, const Duration(seconds: 20));
    });
  });

  group('platform-specific ad unit IDs', () {
    tearDown(() {
      AdFlowPlatform.reset();
      AdFlowConfig.resetCurrent();
    });

    test('bannerAdUnitId returns android ID on Android', () {
      AdFlowPlatform.platformOverride = TargetPlatform.android;
      const config = AdFlowConfig(
        androidBannerAdUnitId: 'android-banner',
        iosBannerAdUnitId: 'ios-banner',
      );
      expect(config.bannerAdUnitId, 'android-banner');
    });

    test('bannerAdUnitId returns ios ID on iOS', () {
      AdFlowPlatform.platformOverride = TargetPlatform.iOS;
      const config = AdFlowConfig(
        androidBannerAdUnitId: 'android-banner',
        iosBannerAdUnitId: 'ios-banner',
      );
      expect(config.bannerAdUnitId, 'ios-banner');
    });

    test('interstitialAdUnitId works per platform', () {
      AdFlowPlatform.platformOverride = TargetPlatform.android;
      const config = AdFlowConfig(
        androidInterstitialAdUnitId: 'android-inter',
        iosInterstitialAdUnitId: 'ios-inter',
      );
      expect(config.interstitialAdUnitId, 'android-inter');
    });

    test('appOpenAdUnitId works per platform', () {
      AdFlowPlatform.platformOverride = TargetPlatform.iOS;
      const config = AdFlowConfig(
        androidAppOpenAdUnitId: 'android-ao',
        iosAppOpenAdUnitId: 'ios-ao',
      );
      expect(config.appOpenAdUnitId, 'ios-ao');
    });

    test('nativeAdUnitId works per platform', () {
      AdFlowPlatform.platformOverride = TargetPlatform.android;
      const config = AdFlowConfig(
        androidNativeAdUnitId: 'android-native',
        iosNativeAdUnitId: 'ios-native',
      );
      expect(config.nativeAdUnitId, 'android-native');
    });

    test('rewardedAdUnitId works per platform', () {
      AdFlowPlatform.platformOverride = TargetPlatform.iOS;
      const config = AdFlowConfig(
        androidRewardedAdUnitId: 'android-reward',
        iosRewardedAdUnitId: 'ios-reward',
      );
      expect(config.rewardedAdUnitId, 'ios-reward');
    });
  });

  group('isUsingTestAds', () {
    setUp(() {
      AdFlowPlatform.platformOverride = TargetPlatform.android;
    });

    tearDown(() {
      AdFlowPlatform.reset();
    });

    test('returns true when using test IDs', () {
      final config = AdFlowConfig.testMode();
      expect(config.isUsingTestAds, true);
    });

    test('returns false when using production IDs', () {
      const config = AdFlowConfig(
        androidBannerAdUnitId: 'ca-app-pub-1234567890/banner',
        iosBannerAdUnitId: 'ca-app-pub-1234567890/banner-ios',
        androidInterstitialAdUnitId: 'ca-app-pub-1234567890/interstitial',
        iosInterstitialAdUnitId: 'ca-app-pub-1234567890/interstitial-ios',
        androidAppOpenAdUnitId: 'ca-app-pub-1234567890/appopen',
        iosAppOpenAdUnitId: 'ca-app-pub-1234567890/appopen-ios',
        androidNativeAdUnitId: 'ca-app-pub-1234567890/native',
        iosNativeAdUnitId: 'ca-app-pub-1234567890/native-ios',
        androidRewardedAdUnitId: 'ca-app-pub-1234567890/rewarded',
        iosRewardedAdUnitId: 'ca-app-pub-1234567890/rewarded-ios',
      );
      expect(config.isUsingTestAds, false);
    });

    test('returns true when no IDs configured', () {
      const config = AdFlowConfig();
      expect(config.isUsingTestAds, true);
    });
  });

  group('has*Configured getters', () {
    setUp(() {
      AdFlowPlatform.platformOverride = TargetPlatform.android;
    });

    tearDown(() {
      AdFlowPlatform.reset();
    });

    test('hasBannerConfigured true with real ID', () {
      const config = AdFlowConfig(
        androidBannerAdUnitId: 'ca-app-pub-real/banner',
      );
      expect(config.hasBannerConfigured, true);
    });

    test('hasBannerConfigured false with test ID', () {
      final config = AdFlowConfig.testMode();
      expect(config.hasBannerConfigured, false);
    });

    test('hasInterstitialConfigured', () {
      const config = AdFlowConfig(
        androidInterstitialAdUnitId: 'ca-app-pub-real/inter',
      );
      expect(config.hasInterstitialConfigured, true);
    });

    test('hasAppOpenConfigured', () {
      const config = AdFlowConfig(
        androidAppOpenAdUnitId: 'ca-app-pub-real/ao',
      );
      expect(config.hasAppOpenConfigured, true);
    });

    test('hasNativeConfigured', () {
      const config = AdFlowConfig(
        androidNativeAdUnitId: 'ca-app-pub-real/native',
      );
      expect(config.hasNativeConfigured, true);
    });

    test('hasRewardedConfigured', () {
      const config = AdFlowConfig(
        androidRewardedAdUnitId: 'ca-app-pub-real/reward',
      );
      expect(config.hasRewardedConfigured, true);
    });
  });

  group('AdFlowConfig.resetCurrent', () {
    test('resets to null (falls back to testMode)', () {
      AdFlowPlatform.platformOverride = TargetPlatform.android;
      AdFlowConfig.setCurrent(
        const AdFlowConfig(maxLoadRetries: 99),
      );
      expect(AdFlowConfig.current.maxLoadRetries, 99);

      AdFlowConfig.resetCurrent();
      // Should fall back to testMode defaults
      expect(AdFlowConfig.current.maxLoadRetries, 3);

      AdFlowPlatform.reset();
    });
  });

  group('timeout configurations', () {
    test('coldStartAdTimeout defaults to 3 seconds', () {
      const config = AdFlowConfig();
      expect(config.coldStartAdTimeout, const Duration(seconds: 3));
    });

    test('custom coldStartAdTimeout is preserved', () {
      const config = AdFlowConfig(
        coldStartAdTimeout: Duration(seconds: 5),
      );
      expect(config.coldStartAdTimeout, const Duration(seconds: 5));
    });
  });

  group('skipGdprConsentIfAttDenied', () {
    test('defaults to true', () {
      const config = AdFlowConfig();
      expect(config.skipGdprConsentIfAttDenied, true);
    });

    test('can be set to false', () {
      const config = AdFlowConfig(skipGdprConsentIfAttDenied: false);
      expect(config.skipGdprConsentIfAttDenied, false);
    });
  });

  group('rewardedAdsIgnoreRemoveAds', () {
    test('defaults to true', () {
      const config = AdFlowConfig();
      expect(config.rewardedAdsIgnoreRemoveAds, true);
    });

    test('can be set to false', () {
      const config = AdFlowConfig(rewardedAdsIgnoreRemoveAds: false);
      expect(config.rewardedAdsIgnoreRemoveAds, false);
    });
  });

  group('retryCooldownAfterMaxAttempts', () {
    test('defaults to 5 minutes', () {
      const config = AdFlowConfig();
      expect(config.retryCooldownAfterMaxAttempts, const Duration(minutes: 5));
    });

    test('can be customized', () {
      const config = AdFlowConfig(
        retryCooldownAfterMaxAttempts: Duration(minutes: 5),
      );
      expect(config.retryCooldownAfterMaxAttempts, const Duration(minutes: 5));
    });
  });

  group('maxAdContentRating', () {
    test('defaults to null', () {
      const config = AdFlowConfig();
      expect(config.maxAdContentRating, isNull);
    });

    test('can be set', () {
      const config = AdFlowConfig(maxAdContentRating: 'G');
      expect(config.maxAdContentRating, 'G');
    });
  });
}
