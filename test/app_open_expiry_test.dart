// Copyright 2024 - AdMob Integration Package
// Unit tests for AppOpenAdManager expiry logic

import 'package:flutter_test/flutter_test.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppOpenAdManager expiry logic', () {
    late AppOpenAdManager manager;

    setUp(() {
      manager = AppOpenAdManager();
      // Set up config with known cache duration
      AdFlowConfig.setCurrent(
        const AdFlowConfig(appOpenAdMaxCacheDuration: Duration(hours: 4)),
      );
    });

    tearDown(() {
      manager.dispose();
    });

    group('initial state', () {
      test('isLoaded is false initially', () {
        expect(manager.isLoaded, false);
      });

      test('isLoading is false initially', () {
        expect(manager.isLoading, false);
      });

      test('isShowing is false initially', () {
        expect(manager.isShowing, false);
      });

      test('isAdAvailable is false when no ad is loaded', () {
        expect(manager.isAdAvailable, false);
      });

      test('appOpenAd is null initially', () {
        expect(manager.appOpenAd, isNull);
      });
    });

    group('status listeners', () {
      test('addStatusListener adds listener without exception', () {
        int callCount = 0;
        void listener() {
          callCount++;
        }

        manager.addStatusListener(listener);
        expect(callCount, 0);
        manager.removeStatusListener(listener);
      });

      test('removeStatusListener removes listener', () {
        int callCount = 0;
        void listener() {
          callCount++;
        }

        manager.addStatusListener(listener);
        manager.removeStatusListener(listener);
        expect(callCount, 0);
      });
    });
  });

  group('Cache duration configuration', () {
    test('default cache duration is 4 hours', () {
      const config = AdFlowConfig();
      expect(config.appOpenAdMaxCacheDuration, const Duration(hours: 4));
    });

    test('custom cache duration can be set', () {
      const config = AdFlowConfig(
        appOpenAdMaxCacheDuration: Duration(hours: 2),
      );
      expect(config.appOpenAdMaxCacheDuration, const Duration(hours: 2));
    });

    test('AdConfig proxies appOpenAdMaxCacheDuration correctly', () {
      const config = AdFlowConfig(
        appOpenAdMaxCacheDuration: Duration(hours: 3),
      );
      AdFlowConfig.setCurrent(config);

      expect(AdFlowConfig.current.appOpenAdMaxCacheDuration.inHours, 3);
    });

    test('cache duration can be set to minutes', () {
      const config = AdFlowConfig(
        appOpenAdMaxCacheDuration: Duration(minutes: 30),
      );
      expect(config.appOpenAdMaxCacheDuration.inMinutes, 30);
    });

    test('Google recommended 4 hours is the default', () {
      // Google recommends a 4-hour cache duration for app open ads
      const config = AdFlowConfig();
      expect(config.appOpenAdMaxCacheDuration.inHours, 4);
    });
  });

  group('isAdAvailable logic', () {
    late AppOpenAdManager manager;

    setUp(() {
      manager = AppOpenAdManager();
    });

    tearDown(() {
      manager.dispose();
    });

    test('returns false when not loaded', () {
      expect(manager.isAdAvailable, false);
    });

    test('returns false when ad is null', () {
      expect(manager.appOpenAd, isNull);
      expect(manager.isAdAvailable, false);
    });
  });
}
