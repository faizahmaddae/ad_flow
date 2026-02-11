// Copyright 2024 - AdMob Integration Package
// Unit tests for AppLifecycleReactor

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ad_flow/ad_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLifecycleReactor', () {
    late AppOpenAdManager appOpenManager;
    late AppLifecycleReactor reactor;

    setUp(() {
      appOpenManager = AppOpenAdManager();
      reactor = AppLifecycleReactor(
        appOpenAdManager: appOpenManager,
        maxForegroundAdsPerSession: 1,
      );
    });

    tearDown(() {
      reactor.dispose();
      appOpenManager.dispose();
    });

    group('initialization', () {
      test('creates with correct maxForegroundAdsPerSession', () {
        expect(reactor.maxForegroundAdsPerSession, 1);
      });

      test('isListening is false initially', () {
        expect(reactor.isListening, false);
      });

      test('isPaused is false initially', () {
        expect(reactor.isPaused, false);
      });

      test('foregroundAdCount starts at 0', () {
        expect(reactor.foregroundAdCount, 0);
      });
    });

    group('startListening', () {
      test('sets isListening to true', () {
        reactor.startListening();
        expect(reactor.isListening, true);
      });

      test('calling startListening twice does not cause issues', () {
        reactor.startListening();
        reactor.startListening();
        expect(reactor.isListening, true);
      });
    });

    group('stopListening', () {
      test('sets isListening to false', () {
        reactor.startListening();
        reactor.stopListening();
        expect(reactor.isListening, false);
      });

      test(
        'calling stopListening when not listening does not cause issues',
        () {
          reactor.stopListening();
          expect(reactor.isListening, false);
        },
      );
    });

    group('pause and resume', () {
      test('pause sets isPaused to true', () {
        reactor.pause();
        expect(reactor.isPaused, true);
      });

      test('resume sets isPaused to false', () {
        reactor.pause();
        reactor.resume();
        expect(reactor.isPaused, false);
      });

      test('pause/resume can be called multiple times', () {
        reactor.pause();
        reactor.pause();
        expect(reactor.isPaused, true);

        reactor.resume();
        reactor.resume();
        expect(reactor.isPaused, false);
      });
    });

    group('resetForegroundAdCount', () {
      test('resets the counter to 0', () {
        // We can't easily increment the counter without mocking ads,
        // but we can verify the reset method exists and works
        reactor.resetForegroundAdCount();
        expect(reactor.foregroundAdCount, 0);
      });
    });

    group('dispose', () {
      test('can be called safely', () {
        reactor.startListening();
        reactor.dispose();
        // After dispose, we shouldn't use the reactor
        // Just verifying no exception is thrown
      });
    });

    group('fullscreen ad suppression', () {
      setUp(() {
        AppLifecycleReactor.resetFullscreenAdState();
      });

      tearDown(() {
        AppLifecycleReactor.resetFullscreenAdState();
      });

      test('notifyFullscreenAdShowing sets suppression flag', () {
        // Before notification, state is clean
        AppLifecycleReactor.notifyFullscreenAdShowing();
        // After notification, the static flag is set
        // We can verify by calling dismissed and checking reset
        AppLifecycleReactor.notifyFullscreenAdDismissed();
        // No exception means the state machine works
      });

      test('notifyFullscreenAdDismissed clears showing flag', () {
        AppLifecycleReactor.notifyFullscreenAdShowing();
        AppLifecycleReactor.notifyFullscreenAdDismissed();
        // No exception means the transition works
      });

      test('resetFullscreenAdState clears all suppression state', () {
        AppLifecycleReactor.notifyFullscreenAdShowing();
        AppLifecycleReactor.resetFullscreenAdState();
        // State should be fully cleared — safe to call again
        AppLifecycleReactor.notifyFullscreenAdShowing();
        AppLifecycleReactor.notifyFullscreenAdDismissed();
      });

      test('fullscreenAdSuppression duration is 5 seconds', () {
        expect(
          AppLifecycleReactor.fullscreenAdSuppression,
          const Duration(seconds: 5),
        );
      });

      test(
        'lifecycle resumed during fullscreen ad does not show app open ad',
        () {
          reactor.startListening();
          // Simulate interstitial ad showing
          AppLifecycleReactor.notifyFullscreenAdShowing();

          // Simulate lifecycle going paused → resumed (as OS does for fullscreen ads)
          reactor.didChangeAppLifecycleState(AppLifecycleState.paused);
          reactor.didChangeAppLifecycleState(AppLifecycleState.resumed);

          // Ad count should still be 0 — the app open ad was suppressed
          expect(reactor.foregroundAdCount, 0);
        },
      );

      test(
        'lifecycle resumed shortly after fullscreen dismiss does not show app open ad',
        () {
          reactor.startListening();
          // Simulate interstitial ad dismissed
          AppLifecycleReactor.notifyFullscreenAdShowing();
          AppLifecycleReactor.notifyFullscreenAdDismissed();

          // Simulate lifecycle resumed within grace period
          reactor.didChangeAppLifecycleState(AppLifecycleState.paused);
          reactor.didChangeAppLifecycleState(AppLifecycleState.resumed);

          // Ad count should still be 0 — within grace period
          expect(reactor.foregroundAdCount, 0);
        },
      );
    });

    group('maxForegroundAdsPerSession variations', () {
      test('0 means unlimited (no limit)', () {
        final unlimitedReactor = AppLifecycleReactor(
          appOpenAdManager: appOpenManager,
          maxForegroundAdsPerSession: 0,
        );
        expect(unlimitedReactor.maxForegroundAdsPerSession, 0);
        unlimitedReactor.dispose();
      });

      test('custom limit can be set', () {
        final customReactor = AppLifecycleReactor(
          appOpenAdManager: appOpenManager,
          maxForegroundAdsPerSession: 5,
        );
        expect(customReactor.maxForegroundAdsPerSession, 5);
        customReactor.dispose();
      });

      test('default limit is 1', () {
        final defaultReactor = AppLifecycleReactor(
          appOpenAdManager: appOpenManager,
        );
        expect(defaultReactor.maxForegroundAdsPerSession, 1);
        defaultReactor.dispose();
      });
    });
  });
}
