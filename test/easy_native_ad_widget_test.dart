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
      testWidgets('returns SizedBox.shrink when ads are disabled', (
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
