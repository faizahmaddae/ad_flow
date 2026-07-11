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

    test(
      'is racy by construction when two callers check-then-act — this is '
      'exactly why no controller uses it to gate an actual show() '
      '(review finding #6; see the method\'s own doc + ADR-024/DECISIONS)',
      () async {
        // Two independent "controllers" both consult canShow() before
        // either has entered the coordinator — an await-separated check
        // lets both observe "nothing is showing" in the same turn.
        final firstSaysOk = await gate.canShow('interstitial');
        final secondSaysOk = await gate.canShow('interstitial');

        expect(firstSaysOk, isTrue);
        expect(secondSaysOk, isTrue); // <- the race: both got a green light
        // Contrast with FullScreenAdCoordinator.tryEnter(), which closes
        // exactly this window (see full_screen_ad_coordinator_test.dart's
        // "two synchronous tryEnter calls: only the first wins").
      },
    );
  });
}
