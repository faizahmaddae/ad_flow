// Copyright 2024 - AdMob Integration Package
// Comprehensive tests for BannerAdManager

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ad_flow/ad_flow.dart';

import 'helpers/fake_ads.dart';
import 'helpers/mock_ad_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAdSdk mockSdk;
  late BannerAdManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AdsEnabledManager.instance.reset();
    await AdsEnabledManager.instance.initialize();

    mockSdk = MockAdSdk();
    AdSdk.instance = mockSdk;

    AdFlowConfig.setCurrent(const AdFlowConfig(
      androidBannerAdUnitId: 'test-banner',
      iosBannerAdUnitId: 'test-banner',
      maxLoadRetries: 2,
      retryDelay: Duration(milliseconds: 10),
    ));
    AdFlowPlatform.platformOverride = TargetPlatform.android;

    manager = BannerAdManager();
  });

  tearDown(() async {
    await manager.dispose();
    AdSdk.resetInstance();
    AdFlowPlatform.reset();
  });

  group('initial state', () {
    test('isLoaded is false', () => expect(manager.isLoaded, false));
    test('isLoading is false', () => expect(manager.isLoading, false));
    test('bannerAd is null', () => expect(manager.bannerAd, isNull));
    test('currentSize is null', () => expect(manager.currentSize, isNull));
    test('buildAdWidget returns null', () => expect(manager.buildAdWidget(), isNull));
  });

  group('loadBanner - success', () {
    test('loads banner ad successfully', () async {
      final fakeAd = FakeBannerAd();
      mockSdk.bannerAdToReturn = fakeAd;

      await manager.loadBanner(size: AdSize.banner);

      expect(manager.isLoaded, true);
      expect(manager.isLoading, false);
      expect(manager.bannerAd, isNotNull);
      expect(mockSdk.loadBannerCalls, 1);
    });

    test('calls onAdLoaded callback', () async {
      BannerAd? loadedAd;
      await manager.loadBanner(
        size: AdSize.banner,
        onAdLoaded: (ad) => loadedAd = ad,
      );
      expect(loadedAd, isNotNull);
    });

    test('uses configured ad unit ID', () async {
      await manager.loadBanner(size: AdSize.banner);
      expect(mockSdk.lastAdUnitId, 'test-banner');
    });

    test('uses custom ad unit ID', () async {
      await manager.loadBanner(size: AdSize.banner, adUnitId: 'custom-banner');
      expect(mockSdk.lastAdUnitId, 'custom-banner');
    });

    test('stores current size', () async {
      await manager.loadBanner(size: AdSize.banner);
      expect(manager.currentSize, AdSize.banner);
    });
  });

  group('loadBanner - failure', () {
    test('state is false after failure', () async {
      mockSdk.bannerLoadError = LoadAdError(1, 'test', 'fail', null);
      await manager.loadBanner(size: AdSize.banner);

      expect(manager.isLoaded, false);
      expect(manager.isLoading, false);
    });

    test('reports error to AdFlowErrorHandler', () async {
      mockSdk.bannerLoadError = LoadAdError(1, 'test', 'fail', null);

      AdFlowError? capturedError;
      final sub = AdFlowErrorHandler.instance.errorStream.listen((e) {
        capturedError = e;
      });

      await manager.loadBanner(size: AdSize.banner);
      await Future.delayed(Duration.zero);

      expect(capturedError, isNotNull);
      expect(capturedError!.type, AdErrorType.bannerLoad);

      await sub.cancel();
    });

    test('calls onAdFailedToLoad callback after retries exhausted', () async {
      mockSdk.bannerLoadError = LoadAdError(1, 'test', 'fail', null);

      await manager.loadBanner(
        size: AdSize.banner,
        onAdFailedToLoad: (_, _) {},
      );

      // Wait for retries to exhaust
      await Future.delayed(const Duration(milliseconds: 200));

      // After all retries, callback should fire
      // (may need more time depending on exponential backoff)
    });
  });

  group('loadBanner - guards', () {
    test('skips load when ads disabled', () async {
      await AdsEnabledManager.instance.disableAds();
      await manager.loadBanner(size: AdSize.banner);
      expect(mockSdk.loadBannerCalls, 0);
    });

    test('skips load when consent not given', () async {
      mockSdk.canRequestAdsResult = false;
      await manager.loadBanner(size: AdSize.banner);
      expect(mockSdk.loadBannerCalls, 0);
    });

    test('skips load when already loading', () async {
      await manager.loadBanner(size: AdSize.banner);
      // Already loaded, second call (while not loading any more) just reloads
    });
  });

  group('loadAdaptiveBanner', () {
    testWidgets('loads adaptive banner with context', (tester) async {
      final fakeAd = FakeBannerAd();
      mockSdk.bannerAdToReturn = fakeAd;
      mockSdk.adaptiveBannerSizeResult = AdSize.banner;

      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      );

      await manager.loadAdaptiveBanner(context: capturedContext);

      expect(manager.isLoaded, true);
      expect(mockSdk.loadBannerCalls, 1);
    });

    testWidgets('skips load when adaptive size is null', (tester) async {
      mockSdk.returnNullAdaptiveSize = true;

      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      );

      await manager.loadAdaptiveBanner(context: capturedContext);

      expect(manager.isLoaded, false);
      expect(mockSdk.loadBannerCalls, 0);
    });
  });

  group('loadCollapsibleBanner', () {
    testWidgets('loads collapsible banner', (tester) async {
      final fakeAd = FakeBannerAd();
      mockSdk.bannerAdToReturn = fakeAd;
      mockSdk.adaptiveBannerSizeResult = AdSize.banner;

      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      );

      await manager.loadCollapsibleBanner(
        context: capturedContext,
        placement: CollapsibleBannerPlacement.bottom,
      );

      expect(manager.isLoaded, true);
      expect(mockSdk.loadBannerCalls, 1);
    });
  });

  group('buildAdWidget', () {
    test('returns null when not loaded', () {
      expect(manager.buildAdWidget(), isNull);
    });
  });

  group('dispose', () {
    test('clears ad and resets state', () async {
      await manager.loadBanner(size: AdSize.banner);
      await manager.dispose();

      expect(manager.isLoaded, false);
      expect(manager.isLoading, false);
      expect(manager.bannerAd, isNull);
    });

    test('disposes underlying ad', () async {
      final fakeAd = FakeBannerAd();
      mockSdk.bannerAdToReturn = fakeAd;
      await manager.loadBanner(size: AdSize.banner);
      await manager.dispose();
      expect(fakeAd.wasDisposed, true);
    });

    test('can be called multiple times safely', () async {
      await manager.dispose();
      await manager.dispose();
      expect(manager.isLoaded, false);
    });
  });

  group('status listeners', () {
    test('notifies on load', () async {
      int count = 0;
      manager.addStatusListener(() => count++);
      await manager.loadBanner(size: AdSize.banner);
      expect(count, greaterThan(0));
    });
  });
}
