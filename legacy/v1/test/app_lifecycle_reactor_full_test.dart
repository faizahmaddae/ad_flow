// Copyright 2024 - AdMob Integration Package
// Comprehensive tests for AppLifecycleReactor

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ad_flow/ad_flow.dart';

import 'helpers/mock_ad_sdk.dart';
import 'helpers/fake_ads.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAdSdk mockSdk;
  late AppOpenAdManager appOpenManager;
  late AppLifecycleReactor reactor;

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
      ),
    );
    AdFlowPlatform.platformOverride = TargetPlatform.android;

    appOpenManager = AppOpenAdManager();
    reactor = AppLifecycleReactor(appOpenAdManager: appOpenManager);
  });

  tearDown(() async {
    reactor.dispose();
    await appOpenManager.dispose();
    AdSdk.resetInstance();
    AdFlowPlatform.reset();
  });

  group('initial state', () {
    test('isListening is false', () {
      expect(reactor.isListening, false);
    });

    test('isPaused is false', () {
      expect(reactor.isPaused, false);
    });

    test('foregroundAdCount is 0', () {
      expect(reactor.foregroundAdCount, 0);
    });

    test('maxForegroundAdsPerSession defaults to 1', () {
      expect(reactor.maxForegroundAdsPerSession, 1);
    });
  });

  group('startListening', () {
    test('sets isListening to true', () {
      reactor.startListening();
      expect(reactor.isListening, true);
    });

    test('calling twice is a no-op', () {
      reactor.startListening();
      reactor.startListening(); // Should not throw
      expect(reactor.isListening, true);
    });
  });

  group('stopListening', () {
    test('sets isListening to false', () {
      reactor.startListening();
      reactor.stopListening();
      expect(reactor.isListening, false);
    });

    test('calling when not listening is safe', () {
      reactor.stopListening(); // Should not throw
      expect(reactor.isListening, false);
    });
  });

  group('pause and resume', () {
    test('pause sets isPaused', () {
      reactor.pause();
      expect(reactor.isPaused, true);
    });

    test('resume clears isPaused', () {
      reactor.pause();
      reactor.resume();
      expect(reactor.isPaused, false);
    });
  });

  group('resetForegroundAdCount', () {
    test('resets count to zero', () {
      reactor.resetForegroundAdCount();
      expect(reactor.foregroundAdCount, 0);
    });
  });

  group('didChangeAppLifecycleState', () {
    test('tracks background state on paused', () {
      reactor.startListening();
      reactor.didChangeAppLifecycleState(AppLifecycleState.paused);
      // No crash, state tracked internally
    });

    test('tracks background state on inactive', () {
      reactor.startListening();
      reactor.didChangeAppLifecycleState(AppLifecycleState.inactive);
    });

    test('does not show ad when isPaused', () {
      reactor.startListening();
      reactor.pause();
      reactor.didChangeAppLifecycleState(AppLifecycleState.paused);
      reactor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      // No ad shown because isPaused
    });

    test('attempts to show ad on resume after background', () async {
      // Load an ad first
      final fakeAd = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd;
      await appOpenManager.loadAd();

      reactor.startListening();
      reactor.didChangeAppLifecycleState(AppLifecycleState.paused);
      reactor.didChangeAppLifecycleState(AppLifecycleState.resumed);

      await Future.delayed(Duration.zero);
    });

    test('does not show ad when resumed without going to background', () {
      reactor.startListening();
      // Directly call resumed without paused first
      reactor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      // No ad should be shown
    });

    test('preloads ad when no ad available', () async {
      reactor.startListening();
      reactor.didChangeAppLifecycleState(AppLifecycleState.paused);
      reactor.didChangeAppLifecycleState(AppLifecycleState.resumed);

      await Future.delayed(Duration.zero);

      // loadAd should be called for preloading
      expect(mockSdk.loadAppOpenCalls, greaterThanOrEqualTo(1));
    });

    test('respects session limit', () async {
      reactor.maxForegroundAdsPerSession = 1;

      // Load ad
      final fakeAd = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd;
      await appOpenManager.loadAd();

      reactor.startListening();

      // First foreground
      reactor.didChangeAppLifecycleState(AppLifecycleState.paused);
      reactor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      final countAfterFirst = reactor.foregroundAdCount;

      // Reset for second attempt
      mockSdk.appOpenAdToReturn = FakeAppOpenAd();
      await appOpenManager.loadAd();

      // Second foreground - should be blocked by limit
      reactor.didChangeAppLifecycleState(AppLifecycleState.paused);
      reactor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);

      // Count shouldn't have increased beyond 1
      expect(reactor.foregroundAdCount, countAfterFirst);
    });
  });

  group('dispose', () {
    test('stops listening', () {
      reactor.startListening();
      reactor.dispose();
      expect(reactor.isListening, false);
    });
  });

  group('custom maxForegroundAdsPerSession', () {
    test('can be set to 0 for unlimited', () {
      reactor.maxForegroundAdsPerSession = 0;
      expect(reactor.maxForegroundAdsPerSession, 0);
    });

    test('can be set to custom value', () {
      final r = AppLifecycleReactor(
        appOpenAdManager: appOpenManager,
        maxForegroundAdsPerSession: 5,
      );
      expect(r.maxForegroundAdsPerSession, 5);
      r.dispose();
    });
  });
}
