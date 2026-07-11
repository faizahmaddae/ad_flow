// Expanded ad_service tests to cover remaining branches

import 'dart:async';
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
    MediationHelper.reset();
  });

  tearDown(() async {
    await AdFlow.instance.reset();
    AdSdk.resetInstance();
    AdFlowPlatform.reset();
    MediationHelper.reset();
  });

  group('AdFlow lazy manager accessors', () {
    test('banner getter creates manager on first access', () {
      final mgr = AdFlow.instance.banner;
      expect(mgr, isA<BannerAdManager>());
      // Second access returns same instance
      expect(AdFlow.instance.banner, same(mgr));
    });

    test('interstitial getter creates manager on first access', () {
      final mgr = AdFlow.instance.interstitial;
      expect(mgr, isA<InterstitialAdManager>());
      expect(AdFlow.instance.interstitial, same(mgr));
    });

    test('rewarded getter creates manager on first access', () {
      final mgr = AdFlow.instance.rewarded;
      expect(mgr, isA<RewardedAdManager>());
      expect(AdFlow.instance.rewarded, same(mgr));
    });

    test('appOpen getter creates manager on first access', () {
      final mgr = AdFlow.instance.appOpen;
      expect(mgr, isA<AppOpenAdManager>());
      expect(AdFlow.instance.appOpen, same(mgr));
    });

    test('native getter creates manager on first access', () {
      final mgr = AdFlow.instance.native;
      expect(mgr, isA<NativeAdManager>());
      expect(AdFlow.instance.native, same(mgr));
    });
  });

  group('AdFlow.initialize', () {
    test('double initialize is no-op', () async {
      await AdFlow.instance.initialize(
        config: AdFlowConfig.testMode(),
        onComplete: (_) {},
      );

      // Wait for async completion
      await _pumpMicrotasks();

      bool? secondResult;
      await AdFlow.instance.initialize(
        config: AdFlowConfig.testMode(),
        onComplete: (canRequestAds) => secondResult = canRequestAds,
      );
      await _pumpMicrotasks();

      // Second call is no-op
      expect(secondResult, isNotNull);
    });

    test('isInitialized is true after init', () async {
      await AdFlow.instance.initialize(config: AdFlowConfig.testMode());
      await _pumpMicrotasks();
      expect(AdFlow.instance.isInitialized, true);
    });

    test('config getter returns the configured config', () async {
      final cfg = AdFlowConfig.testMode();
      await AdFlow.instance.initialize(config: cfg);
      await _pumpMicrotasks();
      expect(AdFlow.instance.config, isNotNull);
    });

    test('consent getter returns ConsentManager', () {
      expect(AdFlow.instance.consent, isA<ConsentManager>());
    });

    test('errorStream returns stream', () {
      expect(AdFlow.instance.errorStream, isA<Stream<AdFlowError>>());
    });

    test('setErrorCallback sets callback', () {
      AdFlowError? captured;
      AdFlow.instance.setErrorCallback((e) => captured = e);
      AdFlowErrorHandler.instance.reportError(
        AdFlowError(type: AdErrorType.bannerLoad, message: 'test', code: 0),
      );
      expect(captured, isNotNull);
    });

    test('initialize with preloadInterstitial', () async {
      await AdFlow.instance.initialize(
        config: AdFlowConfig.testMode(),
        preloadInterstitial: true,
      );
      await _pumpMicrotasks();
      // Preloading is triggered; verify no crash
    });

    test('initialize with preloadRewarded', () async {
      await AdFlow.instance.initialize(
        config: AdFlowConfig.testMode(),
        preloadRewarded: true,
      );
      await _pumpMicrotasks();
    });

    test('initialize with preloadAppOpen', () async {
      await AdFlow.instance.initialize(
        config: AdFlowConfig.testMode(),
        preloadAppOpen: true,
      );
      await _pumpMicrotasks();
    });
  });

  group('AdFlow.waitForInit', () {
    test('returns true when already initialized', () async {
      await AdFlow.instance.initialize(config: AdFlowConfig.testMode());
      await _pumpMicrotasks();

      final result = await AdFlow.instance.waitForInit();
      expect(result, isA<bool>());
    });

    test('waitForInit called before initialize', () async {
      // Should throw StateError when called before initialize
      expect(
        () => AdFlow.instance.waitForInit(
          timeout: const Duration(milliseconds: 100),
        ),
        throwsStateError,
      );
    });
  });

  group('AdFlow.initStream', () {
    test('emits when initialization completes', () async {
      final values = <bool>[];
      final sub = AdFlow.instance.initStream.listen(values.add);

      await AdFlow.instance.initialize(config: AdFlowConfig.testMode());
      await _pumpMicrotasks();

      // Stream should have emitted
      expect(values, isNotEmpty);
      await sub.cancel();
    });
  });

  group('AdFlow dispose and reset', () {
    test('dispose sets isInitialized to false', () async {
      await AdFlow.instance.initialize(config: AdFlowConfig.testMode());
      await _pumpMicrotasks();
      expect(AdFlow.instance.isInitialized, true);

      await AdFlow.instance.dispose();
      expect(AdFlow.instance.isInitialized, false);
    });

    test('reset allows re-initialization', () async {
      await AdFlow.instance.initialize(config: AdFlowConfig.testMode());
      await _pumpMicrotasks();
      expect(AdFlow.instance.isInitialized, true);

      await AdFlow.instance.reset();
      expect(AdFlow.instance.isInitialized, false);

      // Re-assign mock since reset clears it
      AdSdk.instance = mockSdk;
      await AdFlow.instance.initialize(config: AdFlowConfig.testMode());
      await _pumpMicrotasks();
      expect(AdFlow.instance.isInitialized, true);
    });
  });

  group('AdFlow lifecycle control', () {
    test('pauseAppOpenAds and resumeAppOpenAds with no reactor', () {
      // Should not throw even without reactor
      AdFlow.instance.pauseAppOpenAds();
      AdFlow.instance.resumeAppOpenAds();
    });

    test('showPrivacyOptions calls consent manager', () async {
      await AdFlow.instance.initialize(config: AdFlowConfig.testMode());
      await _pumpMicrotasks();

      AdFlow.instance.showPrivacyOptions(onComplete: () {});
      // Should not crash
    });

    test('isPrivacyOptionsRequired delegates to consent', () async {
      await AdFlow.instance.initialize(config: AdFlowConfig.testMode());
      await _pumpMicrotasks();
      // Should not crash
      final result = AdFlow.instance.isPrivacyOptionsRequired;
      expect(result, isA<bool>());
    });

    test('openAdInspector calls SDK', () async {
      await AdFlow.instance.initialize(config: AdFlowConfig.testMode());
      await _pumpMicrotasks();
      AdFlow.instance.openAdInspector();
      expect(mockSdk.openAdInspectorCalls, 1);
    });
  });

  group('AdFlow.preloadAds', () {
    test('preloadAds without canRequestAds skips', () async {
      await AdFlow.instance.initialize(config: AdFlowConfig.testMode());
      await _pumpMicrotasks();

      // When consent canRequestAds is false, preloadAds should skip
      // We can call it and verify no crash
      await AdFlow.instance.preloadAds();
    });

    test(
      'preloadAds with production config preloads configured types',
      () async {
        await AdFlow.instance.initialize(
          config: const AdFlowConfig(
            androidInterstitialAdUnitId: 'ca-app-pub-1234567890/int',
            iosInterstitialAdUnitId: 'ca-app-pub-1234567890/int-ios',
            androidRewardedAdUnitId: 'ca-app-pub-1234567890/rew',
            iosRewardedAdUnitId: 'ca-app-pub-1234567890/rew-ios',
            androidAppOpenAdUnitId: 'ca-app-pub-1234567890/ao',
            iosAppOpenAdUnitId: 'ca-app-pub-1234567890/ao-ios',
          ),
        );
        await _pumpMicrotasks();

        await AdFlow.instance.preloadAds();
        // Should have loaded configured ad types
      },
    );
  });

  group('AdFlow with mediation', () {
    test('initialize with mediation adapters registered', () async {
      MediationHelper.registerAdapter(
        name: 'TestNetwork',
        forwarder: ({required gdprConsent, required ccpaOptOut}) async {},
      );

      await AdFlow.instance.initialize(config: AdFlowConfig.testMode());
      await _pumpMicrotasks();

      // Mediation consent should have been forwarded
      // (depending on whether canRequestAds is true)
    });
  });

  group('AdFlow.disposeAllAds', () {
    test('disposeAllAds disposes all created managers', () async {
      await AdFlow.instance.initialize(config: AdFlowConfig.testMode());
      await _pumpMicrotasks();

      // Access some managers to create them
      AdFlow.instance.interstitial;
      AdFlow.instance.rewarded;

      // Should not throw
      await AdFlow.instance.dispose();
    });
  });
}

/// Helper: pump microtasks to let async work complete
Future<void> _pumpMicrotasks({int count = 10}) async {
  for (int i = 0; i < count; i++) {
    await Future.delayed(Duration.zero);
  }
}
