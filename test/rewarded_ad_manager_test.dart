// Copyright 2024 - AdMob Integration Package
// Unit tests for RewardedAdManager

import 'package:flutter_test/flutter_test.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RewardedAdManager', () {
    late RewardedAdManager manager;

    setUp(() {
      manager = RewardedAdManager();
      AdFlowConfig.setCurrent(const AdFlowConfig());
    });

    tearDown(() {
      manager.dispose();
    });

    group('initial state', () {
      test('isLoaded is false initially', () {
        expect(manager.isLoaded, false);
      });

      test('isLoading is false initially', () {
        expect(manager.isLoading, false);
      });

      test('isShowing is false initially', () {
        expect(manager.isShowing, false);
      });

      test('rewardedAd is null initially', () {
        expect(manager.rewardedAd, isNull);
      });
    });

    group('status listeners', () {
      test('addStatusListener adds listener without exception', () {
        int callCount = 0;
        void listener() {
          callCount++;
        }

        manager.addStatusListener(listener);
        expect(callCount, 0);
        manager.removeStatusListener(listener);
      });

      test('removeStatusListener removes listener', () {
        int callCount = 0;
        void listener() {
          callCount++;
        }

        manager.addStatusListener(listener);
        manager.removeStatusListener(listener);
        expect(callCount, 0);
      });

      test('multiple listeners can be added', () {
        void listener1() {}
        void listener2() {}

        manager.addStatusListener(listener1);
        manager.addStatusListener(listener2);

        // Just verifying no exception is thrown
        manager.removeStatusListener(listener1);
        manager.removeStatusListener(listener2);
      });
    });

    group('dispose', () {
      test('can be called safely', () {
        manager.dispose();
        // Just verifying no exception is thrown
      });

      test('resets state after dispose', () async {
        await manager.dispose();
        expect(manager.isLoaded, false);
        expect(manager.isLoading, false);
        expect(manager.isShowing, false);
      });
    });
  });

  group('Retry configuration', () {
    test('default maxLoadRetries is 3', () {
      const config = AdFlowConfig();
      expect(config.maxLoadRetries, 3);
    });

    test('custom maxLoadRetries can be set', () {
      const config = AdFlowConfig(maxLoadRetries: 5);
      expect(config.maxLoadRetries, 5);
    });

    test('default retryDelay is 5 seconds', () {
      const config = AdFlowConfig();
      expect(config.retryDelay.inSeconds, 5);
    });

    test('custom retryDelay can be set', () {
      const config = AdFlowConfig(retryDelay: Duration(seconds: 10));
      expect(config.retryDelay.inSeconds, 10);
    });

    test('AdConfig proxies retry settings correctly', () {
      const config = AdFlowConfig(
        maxLoadRetries: 7,
        retryDelay: Duration(seconds: 15),
      );
      AdFlowConfig.setCurrent(config);

      expect(AdFlowConfig.current.maxLoadRetries, 7);
      expect(AdFlowConfig.current.retryDelay.inSeconds, 15);
    });
  });
}
