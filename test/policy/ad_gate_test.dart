import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late bool consented;
  late bool enabled;
  late int consentChecks;
  late FullScreenAdCoordinator coordinator;
  late StoredFrequencyCapPolicy caps;
  late AdGate gate;

  setUp(() {
    consented = true;
    enabled = true;
    consentChecks = 0;
    coordinator = FullScreenAdCoordinator();
    caps = StoredFrequencyCapPolicy(
      store: InMemoryKeyValueStore(),
      slotCaps: {'interstitial': const FrequencyCap(maxPerSession: 1)},
      globalCap: const FrequencyCap(),
      now: DateTime.now,
    );
    gate = AdGate(
      canRequestAds: () async {
        consentChecks++;
        return consented;
      },
      isEnabled: () => enabled,
      caps: caps,
      coordinator: coordinator,
    );
  });
  tearDown(() => coordinator.dispose());

  group('canLoad (invariant 1: consent gates every load)', () {
    test('true only when enabled AND consented', () async {
      expect(await gate.canLoad('interstitial'), isTrue);

      consented = false;
      expect(await gate.canLoad('interstitial'), isFalse);

      consented = true;
      enabled = false;
      expect(await gate.canLoad('interstitial'), isFalse);
    });

    test('disabled ads short-circuit before the consent check', () async {
      enabled = false;
      await gate.canLoad('interstitial');
      expect(consentChecks, 0);
    });
  });

  group('canShow', () {
    test('true when everything allows', () async {
      expect(await gate.canShow('interstitial'), isTrue);
    });

    test('false while another full-screen ad is visible', () async {
      coordinator.enter();
      expect(await gate.canShow('interstitial'), isFalse);
      coordinator.exit();
      expect(await gate.canShow('interstitial'), isTrue);
    });

    test('false when the frequency cap is exhausted', () async {
      await caps.recordImpression('interstitial');
      expect(await gate.canShow('interstitial'), isFalse);
      // Loading stays allowed — keep the next ad warm for later.
      expect(await gate.canLoad('interstitial'), isTrue);
    });

    test('false without consent or when disabled', () async {
      consented = false;
      expect(await gate.canShow('interstitial'), isFalse);

      consented = true;
      enabled = false;
      expect(await gate.canShow('interstitial'), isFalse);
    });
  });
}
