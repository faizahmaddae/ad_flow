import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/interstitial_ad_controller.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

/// `canShow` (6.0): the synchronous "would show() show an ad now?" hint that
/// replaces the cap mirrors apps used to keep.
void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late StoredFrequencyCapPolicy caps;
  late DateTime now;
  late bool enabled;

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
    now = DateTime(2026, 11, 18, 9);
    enabled = true;
    coordinator = FullScreenAdCoordinator();
    caps = StoredFrequencyCapPolicy(
      store: InMemoryKeyValueStore(),
      slotCaps: const {
        InterstitialAdController.slotName: FrequencyCap(
          minGap: Duration(minutes: 2),
        ),
      },
      globalCap: const FrequencyCap(),
      now: () => now,
    );
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  InterstitialAdController controller({int minActionsBetween = 0}) =>
      InterstitialAdController(
        sdk: sdk,
        gate: AdGate(
          canRequestAds: sdk.canRequestAds,
          isEnabled: () => enabled,
        ),
        caps: caps,
        coordinator: coordinator,
        config: InterstitialConfig(
          adUnitId: const PlatformAdUnitId(android: 'unit-i'),
          minActionsBetween: minActionsBetween,
        ),
        adUnitId: 'unit-i',
        now: () => now,
      );

  test('false until an ad is loaded, then true', () async {
    final c = controller();
    expect(c.canShow, isFalse);
    await c.load();
    expect(c.canShow, isTrue);
    c.dispose();
  });

  test('false while another full-screen ad is on screen', () async {
    final c = controller();
    await c.load();
    coordinator.enter();
    expect(c.canShow, isFalse);
    coordinator.exit();
    expect(c.canShow, isTrue);
    c.dispose();
  });

  test('follows the frequency cap: false inside the gap after a close, true '
      'after it', () async {
    final c = controller();
    await c.load();
    final shown = c.show();
    await pumpEventQueue();
    sdk.interstitials.single.simulateDismissed();
    await shown;
    await pumpEventQueue(); // the next ad preloads
    expect(c.isReady, isTrue);

    expect(c.canShow, isFalse, reason: 'minGap 2 min not yet elapsed');
    now = now.add(const Duration(minutes: 3));
    expect(c.canShow, isTrue);
    c.dispose();
  });

  test('follows user-action pacing', () async {
    final c = controller(minActionsBetween: 2);
    await c.load();
    c.recordUserAction();
    expect(c.canShow, isFalse, reason: '1 of 2 actions');
    c.recordUserAction();
    expect(c.canShow, isTrue);
    c.dispose();
  });

  test('false while ads are disabled (Remove-Ads)', () async {
    final c = controller();
    await c.load();
    enabled = false;
    expect(c.canShow, isFalse);
    c.dispose();
  });

  test('agrees with show(): true → show() shows', () async {
    final c = controller();
    await c.load();
    expect(c.canShow, isTrue);
    final result = c.show();
    await pumpEventQueue();
    expect(sdk.interstitials.single.showCalls, 1);
    sdk.interstitials.single.simulateDismissed();
    expect((await result).shown, isTrue);
    c.dispose();
  });
}
