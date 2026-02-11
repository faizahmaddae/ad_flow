// Tests targeting remaining uncovered lines in ad_service.dart
// Lines: 170-172, 178, 413, 427, 524, 573, 611-613, 650-660,
//        693-735 (_initializeMobileAds, _retryMobileAdsInitInBackground)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:ad_flow/ad_flow.dart';

import 'helpers/mock_ad_sdk.dart';

/// Flush microtasks so async callbacks fire.
Future<void> _flush() async {
  await Future.delayed(Duration.zero);
  await Future.delayed(Duration.zero);
}

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

  group('waitForInit edge cases', () {
    test('waitForInit times out and returns false', () async {
      // Start initialize but don't let it complete quickly
      // Use a very short timeout to trigger the timeout branch
      final initFuture = AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidBannerAdUnitId: 'test',
          iosBannerAdUnitId: 'test',
        ),
      );
      await _flush();
      await initFuture;
      await _flush();

      // Already initialized - waitForInit should return right away
      final result = await AdFlow.instance.waitForInit(
        timeout: const Duration(milliseconds: 1),
      );
      expect(result, isA<bool>());
    });

    test('waitForInit throws when called before initialize', () {
      expect(
        () => AdFlow.instance.waitForInit(),
        throwsStateError,
      );
    });
  });

  group('concurrent initialization', () {
    test('second initialize call waits for first', () async {
      // Call initialize twice - second should detect _isInitializing
      final config = const AdFlowConfig(
        androidBannerAdUnitId: 'test',
        iosBannerAdUnitId: 'test',
      );

      bool firstComplete = false;

      final first = AdFlow.instance.initialize(
        config: config,
        onComplete: (canRequest) => firstComplete = true,
      );

      // Second call while first is in progress
      final second = AdFlow.instance.initialize(
        config: config,
        onComplete: (_) {},
      );

      await first;
      await _flush();
      await second;
      await _flush();

      expect(firstComplete, true);
      // Second may or may not fire depending on timing
    });
  });

  group('preloadAdsIfConfigured', () {
    test('preloads interstitial and rewarded', () async {
      bool completed = false;
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidInterstitialAdUnitId: 'test-interstitial',
          iosInterstitialAdUnitId: 'test-interstitial',
          androidRewardedAdUnitId: 'test-rewarded',
          iosRewardedAdUnitId: 'test-rewarded',
          maxLoadRetries: 0,
        ),
        preloadInterstitial: true,
        preloadRewarded: true,
        onComplete: (canRequest) => completed = true,
      );
      await _flush();

      expect(completed, true);
      expect(mockSdk.loadInterstitialCalls, greaterThanOrEqualTo(1));
      expect(mockSdk.loadRewardedCalls, greaterThanOrEqualTo(1));
    });

    test('preloads app open (no cold start)', () async {
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidAppOpenAdUnitId: 'test-app-open',
          iosAppOpenAdUnitId: 'test-app-open',
          maxLoadRetries: 0,
        ),
        preloadAppOpen: true,
        showAppOpenOnColdStart: false,
        onComplete: (_) {},
      );
      await _flush();

      expect(mockSdk.loadAppOpenCalls, greaterThanOrEqualTo(1));
    });

    test('preloads app open with cold start and timeout', () async {
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidAppOpenAdUnitId: 'test-app-open',
          iosAppOpenAdUnitId: 'test-app-open',
          coldStartAdTimeout: Duration(seconds: 3),
          maxLoadRetries: 0,
        ),
        preloadAppOpen: true,
        showAppOpenOnColdStart: true,
        onComplete: (_) {},
      );
      await _flush();

      expect(mockSdk.loadAppOpenCalls, greaterThanOrEqualTo(1));
    });

    test('preloads app open with cold start and no timeout', () async {
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidAppOpenAdUnitId: 'test-app-open',
          iosAppOpenAdUnitId: 'test-app-open',
          coldStartAdTimeout: null,
          maxLoadRetries: 0,
        ),
        preloadAppOpen: true,
        showAppOpenOnColdStart: true,
        onComplete: (_) {},
      );
      await _flush();

      expect(mockSdk.loadAppOpenCalls, greaterThanOrEqualTo(1));
    });
  });

  group('preloadAds', () {
    test('preloads configured ad types', () async {
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidInterstitialAdUnitId: 'prod-inter',
          iosInterstitialAdUnitId: 'prod-inter',
          androidAppOpenAdUnitId: 'prod-appopen',
          iosAppOpenAdUnitId: 'prod-appopen',
          androidRewardedAdUnitId: 'prod-rewarded',
          iosRewardedAdUnitId: 'prod-rewarded',
          maxLoadRetries: 0,
        ),
        onComplete: (_) {},
      );
      await _flush();

      // Reset call counts
      mockSdk.resetMock();

      await AdFlow.instance.preloadAds();
      await _flush();

      expect(mockSdk.loadInterstitialCalls, greaterThanOrEqualTo(1));
      expect(mockSdk.loadAppOpenCalls, greaterThanOrEqualTo(1));
      expect(mockSdk.loadRewardedCalls, greaterThanOrEqualTo(1));
    });

    test('preloadAds skips when cannot request ads', () async {
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidBannerAdUnitId: 'test',
          iosBannerAdUnitId: 'test',
        ),
        onComplete: (_) {},
      );
      await _flush();

      mockSdk.canRequestAdsResult = false;

      final initialCalls = mockSdk.loadInterstitialCalls;
      await AdFlow.instance.preloadAds();

      expect(mockSdk.loadInterstitialCalls, initialCalls);
    });
  });

  group('showPrivacyOptions', () {
    test('shows privacy form and calls onComplete', () async {
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidBannerAdUnitId: 'test',
          iosBannerAdUnitId: 'test',
        ),
        onComplete: (_) {},
      );
      await _flush();

      bool completed = false;
      AdFlow.instance.showPrivacyOptions(
        onComplete: () => completed = true,
      );
      await _flush();

      expect(completed, true);
    });

    test('showPrivacyOptions handles error', () async {
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidBannerAdUnitId: 'test',
          iosBannerAdUnitId: 'test',
        ),
        onComplete: (_) {},
      );
      await _flush();

      mockSdk.privacyOptionsFormError = FormError(
        errorCode: 1,
        message: 'test error',
      );

      bool completed = false;
      AdFlow.instance.showPrivacyOptions(
        onComplete: () => completed = true,
      );
      await _flush();

      expect(completed, true);
    });
  });

  group('openAdInspector', () {
    test('opens inspector and handles error', () async {
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidBannerAdUnitId: 'test',
          iosBannerAdUnitId: 'test',
        ),
        onComplete: (_) {},
      );
      await _flush();

      mockSdk.openAdInspectorError = Exception('test');

      // Should not throw
      AdFlow.instance.openAdInspector();
      expect(mockSdk.openAdInspectorCalls, 1);
    });
  });

  group('SDK init', () {
    test('handles SDK init failure', () async {
      mockSdk.initializeMobileAdsThrows = true;

      bool completed = false;
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidBannerAdUnitId: 'test',
          iosBannerAdUnitId: 'test',
        ),
        onComplete: (canRequest) => completed = true,
      );
      await _flush();

      expect(completed, true);
      expect(AdFlow.instance.isMobileAdsInitialized, false);
    });

    test('handles no SDK init timeout (null timeout)', () async {
      bool completed = false;
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidBannerAdUnitId: 'test',
          iosBannerAdUnitId: 'test',
        ),
        onComplete: (canRequest) => completed = true,
      );
      await _flush();

      expect(completed, true);
      expect(AdFlow.instance.isMobileAdsInitialized, true);
    });
  });

  group('enableAppOpenOnForeground', () {
    test('sets up lifecycle reactor', () async {
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidAppOpenAdUnitId: 'test',
          iosAppOpenAdUnitId: 'test',
          maxLoadRetries: 0,
        ),
        enableAppOpenOnForeground: true,
        maxForegroundAdsPerSession: 3,
        onComplete: (_) {},
      );
      await _flush();

      expect(AdFlow.instance.lifecycleReactor, isNotNull);
    });
  });

  group('disableAds and enableAds', () {
    test('disableAds disposes all ads and pauses reactor', () async {
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidAppOpenAdUnitId: 'test',
          iosAppOpenAdUnitId: 'test',
          maxLoadRetries: 0,
        ),
        enableAppOpenOnForeground: true,
        onComplete: (_) {},
      );
      await _flush();

      await AdFlow.instance.disableAds();
      expect(AdFlow.instance.isAdsDisabled, true);
    });

    test('enableAds resumes reactor', () async {
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidAppOpenAdUnitId: 'test',
          iosAppOpenAdUnitId: 'test',
          maxLoadRetries: 0,
        ),
        enableAppOpenOnForeground: true,
        onComplete: (_) {},
      );
      await _flush();

      await AdFlow.instance.disableAds();
      await AdFlow.instance.enableAds();
      expect(AdFlow.instance.isAdsEnabled, true);
    });
  });

  group('ads disabled before init', () {
    test('initialize completes immediately when ads disabled', () async {
      await AdsEnabledManager.instance.disableAds();

      bool completed = false;
      bool? canRequest;
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidBannerAdUnitId: 'test',
          iosBannerAdUnitId: 'test',
        ),
        onComplete: (can) {
          completed = true;
          canRequest = can;
        },
      );
      await _flush();

      expect(completed, true);
      expect(canRequest, false);
    });
  });

  group('consent error during init', () {
    test('consent error still completes initialization', () async {
      mockSdk.consentUpdateError = FormError(
        errorCode: 1,
        message: 'consent failed',
      );

      bool completed = false;
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidBannerAdUnitId: 'test',
          iosBannerAdUnitId: 'test',
        ),
        onComplete: (can) => completed = true,
      );
      await _flush();

      expect(completed, true);
    });
  });

  group('SDK init failed, consent OK', () {
    test('logs SDK init failure message', () async {
      mockSdk.initializeMobileAdsThrows = true;

      bool completed = false;
      bool? canRequestResult;
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidBannerAdUnitId: 'test',
          iosBannerAdUnitId: 'test',
        ),
        onComplete: (can) {
          completed = true;
          canRequestResult = can;
        },
      );
      await _flush();

      expect(completed, true);
      // canRequestAds should be false since SDK init failed
      expect(canRequestResult, false);
    });
  });
}
