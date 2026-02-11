// Copyright 2024 - AdMob Integration Package
// Tests for NativeAdWidget and NativeAdLayoutHelper

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ad_flow/ad_flow.dart';

import 'helpers/mock_ad_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AdsEnabledManager.instance.reset();
    await AdsEnabledManager.instance.initialize();
    AdFlowPlatform.platformOverride = TargetPlatform.android;

    final mockSdk = MockAdSdk();
    AdSdk.instance = mockSdk;
  });

  tearDown(() async {
    AdSdk.resetInstance();
    AdFlowPlatform.reset();
  });

  group('NativeAdWidget', () {
    testWidgets('shows SizedBox.shrink when ads disabled', (tester) async {
      await AdsEnabledManager.instance.disableAds();

      final manager = NativeAdManager();
      await tester.pumpWidget(
        MaterialApp(
          home: NativeAdWidget(manager: manager),
        ),
      );

      // Should show nothing
      expect(find.byType(SizedBox), findsWidgets);
      manager.dispose();
    });

    testWidgets('shows placeholder when not loaded', (tester) async {
      final manager = NativeAdManager();
      await tester.pumpWidget(
        MaterialApp(
          home: NativeAdWidget(
            manager: manager,
            placeholder: const Text('Loading...'),
          ),
        ),
      );

      expect(find.text('Loading...'), findsOneWidget);
      manager.dispose();
    });

    testWidgets('shows SizedBox.shrink when not loaded and no placeholder',
        (tester) async {
      final manager = NativeAdManager();
      await tester.pumpWidget(
        MaterialApp(
          home: NativeAdWidget(manager: manager),
        ),
      );

      expect(find.byType(SizedBox), findsWidgets);
      manager.dispose();
    });
  });

  group('NativeAdLayoutHelper', () {
    test('recommendedHeights contains expected templates', () {
      expect(
        NativeAdLayoutHelper.recommendedHeights.containsKey('small_template'),
        true,
      );
      expect(
        NativeAdLayoutHelper.recommendedHeights.containsKey('medium_template'),
        true,
      );
      expect(
        NativeAdLayoutHelper.recommendedHeights.containsKey('full_template'),
        true,
      );
      expect(
        NativeAdLayoutHelper.recommendedHeights
            .containsKey('list_item_template'),
        true,
      );
      expect(
        NativeAdLayoutHelper.recommendedHeights.containsKey('card_template'),
        true,
      );
      expect(
        NativeAdLayoutHelper.recommendedHeights.containsKey('banner_template'),
        true,
      );
    });

    test('getRecommendedHeight returns correct values', () {
      expect(NativeAdLayoutHelper.getRecommendedHeight('small_template'), 100);
      expect(NativeAdLayoutHelper.getRecommendedHeight('medium_template'), 250);
      expect(NativeAdLayoutHelper.getRecommendedHeight('full_template'), 350);
      expect(
        NativeAdLayoutHelper.getRecommendedHeight('list_item_template'),
        80,
      );
      expect(NativeAdLayoutHelper.getRecommendedHeight('card_template'), 300);
      expect(NativeAdLayoutHelper.getRecommendedHeight('banner_template'), 60);
    });

    test('getRecommendedHeight returns 250 for unknown factory', () {
      expect(NativeAdLayoutHelper.getRecommendedHeight('unknown'), 250);
    });
  });

  group('EasyNativeAd widget', () {
    testWidgets('shows SizedBox.shrink when ads disabled', (tester) async {
      await AdsEnabledManager.instance.disableAds();

      await tester.pumpWidget(
        const MaterialApp(
          home: EasyNativeAd(height: 300),
        ),
      );

      // Should collapse
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('shows SizedBox.shrink while loading (hideOnLoading=true)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EasyNativeAd(height: 300, hideOnLoading: true),
        ),
      );

      // Default hideOnLoading is true, should show nothing while loading
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('shows loading widget when hideOnLoading=false',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EasyNativeAd(
            height: 300,
            hideOnLoading: false,
            loadingWidget: Center(child: Text('Loading native ad')),
          ),
        ),
      );

      // Should show the loading widget
      expect(find.text('Loading native ad'), findsOneWidget);
    });

    testWidgets('disposes without error', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EasyNativeAd(height: 300),
        ),
      );

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      // Should not throw during dispose
    });
  });
}
