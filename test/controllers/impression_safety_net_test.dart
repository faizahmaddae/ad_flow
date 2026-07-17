import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ADR-040 impression safety net: an ad that REACHED THE SCREEN counts,
/// even when its dismiss event never arrives — otherwise the cap
/// under-counts and the next ad can fire too soon (2026-07 audit test gap).
void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late StoredFrequencyCapPolicy caps;
  late DateTime now;

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
    coordinator = FullScreenAdCoordinator();
    now = DateTime(2026, 7, 17, 12);
    caps = StoredFrequencyCapPolicy(
      store: InMemoryKeyValueStore(),
      slotCaps: {
        'interstitial': const FrequencyCap(minGap: Duration(seconds: 30)),
      },
      globalCap: const FrequencyCap(),
      now: () => now,
    );
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  InterstitialAdController controller() => InterstitialAdController(
    sdk: sdk,
    gate: AdGate(
      canRequestAds: sdk.canRequestAds,
      isEnabled: () => true,
      caps: caps,
      coordinator: coordinator,
    ),
    caps: caps,
    coordinator: coordinator,
    config: const InterstitialConfig(
      adUnitId: PlatformAdUnitId(android: 'unit-i'),
    ),
    adUnitId: 'unit-i',
    retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
  );

  test(
    'dispose() while the ad is ON SCREEN still records the impression',
    () async {
      final c = controller();
      await c.load();
      await c.show(); // AdShowedEvent auto-emitted: impression pending
      await pumpEventQueue();

      c.dispose(); // teardown before any dismiss event
      await pumpEventQueue();

      expect(
        await caps.canShow('interstitial'),
        isFalse,
        reason:
            'the ad reached the screen — dropping its impression on teardown '
            'would let the next ad fire too soon',
      );
    },
  );

  test(
    'a failed-to-show AFTER the ad had shown still records the impression',
    () async {
      final c = controller();
      await c.load();
      await c.show();
      await pumpEventQueue();

      // The SDK reports a show failure after the creative had already been on
      // screen (a mid-display crash of the ad activity).
      sdk.interstitials.single.simulateShowFailed(
        const AdFlowError(AdFlowErrorKind.showFailed, 'died mid-display'),
      );
      await pumpEventQueue();

      expect(await caps.canShow('interstitial'), isFalse);
      c.dispose();
    },
  );
}
