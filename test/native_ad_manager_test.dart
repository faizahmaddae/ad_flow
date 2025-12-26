// Copyright 2024 - AdMob Integration Package
// Unit tests for NativeAdManager

import 'package:flutter_test/flutter_test.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NativeAdManager', () {
    late NativeAdManager manager;

    setUp(() {
      manager = NativeAdManager();
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

      test('nativeAd is null initially', () {
        expect(manager.nativeAd, isNull);
      });

      test('currentFactoryId is null initially', () {
        expect(manager.currentFactoryId, isNull);
      });
    });

    group('dispose', () {
      test('can be called safely', () {
        manager.dispose();
        // Just verifying no exception is thrown
      });

      test('resets state after dispose', () async {
        await manager.dispose();
        expect(manager.isLoaded, false);
        expect(manager.isLoading, false);
      });
    });
  });

  group('NativeAdLayoutHelper', () {
    group('recommendedHeights', () {
      test('has small_template height', () {
        expect(NativeAdLayoutHelper.recommendedHeights['small_template'], 100);
      });

      test('has medium_template height', () {
        expect(NativeAdLayoutHelper.recommendedHeights['medium_template'], 250);
      });

      test('has full_template height', () {
        expect(NativeAdLayoutHelper.recommendedHeights['full_template'], 350);
      });

      test('has list_item_template height', () {
        expect(
          NativeAdLayoutHelper.recommendedHeights['list_item_template'],
          80,
        );
      });

      test('has card_template height', () {
        expect(NativeAdLayoutHelper.recommendedHeights['card_template'], 300);
      });

      test('has banner_template height', () {
        expect(NativeAdLayoutHelper.recommendedHeights['banner_template'], 60);
      });
    });

    group('getRecommendedHeight', () {
      test('returns correct height for known factory', () {
        expect(
          NativeAdLayoutHelper.getRecommendedHeight('medium_template'),
          250,
        );
      });

      test('returns default 250 for unknown factory', () {
        expect(
          NativeAdLayoutHelper.getRecommendedHeight('unknown_factory'),
          250,
        );
      });

      test('returns correct height for all known factories', () {
        expect(
          NativeAdLayoutHelper.getRecommendedHeight('small_template'),
          100,
        );
        expect(
          NativeAdLayoutHelper.getRecommendedHeight('medium_template'),
          250,
        );
        expect(NativeAdLayoutHelper.getRecommendedHeight('full_template'), 350);
        expect(
          NativeAdLayoutHelper.getRecommendedHeight('list_item_template'),
          80,
        );
        expect(NativeAdLayoutHelper.getRecommendedHeight('card_template'), 300);
        expect(
          NativeAdLayoutHelper.getRecommendedHeight('banner_template'),
          60,
        );
      });
    });
  });
}
