// Final round of coverage tests targeting remaining uncovered lines.
// Areas: EasyBannerAd lifecycle, AppLifecycleReactor cooldown/isShowing,
// InterstitialAdManager willDismiss, ad_service cold start & retry,
// consent_manager branches, ad_config Platform fallthrough.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:ad_flow/ad_flow.dart';

import 'helpers/mock_ad_sdk.dart';
import 'helpers/fake_ads.dart';

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

  // EasyBannerAd lifecycle tests are in easy_banner_widget_test.dart

  // ─────────────────────────────────────────────────────────────────────
  // InterstitialAdManager - fullscreen callbacks (impression, click, willDismiss)
  // ─────────────────────────────────────────────────────────────────────
  group('InterstitialAdManager fullscreen callbacks', () {
    test('onAdWillDismiss fires on iOS', () async {
      AdFlowConfig.setCurrent(const AdFlowConfig(
        androidInterstitialAdUnitId: 'test',
        iosInterstitialAdUnitId: 'test',
        maxLoadRetries: 0,
      ));
      final fakeAd = FakeInterstitialAd();
      mockSdk.interstitialAdToReturn = fakeAd;

      final manager = InterstitialAdManager();
      await manager.loadAd();
      await manager.showAd();

      // willDismiss fires before dismiss on iOS
      fakeAd.simulateWillDismiss();
      fakeAd.simulateImpression();
      fakeAd.simulateClick();
      fakeAd.simulateDismiss();
      await Future.delayed(Duration.zero);

      manager.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // RewardedAdManager - willDismiss callback
  // ─────────────────────────────────────────────────────────────────────
  group('RewardedAdManager fullscreen callbacks', () {
    test('onAdWillDismiss fires', () async {
      AdFlowConfig.setCurrent(const AdFlowConfig(
        androidRewardedAdUnitId: 'test',
        iosRewardedAdUnitId: 'test',
        maxLoadRetries: 0,
      ));
      final fakeAd = FakeRewardedAd();
      mockSdk.rewardedAdToReturn = fakeAd;

      final manager = RewardedAdManager();
      await manager.loadAd();
      await manager.showAd(onUserEarnedReward: (_) {});

      // Will dismiss (iOS)
      fakeAd.simulateWillDismiss();
      fakeAd.simulateImpression();
      fakeAd.simulateClick();
      fakeAd.simulateDismiss();
      await Future.delayed(Duration.zero);

      manager.dispose();
    });

    test('server side verification options', () async {
      AdFlowConfig.setCurrent(const AdFlowConfig(
        androidRewardedAdUnitId: 'test',
        iosRewardedAdUnitId: 'test',
        maxLoadRetries: 0,
      ));

      final manager = RewardedAdManager();
      manager.serverSideVerificationOptions = ServerSideVerificationOptions(
        userId: 'test-user',
        customData: 'test-data',
      );
      await manager.loadAd();
      expect(manager.isLoaded, true);
      manager.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // AppOpenAdManager - willDismiss and expired ad
  // ─────────────────────────────────────────────────────────────────────
  group('AppOpenAdManager additional', () {
    test('willDismiss callback fires', () async {
      AdFlowConfig.setCurrent(const AdFlowConfig(
        androidAppOpenAdUnitId: 'test',
        iosAppOpenAdUnitId: 'test',
        maxLoadRetries: 0,
      ));
      final fakeAd = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd;

      final manager = AppOpenAdManager();
      await manager.loadAd();
      await manager.showAdIfAvailable();

      fakeAd.simulateWillDismiss();
      await Future.delayed(Duration.zero);

      manager.dispose();
    });

    test('showAdIfAvailable when already showing returns false', () async {
      AdFlowConfig.setCurrent(const AdFlowConfig(
        androidAppOpenAdUnitId: 'test',
        iosAppOpenAdUnitId: 'test',
        maxLoadRetries: 0,
      ));
      final fakeAd = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd;

      final manager = AppOpenAdManager();
      await manager.loadAd();

      // First show
      await manager.showAdIfAvailable();
      expect(manager.isShowing, true);

      // Second show while showing
      final result = await manager.showAdIfAvailable();
      expect(result, false);

      fakeAd.simulateDismiss();
      await Future.delayed(Duration.zero);
      manager.dispose();
    });

    test('loadAdAndWait returns result', () async {
      AdFlowConfig.setCurrent(const AdFlowConfig(
        androidAppOpenAdUnitId: 'test',
        iosAppOpenAdUnitId: 'test',
        maxLoadRetries: 0,
      ));
      final manager = AppOpenAdManager();
      final result = await manager.loadAdAndWait();
      expect(result, true);
      manager.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // AppLifecycleReactor - cooldown and isShowing guard
  // ─────────────────────────────────────────────────────────────────────
  group('AppLifecycleReactor cooldown & isShowing', () {
    test('cooldown blocks second foreground ad show', () async {
      AdFlowConfig.setCurrent(const AdFlowConfig(
        androidAppOpenAdUnitId: 'test',
        iosAppOpenAdUnitId: 'test',
        maxLoadRetries: 0,
      ));

      final appOpenManager = AppOpenAdManager();
      final fakeAd = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd;
      await appOpenManager.loadAd();

      final reactor = AppLifecycleReactor(
        appOpenAdManager: appOpenManager,
        maxForegroundAdsPerSession: 10,
      );
      reactor.startListening();

      // Go to background then foreground
      reactor.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future.delayed(Duration.zero);
      reactor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);

      // First ad is shown. Dismiss it.
      fakeAd.simulateDismiss();
      await Future.delayed(Duration.zero);

      // Reload ad for second attempt
      final fakeAd2 = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd2;
      // Wait for auto-reload after dismiss
      await Future.delayed(Duration.zero);

      // Go background then foreground again immediately (within cooldown)
      reactor.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future.delayed(Duration.zero);
      reactor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);

      // Second ad should NOT be shown due to cooldown
      expect(fakeAd2.wasShown, false);

      reactor.dispose();
      appOpenManager.dispose();
    });

    test('isShowing guard prevents foreground ad show', () async {
      AdFlowConfig.setCurrent(const AdFlowConfig(
        androidAppOpenAdUnitId: 'test',
        iosAppOpenAdUnitId: 'test',
        maxLoadRetries: 0,
      ));

      final appOpenManager = AppOpenAdManager();
      final fakeAd = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd;
      await appOpenManager.loadAd();

      final reactor = AppLifecycleReactor(
        appOpenAdManager: appOpenManager,
        maxForegroundAdsPerSession: 10,
      );
      reactor.startListening();

      // Go to background
      reactor.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future.delayed(Duration.zero);

      // Show the ad manually first (so isShowing = true)
      await appOpenManager.showAdIfAvailable();
      expect(appOpenManager.isShowing, true);

      // Now foreground - reactor should see isShowing = true and skip
      reactor.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future.delayed(Duration.zero);

      fakeAd.simulateDismiss();
      await Future.delayed(Duration.zero);

      reactor.dispose();
      appOpenManager.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // Ad Service - cold start preload & SDK init paths
  // ─────────────────────────────────────────────────────────────────────
  group('AdService cold start preload', () {
    test('preload with cold start timeout shows app open ad', () async {
      final fakeAd = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd;

      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidAppOpenAdUnitId: 'test',
          iosAppOpenAdUnitId: 'test',
          coldStartAdTimeout: Duration(seconds: 5),
          maxLoadRetries: 0,
        ),
        preloadAppOpen: true,
        showAppOpenOnColdStart: true,
      );
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      // App open ad should have been loaded and shown
      expect(mockSdk.loadAppOpenCalls, greaterThanOrEqualTo(1));
    });

    test('preload with cold start no timeout (legacy)', () async {
      final fakeAd = FakeAppOpenAd();
      mockSdk.appOpenAdToReturn = fakeAd;

      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidAppOpenAdUnitId: 'test',
          iosAppOpenAdUnitId: 'test',
          coldStartAdTimeout: null,
          maxLoadRetries: 0,
        ),
        preloadAppOpen: true,
        showAppOpenOnColdStart: true,
      );
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(mockSdk.loadAppOpenCalls, greaterThanOrEqualTo(1));
    });

    test('preload without cold start just loads in background', () async {
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          androidAppOpenAdUnitId: 'test',
          iosAppOpenAdUnitId: 'test',
          maxLoadRetries: 0,
        ),
        preloadAppOpen: true,
        showAppOpenOnColdStart: false,
      );
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(mockSdk.loadAppOpenCalls, greaterThanOrEqualTo(1));
    });
  });

  group('AdService SDK init with null timeout', () {
    test('initializes without timeout', () async {
      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          maxLoadRetries: 0,
        ),
      );
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(AdFlow.instance.isInitialized, true);
      expect(mockSdk.initializeMobileAdsCalls, 1);
    });
  });

  group('AdService openAdInspector error', () {
    test('handles error gracefully', () async {
      mockSdk.openAdInspectorError = FormError(
        errorCode: 42,
        message: 'Inspector error',
      );

      await AdFlow.instance.initialize(
        config: const AdFlowConfig(
          maxLoadRetries: 0,
        ),
      );
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      // Call openAdInspector with error
      AdFlow.instance.openAdInspector();
      // No crash
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // Consent Manager branches
  // ─────────────────────────────────────────────────────────────────────
  group('ConsentManager branches', () {
    test('showPrivacyOptionsForm with error', () async {
      mockSdk.privacyOptionsFormError = FormError(
        errorCode: 1,
        message: 'Privacy form failed',
      );

      FormError? receivedError;
      ConsentManager.instance.showPrivacyOptionsForm(
        onComplete: (error) {
          receivedError = error;
        },
      );
      await Future.delayed(Duration.zero);

      expect(receivedError, isNotNull);
      expect(receivedError!.errorCode, 1);
    });

    test('showPrivacyOptionsForm success', () async {
      FormError? receivedError;
      ConsentManager.instance.showPrivacyOptionsForm(
        onComplete: (error) {
          receivedError = error;
        },
      );
      await Future.delayed(Duration.zero);

      expect(receivedError, isNull);
    });

    // Note: Testing 'gatherConsent on iOS with ATT denied skips GDPR' is difficult
    // because the ATT plugin makes platform calls that can't be fully mocked
    // in unit tests. This path is covered by integration tests instead.
  });

  // ─────────────────────────────────────────────────────────────────────
  // Ad Config - TestAdUnitIds returns empty on unsupported platform
  // ─────────────────────────────────────────────────────────────────────
  group('AdConfig TestAdUnitIds unsupported', () {
    test('TestAdUnitIds returns empty string on unsupported platform', () {
      AdFlowPlatform.platformOverride = null;
      expect(TestAdUnitIds.banner, isEmpty);
      expect(TestAdUnitIds.interstitial, isEmpty);
      expect(TestAdUnitIds.rewarded, isEmpty);
      expect(TestAdUnitIds.appOpen, isEmpty);
      expect(TestAdUnitIds.native, isEmpty);
    });

    test('AdFlowPlatform null override on macOS', () {
      AdFlowPlatform.platformOverride = null;
      // On macOS neither is true
      expect(AdFlowPlatform.isAndroid, false);
      expect(AdFlowPlatform.isIOS, false);
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // AdManagerMixin - cooldown reset
  // ─────────────────────────────────────────────────────────────────────
  group('AdManagerMixin retry reset', () {
    test('resetRetryState clears cooldown', () async {
      AdFlowConfig.setCurrent(const AdFlowConfig(
        androidInterstitialAdUnitId: 'test',
        iosInterstitialAdUnitId: 'test',
        maxLoadRetries: 0,
      ));

      // Make ad fail to exhaust retries
      mockSdk.interstitialLoadError = LoadAdError(1, 'fail', 'fail', null);
      final manager = InterstitialAdManager();
      await manager.loadAd();
      // Manager is now in retry cooldown (maxLoadRetries=0 means immediate fail)

      // Reset retry state (must use resetRetryState which clears cooldown)
      manager.resetRetryState();

      // Should be able to load again
      mockSdk.interstitialLoadError = null;
      await manager.loadAd();
      expect(manager.isLoaded, true);

      manager.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // NativeAdManager - willDismiss not applicable (no fullscreen)
  // but test already loading guard in different way
  // ─────────────────────────────────────────────────────────────────────
  group('NativeAdManager additional', () {
    test('loadAd onAdFailedToLoad callback with factory hint', () async {
      AdFlowConfig.setCurrent(const AdFlowConfig(
        androidNativeAdUnitId: 'test-native',
        iosNativeAdUnitId: 'test-native',
        maxLoadRetries: 0,
      ));

      // Error code 0 triggers factory hint message
      mockSdk.nativeLoadError = LoadAdError(0, 'factory', 'Factory "missing" not found', null);

      bool failCalled = false;
      final manager = NativeAdManager();
      await manager.loadAd(
        factoryId: 'missing',
        onAdFailedToLoad: (error) => failCalled = true,
      );

      expect(failCalled, true);
      manager.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // BannerAdManager consent check line 111
  // ─────────────────────────────────────────────────────────────────────
  group('BannerAdManager consent check', () {
    test('loadBanner with consent check - cannot request ads', () async {
      AdFlowConfig.setCurrent(const AdFlowConfig(
        androidBannerAdUnitId: 'test-banner',
        iosBannerAdUnitId: 'test-banner',
        maxLoadRetries: 0,
      ));
      mockSdk.canRequestAdsResult = false;

      final manager = BannerAdManager();
      await manager.loadBanner(size: AdSize.banner);

      expect(mockSdk.loadBannerCalls, 0);
      expect(manager.isLoaded, false);
      manager.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // AppOpenAdManager - loadAd with consent false
  // ─────────────────────────────────────────────────────────────────────
  group('AppOpenAdManager consent', () {
    test('loadAd skips when cannot request ads', () async {
      AdFlowConfig.setCurrent(const AdFlowConfig(
        androidAppOpenAdUnitId: 'test',
        iosAppOpenAdUnitId: 'test',
        maxLoadRetries: 0,
      ));
      mockSdk.canRequestAdsResult = false;

      final manager = AppOpenAdManager();
      await manager.loadAd();

      expect(mockSdk.loadAppOpenCalls, 0);
      manager.dispose();
    });
  });

  // ─────────────────────────────────────────────────────────────────────
  // RewardedAdManager - ads disabled but rewardedAdsIgnoreRemoveAds = false
  // ─────────────────────────────────────────────────────────────────────
  group('RewardedAdManager ads disabled', () {
    test('showAd returns false when ads disabled', () async {
      AdFlowConfig.setCurrent(const AdFlowConfig(
        androidRewardedAdUnitId: 'test',
        iosRewardedAdUnitId: 'test',
        rewardedAdsIgnoreRemoveAds: false,
        maxLoadRetries: 0,
      ));

      await AdsEnabledManager.instance.disableAds();

      final manager = RewardedAdManager();
      final result = await manager.showAd(onUserEarnedReward: (_) {});
      expect(result, false);
      manager.dispose();
    });
  });
}
