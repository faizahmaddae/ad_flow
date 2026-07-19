import 'dart:async';
import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/rewarded_ad_controller.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

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

  RewardedAdController controller({RewardedConfig? config}) =>
      RewardedAdController(
        sdk: sdk,
        gate: AdGate(
          canRequestAds: () async => consented && sdk.canRequestAdsResult,
          isEnabled: () => true,
        ),
        caps: caps,
        coordinator: coordinator,
        config:
            config ??
            const RewardedConfig(adUnitId: PlatformAdUnitId(android: 'unit-r')),
        adUnitId: 'unit-r',
      );

  test('no load while consent is closed (invariant 1)', () async {
    consented = false;
    sdk.canRequestAdsResult = false;
    final c = controller();
    await c.load();
    expect(sdk.loadLog, isEmpty); // enforceConsentGate would throw if hit
    c.dispose();
  });

  test('loads through the rewarded seam path', () async {
    final c = controller();
    await c.load();
    expect(sdk.loadLog, ['rewarded:unit-r']);
    expect(c.isReady, isTrue);
    c.dispose();
  });

  test('an SSV attach failure is a FAILED load, never a ready ad that '
      'silently lost its server-side verification (4.0 audit)', () async {
    sdk.ssvAttachError = const AdFlowError(
      AdFlowErrorKind.ssv,
      'SSV could not be attached',
    );
    final c = controller(
      config: const RewardedConfig(
        adUnitId: PlatformAdUnitId(android: 'unit-r'),
        ssv: ServerSideVerification(userId: 'user-1'),
      ),
    );
    await c.load();
    expect(
      c.isReady,
      isFalse,
      reason:
          'a reward the publisher configured as server-verified must never '
          'be served without that verification attached',
    );
    expect(c.state.value, isA<AdFailed>());
    c.dispose();
  });

  test('forwards SSV options from config to the seam', () async {
    final c = controller(
      config: const RewardedConfig(
        adUnitId: PlatformAdUnitId(android: 'unit-r'),
        ssv: ServerSideVerification(userId: 'user-1', customData: 'level-9'),
      ),
    );
    await c.load();
    expect(sdk.rewardedSsvs.single?.userId, 'user-1');
    expect(sdk.rewardedSsvs.single?.customData, 'level-9');
    c.dispose();
  });

  test('reward callback fires exactly once even if the SDK misfires', () async {
    final c = controller();
    await c.load();

    final rewards = <RewardEarned>[];
    await c.show(onReward: rewards.add);

    final handle = sdk.rewardeds.single;
    handle.simulateReward(const RewardEarned(amount: 10, type: 'coins'));
    handle.simulateReward(const RewardEarned(amount: 10, type: 'coins'));

    expect(rewards, hasLength(1));
    expect(rewards.single, const RewardEarned(amount: 10, type: 'coins'));
    c.dispose();
  });

  test('dismiss preloads the next rewarded ad', () async {
    final c = controller();
    await c.load();
    await c.show(onReward: (_) {});
    sdk.rewardeds.single.simulateDismissed();
    await Future<void>.delayed(Duration.zero);

    expect(sdk.rewardeds, hasLength(2));
    expect(c.isReady, isTrue);
    c.dispose();
  });

  group('runtime SSV (2026-07 audit)', () {
    test(
      'setServerSideVerification applies to the WARM ad immediately',
      () async {
        final c = controller();
        await c.load();
        expect(c.isReady, isTrue);

        const ssv = ServerSideVerification(
          userId: 'user-42',
          customData: 'mission-7',
        );
        await c.setServerSideVerification(ssv);

        expect(sdk.rewardeds.single.ssvUpdates, [ssv]);
        c.dispose();
      },
    );

    test('the override replaces config SSV on every FUTURE load too', () async {
      final c = controller(
        config: const RewardedConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-r'),
          ssv: ServerSideVerification(userId: 'config-user'),
        ),
      );
      await c.load();
      expect(sdk.rewardedSsvs.last?.userId, 'config-user');

      const ssv = ServerSideVerification(userId: 'user-42');
      await c.setServerSideVerification(ssv);

      // Spend the ad; the automatic reload must carry the override.
      await c.show(onReward: (_) {});
      sdk.rewardeds.single.simulateDismissed();
      await Future<void>.delayed(Duration.zero);
      expect(sdk.rewardedSsvs.last?.userId, 'user-42');
      c.dispose();
    });

    test('set BEFORE any load: the first load already carries it', () async {
      final c = controller();
      await c.setServerSideVerification(
        const ServerSideVerification(userId: 'early'),
      );
      await c.load();
      expect(sdk.rewardedSsvs.last?.userId, 'early');
      c.dispose();
    });

    test('an attach failure on the warm ad SURFACES to the caller', () async {
      final c = controller();
      await c.load();
      sdk.rewardeds.single.ssvUpdateError = StateError('channel down');

      await expectLater(
        c.setServerSideVerification(
          const ServerSideVerification(userId: 'user-42'),
        ),
        throwsA(isA<StateError>()),
        reason:
            'a caller granting high-value rewards must know its '
            'verification payload did not attach',
      );
      c.dispose();
    });

    test('an attach failure DROPS the stale warm ad so it cannot be shown '
        'with the wrong verification (4.1 audit)', () async {
      final c = controller();
      await c.load();
      final stale = sdk.rewardeds.single;
      stale.ssvUpdateError = StateError('channel down');

      await expectLater(
        c.setServerSideVerification(
          const ServerSideVerification(userId: 'user-42'),
        ),
        throwsA(isA<StateError>()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        stale.disposed,
        isTrue,
        reason:
            'the ad whose SSV could not be updated must not remain showable '
            'carrying the OLD verification payload',
      );
      // A fresh ad is warmed to replace it, carrying the new override.
      expect(sdk.rewardeds.length, greaterThan(1));
      expect(sdk.rewardedSsvs.last?.userId, 'user-42');
      c.dispose();
    });

    test('set during an IN-FLIGHT load: the installed ad carries the new ssv, '
        'not the stale value the load dispatched with (4.1 audit)', () async {
      final c = controller();
      // Park the load in flight (the handle is not installed yet, so
      // setServerSideVerification finds no warm ad to update directly).
      sdk.loadHold = Completer<void>();
      final loading = c.load();
      await Future<void>.delayed(Duration.zero);
      expect(c.isReady, isFalse);

      // The app learns the userId (login) while the ad is still loading.
      await c.setServerSideVerification(
        const ServerSideVerification(userId: 'late-login'),
      );

      // The load lands.
      sdk.loadHold!.complete();
      sdk.loadHold = null;
      await loading;
      await Future<void>.delayed(Duration.zero);

      expect(c.isReady, isTrue);
      expect(
        sdk.rewardeds.single.ssvUpdates.map((s) => s.userId),
        contains('late-login'),
        reason:
            'the ad installed by a load that was in flight when '
            'setServerSideVerification ran must be re-attached the latest '
            'ssv, or it silently carries the pre-update payload',
      );
      c.dispose();
    });

    test('LATEST-VALUE-WINS across rapid updates on a warm ad, and on the '
        'next load (release gate)', () async {
      final c = controller();
      await c.load();
      // Two rapid updates; the LAST must be the effective one everywhere.
      await c.setServerSideVerification(
        const ServerSideVerification(userId: 'first'),
      );
      await c.setServerSideVerification(
        const ServerSideVerification(userId: 'second'),
      );
      expect(
        sdk.rewardeds.single.ssvUpdates.last.userId,
        'second',
        reason: 'the warm ad carries the latest payload',
      );

      // The next load must dispatch with 'second', not 'first'.
      await c.show(onReward: (_) {});
      sdk.rewardeds.single.simulateDismissed();
      await Future<void>.delayed(Duration.zero);
      expect(sdk.rewardedSsvs.last?.userId, 'second');
      c.dispose();
    });

    test('LATEST-VALUE-WINS when TWO updates happen during ONE in-flight load '
        '— the install re-attaches the last, not the first (release gate)',
        () async {
      final c = controller();
      sdk.loadHold = Completer<void>();
      final loading = c.load();
      await Future<void>.delayed(Duration.zero);
      expect(c.isReady, isFalse);

      // Two rapid updates while the load is parked in flight.
      await c.setServerSideVerification(
        const ServerSideVerification(userId: 'v1'),
      );
      await c.setServerSideVerification(
        const ServerSideVerification(userId: 'v2'),
      );

      sdk.loadHold!.complete();
      sdk.loadHold = null;
      await loading;
      await Future<void>.delayed(Duration.zero);

      expect(c.isReady, isTrue);
      expect(
        sdk.rewardeds.single.ssvUpdates.last.userId,
        'v2',
        reason: 'onLoaded must re-attach the LATEST override, never a stale one',
      );
      c.dispose();
    });

    test('DISPOSE during an in-flight update does not crash and installs '
        'nothing on the dead controller (release gate)', () async {
      final c = controller();
      await c.load();
      sdk.rewardeds.single.ssvUpdateHold = Completer<void>();

      final update = c.setServerSideVerification(
        const ServerSideVerification(userId: 'racing'),
      );
      await Future<void>.delayed(Duration.zero); // attach parked in flight

      c.dispose(); // hosting screen popped mid-attach
      sdk.rewardeds.single.ssvUpdateHold!.complete();

      // The update future resolves (or reports) without throwing into the
      // zone; nothing is installed on the disposed controller.
      await update.timeout(
        const Duration(seconds: 1),
        onTimeout: () {},
      ).catchError((Object _) {});
      expect(c.state.value, isA<AdLoaded>()); // last state before dispose froze
    });

    test('DISPOSE during an in-flight LOAD with a reapply pending never '
        'attaches to a disposed ad (release gate)', () async {
      final c = controller();
      sdk.loadHold = Completer<void>();
      final loading = c.load();
      await Future<void>.delayed(Duration.zero);

      // Update while loading → reapply pending on install.
      await c.setServerSideVerification(
        const ServerSideVerification(userId: 'late'),
      );
      c.dispose(); // dispose BEFORE the load lands

      sdk.loadHold!.complete();
      sdk.loadHold = null;
      await loading.catchError((Object _) {});
      await Future<void>.delayed(Duration.zero);
      // The handle from a load that completed after dispose is released, and
      // no SSV is attached to it (the controller bailed on its _disposed guard).
      expect(
        sdk.rewardeds.isEmpty || sdk.rewardeds.single.disposed,
        isTrue,
      );
    });
  });
}
