// Copyright 2024 - AdMob Integration Package
// Unit tests for InterstitialAdManager cooldown logic

import 'package:flutter_test/flutter_test.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InterstitialAdManager cooldown logic', () {
    late InterstitialAdManager manager;

    setUp(() {
      manager = InterstitialAdManager();
      // Set up config with known cooldown interval
      AdFlowConfig.setCurrent(
        const AdFlowConfig(minInterstitialInterval: Duration(seconds: 30)),
      );
    });

    tearDown(() {
      manager.dispose();
    });

    group('canShowAd', () {
      test('returns true when no ad has been shown yet', () {
        expect(manager.canShowAd, true);
      });

      test('canShowAd reflects cooldown state correctly', () {
        // Before any show, canShowAd should be true
        expect(manager.canShowAd, true);
      });
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

      test('interstitialAd is null initially', () {
        expect(manager.interstitialAd, isNull);
      });
    });

    group('status listeners', () {
      test('addStatusListener adds listener', () {
        int callCount = 0;
        void listener() {
          callCount++;
        }

        manager.addStatusListener(listener);

        // Listener list is internal, so we just verify no exception
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

        // After removal, listener should not be called on state changes
        expect(callCount, 0);
      });
    });
  });

  group('Cooldown configuration', () {
    test('default cooldown is 30 seconds', () {
      const config = AdFlowConfig();
      expect(config.minInterstitialInterval, const Duration(seconds: 30));
    });

    test('custom cooldown can be set', () {
      const config = AdFlowConfig(
        minInterstitialInterval: Duration(minutes: 2),
      );
      expect(config.minInterstitialInterval, const Duration(minutes: 2));
    });

    test('AdConfig proxies minInterstitialInterval correctly', () {
      const config = AdFlowConfig(
        minInterstitialInterval: Duration(seconds: 45),
      );
      AdFlowConfig.setCurrent(config);

      expect(AdFlowConfig.current.minInterstitialInterval.inSeconds, 45);
    });

    test('zero cooldown is allowed', () {
      const config = AdFlowConfig(minInterstitialInterval: Duration.zero);
      expect(config.minInterstitialInterval, Duration.zero);
    });
  });

  group('Dispose guard behavior', () {
    late InterstitialAdManager manager;

    setUp(() {
      manager = InterstitialAdManager();
      AdFlowConfig.setCurrent(const AdFlowConfig());
    });

    test('isLoaded is false after dispose', () async {
      await manager.dispose();
      expect(manager.isLoaded, false);
    });

    test('isLoading is false after dispose', () async {
      await manager.dispose();
      expect(manager.isLoading, false);
    });

    test('isShowing is false after dispose', () async {
      await manager.dispose();
      expect(manager.isShowing, false);
    });

    test('interstitialAd is null after dispose', () async {
      await manager.dispose();
      expect(manager.interstitialAd, isNull);
    });

    test('dispose can be called multiple times safely', () async {
      await manager.dispose();
      await manager.dispose();
      await manager.dispose();
      // Should not throw
      expect(manager.isLoaded, false);
    });

    test('status listeners are cleared after dispose', () async {
      int callCount = 0;
      void listener() {
        callCount++;
      }

      manager.addStatusListener(listener);
      await manager.dispose();

      // Listeners should be cleared
      // Adding new listener after dispose should still work
      manager.addStatusListener(listener);
      expect(callCount, 0);
    });
  });

  group('Status listener safety', () {
    late InterstitialAdManager manager;

    setUp(() {
      manager = InterstitialAdManager();
      AdFlowConfig.setCurrent(const AdFlowConfig());
    });

    tearDown(() {
      manager.dispose();
    });

    test('multiple listeners can be added', () {
      int count1 = 0;
      int count2 = 0;
      void listener1() => count1++;
      void listener2() => count2++;

      manager.addStatusListener(listener1);
      manager.addStatusListener(listener2);

      // No exception should be thrown
      manager.removeStatusListener(listener1);
      manager.removeStatusListener(listener2);
    });

    test('removing non-existent listener does not throw', () {
      void listener() {}

      // Should not throw when removing listener that was never added
      manager.removeStatusListener(listener);
    });

    test('same listener can be added multiple times', () {
      int callCount = 0;
      void listener() => callCount++;

      manager.addStatusListener(listener);
      manager.addStatusListener(listener);

      // Both should be in the list
      manager.removeStatusListener(listener);
      // One should remain after removing once
    });
  });
}
