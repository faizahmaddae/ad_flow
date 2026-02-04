// Copyright 2024 - AdMob Integration Package
// Unit tests for BannerAdManager

import 'package:flutter_test/flutter_test.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BannerAdManager', () {
    late BannerAdManager manager;

    setUp(() {
      manager = BannerAdManager();
      AdFlowConfig.setCurrent(const AdFlowConfig());
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

      test('bannerAd is null initially', () {
        expect(manager.bannerAd, isNull);
      });

      test('currentSize is null initially', () {
        expect(manager.currentSize, isNull);
      });
    });

    group('buildAdWidget', () {
      test('returns null when no ad is loaded', () {
        expect(manager.buildAdWidget(), isNull);
      });
    });

    group('dispose', () {
      test('can be called safely', () {
        manager.dispose();
        // Just verifying no exception is thrown
      });

      test('can be called multiple times', () {
        manager.dispose();
        manager.dispose();
        // Just verifying no exception is thrown
      });
    });
  });

  group('BannerAdManager multiple instances', () {
    test('each instance is independent', () {
      final manager1 = BannerAdManager();
      final manager2 = BannerAdManager();

      expect(identical(manager1, manager2), false);

      manager1.dispose();
      manager2.dispose();
    });
  });

  group('Dispose guard behavior', () {
    late BannerAdManager manager;

    setUp(() {
      manager = BannerAdManager();
      AdFlowConfig.setCurrent(const AdFlowConfig());
    });

    test('isLoaded is false after dispose', () async {
      await manager.dispose();
      expect(manager.isLoaded, false);
    });

    test('isLoading is false after dispose', () async {
      await manager.dispose();
      expect(manager.isLoading, false);
    });

    test('bannerAd is null after dispose', () async {
      await manager.dispose();
      expect(manager.bannerAd, isNull);
    });

    test('dispose can be called multiple times safely', () async {
      await manager.dispose();
      await manager.dispose();
      await manager.dispose();
      expect(manager.isLoaded, false);
    });

    test('status listeners are cleared after dispose', () async {
      int callCount = 0;
      void listener() {
        callCount++;
      }

      manager.addStatusListener(listener);
      await manager.dispose();

      manager.addStatusListener(listener);
      expect(callCount, 0);
    });
  });

  group('Status listener safety', () {
    late BannerAdManager manager;

    setUp(() {
      manager = BannerAdManager();
      AdFlowConfig.setCurrent(const AdFlowConfig());
    });

    tearDown(() {
      manager.dispose();
    });

    test('addStatusListener adds listener without exception', () {
      int callCount = 0;
      void listener() => callCount++;

      manager.addStatusListener(listener);
      expect(callCount, 0);
      manager.removeStatusListener(listener);
    });

    test('multiple listeners can be added', () {
      int count1 = 0;
      int count2 = 0;
      void listener1() => count1++;
      void listener2() => count2++;

      manager.addStatusListener(listener1);
      manager.addStatusListener(listener2);

      manager.removeStatusListener(listener1);
      manager.removeStatusListener(listener2);
    });

    test('removing non-existent listener does not throw', () {
      void listener() {}
      manager.removeStatusListener(listener);
    });

    test('same listener can be added multiple times', () {
      int callCount = 0;
      void listener() => callCount++;

      manager.addStatusListener(listener);
      manager.addStatusListener(listener);

      manager.removeStatusListener(listener);
    });
  });

  group('buildAdWidget', () {
    late BannerAdManager manager;

    setUp(() {
      manager = BannerAdManager();
      AdFlowConfig.setCurrent(const AdFlowConfig());
    });

    tearDown(() {
      manager.dispose();
    });

    test('returns null when not loaded', () {
      expect(manager.buildAdWidget(), isNull);
    });

    test('returns null when bannerAd is null', () {
      expect(manager.bannerAd, isNull);
      expect(manager.buildAdWidget(), isNull);
    });
  });
}
