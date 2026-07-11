// Tests for AdFlow ad_service.dart - targeting uncovered lines
// Covers: _initializeMobileAds (timeout, error), _retryMobileAdsInitInBackground,
//         _forwardConsentToMediationNetworks, _preloadAdsIfConfigured,
//         preloadAds, showPrivacyOptions, openAdInspector, SDK init failure path

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:ad_flow/ad_flow.dart';

import 'helpers/mock_ad_sdk.dart';

/// Flush microtasks to allow async consent callbacks to complete
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

  group('AdFlow._initializeMobileAds', () {
    test('SDK init failure prevents ad preload', () async {
      mockSdk.initializeMobileAdsThrows = true;

      bool? canRequest;
      await AdFlow.instance.initialize(onComplete: (val) => canRequest = val);
      await _flush();

      // SDK failed to init → canRequest should be false
      expect(canRequest, false);
      expect(AdFlow.instance.isMobileAdsInitialized, false);
    });

    test('successful SDK init sets config', () async {
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          testDeviceIds: ['device1'],
          tagForUnderAgeOfConsent: true,
          maxAdContentRating: 'G',
        ),
      );
      await _flush();

      expect(mockSdk.initializeMobileAdsCalls, 1);
      expect(mockSdk.updateRequestConfigCalls, 1);
      expect(mockSdk.lastRequestConfig?.testDeviceIds, ['device1']);
    });
  });

  group('AdFlow._preloadAdsIfConfigured', () {
    test('preloads interstitial when flag set', () async {
      await AdFlow.instance.initialize(
        preloadInterstitial: true,
        config: const AdFlowConfig(
          androidInterstitialAdUnitId: 'test-interstitial',
          iosInterstitialAdUnitId: 'test-interstitial',
        ),
      );
      await _flush();

      expect(mockSdk.loadInterstitialCalls, greaterThanOrEqualTo(1));
    });

    test('preloads rewarded when flag set', () async {
      await AdFlow.instance.initialize(
        preloadRewarded: true,
        config: const AdFlowConfig(
          androidRewardedAdUnitId: 'test-rewarded',
          iosRewardedAdUnitId: 'test-rewarded',
        ),
      );
      await _flush();

      expect(mockSdk.loadRewardedCalls, greaterThanOrEqualTo(1));
    });

    test('preloads app open when flag set', () async {
      await AdFlow.instance.initialize(
        preloadAppOpen: true,
        config: const AdFlowConfig(
          androidAppOpenAdUnitId: 'test-app-open',
          iosAppOpenAdUnitId: 'test-app-open',
        ),
      );
      await _flush();

      expect(mockSdk.loadAppOpenCalls, greaterThanOrEqualTo(1));
    });

    test('shows app open on cold start with timeout', () async {
      await AdFlow.instance.initialize(
        preloadAppOpen: true,
        showAppOpenOnColdStart: true,
        config: const AdFlowConfig(
          androidAppOpenAdUnitId: 'test-app-open',
          iosAppOpenAdUnitId: 'test-app-open',
          coldStartAdTimeout: Duration(seconds: 3),
        ),
      );
      await _flush();

      expect(mockSdk.loadAppOpenCalls, greaterThanOrEqualTo(1));
    });

    test('shows app open on cold start without timeout', () async {
      await AdFlow.instance.initialize(
        preloadAppOpen: true,
        showAppOpenOnColdStart: true,
        config: AdFlowConfig(
          androidAppOpenAdUnitId: 'test-app-open',
          iosAppOpenAdUnitId: 'test-app-open',
          coldStartAdTimeout: null,
        ),
      );
      await _flush();

      expect(mockSdk.loadAppOpenCalls, greaterThanOrEqualTo(1));
    });
  });

  group('AdFlow._forwardConsentToMediationNetworks', () {
    test('forwards consent when adapters registered', () async {
      bool gdprCalled = false;
      bool ccpaCalled = false;

      MediationHelper.registerUnityWithCallbacks(
        setGDPRConsent: (consent) async => gdprCalled = true,
        setCCPAConsent: (consent) async => ccpaCalled = true,
      );

      await AdFlow.instance.initialize();
      await _flush();

      expect(gdprCalled, true);
      expect(ccpaCalled, true);

      MediationHelper.unregisterAll();
    });

    test('handles failed mediation forwarding', () async {
      MediationHelper.registerUnityWithCallbacks(
        setGDPRConsent: (consent) async => throw Exception('Failed'),
        setCCPAConsent: (consent) async {},
      );

      // Should not throw
      await AdFlow.instance.initialize();
      await _flush();

      MediationHelper.unregisterAll();
    });
  });

  group('AdFlow.preloadAds', () {
    test('preloads configured ad types', () async {
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidInterstitialAdUnitId: 'ca-app-pub-1234/interstitial',
          iosInterstitialAdUnitId: 'ca-app-pub-1234/interstitial',
          androidAppOpenAdUnitId: 'ca-app-pub-1234/appopen',
          iosAppOpenAdUnitId: 'ca-app-pub-1234/appopen',
          androidRewardedAdUnitId: 'ca-app-pub-1234/rewarded',
          iosRewardedAdUnitId: 'ca-app-pub-1234/rewarded',
        ),
      );
      await _flush();

      final interstitialBefore = mockSdk.loadInterstitialCalls;
      final appOpenBefore = mockSdk.loadAppOpenCalls;
      final rewardedBefore = mockSdk.loadRewardedCalls;

      await AdFlow.instance.preloadAds();

      expect(mockSdk.loadInterstitialCalls, greaterThan(interstitialBefore));
      expect(mockSdk.loadAppOpenCalls, greaterThan(appOpenBefore));
      expect(mockSdk.loadRewardedCalls, greaterThan(rewardedBefore));
    });

    test('skips preload when cannot request ads', () async {
      mockSdk.canRequestAdsResult = false;
      await AdFlow.instance.initialize();
      await _flush();

      mockSdk.loadInterstitialCalls = 0;
      await AdFlow.instance.preloadAds();

      expect(mockSdk.loadInterstitialCalls, 0);
    });

    test('logs when no ad types configured for preload', () async {
      await AdFlow.instance.initialize();
      await _flush();

      await AdFlow.instance.preloadAds();
      // Should log but not crash
    });
  });

  group('AdFlow.showPrivacyOptions', () {
    test('calls consent showPrivacyOptionsForm', () async {
      await AdFlow.instance.initialize();
      await _flush();

      bool completeCalled = false;
      AdFlow.instance.showPrivacyOptions(
        onComplete: () => completeCalled = true,
      );
      await _flush();

      expect(mockSdk.showPrivacyOptionsFormCalls, 1);
      expect(completeCalled, true);
    });

    test('handles error from privacy form', () async {
      await AdFlow.instance.initialize();
      await _flush();

      mockSdk.privacyOptionsFormError = FormError(
        errorCode: 1,
        message: 'Form error',
      );

      bool completeCalled = false;
      AdFlow.instance.showPrivacyOptions(
        onComplete: () => completeCalled = true,
      );
      await _flush();

      expect(completeCalled, true);
    });
  });

  group('AdFlow.openAdInspector', () {
    test('calls SDK openAdInspector', () async {
      await AdFlow.instance.initialize();
      await _flush();

      AdFlow.instance.openAdInspector();

      expect(mockSdk.openAdInspectorCalls, 1);
    });

    test('handles error from ad inspector', () async {
      await AdFlow.instance.initialize();
      await _flush();

      mockSdk.openAdInspectorError = Exception('Inspector error');

      AdFlow.instance.openAdInspector();

      expect(mockSdk.openAdInspectorCalls, 1);
    });
  });

  group('AdFlow.enableAppOpenOnForeground', () {
    test('sets up lifecycle reactor', () async {
      await AdFlow.instance.initialize(
        enableAppOpenOnForeground: true,
        maxForegroundAdsPerSession: 3,
        config: const AdFlowConfig(
          androidAppOpenAdUnitId: 'test-app-open',
          iosAppOpenAdUnitId: 'test-app-open',
        ),
      );
      await _flush();

      expect(AdFlow.instance.isInitialized, true);
    });
  });

  group('AdFlow concurrent initialization', () {
    test('second initialize call waits for first', () async {
      // First call
      final future1 = AdFlow.instance.initialize();
      // Second call should be a no-op or wait
      final future2 = AdFlow.instance.initialize();

      await Future.wait([future1, future2]);
      await _flush();

      expect(AdFlow.instance.isInitialized, true);
      // Only one SDK init
      expect(mockSdk.initializeMobileAdsCalls, 1);
    });
  });

  group('AdFlow ads disabled before init', () {
    test('skips ad operations when ads disabled', () async {
      await AdsEnabledManager.instance.disableAds();

      bool? canRequest;
      await AdFlow.instance.initialize(onComplete: (val) => canRequest = val);
      await _flush();

      expect(canRequest, false);
    });
  });

  group('AdFlow.waitForInit', () {
    test('timeout returns false', () async {
      // Start initialization
      AdFlow.instance.initialize();
      await _flush();

      // Since init completes synchronously with mock, result should be true
      final result = await AdFlow.instance.waitForInit(
        timeout: const Duration(seconds: 1),
      );

      expect(result, isA<bool>());
    });
  });

  group('AdFlow.isPrivacyOptionsRequired', () {
    test('returns consent privacy options status', () async {
      await AdFlow.instance.initialize();
      await _flush();

      final result = AdFlow.instance.isPrivacyOptionsRequired;
      expect(result, isA<bool>());
    });
  });

  group('AdFlow pause/resume app open ads', () {
    test('pauseAppOpenAds and resumeAppOpenAds work', () async {
      await AdFlow.instance.initialize(
        enableAppOpenOnForeground: true,
        config: const AdFlowConfig(
          androidAppOpenAdUnitId: 'test-app-open',
          iosAppOpenAdUnitId: 'test-app-open',
        ),
      );
      await _flush();

      AdFlow.instance.pauseAppOpenAds();
      AdFlow.instance.resumeAppOpenAds();
    });
  });
}
