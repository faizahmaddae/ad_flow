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

/// Far above the 183 blocked loads that three healthy hours make.
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

  /// Holds the gate closed for three hours, counting the blocked loads in
  /// each hour, then opens it.
  void closedForThreeHours(
    FakeAsync async, {
    required ValueListenable<AdLoadState> state,
    required void Function() load,
  }) {
    load();
    async.flushMicrotasks();
    expect(blocked, 1);
    expect(state.value, const AdBlocked(AdBlockReason.adsDisabled));

    final perHour = <int>[];
    for (var hour = 0; hour < 3; hour++) {
      final before = blocked;
      async.elapse(const Duration(hours: 1));
      perHour.add(blocked - before);
    }
    // 62 re-checks in the first hour (at 5, 15, 35, 75 and 135 s, then one a
    // minute), then exactly one a minute: never a zero-delay spin.
    expect(perHour, [62, 60, 60]);
    expect(state.value, const AdBlocked(AdBlockReason.adsDisabled));
    expect(sdk.loadLog, isEmpty);

    // Ads are allowed again (a refund, consent given): the slot loads within
    // the minute.
    enabled = true;
    async.elapse(const Duration(minutes: 1));
    expect(state.value, const AdLoaded());
    expect(sdk.loadLog, hasLength(1));
  }

  test('banner: a gate closed for hours is re-checked once a minute, '
      'never on a zero-delay timer', () {
    fakeAsync((async) {
      final c = BannerAdController(
        sdk: sdk,
        gate: gate(),
        config: const BannerConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-b'),
        ),
        adUnitId: 'unit-b',
        retry: retry(),
        onBlocked: onBlocked,
      );
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
      final c = NativeAdController(
        sdk: sdk,
        gate: gate(),
        config: const NativeConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-n'),
          templateKind: NativeTemplateKind.medium,
        ),
        adUnitId: 'unit-n',
        retry: retry(),
        onBlocked: onBlocked,
      );
      closedForThreeHours(async, state: c.state, load: c.load);
      c.dispose();
    });
  });

  test('full-screen (interstitial): a gate closed for hours is re-checked '
      'once a minute, never on a zero-delay timer', () {
    fakeAsync((async) {
      final c = InterstitialAdController(
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
        retry: retry(),
        onBlocked: onBlocked,
      );
      closedForThreeHours(async, state: c.state, load: c.load);
      c.dispose();
    });
  });
}
