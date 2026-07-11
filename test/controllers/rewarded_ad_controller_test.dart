import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/rewarded_ad_controller.dart';
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
          caps: caps,
          coordinator: coordinator,
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
}
