import 'dart:async';

import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/full_screen_ad_controller_base.dart';
import 'package:ad_flow/src/controllers/interstitial_ad_controller.dart';
import 'package:ad_flow/src/controllers/rewarded_ad_controller.dart';
import 'package:ad_flow/src/core/ad_block_reason.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/core/ad_show_result.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// `show()` completes when the ad CLOSES, with a result that says what
/// happened (6.0) — the wait every app used to hand-write around the
/// controller's state.
void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late StoredFrequencyCapPolicy caps;

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
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
      AdGate(canRequestAds: sdk.canRequestAds, isEnabled: () => true);

  InterstitialAdController interstitial() => InterstitialAdController(
    sdk: sdk,
    gate: gate(),
    caps: caps,
    coordinator: coordinator,
    config: const InterstitialConfig(
      adUnitId: PlatformAdUnitId(android: 'unit-i'),
      cap: FrequencyCap(),
    ),
    adUnitId: 'unit-i',
  );

  RewardedAdController rewarded() => RewardedAdController(
    sdk: sdk,
    gate: gate(),
    caps: caps,
    coordinator: coordinator,
    config: const RewardedConfig(adUnitId: PlatformAdUnitId(android: 'unit-r')),
    adUnitId: 'unit-r',
  );

  test('completes only when the ad closes, with shown', () async {
    final c = interstitial();
    await c.load();
    AdShowResult? result;
    unawaited(c.show().then((r) => result = r));
    await pumpEventQueue();
    expect(sdk.interstitials.single.showCalls, 1);
    expect(result, isNull, reason: 'the ad is still on screen');

    sdk.interstitials.single.simulateDismissed();
    await pumpEventQueue();
    expect(result, const AdShowResult.shown());
    c.dispose();
  });

  test('a refused show completes at once with the reason', () async {
    final c = interstitial(); // never loaded
    expect(await c.show(), const AdShowResult.blocked(AdBlockReason.notReady));
    c.dispose();
  });

  test('another full-screen ad on screen → blocked(otherAdShowing)', () async {
    final c = interstitial();
    await c.load();
    coordinator.enter(); // e.g. an app-open ad is up
    expect(
      await c.show(),
      const AdShowResult.blocked(AdBlockReason.otherAdShowing),
    );
    coordinator.exit();
    c.dispose();
  });

  test('a failure before the ad reached the screen → failed', () async {
    final c = interstitial();
    await c.load();
    final handle = sdk.interstitials.single
      ..autoEmitShowed = false
      ..showError = const AdFlowError(AdFlowErrorKind.showFailed, 'gone');
    final result = await c.show();
    expect(result.shown, isFalse);
    expect(result.error?.message, 'gone');
    expect(handle.showCalls, 1);
    c.dispose();
  });

  test('rewarded: the result carries the reward, and onReward still fires '
      'once', () async {
    final c = rewarded();
    await c.load();
    final granted = <RewardEarned>[];
    final pending = c.show(onReward: granted.add);
    await pumpEventQueue();
    const reward = RewardEarned(amount: 10, type: 'coins');
    sdk.rewardeds.single
      ..simulateReward(reward)
      ..simulateReward(reward) // an SDK misfire
      ..simulateDismissed();

    final result = await pending;
    expect(result, const AdShowResult.shown(reward: reward));
    expect(granted, [reward]);
    c.dispose();
  });

  test(
    'rewarded without onReward: the reward is still in the result',
    () async {
      final c = rewarded();
      await c.load();
      final pending = c.show();
      await pumpEventQueue();
      const reward = RewardEarned(amount: 1, type: 'life');
      sdk.rewardeds.single
        ..simulateReward(reward)
        ..simulateDismissed();
      expect((await pending).reward, reward);
      c.dispose();
    },
  );

  test('closed without a reward → shown, reward null', () async {
    final c = rewarded();
    await c.load();
    final pending = c.show();
    await pumpEventQueue();
    sdk.rewardeds.single.simulateDismissed();
    expect(await pending, const AdShowResult.shown());
    c.dispose();
  });

  test('an ad the SDK never puts on screen completes failed(timeout) after '
      'presentationTimeout', () {
    fakeAsync((async) {
      final c = interstitial();
      c.load();
      async.flushMicrotasks();
      sdk.interstitials.single.autoEmitShowed = false; // never presented
      AdShowResult? result;
      c.show().then((r) => result = r);
      async.flushMicrotasks();

      async.elapse(FullScreenAdControllerBase.presentationTimeout);
      expect(result?.shown, isFalse);
      expect(result?.error?.kind, AdFlowErrorKind.timeout);
      c.dispose();
    });
  });

  test('a show call that never replies is still bounded', () {
    fakeAsync((async) {
      final c = interstitial();
      c.load();
      async.flushMicrotasks();
      sdk.interstitials.single.showHold = Completer<void>();
      AdShowResult? result;
      c.show().then((r) => result = r);
      async.elapse(FullScreenAdControllerBase.presentationTimeout);
      expect(result?.error?.kind, AdFlowErrorKind.timeout);
      c.dispose();
    });
  });

  test('ON SCREEN there is no timeout: a user who leaves mid-video and '
      'finishes later still gets the reward in the result', () {
    fakeAsync((async) {
      final c = rewarded();
      c.load();
      async.flushMicrotasks();
      AdShowResult? result;
      c.show().then((r) => result = r);
      async.flushMicrotasks();

      async.elapse(const Duration(minutes: 20)); // away, ad still open
      expect(result, isNull);

      const reward = RewardEarned(amount: 5, type: 'coins');
      sdk.rewardeds.single
        ..simulateReward(reward)
        ..simulateDismissed();
      async.flushMicrotasks();
      expect(result, const AdShowResult.shown(reward: reward));
      c.dispose();
    });
  });

  test('dispose while the ad is on screen completes the result', () async {
    final c = interstitial();
    await c.load();
    final pending = c.show();
    await pumpEventQueue();
    c.dispose();
    expect(await pending, const AdShowResult.shown());
  });
}
