// Copyright 2024 - AdMob Integration Package
// Unit tests for EasyNativeAd widget hide behaviors

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AdsEnabledManager.instance.reset();
    await AdFlow.instance.reset();
  });

  group('EasyNativeAd', () {
    group('hideOnLoading parameter', () {
      testWidgets('defaults to true - collapses while loading', (tester) async {
        // Disable ads to prevent plugin calls during test
        await AdsEnabledManager.instance.initialize();
        await AdsEnabledManager.instance.disableAds();

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: EasyNativeAd(factoryId: 'medium_template', height: 300),
            ),
          ),
        );

        // With ads disabled, should show SizedBox.shrink (zero height)
        final sizeFinder = find.byType(SizedBox);
        expect(sizeFinder, findsOneWidget);

        final sizedBox = tester.widget<SizedBox>(sizeFinder);
        // SizedBox.shrink() has height and width of 0.0
        expect(sizedBox.height, 0.0);
        expect(sizedBox.width, 0.0);
      });
    });

    group('hideOnError parameter', () {
      testWidgets('defaults to true', (tester) async {
        // Verify the default value via constructor
        const widget = EasyNativeAd(factoryId: 'test', height: 100);
        expect(widget.hideOnError, true);
      });

      testWidgets('hideOnLoading defaults to true', (tester) async {
        const widget = EasyNativeAd(factoryId: 'test', height: 100);
        expect(widget.hideOnLoading, true);
      });
    });

    group('ads disabled', () {
      testWidgets('returns SizedBox.shrink when ads are disabled before mount', (
        tester,
      ) async {
        // Disable ads first
        await AdsEnabledManager.instance.initialize();
        await AdsEnabledManager.instance.disableAds();

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: EasyNativeAd(
                factoryId: 'medium_template',
                height: 300,
                hideOnLoading: false, // Would show loading, but ads disabled
              ),
            ),
          ),
        );

        // Should not show loading indicator because ads are disabled
        expect(find.byType(CircularProgressIndicator), findsNothing);
      });

      testWidgets('collapses to zero height when ads disabled AFTER widget mounted', (
        tester,
      ) async {
        // Initialize with ads ENABLED
        await AdsEnabledManager.instance.initialize();
        expect(AdsEnabledManager.instance.isEnabled, true);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(
                child: EasyNativeAd(
                  factoryId: 'medium_template',
                  height: 300,
                  hideOnLoading: false, // Show loading indicator
                ),
              ),
            ),
          ),
        );
        await tester.pump(); // Allow post frame callback

        // Widget should show loading state (ads enabled, hideOnLoading: false)
        // The EasyNativeAd renders a SizedBox(height: 300) with loading inside
        final renderBoxBefore = tester.renderObject<RenderBox>(
          find.byType(EasyNativeAd),
        );
        expect(renderBoxBefore.size.height, 300);

        // Now disable ads AFTER widget is mounted
        await AdFlow.instance.disableAds();
        await tester.pump(); // Allow listener callback and rebuild

        // Widget should now collapse to zero height (SizedBox.shrink)
        final renderBoxAfter = tester.renderObject<RenderBox>(
          find.byType(EasyNativeAd),
        );
        expect(renderBoxAfter.size.height, 0.0);
        expect(renderBoxAfter.size.width, 0.0);
      });

      testWidgets('collapses when ads disabled IMMEDIATELY after mount (same frame)', (
        tester,
      ) async {
        // Initialize with ads ENABLED
        await AdsEnabledManager.instance.initialize();
        expect(AdsEnabledManager.instance.isEnabled, true);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(
                child: EasyNativeAd(
                  factoryId: 'medium_template',
                  height: 300,
                  hideOnLoading: false,
                ),
              ),
            ),
          ),
        );
        // DON'T pump - disable ads in the same frame as mount!
        await AdFlow.instance.disableAds();
        
        // Now pump to process everything
        await tester.pump();

        // Widget should collapse to zero height
        final renderBox = tester.renderObject<RenderBox>(
          find.byType(EasyNativeAd),
        );
        expect(renderBox.size.height, 0.0);
        expect(renderBox.size.width, 0.0);
      });

      testWidgets('collapses when AdsEnabledManager NOT initialized (edge case)', (
        tester,
      ) async {
        // DON'T initialize AdsEnabledManager - simulating user forgetting to call init
        // AdsEnabledManager.instance.isEnabled defaults to true
        expect(AdsEnabledManager.instance.isEnabled, true);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(
                child: EasyNativeAd(
                  factoryId: 'medium_template',
                  height: 300,
                  hideOnLoading: false,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Should show loading (height: 300) because ads enabled by default
        final renderBoxBefore = tester.renderObject<RenderBox>(
          find.byType(EasyNativeAd),
        );
        expect(renderBoxBefore.size.height, 300);

        // Disable ads directly (skipping initialize)
        await AdsEnabledManager.instance.disableAds();
        await tester.pump();

        // Should collapse
        final renderBoxAfter = tester.renderObject<RenderBox>(
          find.byType(EasyNativeAd),
        );
        expect(renderBoxAfter.size.height, 0.0);
      });
    });

    group('NativeAdWidget (non-Easy version)', () {
      testWidgets('NativeAdWidget checks AdsEnabledManager on initial build', (
        tester,
      ) async {
        // Disable ads BEFORE building widget
        await AdsEnabledManager.instance.initialize();
        await AdsEnabledManager.instance.disableAds();
        
        final manager = NativeAdManager();
        
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NativeAdWidget(
                manager: manager,
                height: 300,
                placeholder: const SizedBox(height: 300, child: Text('Loading')),
              ),
            ),
          ),
        );

        // NativeAdWidget should NOT show placeholder because ads are disabled
        expect(find.text('Loading'), findsNothing);
        
        manager.dispose();
      });

      testWidgets('NativeAdWidget requires parent rebuild to react to disableAds', (
        tester,
      ) async {
        // This documents that NativeAdWidget (StatelessWidget) doesn't auto-update
        // Use EasyNativeAd for automatic handling, or wrap NativeAdWidget in
        // a StreamBuilder with AdsEnabledManager.instance.stream
        await AdsEnabledManager.instance.initialize();
        
        final manager = NativeAdManager();
        
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NativeAdWidget(
                manager: manager,
                height: 300,
                placeholder: const SizedBox(height: 300, child: Text('Loading')),
              ),
            ),
          ),
        );

        // Shows placeholder initially (ads enabled)
        expect(find.text('Loading'), findsOneWidget);
        
        // Disable ads - NativeAdWidget won't auto-update (StatelessWidget)
        await AdsEnabledManager.instance.disableAds();
        await tester.pump();
        
        // Still shows because StatelessWidget doesn't listen to changes
        // This is expected - use EasyNativeAd for auto-handling
        expect(find.text('Loading'), findsOneWidget);
        
        manager.dispose();
      });
    });

    group('constructor parameters', () {
      test('all parameters are properly assigned', () {
        const errorWidget = Text('Error');
        const loadingWidget = Text('Loading');

        const widget = EasyNativeAd(
          factoryId: 'custom_factory',
          height: 200,
          width: 400,
          hideOnLoading: false,
          hideOnError: false,
          loadingWidget: loadingWidget,
          errorWidget: errorWidget,
          padding: EdgeInsets.all(8),
          backgroundColor: Colors.blue,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        );

        expect(widget.factoryId, 'custom_factory');
        expect(widget.height, 200);
        expect(widget.width, 400);
        expect(widget.hideOnLoading, false);
        expect(widget.hideOnError, false);
        expect(widget.loadingWidget, loadingWidget);
        expect(widget.errorWidget, errorWidget);
        expect(widget.padding, const EdgeInsets.all(8));
        expect(widget.backgroundColor, Colors.blue);
        expect(widget.borderRadius, const BorderRadius.all(Radius.circular(8)));
      });
    });
  });
}
