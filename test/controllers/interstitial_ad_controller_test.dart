import 'dart:async';

import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/app_open_ad_controller.dart';
import 'package:ad_flow/src/controllers/interstitial_ad_controller.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/policy/retry_policy.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late StoredFrequencyCapPolicy caps;
  late DateTime now;
  late bool consented;

  setUp(() {
    sdk = FakeAdSdk();
    sdk.enforceConsentGate = true;
    sdk.canRequestAdsResult = true;
    consented = true;
    coordinator = FullScreenAdCoordinator();
    now = DateTime(2026, 7, 11, 12);
    caps = StoredFrequencyCapPolicy(
      store: InMemoryKeyValueStore(),
      slotCaps: {
        'interstitial': const FrequencyCap(minGap: Duration(seconds: 30)),
      },
      globalCap: const FrequencyCap(),
      now: () => now,
    );
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  InterstitialAdController controller({
    InterstitialConfig? config,
    RetryConfig retryConfig = const RetryConfig(),
  }) => InterstitialAdController(
    sdk: sdk,
    gate: AdGate(
      canRequestAds: () async => consented && sdk.canRequestAdsResult,
      isEnabled: () => true,
      caps: caps,
      coordinator: coordinator,
    ),
    caps: caps,
    coordinator: coordinator,
    config:
        config ??
        const InterstitialConfig(adUnitId: PlatformAdUnitId(android: 'unit-i')),
    adUnitId: 'unit-i',
    retry: RetryPolicy(retryConfig, random: () => 0.5),
  );

  group('gating (invariant 1)', () {
    test('no load while consent is closed', () async {
      consented = false;
      sdk.canRequestAdsResult = false;
      final c = controller();
      await c.load();
      expect(sdk.loadLog, isEmpty);
      expect(c.state.value, const AdIdle());
      c.dispose();
    });

    test(
      'show without a loaded ad returns false and warms a preload',
      () async {
        final c = controller();
        expect(await c.show(), isFalse);
        await Future<void>.delayed(Duration.zero); // let the preload land
        expect(sdk.interstitials, hasLength(1)); // preload kicked off
        c.dispose();
      },
    );
  });

  group('show', () {
    test(
      'shows a warm ad, enters the coordinator, and records the impression on '
      'DISMISS (ADR-040)',
      () async {
        final c = controller();
        await c.load();
        expect(c.isReady, isTrue);

        final shown = await c.show();
        await Future<void>.delayed(Duration.zero);

        expect(shown, isTrue);
        expect(c.state.value, const AdShowing());
        expect(sdk.interstitials.single.showCalls, 1);
        expect(coordinator.isFullScreenAdVisible, isTrue);

        // While the ad is ON SCREEN the impression is not recorded yet — the
        // cap clock must start when it CLOSES, not while the user is still
        // watching (ADR-040). Nothing else can show meanwhile: the coordinator
        // holds the claim, which is the guard that actually matters here.
        sdk.interstitials.single.simulateShowed();
        sdk.interstitials.single.simulateDismissed();
        await Future<void>.delayed(Duration.zero);

        expect(await caps.canShow('interstitial'), isFalse); // minGap running
        c.dispose();
      },
    );

    test('never double-shows while an ad is on screen', () async {
      final c = controller();
      await c.load();
      await c.show();

      expect(await c.show(), isFalse);
      expect(sdk.interstitials.single.showCalls, 1);
      c.dispose();
    });

    test('suppressed while ANY full-screen ad is visible', () async {
      final c = controller();
      await c.load();
      coordinator.enter(); // e.g. an app-open ad is showing
      expect(await c.show(), isFalse);
      coordinator.exit();
      expect(await c.show(), isTrue);
      c.dispose();
    });

    test('frequency cap blocks the next show until the gap elapses', () async {
      final c = controller();
      await c.load();
      await c.show();
      sdk.interstitials.single.simulateDismissed(); // reload starts
      await Future<void>.delayed(Duration.zero);
      expect(c.isReady, isTrue);

      expect(await c.show(), isFalse); // 30s minGap not yet elapsed
      now = now.add(const Duration(seconds: 30));
      expect(await c.show(), isTrue);
      c.dispose();
    });

    test('dismiss exits the coordinator, disposes the handle and reloads '
        'immediately (invariant 7)', () async {
      final c = controller();
      await c.load();
      await c.show();
      final first = sdk.interstitials.single;

      first.simulateDismissed();
      await Future<void>.delayed(Duration.zero);

      expect(coordinator.isFullScreenAdVisible, isFalse);
      expect(first.disposed, isTrue);
      expect(sdk.interstitials, hasLength(2)); // next one warm
      expect(c.state.value, const AdLoaded());
      c.dispose();
    });

    test('failed show exits the coordinator and reloads', () async {
      final c = controller();
      await c.load();
      final handle = sdk.interstitials.single;
      handle.showError = const AdFlowError(
        AdFlowErrorKind.showFailed,
        'not ready',
      );

      final shown = await c.show();
      await Future<void>.delayed(Duration.zero);

      expect(shown, isTrue); // dispatched; failure arrived via the event
      expect(coordinator.isFullScreenAdVisible, isFalse);
      expect(handle.disposed, isTrue);
      expect(sdk.interstitials, hasLength(2));
      c.dispose();
    });
  });

  group('show path is cheap (2026-07 audit)', () {
    test('show() must not re-run the consent settle while holding the '
        'coordinator claim', () {
      fakeAsync((async) {
        var settleCalls = 0;
        var hangSettle = false;
        final gate = AdGate(
          canRequestAds: () async => true,
          isEnabled: () => true,
          caps: caps,
          coordinator: coordinator,
          settleConsent: () async {
            settleCalls++;
            if (hangSettle) await Completer<void>().future;
          },
        );
        final c = InterstitialAdController(
          sdk: sdk,
          gate: gate,
          caps: caps,
          coordinator: coordinator,
          config: const InterstitialConfig(
            adUnitId: PlatformAdUnitId(android: 'unit-i'),
          ),
          adUnitId: 'unit-i',
          retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
        );
        c.load();
        async.flushMicrotasks();
        expect(c.isReady, isTrue);
        final callsAfterLoad = settleCalls;

        // A consent re-settle would now BLOCK (e.g. the ADR-035 retry of a
        // failed flow, network-bound, up to the 30s info-update timeout).
        // The warm ad already passed consent AND request configuration at
        // load time; show() holds the shared coordinator claim across its
        // checks, so joining a consent flow here would freeze EVERY
        // full-screen format behind it.
        hangSettle = true;
        var shown = false;
        unawaited(c.show().then((v) => shown = v));
        async.flushMicrotasks();

        expect(
          shown,
          isTrue,
          reason:
              'show() must use the cheap current consent answer, never '
              'join/re-run the consent flow',
        );
        expect(settleCalls, callsAfterLoad);
        expect(coordinator.isFullScreenAdVisible, isTrue);
        c.dispose();
      });
    });
  });

  group('user-action pacing', () {
    test('inactive until the first recordUserAction call', () async {
      final c = controller();
      await c.load();
      expect(await c.show(), isTrue); // no tracking → caps only
      c.dispose();
    });

    test('enforces minActionsBetween once tracking is active', () async {
      // No caps in play — isolate the action pacing.
      caps = StoredFrequencyCapPolicy(
        store: InMemoryKeyValueStore(),
        slotCaps: const {},
        globalCap: const FrequencyCap(),
        now: () => now,
      );
      final c = controller(
        config: const InterstitialConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-i'),
          minActionsBetween: 2,
        ),
      );

      await c.load();
      c.recordUserAction();
      expect(await c.show(), isFalse); // 1 of 2 actions

      c.recordUserAction();
      expect(await c.show(), isTrue);
      sdk.interstitials.first.simulateDismissed();
      await Future<void>.delayed(Duration.zero);

      // Counter reset on show: two fresh actions needed again.
      now = now.add(const Duration(minutes: 5));
      expect(await c.show(), isFalse);
      c.recordUserAction();
      c.recordUserAction();
      expect(await c.show(), isTrue);
      c.dispose();
    });
  });

  group('load retry', () {
    test('backs off, cools down, auto re-arms', () {
      fakeAsync((async) {
        sdk.alwaysLoadError = const AdFlowError(
          AdFlowErrorKind.loadFailed,
          'no fill',
        );
        final c = controller(
          retryConfig: const RetryConfig(
            maxAttempts: 2,
            baseDelay: Duration(seconds: 5),
            cooldown: Duration(minutes: 5),
          ),
        );
        c.load();
        async.flushMicrotasks();
        expect(c.state.value, isA<AdFailed>());

        async.elapse(const Duration(seconds: 5)); // retry #1 fails
        expect(c.state.value, isA<AdFailed>());

        sdk.alwaysLoadError = null;
        async.elapse(const Duration(minutes: 5)); // cooldown re-arm succeeds
        expect(c.state.value, const AdLoaded());
        c.dispose();
      });
    });

    test('a stale retry timer does not stomp a since-recovered AdLoaded/'
        'AdShowing state (review finding #3)', () {
      fakeAsync((async) {
        sdk.alwaysLoadError = const AdFlowError(
          AdFlowErrorKind.loadFailed,
          'no fill',
        );
        final c = controller(
          retryConfig: const RetryConfig(
            maxAttempts: 1,
            cooldown: Duration(minutes: 5),
          ),
        );

        // Load #1 fails; a cooldown-timer retry is now armed for 5 min.
        c.load();
        async.flushMicrotasks();
        expect(c.state.value, isA<AdFailed>());

        // Independently of that timer, a natural-break show() attempt
        // triggers its own load(), which now succeeds.
        sdk.alwaysLoadError = null;
        c.show();
        async.flushMicrotasks();
        expect(c.state.value, const AdLoaded());
        expect(sdk.interstitials, hasLength(1));

        // The ad is actually shown.
        c.show();
        async.flushMicrotasks();
        expect(c.state.value, const AdShowing());
        expect(coordinator.isFullScreenAdVisible, isTrue);
        final shownHandle = sdk.interstitials.single;

        // The STALE timer from the original failure fires now, while
        // that ad is on screen. Before the fix this stomped state to
        // AdIdle and triggered a second, unrelated load — leaking the
        // shown ad's handle/subscription and orphaning the coordinator
        // claim it held.
        async.elapse(const Duration(minutes: 5));

        expect(c.state.value, const AdShowing());
        expect(coordinator.isFullScreenAdVisible, isTrue);
        expect(sdk.interstitials, hasLength(1)); // no second, stray load
        expect(shownHandle.disposed, isFalse); // the shown ad is intact

        // The shown ad dismissing still behaves normally afterward.
        shownHandle.simulateDismissed();
        async.flushMicrotasks();
        expect(coordinator.isFullScreenAdVisible, isFalse);
        expect(shownHandle.disposed, isTrue);
        expect(sdk.interstitials, hasLength(2)); // the real reload

        c.dispose();
      });
    });
  });

  test('dispose cancels everything and discards in-flight loads', () {
    fakeAsync((async) {
      final c = controller();
      c.load();
      async.flushMicrotasks();
      final handle = sdk.interstitials.single;

      c.dispose();
      expect(handle.disposed, isTrue);
      async.elapse(const Duration(hours: 1));
      expect(sdk.interstitials, hasLength(1));
    });
  });

  group('concurrency safety', () {
    test('two concurrent load() calls produce exactly one handle', () async {
      final c = controller();
      final l1 = c.load();
      final l2 = c.load();
      await Future.wait([l1, l2]);
      await Future<void>.delayed(Duration.zero);

      expect(sdk.interstitials, hasLength(1));
      expect(sdk.interstitials.single.disposed, isFalse);
      c.dispose();
    });

    test(
      'two concurrent show() calls invoke the SDK show() exactly once',
      () async {
        final c = controller();
        await c.load();

        final f1 = c.show();
        final f2 = c.show();
        final results = await Future.wait([f1, f2]);

        expect(results.where((r) => r).length, 1); // exactly one succeeded
        expect(sdk.interstitials.single.showCalls, 1);
        c.dispose();
      },
    );
  });

  group('show() rejection (review finding #1 — blocker)', () {
    test('a rejected handle.show() does not wedge the coordinator or leave '
        'the controller stuck — recovers for the next show()', () async {
      final c = controller();
      await c.load();
      final first = sdk.interstitials.single;
      first.showRejectsWith = Exception('ad already released');

      // Must not throw uncaught, must not return true, must roll back.
      final shown = await c.show();
      expect(shown, isFalse);
      expect(coordinator.isFullScreenAdVisible, isFalse);

      // The controller must reload and be usable again — a single
      // rejected show() must not wedge the rest of the session.
      await Future<void>.delayed(Duration.zero);
      expect(sdk.interstitials, hasLength(2));
      expect(c.isReady, isTrue);
      expect(await c.show(), isTrue);

      c.dispose();
    });

    test('a rejected show() releases the coordinator for OTHER full-screen '
        'controllers sharing it', () async {
      final c = controller();
      final appOpen = AppOpenAdController(
        sdk: sdk,
        gate: AdGate(
          canRequestAds: () async => consented && sdk.canRequestAdsResult,
          isEnabled: () => true,
          caps: caps,
          coordinator: coordinator,
        ),
        caps: caps,
        coordinator: coordinator,
        config: const AppOpenConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-ao'),
          cap: FrequencyCap(),
        ),
        adUnitId: 'unit-ao',
      );
      await c.load();
      await appOpen.load();
      sdk.interstitials.single.showRejectsWith = Exception('rejected');

      await c.show();
      // Before the fix, the coordinator stays claimed forever, so every
      // OTHER full-screen controller is wedged too.
      expect(await appOpen.show(), isTrue);

      c.dispose();
      appOpen.dispose();
    });
  });
}
