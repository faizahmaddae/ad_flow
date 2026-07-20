import 'dart:async';

import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/rewarded_ad_controller.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runtime-SSV readiness/concurrency invariants (5.1 hardening).
///
/// A rewarded / rewarded-interstitial ad must never be externally ready or
/// showable until the LATEST required SSV payload has settled successfully.
/// These are the adversarial cases the pre-5.1 design could not honour: the
/// old design published `AdLoaded` first and re-attached the override
/// afterwards (unawaited), so a state listener or an immediate `show()` could
/// use the stale payload; and concurrent updates had no generation guard, so a
/// stale completion could clobber the latest.
void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late StoredFrequencyCapPolicy caps;
  late bool consented;

  setUp(() {
    sdk = FakeAdSdk();
    sdk.enforceConsentGate = true;
    sdk.canRequestAdsResult = true;
    consented = true;
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

  RewardedAdController controller() => RewardedAdController(
    sdk: sdk,
    gate: AdGate(
      canRequestAds: () async => consented && sdk.canRequestAdsResult,
      isEnabled: () => true,
    ),
    caps: caps,
    coordinator: coordinator,
    config: const RewardedConfig(adUnitId: PlatformAdUnitId(android: 'unit-r')),
    adUnitId: 'unit-r',
  );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('an ad is NOT showable until an in-flight-load SSV re-attach settles '
      '(set while load held → complete load → show while attach held)', () async {
    final attachHold = Completer<void>();
    final c = controller();
    sdk.loadHold = Completer<void>();
    // Arm the re-attach hold on the handle the load will install.
    sdk.onFullScreenHandleCreated = (h) => h.ssvUpdateHold = attachHold;

    final loading = c.load();
    await settle();
    expect(c.isReady, isFalse);

    // The app learns the userId (login) while the ad is still loading.
    await c.setServerSideVerification(
      const ServerSideVerification(userId: 'u1'),
    );

    // The load lands; finalization re-attaches the override — but that attach
    // is HELD, so the ad is not yet settled.
    sdk.loadHold!.complete();
    sdk.loadHold = null;
    await settle();

    expect(
      c.isReady,
      isFalse,
      reason:
          'the ad carries the pre-update SSV payload until the re-attach '
          'settles — it must not be showable',
    );
    final shown = await c.show(onReward: (_) {});
    expect(shown, isFalse);
    expect(sdk.rewardeds.single.showCalls, 0);

    // Release the attach → settled → showable.
    attachHold.complete();
    await settle();
    expect(c.isReady, isTrue);
    c.dispose();
  });

  test('AdLoaded is not published to listeners until the SSV re-attach settles '
      '(a show() from an AdLoaded listener never uses the stale payload)',
      () async {
    final attachHold = Completer<void>();
    final c = controller();
    sdk.loadHold = Completer<void>();
    sdk.onFullScreenHandleCreated = (h) => h.ssvUpdateHold = attachHold;

    final loading = c.load();
    await settle();
    await c.setServerSideVerification(
      const ServerSideVerification(userId: 'u2'),
    );

    var loadedFired = false;
    c.state.addListener(() {
      if (c.state.value is AdLoaded) loadedFired = true;
    });

    sdk.loadHold!.complete();
    sdk.loadHold = null;
    await settle();

    expect(
      loadedFired,
      isFalse,
      reason:
          'a state listener must not observe AdLoaded while the required SSV '
          'is still settling — otherwise show()-on-loaded shows the stale ad',
    );
    expect(c.state.value, isA<AdLoading>());

    attachHold.complete();
    await settle();
    expect(loadedFired, isTrue);
    expect(
      sdk.rewardeds.single.ssvUpdates.map((s) => s.userId),
      contains('u2'),
    );
    await loading;
    c.dispose();
  });

  test('a superseded SSV update that FAILS late (reverse-order completion) '
      'does not clobber the latest-verified ad', () async {
    final c = controller();
    await c.load();
    final handle = sdk.rewardeds.single;

    final holdA = Completer<void>();
    final holdB = Completer<void>();

    handle.ssvUpdateHold = holdA;
    final a = c.setServerSideVerification(
      const ServerSideVerification(userId: 'A'),
    );
    handle.ssvUpdateHold = holdB;
    final b = c.setServerSideVerification(
      const ServerSideVerification(userId: 'B'),
    );

    // The LATEST (B) settles first.
    holdB.complete();
    await b;

    // The stale (A) then FAILS late — it must be ignored as superseded, never
    // discard the B-verified ad.
    handle.ssvUpdateError = StateError('late stale failure');
    holdA.complete();
    await a.catchError((Object _) {});
    await settle();

    expect(
      handle.disposed,
      isFalse,
      reason:
          'a superseded update failing late must not drop the ad the latest '
          'update already validated',
    );
    expect(c.isReady, isTrue);
    expect(
      sdk.rewardeds,
      hasLength(1),
      reason: 'no spurious reload triggered by the stale failure',
    );
    c.dispose();
  });

  test('a re-attach failure during load finalization fails the load CLOSED '
      '(never a ready ad missing its required verification)', () async {
    final c = controller();
    sdk.loadHold = Completer<void>();
    // The re-attach on the finalized handle will fail.
    sdk.onFullScreenHandleCreated =
        (h) => h.ssvUpdateError = StateError('attach failed');

    final loading = c.load();
    await settle();
    await c.setServerSideVerification(
      const ServerSideVerification(userId: 'u'),
    );

    sdk.loadHold!.complete();
    sdk.loadHold = null;
    await loading;
    await settle();

    expect(
      c.isReady,
      isFalse,
      reason:
          'a load whose required SSV could not attach must fail closed, never '
          'present a ready ad missing its verification',
    );
    expect(c.state.value, isA<AdFailed>());
    expect(
      sdk.rewardeds.first.disposed,
      isTrue,
      reason: 'the un-verifiable handle is dropped',
    );
    c.dispose();
  });

  test('DISPOSE during load finalization installs nothing and does not crash',
      () async {
    final attachHold = Completer<void>();
    final c = controller();
    sdk.loadHold = Completer<void>();
    sdk.onFullScreenHandleCreated = (h) => h.ssvUpdateHold = attachHold;

    final loading = c.load();
    await settle();
    await c.setServerSideVerification(
      const ServerSideVerification(userId: 'u'),
    );

    sdk.loadHold!.complete();
    sdk.loadHold = null;
    await settle(); // finalization now parked on attachHold

    c.dispose(); // hosting screen popped mid-finalization
    attachHold.complete();
    await loading.catchError((Object _) {});
    await settle();

    expect(
      c.state.value,
      isNot(isA<AdLoaded>()),
      reason: 'a load that finalized after dispose must never publish AdLoaded',
    );
  });
}
