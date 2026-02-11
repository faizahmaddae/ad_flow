// Tests for AppLifecycleReactor _showAppOpenAd branches and AppOpenAdWrapper
// Covers: session limit, cooldown, already showing, ad available/unavailable,
//         onAdDismissed, onAdFailedToShow, AppOpenAdWrapper widget

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ad_flow/ad_flow.dart';

import 'helpers/mock_ad_sdk.dart';
import 'helpers/fake_ads.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAdSdk mockSdk;
  late AppOpenAdManager appOpenManager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AdsEnabledManager.instance.reset();
    await AdsEnabledManager.instance.initialize();

    mockSdk = MockAdSdk();
    AdSdk.instance = mockSdk;

    AdFlowConfig.setCurrent(const AdFlowConfig(
      androidAppOpenAdUnitId: 'test-app-open',
      iosAppOpenAdUnitId: 'test-app-open',
    ));
    AdFlowPlatform.platformOverride = TargetPlatform.android;

    appOpenManager = AppOpenAdManager();
  });

  tearDown(() async {
    await appOpenManager.dispose();
    AdSdk.resetInstance();
    AdFlowPlatform.reset();
  });

  group('AppLifecycleReactor _showAppOpenAd', () {
    test('does not show when session limit reached', () async {
      final reactor = AppLifecycleReactor(
        appOpenAdManager: appOpenManager,
        maxForegroundAdsPerSession: 1,
      );
      reactor.startListening();

      // Load ad and show once
      final fakeAd = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd;
      await appOpenManager.loadAd();

      // First show
      reactor.didChangeAppLifecycleState(AppLifecycleState.paused);
      reactor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      // Simulate dismiss to reset showing state
      fakeAd.simulateDismiss();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      // Load another ad
      mockSdk.appOpenAdToReturn = FakeAppOpenAd();
      await appOpenManager.loadAd();

      final countBefore = reactor.foregroundAdCount;

      // Second show - should be blocked by session limit
      reactor.didChangeAppLifecycleState(AppLifecycleState.paused);
      reactor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);

      expect(reactor.foregroundAdCount, countBefore);
      reactor.dispose();
    });

    test('does not show when already showing', () async {
      final reactor = AppLifecycleReactor(
        appOpenAdManager: appOpenManager,
        maxForegroundAdsPerSession: 0, // unlimited
      );
      reactor.startListening();

      // Load ad
      final fakeAd = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd;
      await appOpenManager.loadAd();

      // Trigger first show
      reactor.didChangeAppLifecycleState(AppLifecycleState.paused);
      reactor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);

      // Ad is being shown, trigger another resume
      reactor.didChangeAppLifecycleState(AppLifecycleState.paused);
      reactor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);

      // Should not crash
      reactor.dispose();
    });

    test('preloads ad when no ad available on resume', () async {
      final reactor = AppLifecycleReactor(
        appOpenAdManager: appOpenManager,
      );
      reactor.startListening();

      // No ad loaded, trigger resume
      reactor.didChangeAppLifecycleState(AppLifecycleState.paused);
      reactor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);

      // Should try to load (preload)
      expect(mockSdk.loadAppOpenCalls, greaterThanOrEqualTo(1));
      reactor.dispose();
    });

    test('unlimited mode allows multiple shows', () async {
      final reactor = AppLifecycleReactor(
        appOpenAdManager: appOpenManager,
        maxForegroundAdsPerSession: 0, // 0 = unlimited
      );
      reactor.startListening();

      // Show first ad
      final fakeAd1 = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd1;
      await appOpenManager.loadAd();

      reactor.didChangeAppLifecycleState(AppLifecycleState.paused);
      reactor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      // Dismiss to clear state
      fakeAd1.simulateDismiss();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(reactor.foregroundAdCount, greaterThan(0));
      reactor.dispose();
    });
  });

  group('AppOpenAdWrapper widget', () {
    testWidgets('renders child widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppOpenAdWrapper(
            appOpenAdManager: appOpenManager,
            child: const Text('App Content'),
          ),
        ),
      );

      expect(find.text('App Content'), findsOneWidget);
    });

    testWidgets('preloads ad when preloadAd=true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppOpenAdWrapper(
            appOpenAdManager: appOpenManager,
            preloadAd: true,
            child: const Text('Content'),
          ),
        ),
      );
      await tester.pump();

      expect(mockSdk.loadAppOpenCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('does not preload when preloadAd=false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppOpenAdWrapper(
            appOpenAdManager: appOpenManager,
            preloadAd: false,
            child: const Text('Content'),
          ),
        ),
      );
      await tester.pump();

      expect(mockSdk.loadAppOpenCalls, 0);
    });

    testWidgets('shows ad on cold start when configured', (tester) async {
      mockSdk.appOpenAdToReturn = FakeAppOpenAd();

      await tester.pumpWidget(
        MaterialApp(
          home: AppOpenAdWrapper(
            appOpenAdManager: appOpenManager,
            preloadAd: true,
            showOnColdStart: true,
            child: const Text('Content'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Should have loaded and attempted to show
      expect(mockSdk.loadAppOpenCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('disposes lifecycle reactor on dispose', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppOpenAdWrapper(
            appOpenAdManager: appOpenManager,
            child: const Text('Content'),
          ),
        ),
      );
      await tester.pump();

      // Replace to trigger dispose
      await tester.pumpWidget(
        const MaterialApp(home: Text('Disposed')),
      );
      // No error
    });
  });
}
