// Copyright 2024 - AdMob Integration Package
// Comprehensive tests for AppOpenAdManager

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ad_flow/ad_flow.dart';

import 'helpers/fake_ads.dart';
import 'helpers/mock_ad_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAdSdk mockSdk;
  late AppOpenAdManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AdsEnabledManager.instance.reset();
    await AdsEnabledManager.instance.initialize();

    mockSdk = MockAdSdk();
    AdSdk.instance = mockSdk;

    AdFlowConfig.setCurrent(
      const AdFlowConfig(
        androidAppOpenAdUnitId: 'test-app-open',
        iosAppOpenAdUnitId: 'test-app-open',
        appOpenAdMaxCacheDuration: Duration(hours: 4),
        maxLoadRetries: 2,
        retryDelay: Duration(milliseconds: 10),
      ),
    );
    AdFlowPlatform.platformOverride = TargetPlatform.android;

    manager = AppOpenAdManager();
  });

  tearDown(() async {
    await manager.dispose();
    AdSdk.resetInstance();
    AdFlowPlatform.reset();
  });

  group('initial state', () {
    test('isLoaded is false', () => expect(manager.isLoaded, false));
    test('isLoading is false', () => expect(manager.isLoading, false));
    test('isShowing is false', () => expect(manager.isShowing, false));
    test('appOpenAd is null', () => expect(manager.appOpenAd, isNull));
    test('isAdAvailable is false', () => expect(manager.isAdAvailable, false));
  });

  group('loadAd - success', () {
    test('loads ad successfully', () async {
      final fakeAd = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd;

      await manager.loadAd();

      expect(manager.isLoaded, true);
      expect(manager.isLoading, false);
      expect(manager.appOpenAd, isNotNull);
      expect(manager.isAdAvailable, true);
      expect(mockSdk.loadAppOpenCalls, 1);
    });

    test('calls onAdLoaded callback', () async {
      AppOpenAd? loadedAd;
      await manager.loadAd(onAdLoaded: (ad) => loadedAd = ad);
      expect(loadedAd, isNotNull);
    });

    test('uses configured ad unit ID', () async {
      await manager.loadAd();
      expect(mockSdk.lastAdUnitId, 'test-app-open');
    });

    test('uses custom ad unit ID', () async {
      await manager.loadAd(adUnitId: 'custom-app-open');
      expect(mockSdk.lastAdUnitId, 'custom-app-open');
    });
  });

  group('loadAd - failure', () {
    test('state is false after failure', () async {
      mockSdk.appOpenLoadError = LoadAdError(1, 'test', 'fail', null);
      await manager.loadAd();

      expect(manager.isLoaded, false);
      expect(manager.isLoading, false);
    });

    test('reports error to AdFlowErrorHandler', () async {
      mockSdk.appOpenLoadError = LoadAdError(1, 'test', 'fail', null);

      AdFlowError? capturedError;
      final sub = AdFlowErrorHandler.instance.errorStream.listen((e) {
        capturedError = e;
      });

      await manager.loadAd();
      await Future.delayed(Duration.zero);

      expect(capturedError, isNotNull);
      expect(capturedError!.type, AdErrorType.appOpenLoad);

      await sub.cancel();
    });
  });

  group('loadAd - guards', () {
    test('skips load when ads disabled', () async {
      await AdsEnabledManager.instance.disableAds();
      await manager.loadAd();
      expect(mockSdk.loadAppOpenCalls, 0);
    });

    test('skips load when consent not given', () async {
      mockSdk.canRequestAdsResult = false;
      await manager.loadAd();
      expect(mockSdk.loadAppOpenCalls, 0);
    });

    test('skips load when valid ad already available', () async {
      await manager.loadAd();
      await manager.loadAd();
      expect(mockSdk.loadAppOpenCalls, 1);
    });
  });

  group('loadAdAndWait', () {
    test('returns true on success', () async {
      final result = await manager.loadAdAndWait();
      expect(result, true);
    });

    test('returns true when ad already available', () async {
      await manager.loadAd();
      final result = await manager.loadAdAndWait();
      expect(result, true);
    });
  });

  group('showAdIfAvailable - success', () {
    test('shows loaded ad', () async {
      final fakeAd = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd;
      await manager.loadAd();

      final result = await manager.showAdIfAvailable();

      expect(result, true);
      expect(fakeAd.wasShown, true);
    });

    test('onAdDismissed fires on dismiss', () async {
      final fakeAd = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd;
      await manager.loadAd();

      bool dismissed = false;
      await manager.showAdIfAvailable(onAdDismissed: () => dismissed = true);

      fakeAd.simulateDismiss();
      expect(dismissed, true);
    });

    test('ad is disposed after dismiss', () async {
      final fakeAd = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd;
      await manager.loadAd();
      await manager.showAdIfAvailable();
      fakeAd.simulateDismiss();

      expect(fakeAd.wasDisposed, true);
      expect(manager.isLoaded, false);
      expect(manager.appOpenAd, isNull);
    });

    test('isShowing is true while showing', () async {
      final fakeAd = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd;
      await manager.loadAd();
      await manager.showAdIfAvailable();
      expect(manager.isShowing, true);
    });
  });

  group('showAdIfAvailable - guards', () {
    test('returns false when no ad loaded', () async {
      final result = await manager.showAdIfAvailable();
      expect(result, false);
    });

    test('returns false when ads disabled', () async {
      await manager.loadAd();
      await AdsEnabledManager.instance.disableAds();
      final result = await manager.showAdIfAvailable();
      expect(result, false);
    });

    test('returns false when already showing', () async {
      final fakeAd = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd;
      await manager.loadAd();
      await manager.showAdIfAvailable();
      final result = await manager.showAdIfAvailable();
      expect(result, false);
    });

    test('calls onAdFailedToShow when no ad available', () async {
      bool failedCalled = false;
      await manager.showAdIfAvailable(
        onAdFailedToShow: () => failedCalled = true,
      );
      expect(failedCalled, true);
    });
  });

  group('ad expiry', () {
    test('isAdAvailable is false when ad is expired', () async {
      // Load ad with very short cache duration
      AdFlowConfig.setCurrent(
        const AdFlowConfig(
          androidAppOpenAdUnitId: 'test-app-open',
          iosAppOpenAdUnitId: 'test-app-open',
          appOpenAdMaxCacheDuration: Duration.zero,
        ),
      );

      await manager.loadAd();

      // The ad should be expired immediately since Duration.zero
      await Future.delayed(const Duration(milliseconds: 1));
      expect(manager.isAdAvailable, false);
    });
  });

  group('auto-preload', () {
    test('triggers loadAd after dismiss', () async {
      final fakeAd = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd;
      await manager.loadAd();
      expect(mockSdk.loadAppOpenCalls, 1);

      await manager.showAdIfAvailable();
      fakeAd.simulateDismiss();
      await Future.delayed(Duration.zero);

      expect(mockSdk.loadAppOpenCalls, greaterThan(1));
    });
  });

  group('dispose', () {
    test('clears ad and resets state', () async {
      await manager.loadAd();
      await manager.dispose();

      expect(manager.isLoaded, false);
      expect(manager.isLoading, false);
      expect(manager.isShowing, false);
      expect(manager.appOpenAd, isNull);
    });

    test('disposes underlying ad', () async {
      final fakeAd = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd;
      await manager.loadAd();
      await manager.dispose();
      expect(fakeAd.wasDisposed, true);
    });
  });

  group('status listeners', () {
    test('notifies on load', () async {
      int count = 0;
      manager.addStatusListener(() => count++);
      await manager.loadAd();
      expect(count, greaterThan(0));
    });
  });
}
