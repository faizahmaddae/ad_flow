import 'package:ad_flow/src/core/ad_block_reason.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:flutter_test/flutter_test.dart';

/// 3.0: `AdGate` is a pure PERMISSION gate — frequency caps and the
/// full-screen coordinator moved out (they are show-pacing concerns owned by
/// the controllers), and the unfixably racy composed `canShow` query was
/// removed with them (review finding #6; controllers were already forbidden
/// from using it to gate a real show since ADR-024).
void main() {
  late bool consented;
  late bool enabled;
  late int consentChecks;
  late AdGate gate;

  setUp(() {
    consented = true;
    enabled = true;
    consentChecks = 0;
    gate = AdGate(
      canRequestAds: () async {
        consentChecks++;
        return consented;
      },
      isEnabled: () => enabled,
    );
  });

  group(
    'canLoad / loadBlockReason (invariant 1: consent gates every load)',
    () {
      test('open only when enabled AND consented, with the reason', () async {
        expect(await gate.canLoad('interstitial'), isTrue);
        expect(await gate.loadBlockReason('interstitial'), isNull);

        consented = false;
        expect(
          await gate.loadBlockReason('interstitial'),
          AdBlockReason.consentNotGranted,
        );

        consented = true;
        enabled = false;
        expect(
          await gate.loadBlockReason('interstitial'),
          AdBlockReason.adsDisabled,
        );
      });

      test('disabled ads short-circuit before the consent check', () async {
        enabled = false;
        await gate.canLoad('interstitial');
        expect(consentChecks, 0);
      });
    },
  );

  group('showBlockReason (cheap live checks for the show path)', () {
    test('reflects enabled + live consent, nothing else', () async {
      expect(await gate.showBlockReason('interstitial'), isNull);

      consented = false; // e.g. withdrawn between load and show
      expect(
        await gate.showBlockReason('interstitial'),
        AdBlockReason.consentNotGranted,
      );

      consented = true;
      enabled = false;
      expect(
        await gate.showBlockReason('interstitial'),
        AdBlockReason.adsDisabled,
      );
    });
  });
}
