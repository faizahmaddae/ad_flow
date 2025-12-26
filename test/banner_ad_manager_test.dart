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
}
