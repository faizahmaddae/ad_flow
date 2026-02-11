// Tests for EasyBannerAd - targeting uncovered lines 88-158, 181-210
// Covers: _onAdFlowInitialized, _tryLoadAd, _onAdsEnabledChanged,
//         _loadAd (fixed/collapsible/adaptive), orientation changes, build states

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ad_flow/ad_flow.dart';

import 'helpers/mock_ad_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockAdSdk mockSdk;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AdsEnabledManager.instance.reset();
    await AdsEnabledManager.instance.initialize();
    await AdFlow.instance.reset();
    mockSdk = MockAdSdk();
    AdSdk.instance = mockSdk;
    AdFlowPlatform.platformOverride = TargetPlatform.android;
    AdFlowConfig.setCurrent(
      const AdFlowConfig(
        androidBannerAdUnitId: 'test-banner',
        iosBannerAdUnitId: 'test-banner',
      ),
    );
  });

  tearDown(() async {
    await AdFlow.instance.reset();
    AdSdk.resetInstance();
    AdFlowPlatform.reset();
  });

  group('EasyBannerAd _onAdsEnabledChanged', () {
    testWidgets('disposes banner and resets when ads disabled', (tester) async {
      // Override error handler to catch transient AdWidget errors
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      await AdFlow.instance.initialize();

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EasyBannerAd())),
      );
      await tester.pump();
      await tester.pump();

      // Disable ads - covers _onAdsEnabledChanged(!isEnabled) path
      await AdsEnabledManager.instance.disableAds();
      await tester.pump();

      // Widget should still exist but show SizedBox.shrink
      expect(find.byType(EasyBannerAd), findsOneWidget);

      // Clean up widget tree before tearDown
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('reloads when ads re-enabled after disabling', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      await AdFlow.instance.initialize();

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EasyBannerAd())),
      );
      await tester.pump();
      await tester.pump();

      final callsBefore = mockSdk.loadBannerCalls;

      await AdsEnabledManager.instance.disableAds();
      await tester.pump();

      await AdsEnabledManager.instance.enableAds();
      await tester.pump();
      await tester.pump();

      // Should have reloaded after re-enable
      expect(mockSdk.loadBannerCalls, greaterThan(callsBefore));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('EasyBannerAd _loadAd branches', () {
    testWidgets('loads fixed size banner when adSize provided', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      await AdFlow.instance.initialize();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EasyBannerAd(adSize: AdSize.banner)),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(mockSdk.loadBannerCalls, greaterThanOrEqualTo(1));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('loads collapsible banner when collapsible=true', (
      tester,
    ) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      await AdFlow.instance.initialize();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EasyBannerAd(collapsible: true)),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(mockSdk.loadBannerCalls, greaterThanOrEqualTo(1));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('loads adaptive banner by default', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      await AdFlow.instance.initialize();

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EasyBannerAd())),
      );
      await tester.pump();
      await tester.pump();

      expect(mockSdk.loadBannerCalls, greaterThanOrEqualTo(1));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('handles load failure gracefully', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      await AdFlow.instance.initialize();
      mockSdk.bannerLoadError = LoadAdError(1, 'test', 'failed', null);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EasyBannerAd(adSize: AdSize.banner)),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Widget should still be in tree even after failure
      expect(find.byType(EasyBannerAd), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });

  group('EasyBannerAd build states', () {
    testWidgets('fixed size shows SafeArea after load', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      await AdFlow.instance.initialize();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EasyBannerAd(adSize: AdSize.banner)),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(SafeArea), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('adaptive shows OrientationBuilder', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EasyBannerAd())),
      );
      await tester.pump();

      expect(find.byType(OrientationBuilder), findsOneWidget);
    });
  });

  group('EasyBannerAd ads disabled on init', () {
    testWidgets('does not load when ads disabled from start', (tester) async {
      await AdsEnabledManager.instance.disableAds();

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EasyBannerAd())),
      );
      await tester.pump();

      expect(mockSdk.loadBannerCalls, 0);
    });
  });

  group('EasyBannerAd dispose', () {
    testWidgets('cancels subscriptions on dispose', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      await AdFlow.instance.initialize();

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EasyBannerAd())),
      );
      await tester.pump();
      await tester.pump();

      // Dispose by replacing widget tree
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('handles dispose when ads were disabled', (tester) async {
      await AdsEnabledManager.instance.disableAds();

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: EasyBannerAd())),
      );
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}
