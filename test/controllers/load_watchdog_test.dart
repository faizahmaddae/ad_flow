import 'dart:async';

import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/banner_ad_controller.dart';
import 'package:ad_flow/src/controllers/interstitial_ad_controller.dart';
import 'package:ad_flow/src/controllers/native_ad_controller.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/policy/retry_policy.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

// Per-load watchdog (4.0 audit). The google_mobile_ads plugin has NO load
// timeout of its own (verified against the 9.0.0 source: no Timer/timeout
// anywhere in its load paths), and if a load callback never arrives —
// a dropped channel, a hung SSV attach, a hung getPlatformAdSize — the
// controller's await never resolves. Before the watchdog, the slot was
// pinned at AdLoading for the rest of the session with nothing armed.
void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late StoredFrequencyCapPolicy caps;

  setUp(() {
    sdk = FakeAdSdk()..canRequestAdsResult = true;
    coordinator = FullScreenAdCoordinator();
    caps = StoredFrequencyCapPolicy(
      store: InMemoryKeyValueStore(),
      slotCaps: const {},
      globalCap: const FrequencyCap(),
    );
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  AdGate gate() =>
      AdGate(canRequestAds: () async => true, isEnabled: () => true);

  InterstitialAdController interstitial({RetryConfig? retry}) =>
      InterstitialAdController(
        sdk: sdk,
        gate: gate(),
        caps: caps,
        coordinator: coordinator,
        config: const InterstitialConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-i'),
        ),
        adUnitId: 'unit-i',
        retry: RetryPolicy(retry ?? const RetryConfig(), random: () => 0.5),
      );

  group('a load whose SDK callback never arrives times out', () {
    test('full-screen: AdFailed(timeout) + retry armed, never a permanent '
        'AdLoading', () {
      fakeAsync((async) {
        sdk.loadHold = Completer<void>();
        final controller = interstitial();
        unawaited(controller.load());

        // Just before the default 60s watchdog: still legitimately loading.
        async.elapse(const Duration(seconds: 59));
        expect(controller.state.value, isA<AdLoading>());

        async.elapse(const Duration(seconds: 2));
        expect(
          controller.state.value,
          isNot(isA<AdLoading>()),
          reason:
              'a load callback that never arrives must not pin the slot at '
              'AdLoading for the session',
        );

        // The SDK heals: the retry (or cooldown re-arm) must recover the slot
        // on its own.
        sdk.loadHold!.complete();
        sdk.loadHold = null;
        async.elapse(const Duration(minutes: 6));
        expect(controller.state.value, isA<AdLoaded>());
        controller.dispose();
      });
    });

    test('banner: same containment', () {
      fakeAsync((async) {
        sdk.loadHold = Completer<void>();
        final controller = BannerAdController(
          sdk: sdk,
          gate: gate(),
          config: const BannerConfig(
            adUnitId: PlatformAdUnitId(android: 'unit-b'),
          ),
          adUnitId: 'unit-b',
          retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
        );
        unawaited(controller.load(width: 320));
        async.elapse(const Duration(seconds: 61));
        expect(controller.state.value, isNot(isA<AdLoading>()));

        sdk.loadHold!.complete();
        sdk.loadHold = null;
        async.elapse(const Duration(minutes: 6));
        expect(controller.state.value, isA<AdLoaded>());
        controller.dispose();
      });
    });

    test('native: same containment', () {
      fakeAsync((async) {
        sdk.loadHold = Completer<void>();
        final controller = NativeAdController(
          sdk: sdk,
          gate: gate(),
          config: const NativeConfig(
            adUnitId: PlatformAdUnitId(android: 'unit-n'),
            templateKind: NativeTemplateKind.small,
          ),
          adUnitId: 'unit-n',
          retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
        );
        unawaited(controller.load());
        async.elapse(const Duration(seconds: 61));
        expect(controller.state.value, isNot(isA<AdLoading>()));

        sdk.loadHold!.complete();
        sdk.loadHold = null;
        async.elapse(const Duration(minutes: 6));
        expect(controller.state.value, isA<AdLoaded>());
        controller.dispose();
      });
    });
  });

  group('a LATE completion after the watchdog fired', () {
    test('is disposed, never installed, never stomps the newer attempt', () {
      fakeAsync((async) {
        sdk.loadHold = Completer<void>();
        // One attempt then a long cooldown, so the timed-out attempt is the
        // only load in flight when the late handle finally arrives.
        final controller = interstitial(
          retry: const RetryConfig(maxAttempts: 1),
        );
        unawaited(controller.load());
        async.elapse(const Duration(seconds: 61));
        expect(controller.state.value, isNot(isA<AdLoading>()));
        expect(sdk.interstitials, isEmpty, reason: 'load still held');

        // The stuck load finally calls back — long after the controller gave
        // up on it.
        sdk.loadHold!.complete();
        sdk.loadHold = null;
        async.flushMicrotasks();

        expect(sdk.interstitials, hasLength(1));
        expect(
          sdk.interstitials.single.disposed,
          isTrue,
          reason:
              'the late handle belongs to an attempt the controller already '
              'abandoned — it must be released, not leaked',
        );
        expect(controller.state.value, isNot(isA<AdLoaded>()));
        expect(controller.isReady, isFalse);
        controller.dispose();
      });
    });
  });

  group('loadTimeout: null disables the watchdog', () {
    test('a held load stays AdLoading indefinitely by explicit choice', () {
      fakeAsync((async) {
        sdk.loadHold = Completer<void>();
        final controller = interstitial(
          retry: const RetryConfig(loadTimeout: null),
        );
        unawaited(controller.load());
        async.elapse(const Duration(hours: 1));
        expect(controller.state.value, isA<AdLoading>());
        controller.dispose();
      });
    });
  });
}
