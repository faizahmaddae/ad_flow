// Tests for BannerAdManager, InterstitialAdManager, RewardedAdManager
// Targeting remaining uncovered lines in each

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
    mockSdk = MockAdSdk();
    AdSdk.instance = mockSdk;
    AdFlowPlatform.platformOverride = TargetPlatform.android;
  });

  tearDown(() async {
    AdSdk.resetInstance();
    AdFlowPlatform.reset();
  });

  group('BannerAdManager coverage', () {
    late BannerAdManager bannerManager;

    setUp(() {
      AdFlowConfig.setCurrent(const AdFlowConfig(
        androidBannerAdUnitId: 'test-banner',
        iosBannerAdUnitId: 'test-banner',
        maxLoadRetries: 0,
      ));
      bannerManager = BannerAdManager();
    });

    tearDown(() {
      bannerManager.dispose();
    });

    test('loadBanner with onAdLoaded callback', () async {
      bool loaded = false;
      await bannerManager.loadBanner(
        size: AdSize.banner,
        onAdLoaded: (ad) => loaded = true,
      );

      expect(loaded, true);
      expect(bannerManager.isLoaded, true);
    });

    test('loadBanner with onAdFailedToLoad callback', () async {
      mockSdk.bannerLoadError = LoadAdError(1, 'test', 'failed', null);

      bool failed = false;
      await bannerManager.loadBanner(
        size: AdSize.banner,
        onAdFailedToLoad: (ad, error) => failed = true,
      );

      expect(failed, true);
    });

    test('loadBanner skips when ads disabled', () async {
      await AdsEnabledManager.instance.disableAds();

      await bannerManager.loadBanner(size: AdSize.banner);
      expect(mockSdk.loadBannerCalls, 0);
    });

    testWidgets('loadAdaptiveBanner with callbacks', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Builder(builder: (context) {
          // Schedule the load after the build
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            bool loaded = false;
            await bannerManager.loadAdaptiveBanner(
              context: context,
              onAdLoaded: (ad) => loaded = true,
            );
            expect(loaded, true);
          });
          return const SizedBox();
        })),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('loadAdaptiveBanner with null size', (tester) async {
      mockSdk.returnNullAdaptiveSize = true;

      await tester.pumpWidget(
        MaterialApp(home: Builder(builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await bannerManager.loadAdaptiveBanner(
              context: context,
            );
            // When adaptive size is null, isLoaded should be false
            expect(bannerManager.isLoaded, false);
          });
          return const SizedBox();
        })),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('loadCollapsibleBanner loads with placement', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Builder(builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await bannerManager.loadCollapsibleBanner(
              context: context,
              placement: CollapsibleBannerPlacement.bottom,
              onAdLoaded: (_) {},
            );
            expect(mockSdk.loadBannerCalls, greaterThanOrEqualTo(1));
          });
          return const SizedBox();
        })),
      );
      await tester.pumpAndSettle();
    });

    test('buildAdWidget returns null when not loaded', () {
      final widget = bannerManager.buildAdWidget();
      expect(widget, isNull);
    });

    test('dispose clears ad', () {
      bannerManager.dispose();
      expect(bannerManager.isLoaded, false);
    });

    test('status listeners work', () async {
      int notifyCount = 0;
      bannerManager.addStatusListener(() => notifyCount++);

      await bannerManager.loadBanner(size: AdSize.banner);

      expect(notifyCount, greaterThan(0));
    });
  });

  group('InterstitialAdManager coverage', () {
    late InterstitialAdManager interstitialManager;

    setUp(() {
      AdFlowConfig.setCurrent(const AdFlowConfig(
        androidInterstitialAdUnitId: 'test-interstitial',
        iosInterstitialAdUnitId: 'test-interstitial',
      ));
      interstitialManager = InterstitialAdManager();
    });

    tearDown(() {
      interstitialManager.dispose();
    });

    test('show - dismiss callback works', () async {
      final fakeAd = FakeInterstitialAd();
      mockSdk.interstitialAdToReturn = fakeAd;
      await interstitialManager.loadAd();

      bool dismissed = false;
      await interstitialManager.showAd(
        onAdDismissed: () => dismissed = true,
      );

      fakeAd.simulateDismiss();
      await Future.delayed(Duration.zero);

      expect(dismissed, true);
    });

    test('show - failed to show callback', () async {
      final fakeAd = FakeInterstitialAd();
      mockSdk.interstitialAdToReturn = fakeAd;
      await interstitialManager.loadAd();

      bool failCalled = false;
      await interstitialManager.showAd(
        onAdFailedToShow: () => failCalled = true,
      );

      fakeAd.simulateShowFailure(AdError(1, 'test', 'failed'));
      await Future.delayed(Duration.zero);

      expect(failCalled, true);
    });

    test('show skips when ads disabled', () async {
      await AdsEnabledManager.instance.disableAds();
      await interstitialManager.showAd();
      // No crash
    });

    test('impression and click callbacks', () async {
      final fakeAd = FakeInterstitialAd();
      mockSdk.interstitialAdToReturn = fakeAd;
      await interstitialManager.loadAd();
      await interstitialManager.showAd();

      fakeAd.simulateImpression();
      fakeAd.simulateClick();
      // No crash
    });

    test('canShowAd respects cooldown', () async {
      AdFlowConfig.setCurrent(const AdFlowConfig(
        androidInterstitialAdUnitId: 'test-interstitial',
        iosInterstitialAdUnitId: 'test-interstitial',
        minInterstitialInterval: Duration(seconds: 60),
      ));

      final manager = InterstitialAdManager();
      final fakeAd = FakeInterstitialAd();
      mockSdk.interstitialAdToReturn = fakeAd;
      await manager.loadAd();
      await manager.showAd();
      fakeAd.simulateDismiss();
      await Future.delayed(Duration.zero);

      // Load another ad
      mockSdk.interstitialAdToReturn = FakeInterstitialAd();
      await manager.loadAd();

      // Should be in cooldown
      expect(manager.canShowAd, false);
      manager.dispose();
    });
  });

  group('RewardedAdManager coverage', () {
    late RewardedAdManager rewardedManager;

    setUp(() {
      AdFlowConfig.setCurrent(const AdFlowConfig(
        androidRewardedAdUnitId: 'test-rewarded',
        iosRewardedAdUnitId: 'test-rewarded',
      ));
      rewardedManager = RewardedAdManager();
    });

    tearDown(() {
      rewardedManager.dispose();
    });

    test('show calls reward callback', () async {
      final fakeAd = FakeRewardedAd();
      mockSdk.rewardedAdToReturn = fakeAd;
      await rewardedManager.loadAd();

      bool rewarded = false;
      await rewardedManager.showAd(
        onUserEarnedReward: (reward) => rewarded = true,
      );

      fakeAd.simulateReward(amount: 10, type: 'coins');
      await Future.delayed(Duration.zero);

      expect(rewarded, true);
    });

    test('show - dismiss callback', () async {
      final fakeAd = FakeRewardedAd();
      mockSdk.rewardedAdToReturn = fakeAd;
      await rewardedManager.loadAd();

      bool dismissed = false;
      await rewardedManager.showAd(
        onAdDismissed: () => dismissed = true,
        onUserEarnedReward: (_) {},
      );

      fakeAd.simulateDismiss();
      await Future.delayed(Duration.zero);

      expect(dismissed, true);
    });

    test('show - failed to show', () async {
      final fakeAd = FakeRewardedAd();
      mockSdk.rewardedAdToReturn = fakeAd;
      await rewardedManager.loadAd();

      bool failCalled = false;
      await rewardedManager.showAd(
        onAdFailedToShow: () => failCalled = true,
        onUserEarnedReward: (_) {},
      );

      fakeAd.simulateShowFailure(AdError(1, 'test', 'failed'));
      await Future.delayed(Duration.zero);

      expect(failCalled, true);
    });

    test('show skips when ads disabled but rewardedAdsIgnoreRemoveAds=false',
        () async {
      AdFlowConfig.setCurrent(const AdFlowConfig(
        androidRewardedAdUnitId: 'test-rewarded',
        iosRewardedAdUnitId: 'test-rewarded',
        rewardedAdsIgnoreRemoveAds: false,
      ));

      final manager = RewardedAdManager();
      await AdsEnabledManager.instance.disableAds();
      await manager.showAd(onUserEarnedReward: (_) {});
      // Should not show
      manager.dispose();
    });

    test('load skips when cannot request ads', () async {
      mockSdk.canRequestAdsResult = false;
      await rewardedManager.loadAd();
      expect(mockSdk.loadRewardedCalls, 0);
    });

    test('sets immersive mode on show', () async {
      final fakeAd = FakeRewardedAd();
      mockSdk.rewardedAdToReturn = fakeAd;
      await rewardedManager.loadAd();
      await rewardedManager.showAd(onUserEarnedReward: (_) {});

      expect(fakeAd.immersiveModeSet, true);
    });
  });
}
