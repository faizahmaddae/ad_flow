import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/banner_ad_controller.dart';
import 'package:ad_flow/src/controllers/interstitial_ad_controller.dart';
import 'package:ad_flow/src/controllers/native_ad_controller.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/policy/retry_policy.dart';
import 'package:ad_flow/src/seam/ad_sdk.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Far above the 366 load requests the busiest case below makes in two
/// minutes and a second.
const _spinCeiling = 1000;

const _noFill = AdFlowError(AdFlowErrorKind.loadFailed, 'no fill');

/// A [FakeAdSdk] that counts every load request, failed or not, as it
/// arrives, and stops failing them at [_spinCeiling].
///
/// The count runs INSIDE the re-arm loop, so a zero-delay spin ends in a
/// successful load and the test fails on its counts instead of hanging. A
/// check between two `elapse` calls would never run: a zero-delay loop never
/// lets `elapse` return.
class _CountingSdk extends FakeAdSdk {
  int loads = 0;

  void _count() {
    loads++;
    if (loads >= _spinCeiling) alwaysLoadError = null;
  }

  @override
  Future<BannerHandle> loadBanner(BannerLoadSpec spec) {
    _count();
    return super.loadBanner(spec);
  }

  @override
  Future<NativeHandle> loadNative(NativeLoadSpec spec) {
    _count();
    return super.loadNative(spec);
  }

  @override
  Future<InterstitialHandle> loadInterstitial(
    String adUnitId,
    AdRequestOptions options,
  ) {
    _count();
    return super.loadInterstitial(adUnitId, options);
  }
}

/// A load that keeps failing (no network, no fill) retries `maxAttempts`
/// times, then waits `RetryConfig.cooldown`, resets its attempts and loads
/// again: a loop that runs for as long as the loads keep failing (ADR-008).
///
/// `AdFlowConfig.validate()` rejects only a NEGATIVE cooldown. With a zero one
/// and no retries (`maxAttempts` 0 or 1), or with retries whose delays are all
/// 0 ms (a base under 1 ms), every turn of that loop was a zero-delay timer: a
/// busy loop, each turn a real SDK load request. The cooldown re-arm now waits
/// at least a second (ADR-077), so a slot makes at most one turn a second:
/// one request a turn without retries, `maxAttempts` with 0 ms retries.
void main() {
  late _CountingSdk sdk;
  late FullScreenAdCoordinator coordinator;

  setUp(() {
    sdk = _CountingSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true
      ..alwaysLoadError = _noFill;
    coordinator = FullScreenAdCoordinator();
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  AdGate gate() => AdGate(
    canRequestAds: () async => sdk.canRequestAdsResult,
    isEnabled: () => true,
  );

  BannerAdController banner(RetryPolicy retry, {Duration? minRefresh}) =>
      BannerAdController(
        sdk: sdk,
        gate: gate(),
        config: BannerConfig(
          adUnitId: const PlatformAdUnitId(android: 'unit-b'),
          minRefresh: minRefresh,
        ),
        adUnitId: 'unit-b',
        retry: retry,
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
      );

  /// Each [config] passes `AdFlowConfig.validate()`. [perTurn] is how many
  /// load requests one turn of the loop makes: the first, plus a 0 ms retry
  /// for each attempt left (a 500 µs base is 0 ms in whole milliseconds).
  final cases = [
    (
      name: 'maxAttempts 0, zero cooldown',
      config: const RetryConfig(maxAttempts: 0, cooldown: Duration.zero),
      perTurn: 1,
    ),
    (
      name: 'maxAttempts 1, zero cooldown',
      config: const RetryConfig(maxAttempts: 1, cooldown: Duration.zero),
      perTurn: 1,
    ),
    (
      name: 'a 500 µs base, zero cooldown',
      config: const RetryConfig(
        baseDelay: Duration(microseconds: 500),
        maxDelay: Duration(microseconds: 500),
        cooldown: Duration.zero,
      ),
      perTurn: 3,
    ),
  ];

  /// Counts the load requests made by [start] (with the 0 ms retries that
  /// follow it at once) and then in each of two minutes while every load
  /// fails: [perTurn] at once, then one turn a second. Then lets loads succeed
  /// and expects a load within the second.
  void keepFailing(
    FakeAsync async, {
    required void Function() start,
    required int perTurn,
    required ValueListenable<AdLoadState> state,
    required bool Function() loaded,
  }) {
    final counts = <int>[];
    var before = sdk.loads;
    void count() {
      counts.add(sdk.loads - before);
      before = sdk.loads;
    }

    start();
    count();
    for (var minute = 0; minute < 2; minute++) {
      async.elapse(const Duration(minutes: 1));
      count();
    }
    expect(counts, [perTurn, 60 * perTurn, 60 * perTurn]);
    expect(loaded(), isFalse);

    sdk.alwaysLoadError = null; // the network is back
    async.elapse(const Duration(seconds: 1));
    expect(loaded(), isTrue);
    expect(state.value, const AdLoaded());
  }

  for (final (:name, :config, :perTurn) in cases) {
    // random() is irrelevant: the cooldown is not jittered, and 0 ms jittered
    // is 0 ms.
    RetryPolicy retry() => RetryPolicy(config, random: () => 0.5);

    group(name, () {
      test('banner: a load that keeps failing re-arms at most once a second, '
          'never on a zero-delay timer', () {
        fakeAsync((async) {
          final c = banner(retry());
          keepFailing(
            async,
            start: () {
              c.load(width: 320);
              async.elapse(Duration.zero);
            },
            perTurn: perTurn,
            state: c.state,
            loaded: () => sdk.loadLog.isNotEmpty,
          );
          expect(sdk.loadLog, hasLength(1));
          c.dispose();
        });
      });

      test('native: a load that keeps failing re-arms at most once a second, '
          'never on a zero-delay timer', () {
        fakeAsync((async) {
          final c = native(retry());
          keepFailing(
            async,
            start: () {
              c.load();
              async.elapse(Duration.zero);
            },
            perTurn: perTurn,
            state: c.state,
            loaded: () => sdk.loadLog.isNotEmpty,
          );
          expect(sdk.loadLog, hasLength(1));
          c.dispose();
        });
      });

      test('full-screen (interstitial): a load that keeps failing re-arms at '
          'most once a second, never on a zero-delay timer', () {
        fakeAsync((async) {
          final c = interstitial(retry());
          keepFailing(
            async,
            start: () {
              c.load();
              async.elapse(Duration.zero);
            },
            perTurn: perTurn,
            state: c.state,
            loaded: () => sdk.loadLog.isNotEmpty,
          );
          expect(sdk.loadLog, hasLength(1));
          c.dispose();
        });
      });

      test('banner: a refresh that keeps failing re-arms at most once a '
          'second, and the ad on screen stays', () {
        fakeAsync((async) {
          sdk.alwaysLoadError = null; // the first load fills
          final c = banner(retry(), minRefresh: const Duration(seconds: 30));
          c.load(width: 320);
          async.flushMicrotasks();
          expect(c.state.value, const AdLoaded());
          final onScreen = c.handle;
          sdk.alwaysLoadError = _noFill; // every refresh fails from now on

          keepFailing(
            async,
            // The first refresh, 30 s after the load.
            start: () => async.elapse(const Duration(seconds: 30)),
            perTurn: perTurn,
            state: c.state,
            loaded: () => c.revision.value > 0, // a refresh swapped in
          );
          expect(sdk.loadLog, hasLength(2));
          expect(c.handle, isNot(same(onScreen)));
          c.dispose();
        });
      });
    });
  }
}
