import 'package:ad_flow/src/config/ad_flow_config.dart';
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

    test('show without a loaded ad returns false and warms a preload',
        () async {
      final c = controller();
      expect(await c.show(), isFalse);
      await Future<void>.delayed(Duration.zero); // let the preload land
      expect(sdk.interstitials, hasLength(1)); // preload kicked off
      c.dispose();
    });
  });

  group('show', () {
    test('shows a warm ad, enters the coordinator, records the impression',
        () async {
      final c = controller();
      await c.load();
      expect(c.isReady, isTrue);

      final shown = await c.show();
      await Future<void>.delayed(Duration.zero); // let recordImpression land

      expect(shown, isTrue);
      expect(c.state.value, const AdShowing());
      expect(sdk.interstitials.single.showCalls, 1);
      expect(coordinator.isFullScreenAdVisible, isTrue);
      expect(await caps.canShow('interstitial'), isFalse); // minGap running
      c.dispose();
    });

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

    test('frequency cap blocks the next show until the gap elapses',
        () async {
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
}
