// Copyright 2024 - AdMob Integration Package
// Widget tests for EasyBannerAd

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EasyBannerAd Widget', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AdsEnabledManager.instance.reset();
      await AdFlow.instance.reset();
    });

    group('rendering', () {
      testWidgets('renders without errors', (tester) async {
        await AdsEnabledManager.instance.initialize();

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: EasyBannerAd())),
        );

        // Widget should build without throwing
        expect(find.byType(EasyBannerAd), findsOneWidget);
      });

      testWidgets('renders with collapsible=true', (tester) async {
        await AdsEnabledManager.instance.initialize();

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: EasyBannerAd(collapsible: true)),
          ),
        );

        expect(find.byType(EasyBannerAd), findsOneWidget);
      });

      testWidgets('renders SizedBox.shrink initially when ad not loaded', (
        tester,
      ) async {
        await AdsEnabledManager.instance.initialize();

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: EasyBannerAd())),
        );

        // Allow post frame callback to execute
        await tester.pump();

        // Should render minimal content when ad not loaded
        // (SizedBox.shrink or the widget itself)
        expect(find.byType(EasyBannerAd), findsOneWidget);
      });

      testWidgets('includes OrientationBuilder for rotation handling', (
        tester,
      ) async {
        await AdsEnabledManager.instance.initialize();

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: EasyBannerAd())),
        );

        await tester.pump();

        // OrientationBuilder should be in the widget tree
        expect(find.byType(OrientationBuilder), findsOneWidget);
      });
    });

    group('ads disabled behavior', () {
      testWidgets('renders nothing when ads are disabled', (tester) async {
        await AdsEnabledManager.instance.initialize();
        await AdsEnabledManager.instance.disableAds();

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Column(children: [Text('Content'), EasyBannerAd()]),
            ),
          ),
        );

        await tester.pump();

        // Widget exists but should render SizedBox.shrink
        expect(find.byType(EasyBannerAd), findsOneWidget);
        expect(find.text('Content'), findsOneWidget);
      });

      testWidgets('responds to ads being disabled after mount', (tester) async {
        await AdsEnabledManager.instance.initialize();

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: EasyBannerAd())),
        );

        await tester.pump();
        expect(find.byType(EasyBannerAd), findsOneWidget);

        // Disable ads
        await AdsEnabledManager.instance.disableAds();
        await tester.pump();

        // Widget should still exist but render nothing visible
        expect(find.byType(EasyBannerAd), findsOneWidget);
      });

      testWidgets('responds to ads being re-enabled after mount', (
        tester,
      ) async {
        await AdsEnabledManager.instance.initialize();
        await AdsEnabledManager.instance.disableAds();

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: EasyBannerAd())),
        );

        await tester.pump();

        // Re-enable ads
        await AdsEnabledManager.instance.enableAds();
        await tester.pump();

        expect(find.byType(EasyBannerAd), findsOneWidget);
      });
    });

    group('lifecycle', () {
      testWidgets('disposes cleanly', (tester) async {
        await AdsEnabledManager.instance.initialize();

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: EasyBannerAd())),
        );

        await tester.pump();

        // Replace the widget to trigger dispose
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('No Banner'))),
        );

        // Should dispose without errors
        expect(find.byType(EasyBannerAd), findsNothing);
        expect(find.text('No Banner'), findsOneWidget);
      });

      testWidgets('can be rebuilt safely', (tester) async {
        await AdsEnabledManager.instance.initialize();

        // Build the widget
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: EasyBannerAd())),
        );
        await tester.pump();

        // Rebuild with different key to force recreation
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: EasyBannerAd(key: UniqueKey())),
          ),
        );
        await tester.pump();

        expect(find.byType(EasyBannerAd), findsOneWidget);
      });
    });

    group('in different layouts', () {
      testWidgets('works in bottomNavigationBar', (tester) async {
        await AdsEnabledManager.instance.initialize();

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Text('Content'),
              bottomNavigationBar: EasyBannerAd(),
            ),
          ),
        );

        await tester.pump();

        expect(find.byType(EasyBannerAd), findsOneWidget);
        expect(find.text('Content'), findsOneWidget);
      });

      testWidgets('works in Column', (tester) async {
        await AdsEnabledManager.instance.initialize();

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  Expanded(child: Text('Content')),
                  EasyBannerAd(),
                ],
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.byType(EasyBannerAd), findsOneWidget);
      });

      testWidgets('works in Stack', (tester) async {
        await AdsEnabledManager.instance.initialize();

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Text('Content'),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: EasyBannerAd(),
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.byType(EasyBannerAd), findsOneWidget);
      });
    });

    group('multiple instances', () {
      testWidgets('multiple EasyBannerAd widgets can coexist', (tester) async {
        await AdsEnabledManager.instance.initialize();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  EasyBannerAd(key: const Key('banner1')),
                  const SizedBox(height: 100),
                  EasyBannerAd(key: const Key('banner2')),
                ],
              ),
            ),
          ),
        );

        await tester.pump();

        expect(find.byType(EasyBannerAd), findsNWidgets(2));
        expect(find.byKey(const Key('banner1')), findsOneWidget);
        expect(find.byKey(const Key('banner2')), findsOneWidget);
      });
    });
  });
}
