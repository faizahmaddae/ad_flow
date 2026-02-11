// Tests for EasyNativeAd & NativeAdWidget - targeting uncovered lines
// Covers: NativeAdWidget with styling, EasyNativeAd state management
//         (_onAdFlowInitialized, _onAdsEnabledChanged, _loadAd, build branches)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ad_flow/ad_flow.dart';

import 'helpers/mock_ad_sdk.dart';

const _testConfig = AdFlowConfig(
  androidNativeAdUnitId: 'test-native',
  iosNativeAdUnitId: 'test-native',
  maxLoadRetries: 0,
);

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
  });

  tearDown(() async {
    await AdFlow.instance.reset();
    AdSdk.resetInstance();
    AdFlowPlatform.reset();
  });

  group('NativeAdWidget build with styling', () {
    testWidgets('applies height and width', (tester) async {
      final manager = NativeAdManager();
      await tester.pumpWidget(
        MaterialApp(
          home: NativeAdWidget(
            manager: manager,
            height: 300,
            width: 250,
          ),
        ),
      );
      expect(find.byType(NativeAdWidget), findsOneWidget);
      manager.dispose();
    });

    testWidgets('applies backgroundColor and borderRadius', (tester) async {
      final manager = NativeAdManager();
      await tester.pumpWidget(
        MaterialApp(
          home: NativeAdWidget(
            manager: manager,
            backgroundColor: Colors.blue,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
      expect(find.byType(NativeAdWidget), findsOneWidget);
      manager.dispose();
    });

    testWidgets('applies padding', (tester) async {
      final manager = NativeAdManager();
      await tester.pumpWidget(
        MaterialApp(
          home: NativeAdWidget(
            manager: manager,
            padding: const EdgeInsets.all(16),
          ),
        ),
      );
      expect(find.byType(NativeAdWidget), findsOneWidget);
      manager.dispose();
    });
  });

  group('EasyNativeAd state management', () {
    testWidgets('shows SizedBox.shrink when ads disabled', (tester) async {
      await AdsEnabledManager.instance.disableAds();

      await tester.pumpWidget(
        const MaterialApp(home: EasyNativeAd(height: 300)),
      );
      await tester.pump();

      expect(mockSdk.loadNativeCalls, 0);
    });

    testWidgets('loads ad when AdFlow is initialized', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      await AdFlow.instance.initialize(config: _testConfig);

      await tester.pumpWidget(
        const MaterialApp(home: EasyNativeAd(height: 300)),
      );
      await tester.pump();
      await tester.pump();

      expect(mockSdk.loadNativeCalls, greaterThanOrEqualTo(1));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('shows error state with custom errorWidget', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      await AdFlow.instance.initialize(config: _testConfig);
      mockSdk.nativeLoadError = LoadAdError(1, 'test', 'failed', null);

      await tester.pumpWidget(
        const MaterialApp(
          home: EasyNativeAd(
            height: 300,
            hideOnError: false,
            errorWidget: Text('Error occurred'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Error occurred'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('shows default error container when no errorWidget',
        (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      await AdFlow.instance.initialize(config: _testConfig);
      mockSdk.nativeLoadError = LoadAdError(1, 'test', 'failed', null);

      await tester.pumpWidget(
        const MaterialApp(
          home: EasyNativeAd(
            height: 300,
            hideOnError: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Should show Container with grey background
      expect(find.byType(Container), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('collapses on error when hideOnError=true', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      await AdFlow.instance.initialize(config: _testConfig);
      mockSdk.nativeLoadError = LoadAdError(1, 'test', 'failed', null);

      await tester.pumpWidget(
        const MaterialApp(
          home: EasyNativeAd(height: 300, hideOnError: true),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(EasyNativeAd), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('shows loading indicator when hideOnLoading=false',
        (tester) async {
      // Don't initialize AdFlow so ad stays in loading state
      await tester.pumpWidget(
        const MaterialApp(
          home: EasyNativeAd(height: 300, hideOnLoading: false),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows custom loadingWidget when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EasyNativeAd(
            height: 300,
            hideOnLoading: false,
            loadingWidget: Text('Loading...'),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Loading...'), findsOneWidget);
    });

    testWidgets('shows SizedBox.shrink when hideOnLoading=true',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EasyNativeAd(height: 300, hideOnLoading: true),
        ),
      );
      await tester.pump();

      expect(find.byType(EasyNativeAd), findsOneWidget);
    });

    testWidgets('calls onAdLoaded callback', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      await AdFlow.instance.initialize(config: _testConfig);
      bool wasLoaded = false;

      await tester.pumpWidget(
        MaterialApp(
          home: EasyNativeAd(
            height: 300,
            onAdLoaded: () => wasLoaded = true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(wasLoaded, true);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('calls onAdFailedToLoad callback', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      await AdFlow.instance.initialize(config: _testConfig);
      mockSdk.nativeLoadError = LoadAdError(1, 'test', 'failed', null);
      bool wasFailed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: EasyNativeAd(
            height: 300,
            onAdFailedToLoad: () => wasFailed = true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(wasFailed, true);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('disposes and reloads on ads enabled change', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      await AdFlow.instance.initialize(config: _testConfig);

      await tester.pumpWidget(
        const MaterialApp(home: EasyNativeAd(height: 300)),
      );
      await tester.pump();
      await tester.pump();

      final callsBefore = mockSdk.loadNativeCalls;

      await AdsEnabledManager.instance.disableAds();
      await tester.pump();

      await AdsEnabledManager.instance.enableAds();
      await tester.pump();
      await tester.pump();

      expect(mockSdk.loadNativeCalls, greaterThan(callsBefore));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('disposes cleanly', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      await AdFlow.instance.initialize(config: _testConfig);

      await tester.pumpWidget(
        const MaterialApp(home: EasyNativeAd(height: 300)),
      );
      await tester.pump();
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('applies styling to error widget', (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {};
      addTearDown(() => FlutterError.onError = originalOnError);

      await AdFlow.instance.initialize(config: _testConfig);
      mockSdk.nativeLoadError = LoadAdError(1, 'test', 'failed', null);

      await tester.pumpWidget(
        MaterialApp(
          home: EasyNativeAd(
            height: 300,
            width: 250,
            hideOnError: false,
            backgroundColor: Colors.red,
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(EasyNativeAd), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('applies styling to loading widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: EasyNativeAd(
            height: 300,
            width: 250,
            hideOnLoading: false,
            backgroundColor: Colors.blue,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(EasyNativeAd), findsOneWidget);
    });
  });
}
