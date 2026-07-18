import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two rules about WHAT the frequency caps mean — as opposed to how they are
/// computed (covered by `test/policy/frequency_cap_policy_test.dart`).
void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late DateTime now;
  late StoredFrequencyCapPolicy caps;

  const globalCap = FrequencyCap(minGap: Duration(seconds: 15));

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
    coordinator = FullScreenAdCoordinator();
    now = DateTime(2026, 7, 14, 12);
    // Mirrors the facade's wiring (4.0): only CLASSIC rewarded is exempt —
    // the rewarded interstitial's intro is an app-chosen interruption, so its
    // sequence is paced by the global cap like any other involuntary ad.
    caps = StoredFrequencyCapPolicy(
      store: InMemoryKeyValueStore(),
      slotCaps: const {},
      globalCap: globalCap,
      globalCapExemptSlots: const {RewardedAdController.slotName},
      now: () => now,
    );
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  AdGate gate() =>
      AdGate(canRequestAds: sdk.canRequestAds, isEnabled: () => true);

  InterstitialAdController interstitial() => InterstitialAdController(
    sdk: sdk,
    gate: gate(),
    caps: caps,
    coordinator: coordinator,
    config: const InterstitialConfig(
      adUnitId: PlatformAdUnitId(android: 'i'),
      cap: FrequencyCap(),
    ),
    adUnitId: 'i',
  );

  RewardedAdController rewarded() => RewardedAdController(
    sdk: sdk,
    gate: gate(),
    caps: caps,
    coordinator: coordinator,
    config: const RewardedConfig(adUnitId: PlatformAdUnitId(android: 'r')),
    adUnitId: 'r',
  );

  group('the GLOBAL cap gates involuntary ads only (ADR-039)', () {
    test(
      'a user-initiated REWARDED show is never blocked by the global cap',
      () async {
        // An interstitial fires (an ad the user did not ask for), so the global
        // 15s gap is now running.
        final i = interstitial();
        await i.load();
        expect(await i.show(), isTrue);
        sdk.interstitials.single.simulateShowed();
        sdk.interstitials.single.simulateDismissed();

        // 1 second later the user taps "Watch an ad for 100 coins".
        now = now.add(const Duration(seconds: 1));
        final r = rewarded();
        await r.load();

        expect(
          await r.show(onReward: (_) {}),
          isTrue,
          reason:
              'the user ASKED for this ad and is owed a reward for it — the '
              'global involuntary-ad gap must never silently swallow it, '
              'leaving them with no ad and no reward and no explanation',
        );
        i.dispose();
        r.dispose();
      },
    );

    test('the rewarded-interstitial SEQUENCE is paced by the global cap — '
        'and the intro is never presented for a capped one (4.0)', () async {
      final i = interstitial();
      await i.load();
      expect(await i.show(), isTrue);
      sdk.interstitials.single.simulateShowed();
      sdk.interstitials.single.simulateDismissed();

      now = now.add(const Duration(seconds: 1));
      final intros = <RewardIntroContent>[];
      final ri = RewardedInterstitialAdController(
        sdk: sdk,
        gate: gate(),
        caps: caps,
        coordinator: coordinator,
        config: const RewardedInterstitialConfig(
          adUnitId: PlatformAdUnitId(android: 'ri'),
        ),
        adUnitId: 'ri',
        showIntro: (content) async {
          intros.add(content);
          return true;
        },
      );
      await ri.load();

      expect(
        await ri.show(onReward: (_) {}),
        isFalse,
        reason:
            'the intro appears at an app-chosen transition the user did not '
            'ask for — an interruption 1s after an interstitial is exactly '
            'what the global cap paces',
      );
      expect(
        intros,
        isEmpty,
        reason: 'a capped sequence never starts — no promise, no refusal',
      );
      i.dispose();
      ri.dispose();
    });

    test('an INTERSTITIAL is still blocked by the same global gap', () async {
      final r = rewarded();
      await r.load();
      expect(await r.show(onReward: (_) {}), isTrue);
      sdk.rewardeds.single.simulateShowed();
      sdk.rewardeds.single.simulateDismissed();

      now = now.add(const Duration(seconds: 1));
      final i = interstitial();
      await i.load();

      expect(
        await i.show(),
        isFalse,
        reason:
            "a rewarded impression still COUNTS globally: the user just "
            'watched an ad, so an involuntary interstitial 1s later is exactly '
            'what the global cap exists to prevent',
      );
      i.dispose();
      r.dispose();
    });
  });

  group('the global gap runs from DISMISS, not from show (ADR-040)', () {
    test('an interstitial cannot fire the moment a long ad closes', () async {
      final r = rewarded();
      await r.load();
      expect(await r.show(onReward: (_) {}), isTrue);
      sdk.rewardeds.single.simulateShowed();

      // A rewarded ad is long: the user watches for 30s — longer than the 15s
      // global gap — and only then closes it.
      now = now.add(const Duration(seconds: 30));
      sdk.rewardeds.single.simulateDismissed();

      final i = interstitial();
      await i.load();

      expect(
        await i.show(),
        isFalse,
        reason:
            'measured from the SHOW timestamp the gap has "elapsed" while '
            'the user was still watching, so an interstitial would slam in the '
            'instant they closed the ad — two full-screen ads back to back. '
            'The gap must run from the DISMISS.',
      );

      // 15s after the dismiss it is allowed again.
      now = now.add(const Duration(seconds: 16));
      expect(await i.show(), isTrue);

      i.dispose();
      r.dispose();
    });
  });
}
