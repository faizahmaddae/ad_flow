import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/banner_ad_controller.dart';
import 'package:ad_flow/src/controllers/interstitial_ad_controller.dart';
import 'package:ad_flow/src/controllers/native_ad_controller.dart';
import 'package:ad_flow/src/core/ad_block_reason.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/policy/retry_policy.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Far above the 183 blocked loads that three healthy hours make, and the 121
/// that two minutes at the one-second floor make.
const _spinCeiling = 300;

/// A gate that stays CLOSED for hours (Remove-Ads bought, consent declined) is
/// re-checked about once a minute for as long as it stays closed (ADR-035),
/// and the slot loads within a minute of it opening.
///
/// The backoff used to be computed in `int` and overflowed: from the 61st
/// re-check (53 minutes in, with these settings) every delay was 0 ms, so the
/// re-check spun on a zero-delay timer, with an `onAdBlocked` per spin. Under
/// fakeAsync that spin never lets `elapse` return, so these tests count the
/// blocked loads and, at [_spinCeiling], OPEN the gate: the spin then ends in a
/// successful load, and the test fails on its counts instead of hanging.
///
/// A `RetryConfig` whose delays are zero (or under 1 ms) spun the same way from
/// the first re-check on; the re-check now waits at least a second (ADR-076).
void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late bool enabled;
  late int blocked;

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
    coordinator = FullScreenAdCoordinator();
    enabled = false; // Remove-Ads bought before the slot's first load
    blocked = 0;
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  AdGate gate() => AdGate(
    canRequestAds: () async => sdk.canRequestAdsResult,
    isEnabled: () => enabled,
  );

  // The defaults, spelled out so the schedule below does not move with them.
  // random() == 0.5 makes the jitter multiplier exactly 1.0: blocked loads at
  // 0, 5, 15, 35, 75 and 135 s, then one every 60 s.
  RetryPolicy retry() => RetryPolicy(
    const RetryConfig(
      baseDelay: Duration(seconds: 5),
      maxDelay: Duration(minutes: 1),
    ),
    random: () => 0.5,
  );

  void onBlocked(String slot, AdBlockReason reason) {
    blocked++;
    // The re-check is spinning: open the gate, so the next load succeeds and
    // the spin ends, and let the counts below fail.
    if (blocked >= _spinCeiling) enabled = true;
  }

  BannerAdController banner(RetryPolicy retry) => BannerAdController(
    sdk: sdk,
    gate: gate(),
    config: const BannerConfig(adUnitId: PlatformAdUnitId(android: 'unit-b')),
    adUnitId: 'unit-b',
    retry: retry,
    onBlocked: onBlocked,
  );

  NativeAdController native(RetryPolicy retry) => NativeAdController(
    sdk: sdk,
    gate: gate(),
    config: const NativeConfig(
      adUnitId: PlatformAdUnitId(android: 'unit-n'),
      templateKind: NativeTemplateKind.medium,
    ),
    adUnitId: 'unit-n',
    retry: retry,
    onBlocked: onBlocked,
  );

  InterstitialAdController interstitial(RetryPolicy retry) =>
      InterstitialAdController(
        sdk: sdk,
        gate: gate(),
        caps: StoredFrequencyCapPolicy(
          store: InMemoryKeyValueStore(),
          slotCaps: const {},
          globalCap: const FrequencyCap(),
        ),
        coordinator: coordinator,
        config: const InterstitialConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-i'),
        ),
        adUnitId: 'unit-i',
        retry: retry,
        onBlocked: onBlocked,
      );

  /// Holds the gate closed for `perStretch.length` stretches of [stretch],
  /// expecting [perStretch] blocked loads in each, then opens it and expects
  /// the slot to load within [reopen].
  void holdClosed(
    FakeAsync async, {
    required ValueListenable<AdLoadState> state,
    required void Function() load,
    required Duration stretch,
    required List<int> perStretch,
    required Duration reopen,
  }) {
    load();
    async.flushMicrotasks();
    expect(blocked, 1);
    expect(state.value, const AdBlocked(AdBlockReason.adsDisabled));

    final counts = <int>[];
    for (var i = 0; i < perStretch.length; i++) {
      final before = blocked;
      async.elapse(stretch);
      counts.add(blocked - before);
    }
    expect(counts, perStretch);
    expect(state.value, const AdBlocked(AdBlockReason.adsDisabled));
    expect(sdk.loadLog, isEmpty);

    // Ads are allowed again (a refund, consent given): the slot loads within
    // the next re-check.
    enabled = true;
    async.elapse(reopen);
    expect(state.value, const AdLoaded());
    expect(sdk.loadLog, hasLength(1));
  }

  /// Holds the gate closed for three hours, counting the blocked loads in
  /// each hour, then opens it: 62 re-checks in the first hour (at 5, 15, 35,
  /// 75 and 135 s, then one a minute), then exactly one a minute, never a
  /// zero-delay spin; loaded within the minute once ads are allowed again.
  void closedForThreeHours(
    FakeAsync async, {
    required ValueListenable<AdLoadState> state,
    required void Function() load,
  }) => holdClosed(
    async,
    state: state,
    load: load,
    stretch: const Duration(hours: 1),
    perStretch: const [62, 60, 60],
    reopen: const Duration(minutes: 1),
  );

  test('banner: a gate closed for hours is re-checked once a minute, '
      'never on a zero-delay timer', () {
    fakeAsync((async) {
      final c = banner(retry());
      closedForThreeHours(
        async,
        state: c.state,
        load: () => c.load(width: 320),
      );
      c.dispose();
    });
  });

  test('native: a gate closed for hours is re-checked once a minute, '
      'never on a zero-delay timer', () {
    fakeAsync((async) {
      final c = native(retry());
      closedForThreeHours(async, state: c.state, load: c.load);
      c.dispose();
    });
  });

  test('full-screen (interstitial): a gate closed for hours is re-checked '
      'once a minute, never on a zero-delay timer', () {
    fakeAsync((async) {
      final c = interstitial(retry());
      closedForThreeHours(async, state: c.state, load: c.load);
      c.dispose();
    });
  });

  group('a zero RetryConfig (ADR-076)', () {
    // A hand-built controller's RetryPolicy never meets
    // AdFlowConfig.validate(). With a zero baseDelay and maxDelay every delay
    // is 0 ms, so the closed gate was re-checked on a zero-delay timer from
    // the first re-check on. random() is irrelevant: 0 ms jittered is 0 ms.
    RetryPolicy zero() => RetryPolicy(
      const RetryConfig(baseDelay: Duration.zero, maxDelay: Duration.zero),
      random: () => 0.5,
    );

    /// One re-check a second (at 1, 2, … 120 s), never a zero-delay spin;
    /// loaded within the second once ads are allowed again.
    void closedForTwoMinutes(
      FakeAsync async, {
      required ValueListenable<AdLoadState> state,
      required void Function() load,
    }) => holdClosed(
      async,
      state: state,
      load: load,
      stretch: const Duration(minutes: 1),
      perStretch: const [60, 60],
      reopen: const Duration(seconds: 1),
    );

    test('banner: a closed gate is re-checked once a second, never on a '
        'zero-delay timer', () {
      fakeAsync((async) {
        final c = banner(zero());
        closedForTwoMinutes(
          async,
          state: c.state,
          load: () => c.load(width: 320),
        );
        c.dispose();
      });
    });

    test('native: a closed gate is re-checked once a second, never on a '
        'zero-delay timer', () {
      fakeAsync((async) {
        final c = native(zero());
        closedForTwoMinutes(async, state: c.state, load: c.load);
        c.dispose();
      });
    });

    test('full-screen (interstitial): a closed gate is re-checked once a '
        'second, never on a zero-delay timer', () {
      fakeAsync((async) {
        final c = interstitial(zero());
        closedForTwoMinutes(async, state: c.state, load: c.load);
        c.dispose();
      });
    });
  });
}
