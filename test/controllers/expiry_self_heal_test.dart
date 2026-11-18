import 'dart:async';

import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/interstitial_ad_controller.dart';
import 'package:ad_flow/src/controllers/rewarded_interstitial_ad_controller.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// An expired warm ad is always replaced, even when nothing calls show()
/// (6.0 review): `canShow` heals it, and a show that held the slot past the
/// ad's age (a long rewarded intro) drops it on rollback.
void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late StoredFrequencyCapPolicy caps;
  late DateTime now;

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
    now = DateTime(2026, 11, 18, 9);
    coordinator = FullScreenAdCoordinator();
    caps = StoredFrequencyCapPolicy(
      store: InMemoryKeyValueStore(),
      slotCaps: const {},
      globalCap: const FrequencyCap(),
      now: () => now,
    );
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  AdGate gate() =>
      AdGate(canRequestAds: sdk.canRequestAds, isEnabled: () => true);

  test('canShow replaces a warm ad the wall clock says is stale, though the '
      'expiry timer has not fired (the device slept)', () {
    fakeAsync((async) {
      final c = InterstitialAdController(
        sdk: sdk,
        gate: gate(),
        caps: caps,
        coordinator: coordinator,
        config: const InterstitialConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-i'),
          cap: FrequencyCap(),
          maxAdAge: Duration(minutes: 55),
        ),
        adUnitId: 'unit-i',
        now: () => now,
      );
      c.load();
      async.flushMicrotasks();
      expect(c.canShow, isTrue);

      // Wall clock jumps; Dart timers did not run (device asleep).
      now = now.add(const Duration(hours: 8));
      expect(c.canShow, isFalse);
      async.flushMicrotasks();

      expect(sdk.interstitials.first.disposed, isTrue);
      expect(sdk.interstitials, hasLength(2), reason: 'a fresh ad loaded');
      expect(c.canShow, isTrue);
      expect(c.lastBlockReason, isNull);
      c.dispose();
    });
  });

  test('a rewarded intro that outlasts the ad: skipping drops the expired ad '
      'and loads a fresh one, instead of leaving it warm forever', () {
    fakeAsync((async) {
      final intro = Completer<bool>();
      final c = RewardedInterstitialAdController(
        sdk: sdk,
        gate: gate(),
        caps: caps,
        coordinator: coordinator,
        config: const RewardedInterstitialConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-ri'),
          maxAdAge: Duration(minutes: 55),
        ),
        adUnitId: 'unit-ri',
        showIntro: (_) => intro.future,
        now: () => now,
      );
      c.load();
      async.flushMicrotasks();
      final first = sdk.rewardedInterstitials.single;

      c.show();
      async.flushMicrotasks(); // the intro is on screen
      now = now.add(const Duration(hours: 1));
      async.elapse(const Duration(hours: 1)); // expiry timer fires, no-op
      intro.complete(false); // skip
      async.flushMicrotasks();

      expect(first.disposed, isTrue);
      expect(first.showCalls, 0);
      expect(sdk.rewardedInterstitials, hasLength(2));
      expect(c.state.value, const AdLoaded());
      expect(coordinator.isFullScreenAdVisible, isFalse);
      c.dispose();
    });
  });

  test('a skip well inside the age re-arms the expiry: the ad is still '
      'replaced on time later', () {
    fakeAsync((async) {
      final intro = Completer<bool>();
      final c = RewardedInterstitialAdController(
        sdk: sdk,
        gate: gate(),
        caps: caps,
        coordinator: coordinator,
        config: const RewardedInterstitialConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-ri'),
          maxAdAge: Duration(minutes: 55),
        ),
        adUnitId: 'unit-ri',
        showIntro: (_) => intro.future,
        now: () => now,
      );
      c.load();
      async.flushMicrotasks();
      c.show();
      async.flushMicrotasks();
      now = now.add(const Duration(minutes: 10));
      async.elapse(const Duration(minutes: 10));
      intro.complete(false);
      async.flushMicrotasks();
      expect(sdk.rewardedInterstitials, hasLength(1), reason: 'still fresh');

      now = now.add(const Duration(minutes: 45));
      async.elapse(const Duration(minutes: 45));
      expect(sdk.rewardedInterstitials.first.disposed, isTrue);
      expect(sdk.rewardedInterstitials, hasLength(2));
      c.dispose();
    });
  });
}
