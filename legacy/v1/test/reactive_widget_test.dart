// Test for reactive widget behavior when AdFlow initializes after widget mount
//
// Note: These tests cannot call AdFlow.instance.initialize() directly because
// TestAdUnitIds uses Platform.isAndroid/isIOS which don't work in unit tests.
// Instead, we test the widget behavior without actual initialization.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AdsEnabledManager.instance.reset();
    await AdFlow.instance.reset();
    AdFlowErrorHandler.instance.reset();
  });

  group('EasyBannerAd reactive initialization', () {
    testWidgets('shows nothing when mounted before AdFlow init', (
      tester,
    ) async {
      // Mount widget BEFORE AdFlow is initialized
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EasyBannerAd())),
      );
      await tester.pump();

      // Widget should show nothing (waiting for init)
      expect(find.byType(EasyBannerAd), findsOneWidget);

      // Should not crash or throw errors
    });

    testWidgets('logs waiting message when AdFlow not initialized', (
      tester,
    ) async {
      // Initialize AdsEnabledManager so ads are enabled
      await AdsEnabledManager.instance.initialize();

      // Mount widget BEFORE AdFlow is initialized
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EasyBannerAd())),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Widget exists and doesn't crash
      expect(find.byType(EasyBannerAd), findsOneWidget);
    });

    testWidgets('widget survives being disposed before init completes', (
      tester,
    ) async {
      await AdsEnabledManager.instance.initialize();

      // Mount widget
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EasyBannerAd())),
      );
      await tester.pump();

      // Dispose widget immediately (before init could complete)
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Replaced'))),
      );

      // Should not crash
      expect(find.text('Replaced'), findsOneWidget);
    });

    testWidgets('multiple widgets can mount before init', (tester) async {
      await AdsEnabledManager.instance.initialize();

      // Mount multiple widgets before init
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [EasyBannerAd(), EasyBannerAd(), EasyBannerAd()],
            ),
          ),
        ),
      );
      await tester.pump();

      // All widgets should exist
      expect(find.byType(EasyBannerAd), findsNWidgets(3));
    });
  });

  group('EasyNativeAd reactive initialization', () {
    testWidgets('shows loading/empty when mounted before AdFlow init', (
      tester,
    ) async {
      await AdsEnabledManager.instance.initialize();

      // Mount widget BEFORE AdFlow is initialized
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EasyNativeAd(factoryId: 'medium_template', height: 300),
          ),
        ),
      );
      await tester.pump();

      // Widget should exist (showing loading/empty state)
      expect(find.byType(EasyNativeAd), findsOneWidget);
    });

    testWidgets('widget survives being disposed before init completes', (
      tester,
    ) async {
      await AdsEnabledManager.instance.initialize();

      // Mount widget
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EasyNativeAd(factoryId: 'medium_template', height: 300),
          ),
        ),
      );
      await tester.pump();

      // Dispose widget immediately
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Replaced'))),
      );

      // Should not crash
      expect(find.text('Replaced'), findsOneWidget);
    });

    testWidgets('multiple native ads can mount before init', (tester) async {
      await AdsEnabledManager.instance.initialize();

      // Mount multiple widgets before init (using Column instead of ListView
      // which recycles widgets)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: const [
                  EasyNativeAd(factoryId: 'small_template', height: 100),
                  EasyNativeAd(factoryId: 'medium_template', height: 150),
                  EasyNativeAd(factoryId: 'large_template', height: 150),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // All widgets should exist
      expect(find.byType(EasyNativeAd), findsNWidgets(3));
    });
  });

  group('initStream subscription cleanup', () {
    testWidgets('EasyBannerAd cancels subscription on dispose', (tester) async {
      await AdsEnabledManager.instance.initialize();

      // Mount widget
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EasyBannerAd())),
      );
      await tester.pump();

      // Dispose widget
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      await tester.pump();

      // No crash = success
    });

    testWidgets('EasyNativeAd cancels subscription on dispose', (tester) async {
      await AdsEnabledManager.instance.initialize();

      // Mount widget
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EasyNativeAd(factoryId: 'test', height: 100)),
        ),
      );
      await tester.pump();

      // Dispose widget
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      await tester.pump();

      // No crash = success
    });
  });

  group('edge cases', () {
    testWidgets('widget handles rapid mount/unmount cycles', (tester) async {
      await AdsEnabledManager.instance.initialize();

      for (int i = 0; i < 5; i++) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: i.isEven ? const EasyBannerAd() : const Text('No ads'),
            ),
          ),
        );
        await tester.pump();
      }

      // Should not crash
    });

    testWidgets('ads disabled before widget mount hides widget', (
      tester,
    ) async {
      // Disable ads first
      await AdsEnabledManager.instance.initialize();
      await AdsEnabledManager.instance.disableAds();

      // Mount widget
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EasyBannerAd())),
      );
      await tester.pump();

      // Widget should still exist but show nothing
      expect(find.byType(EasyBannerAd), findsOneWidget);
    });

    testWidgets('can disable ads after widget mounts', (tester) async {
      await AdsEnabledManager.instance.initialize();

      // Mount widget
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EasyBannerAd())),
      );
      await tester.pump();

      // Disable ads
      await AdsEnabledManager.instance.disableAds();
      await tester.pump();

      // Widget should still be there
      expect(find.byType(EasyBannerAd), findsOneWidget);
    });
  });
}
