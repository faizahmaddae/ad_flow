// Copyright 2024 - AdMob Integration Package
// Comprehensive tests for NativeAdManager

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ad_flow/ad_flow.dart';

import 'helpers/fake_ads.dart';
import 'helpers/mock_ad_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAdSdk mockSdk;
  late NativeAdManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AdsEnabledManager.instance.reset();
    await AdsEnabledManager.instance.initialize();

    mockSdk = MockAdSdk();
    AdSdk.instance = mockSdk;

    AdFlowConfig.setCurrent(
      const AdFlowConfig(
        androidNativeAdUnitId: 'test-native',
        iosNativeAdUnitId: 'test-native',
        maxLoadRetries: 2,
        retryDelay: Duration(milliseconds: 10),
      ),
    );
    AdFlowPlatform.platformOverride = TargetPlatform.android;

    manager = NativeAdManager();
  });

  tearDown(() async {
    await manager.dispose();
    AdSdk.resetInstance();
    AdFlowPlatform.reset();
  });

  group('initial state', () {
    test('isLoaded is false', () => expect(manager.isLoaded, false));
    test('isLoading is false', () => expect(manager.isLoading, false));
    test('isShowing is false (always)', () => expect(manager.isShowing, false));
    test('nativeAd is null', () => expect(manager.nativeAd, isNull));
    test(
      'currentFactoryId is null',
      () => expect(manager.currentFactoryId, isNull),
    );
  });

  group('loadAd - success', () {
    test('loads ad successfully', () async {
      final fakeAd = FakeNativeAd();
      mockSdk.nativeAdToReturn = fakeAd;

      await manager.loadAd(factoryId: 'medium_template');

      expect(manager.isLoaded, true);
      expect(manager.isLoading, false);
      expect(manager.nativeAd, isNotNull);
      expect(mockSdk.loadNativeCalls, 1);
    });

    test('calls onAdLoaded callback', () async {
      NativeAd? loadedAd;
      await manager.loadAd(
        factoryId: 'medium_template',
        onAdLoaded: (ad) => loadedAd = ad,
      );
      expect(loadedAd, isNotNull);
    });

    test('uses configured ad unit ID', () async {
      await manager.loadAd(factoryId: 'medium_template');
      expect(mockSdk.lastAdUnitId, 'test-native');
    });

    test('uses custom ad unit ID', () async {
      await manager.loadAd(
        factoryId: 'medium_template',
        adUnitId: 'custom-native',
      );
      expect(mockSdk.lastAdUnitId, 'custom-native');
    });

    test('stores current factory ID', () async {
      await manager.loadAd(factoryId: 'medium_template');
      expect(manager.currentFactoryId, 'medium_template');
    });

    test('passes factory ID to SDK', () async {
      await manager.loadAd(factoryId: 'small_template');
      expect(mockSdk.lastFactoryId, 'small_template');
    });
  });

  group('loadAd - failure', () {
    test('state is false after failure', () async {
      mockSdk.nativeLoadError = LoadAdError(1, 'test', 'fail', null);
      await manager.loadAd(factoryId: 'medium_template');

      expect(manager.isLoaded, false);
      expect(manager.isLoading, false);
    });

    test('reports error to AdFlowErrorHandler', () async {
      mockSdk.nativeLoadError = LoadAdError(1, 'test', 'fail', null);

      AdFlowError? capturedError;
      final sub = AdFlowErrorHandler.instance.errorStream.listen((e) {
        capturedError = e;
      });

      await manager.loadAd(factoryId: 'medium_template');
      await Future.delayed(Duration.zero);

      expect(capturedError, isNotNull);
      expect(capturedError!.type, AdErrorType.nativeLoad);

      await sub.cancel();
    });
  });

  group('loadAd - guards', () {
    test('skips load when ads disabled', () async {
      await AdsEnabledManager.instance.disableAds();
      await manager.loadAd(factoryId: 'medium_template');
      expect(mockSdk.loadNativeCalls, 0);
    });

    test('skips load when consent not given', () async {
      mockSdk.canRequestAdsResult = false;
      await manager.loadAd(factoryId: 'medium_template');
      expect(mockSdk.loadNativeCalls, 0);
    });

    test('skips load when already loaded with same factory', () async {
      await manager.loadAd(factoryId: 'medium_template');
      await manager.loadAd(factoryId: 'medium_template');
      expect(mockSdk.loadNativeCalls, 1);
    });

    test('reloads when factory ID changes', () async {
      await manager.loadAd(factoryId: 'medium_template');
      await manager.loadAd(factoryId: 'small_template');
      expect(mockSdk.loadNativeCalls, 2);
    });
  });

  group('dispose', () {
    test('clears ad and resets state', () async {
      await manager.loadAd(factoryId: 'medium_template');
      await manager.dispose();

      expect(manager.isLoaded, false);
      expect(manager.isLoading, false);
      expect(manager.nativeAd, isNull);
    });

    test('disposes underlying ad', () async {
      final fakeAd = FakeNativeAd();
      mockSdk.nativeAdToReturn = fakeAd;
      await manager.loadAd(factoryId: 'medium_template');
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
      await manager.loadAd(factoryId: 'medium_template');
      expect(count, greaterThan(0));
    });

    test('removing listener stops notifications', () async {
      int count = 0;
      void listener() => count++;
      manager.addStatusListener(listener);
      manager.removeStatusListener(listener);
      await manager.loadAd(factoryId: 'medium_template');
      expect(count, 0);
    });
  });

  group('NativeAdLayoutHelper', () {
    test('returns correct height for known factories', () {
      expect(NativeAdLayoutHelper.getRecommendedHeight('small_template'), 100);
      expect(NativeAdLayoutHelper.getRecommendedHeight('medium_template'), 250);
      expect(NativeAdLayoutHelper.getRecommendedHeight('full_template'), 350);
    });

    test('returns default 250 for unknown factory', () {
      expect(NativeAdLayoutHelper.getRecommendedHeight('unknown'), 250);
    });
  });
}
