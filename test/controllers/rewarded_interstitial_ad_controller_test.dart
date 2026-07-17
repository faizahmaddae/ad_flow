import 'dart:async';

import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/rewarded_interstitial_ad_controller.dart';
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
  late List<RewardIntroContent> introsShown;
  late bool introAnswer;
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
    introsShown = [];
    introAnswer = true;
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  RewardedInterstitialAdController controller() =>
      RewardedInterstitialAdController(
        sdk: sdk,
        gate: AdGate(
          canRequestAds: () async => consented && sdk.canRequestAdsResult,
          isEnabled: () => true,
        ),
        caps: caps,
        coordinator: coordinator,
        config: const RewardedInterstitialConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-ri'),
          intro: RewardIntroContent(title: 'Get 50 coins'),
          ssv: ServerSideVerification(userId: 'user-1'),
        ),
        adUnitId: 'unit-ri',
        showIntro: (content) async {
          introsShown.add(content);
          return introAnswer;
        },
      );

  test('no load while consent is closed (invariant 1)', () async {
    consented = false;
    sdk.canRequestAdsResult = false;
    final c = controller();
    await c.load();
    expect(sdk.loadLog, isEmpty); // enforceConsentGate would throw if hit
    expect(introsShown, isEmpty); // never reaches the intro without an ad
    c.dispose();
  });

  test('the intro always precedes the ad (policy, ADR-013)', () async {
    final c = controller();
    await c.load();

    final shown = await c.show(onReward: (_) {});

    expect(shown, isTrue);
    expect(introsShown, hasLength(1));
    expect(introsShown.single.title, 'Get 50 coins');
    expect(sdk.rewardedInterstitials.single.showCalls, 1);
    c.dispose();
  });

  test('skipping the intro shows no ad and keeps it warm', () async {
    introAnswer = false;
    final c = controller();
    await c.load();

    final shown = await c.show(onReward: (_) {});

    expect(shown, isFalse);
    expect(introsShown, hasLength(1));
    expect(sdk.rewardedInterstitials.single.showCalls, 0);
    expect(c.isReady, isTrue); // ad still warm for a later attempt
    c.dispose();
  });

  test('no warm ad: intro is NOT shown, preload starts instead', () async {
    final c = controller();
    expect(await c.show(onReward: (_) {}), isFalse);
    await Future<void>.delayed(Duration.zero);

    expect(introsShown, isEmpty); // never bother the user without an ad
    expect(sdk.rewardedInterstitials, hasLength(1));
    c.dispose();
  });

  test('re-entrant show during an open intro is rejected', () async {
    // The intro presenter suspends until we release it, so the second
    // show() arrives while the first intro is still on screen.
    final introGate = Completer<bool>();
    final c = RewardedInterstitialAdController(
      sdk: sdk,
      gate: AdGate(canRequestAds: sdk.canRequestAds, isEnabled: () => true),
      caps: caps,
      coordinator: coordinator,
      config: const RewardedInterstitialConfig(
        adUnitId: PlatformAdUnitId(android: 'unit-ri'),
      ),
      adUnitId: 'unit-ri',
      showIntro: (content) {
        introsShown.add(content);
        return introGate.future;
      },
    );
    await c.load();

    final first = c.show(onReward: (_) {});
    await Future<void>.delayed(Duration.zero);
    final second = await c.show(onReward: (_) {});
    introGate.complete(true);

    expect(second, isFalse);
    expect(await first, isTrue);
    expect(introsShown, hasLength(1));
    expect(sdk.rewardedInterstitials.single.showCalls, 1);
    c.dispose();
  });

  test('dispose while the intro is on screen never shows the ad once the '
      'intro later resolves', () async {
    final introGate = Completer<bool>();
    final c = RewardedInterstitialAdController(
      sdk: sdk,
      gate: AdGate(canRequestAds: sdk.canRequestAds, isEnabled: () => true),
      caps: caps,
      coordinator: coordinator,
      config: const RewardedInterstitialConfig(
        adUnitId: PlatformAdUnitId(android: 'unit-ri'),
      ),
      adUnitId: 'unit-ri',
      showIntro: (content) {
        introsShown.add(content);
        return introGate.future;
      },
    );
    await c.load();
    final handle = sdk.rewardedInterstitials.single;

    final shown = c.show(onReward: (_) {});
    await Future<void>.delayed(Duration.zero); // intro is now "on screen"
    c.dispose(); // e.g. the hosting screen was popped mid-intro
    introGate.complete(true); // user taps "watch" after the screen is gone

    expect(await shown, isFalse);
    expect(handle.showCalls, 0);
  });

  test('forwards SSV options to the seam', () async {
    final c = controller();
    await c.load();
    expect(sdk.rewardedInterstitialSsvs.single?.userId, 'user-1');
    c.dispose();
  });

  test('reward fires exactly once through the intro path', () async {
    final c = controller();
    await c.load();

    final rewards = <RewardEarned>[];
    await c.show(onReward: rewards.add);
    final handle = sdk.rewardedInterstitials.single;
    handle.simulateReward(const RewardEarned(amount: 50, type: 'coins'));
    handle.simulateReward(const RewardEarned(amount: 50, type: 'coins'));

    expect(rewards, hasLength(1));
    c.dispose();
  });
}
