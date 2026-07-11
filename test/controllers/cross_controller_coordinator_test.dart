import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/app_open_ad_controller.dart';
import 'package:ad_flow/src/controllers/interstitial_ad_controller.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for a cross-controller race: two independently
/// gated FullScreenAdControllerBase instances sharing one coordinator
/// must never both show at once, even when show() is invoked on both in
/// the same synchronous turn (e.g. an interstitial triggered by a
/// navigation event at the same moment the app-open manager reacts to a
/// foreground event).
void main() {
  test(
    'two independent controllers racing for show() — only one wins',
    () async {
      final sdk = FakeAdSdk()
        ..enforceConsentGate = true
        ..canRequestAdsResult = true;
      final coordinator = FullScreenAdCoordinator();
      final caps = StoredFrequencyCapPolicy(
        store: InMemoryKeyValueStore(),
        slotCaps: const {},
        globalCap: const FrequencyCap(),
      );
      final gate = AdGate(
        canRequestAds: sdk.canRequestAds,
        isEnabled: () => true,
        caps: caps,
        coordinator: coordinator,
      );

      final interstitial = InterstitialAdController(
        sdk: sdk,
        gate: gate,
        caps: caps,
        coordinator: coordinator,
        config: const InterstitialConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-i'),
          cap: FrequencyCap(),
        ),
        adUnitId: 'unit-i',
      );
      final appOpen = AppOpenAdController(
        sdk: sdk,
        gate: gate,
        caps: caps,
        coordinator: coordinator,
        config: const AppOpenConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-ao'),
          cap: FrequencyCap(),
        ),
        adUnitId: 'unit-ao',
      );
      await interstitial.load();
      await appOpen.load();

      // Same-turn shows, e.g. a navigation-triggered interstitial and a
      // foreground-triggered app-open ad firing at once.
      final f1 = interstitial.show();
      final f2 = appOpen.show();
      final results = await Future.wait([f1, f2]);

      expect(results.where((r) => r).length, 1); // exactly one shown
      final showingCount = [
        interstitial.state.value,
        appOpen.state.value,
      ].whereType<AdShowing>().length;
      expect(showingCount, 1); // never both AdShowing at once
      expect(
        sdk.interstitials.single.showCalls + sdk.appOpens.single.showCalls,
        1,
      );
      expect(coordinator.isFullScreenAdVisible, isTrue);

      interstitial.dispose();
      appOpen.dispose();
      coordinator.dispose();
      await sdk.dispose();
    },
  );
}
