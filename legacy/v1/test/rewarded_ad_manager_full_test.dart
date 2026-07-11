// Copyright 2024 - AdMob Integration Package
// Comprehensive tests for RewardedAdManager

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ad_flow/ad_flow.dart';

import 'helpers/fake_ads.dart';
import 'helpers/mock_ad_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAdSdk mockSdk;
  late RewardedAdManager manager;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AdsEnabledManager.instance.reset();
    await AdsEnabledManager.instance.initialize();

    mockSdk = MockAdSdk();
    AdSdk.instance = mockSdk;

    AdFlowConfig.setCurrent(
      const AdFlowConfig(
        androidRewardedAdUnitId: 'test-rewarded',
        iosRewardedAdUnitId: 'test-rewarded',
        maxLoadRetries: 2,
        retryDelay: Duration(milliseconds: 10),
      ),
    );
    AdFlowPlatform.platformOverride = TargetPlatform.android;

    manager = RewardedAdManager();
  });

  tearDown(() async {
    await manager.dispose();
    AdSdk.resetInstance();
    AdFlowPlatform.reset();
  });

  group('initial state', () {
    test('isLoaded is false', () => expect(manager.isLoaded, false));
    test('isLoading is false', () => expect(manager.isLoading, false));
    test('isShowing is false', () => expect(manager.isShowing, false));
    test('rewardedAd is null', () => expect(manager.rewardedAd, isNull));
  });

  group('loadAd - success', () {
    test('loads ad successfully', () async {
      final fakeAd = FakeRewardedAd();
      mockSdk.rewardedAdToReturn = fakeAd;

      await manager.loadAd();

      expect(manager.isLoaded, true);
      expect(manager.isLoading, false);
      expect(manager.rewardedAd, isNotNull);
      expect(mockSdk.loadRewardedCalls, 1);
    });

    test('calls onAdLoaded callback', () async {
      RewardedAd? loadedAd;
      await manager.loadAd(onAdLoaded: (ad) => loadedAd = ad);
      expect(loadedAd, isNotNull);
    });

    test('uses configured ad unit ID', () async {
      await manager.loadAd();
      expect(mockSdk.lastAdUnitId, 'test-rewarded');
    });

    test('uses custom ad unit ID', () async {
      await manager.loadAd(adUnitId: 'custom-rewarded');
      expect(mockSdk.lastAdUnitId, 'custom-rewarded');
    });

    test('sets up full screen content callbacks', () async {
      final fakeAd = FakeRewardedAd();
      mockSdk.rewardedAdToReturn = fakeAd;
      await manager.loadAd();
      expect(fakeAd.fullScreenContentCallback, isNotNull);
    });
  });

  group('loadAd - failure', () {
    test('state is false after failure', () async {
      mockSdk.rewardedLoadError = LoadAdError(1, 'test', 'fail', null);
      await manager.loadAd();

      expect(manager.isLoaded, false);
      expect(manager.isLoading, false);
    });

    test('reports error to AdFlowErrorHandler', () async {
      mockSdk.rewardedLoadError = LoadAdError(1, 'test', 'fail', null);

      AdFlowError? capturedError;
      final sub = AdFlowErrorHandler.instance.errorStream.listen((e) {
        capturedError = e;
      });

      await manager.loadAd();
      await Future.delayed(Duration.zero);

      expect(capturedError, isNotNull);
      expect(capturedError!.type, AdErrorType.rewardedLoad);

      await sub.cancel();
    });
  });

  group('loadAd - guards', () {
    test('skips load when consent not given', () async {
      mockSdk.canRequestAdsResult = false;
      await manager.loadAd();
      expect(mockSdk.loadRewardedCalls, 0);
    });

    test('skips load when already loaded', () async {
      await manager.loadAd();
      await manager.loadAd();
      expect(mockSdk.loadRewardedCalls, 1);
    });

    test('respects rewardedAdsIgnoreRemoveAds config', () async {
      // By default, rewardedAdsIgnoreRemoveAds is true
      await AdsEnabledManager.instance.disableAds();
      await manager.loadAd();
      // Should still load because rewarded ads ignore remove ads by default
      expect(mockSdk.loadRewardedCalls, 1);
    });

    test(
      'skips load when ads disabled and config says not to ignore',
      () async {
        AdFlowConfig.setCurrent(
          const AdFlowConfig(
            androidRewardedAdUnitId: 'test-rewarded',
            iosRewardedAdUnitId: 'test-rewarded',
            rewardedAdsIgnoreRemoveAds: false,
          ),
        );
        await AdsEnabledManager.instance.disableAds();
        await manager.loadAd();
        expect(mockSdk.loadRewardedCalls, 0);
      },
    );
  });

  group('showAd - success', () {
    test('shows loaded ad', () async {
      final fakeAd = FakeRewardedAd();
      mockSdk.rewardedAdToReturn = fakeAd;
      await manager.loadAd();

      final result = await manager.showAd(onUserEarnedReward: (_) {});

      expect(result, true);
      expect(fakeAd.wasShown, true);
    });

    test('delivers reward to callback', () async {
      final fakeAd = FakeRewardedAd();
      mockSdk.rewardedAdToReturn = fakeAd;
      await manager.loadAd();

      RewardItem? receivedReward;
      await manager.showAd(
        onUserEarnedReward: (reward) => receivedReward = reward,
      );

      fakeAd.simulateReward(amount: 50, type: 'gems');

      expect(receivedReward, isNotNull);
      expect(receivedReward!.amount, 50);
      expect(receivedReward!.type, 'gems');
    });

    test('onAdDismissed fires on dismiss', () async {
      final fakeAd = FakeRewardedAd();
      mockSdk.rewardedAdToReturn = fakeAd;
      await manager.loadAd();

      bool dismissed = false;
      await manager.showAd(
        onUserEarnedReward: (_) {},
        onAdDismissed: () => dismissed = true,
      );

      fakeAd.simulateDismiss();
      expect(dismissed, true);
    });

    test('ad is disposed after dismiss', () async {
      final fakeAd = FakeRewardedAd();
      mockSdk.rewardedAdToReturn = fakeAd;
      await manager.loadAd();
      await manager.showAd(onUserEarnedReward: (_) {});
      fakeAd.simulateDismiss();

      expect(fakeAd.wasDisposed, true);
      expect(manager.isLoaded, false);
      expect(manager.rewardedAd, isNull);
    });

    test('isShowing is true while showing', () async {
      final fakeAd = FakeRewardedAd();
      mockSdk.rewardedAdToReturn = fakeAd;
      await manager.loadAd();
      await manager.showAd(onUserEarnedReward: (_) {});
      expect(manager.isShowing, true);
    });

    test('sets immersive mode', () async {
      final fakeAd = FakeRewardedAd();
      mockSdk.rewardedAdToReturn = fakeAd;
      await manager.loadAd();
      await manager.showAd(onUserEarnedReward: (_) {});
      expect(fakeAd.immersiveModeSet, true);
    });
  });

  group('showAd - guards', () {
    test('returns false when no ad loaded', () async {
      final result = await manager.showAd(onUserEarnedReward: (_) {});
      expect(result, false);
    });

    test(
      'returns false when ads disabled and rewardedAdsIgnoreRemoveAds is false',
      () async {
        AdFlowConfig.setCurrent(
          const AdFlowConfig(
            androidRewardedAdUnitId: 'test',
            iosRewardedAdUnitId: 'test',
            maxLoadRetries: 0,
            rewardedAdsIgnoreRemoveAds: false,
          ),
        );
        await manager.loadAd();
        await AdsEnabledManager.instance.disableAds();
        final result = await manager.showAd(onUserEarnedReward: (_) {});
        expect(result, false);
      },
    );

    test(
      'allows showAd when ads disabled but rewardedAdsIgnoreRemoveAds is true (default)',
      () async {
        final fakeAd = FakeRewardedAd();
        mockSdk.rewardedAdToReturn = fakeAd;
        await manager.loadAd();
        await AdsEnabledManager.instance.disableAds();
        final result = await manager.showAd(onUserEarnedReward: (_) {});
        expect(result, true);
      },
    );

    test('returns false when already showing', () async {
      final fakeAd = FakeRewardedAd();
      mockSdk.rewardedAdToReturn = fakeAd;
      await manager.loadAd();
      await manager.showAd(onUserEarnedReward: (_) {});
      final result = await manager.showAd(onUserEarnedReward: (_) {});
      expect(result, false);
    });

    test('calls onAdFailedToShow when no ad loaded', () async {
      bool failedCalled = false;
      await manager.showAd(
        onUserEarnedReward: (_) {},
        onAdFailedToShow: () => failedCalled = true,
      );
      expect(failedCalled, true);
    });
  });

  group('showAd - failure handling', () {
    test('handles show failure', () async {
      final fakeAd = FakeRewardedAd();
      mockSdk.rewardedAdToReturn = fakeAd;
      await manager.loadAd();

      bool failedToShow = false;
      await manager.showAd(
        onUserEarnedReward: (_) {},
        onAdFailedToShow: () => failedToShow = true,
      );
      fakeAd.simulateShowFailure(AdError(1, 'test', 'Failed'));

      expect(failedToShow, true);
      expect(manager.isShowing, false);
      expect(manager.isLoaded, false);
    });
  });

  group('auto-preload', () {
    test('triggers loadAd after dismiss', () async {
      final fakeAd = FakeRewardedAd();
      mockSdk.rewardedAdToReturn = fakeAd;
      await manager.loadAd();
      expect(mockSdk.loadRewardedCalls, 1);

      await manager.showAd(onUserEarnedReward: (_) {});
      fakeAd.simulateDismiss();
      await Future.delayed(Duration.zero);

      expect(mockSdk.loadRewardedCalls, greaterThan(1));
    });
  });

  group('dispose', () {
    test('clears ad and resets state', () async {
      await manager.loadAd();
      await manager.dispose();

      expect(manager.isLoaded, false);
      expect(manager.isLoading, false);
      expect(manager.isShowing, false);
      expect(manager.rewardedAd, isNull);
    });

    test('disposes underlying ad', () async {
      final fakeAd = FakeRewardedAd();
      mockSdk.rewardedAdToReturn = fakeAd;
      await manager.loadAd();
      await manager.dispose();
      expect(fakeAd.wasDisposed, true);
    });
  });

  group('status listeners', () {
    test('notifies on load', () async {
      int count = 0;
      manager.addStatusListener(() => count++);
      await manager.loadAd();
      expect(count, greaterThan(0));
    });

    test('removing listener stops notifications', () async {
      int count = 0;
      void listener() => count++;
      manager.addStatusListener(listener);
      manager.removeStatusListener(listener);
      await manager.loadAd();
      expect(count, 0);
    });
  });
}
