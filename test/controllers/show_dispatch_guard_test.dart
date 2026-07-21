import 'dart:async';

import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/interstitial_ad_controller.dart';
import 'package:ad_flow/src/core/ad_block_reason.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/retry_policy.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

/// A cap policy whose `canShow` can be HELD by a completer, to open the
/// check-to-dispatch window in `showEngine`.
class _HoldableCaps implements FrequencyCapPolicy {
  Completer<void>? canShowHold;

  @override
  Future<bool> canShow(String slot) async {
    final hold = canShowHold;
    if (hold != null) await hold.future;
    return true;
  }

  @override
  Future<void> recordImpression(String slot) async {}
}

/// The final full-screen dispatch boundary (5.2.1).
///
/// `showEngine` claims the coordinator + publishes `AdShowing`, then awaits
/// `showBlockReason` and `_caps.canShow` before the irreversible
/// `handle.show()`. A `disableAds()` / consent mutation / expiry that lands
/// during those awaits is ignored by `_recheckAll` (it skips `AdShowing`), so
/// the ad could be dispatched despite being revoked or stale. A cheap
/// synchronous re-check immediately before `handle.show()` closes that window.
void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late _HoldableCaps caps;

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
    coordinator = FullScreenAdCoordinator();
    caps = _HoldableCaps();
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  InterstitialAdController build({
    required bool Function() isEnabled,
    int Function()? consentGeneration,
    Duration? maxAdAge,
    DateTime Function()? now,
  }) => InterstitialAdController(
    sdk: sdk,
    gate: AdGate(
      canRequestAds: () async => true,
      isEnabled: isEnabled,
      consentGeneration: consentGeneration,
    ),
    caps: caps,
    coordinator: coordinator,
    config: InterstitialConfig(
      adUnitId: const PlatformAdUnitId(android: 'unit-i'),
      maxAdAge: maxAdAge,
    ),
    adUnitId: 'unit-i',
    retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
    now: now,
  );

  test('ads disabled while the cap check is held → show() returns false and '
      'never dispatches the ad', () async {
    var enabled = true;
    final controller = build(isEnabled: () => enabled);
    await controller.load();
    expect(controller.state.value, isA<AdLoaded>());
    final handle = sdk.interstitials.single;

    // Hold the cap check, start the show, and reach the held await.
    caps.canShowHold = Completer<void>();
    final showFuture = controller.show();
    await pumpEventQueue();

    // Remove-Ads bought mid-show — _recheckAll() skips the AdShowing controller.
    enabled = false;

    // Release the cap check; the show reaches the dispatch boundary.
    caps.canShowHold!.complete();
    final shown = await showFuture;

    expect(shown, isFalse, reason: 'a revoked ad must not be dispatched');
    expect(
      handle.showCalls,
      0,
      reason: 'handle.show() must never be called once ads are disabled',
    );
    expect(
      coordinator.isFullScreenAdVisible,
      isFalse,
      reason: 'the coordinator claim must be released',
    );
    // Not left warm under adsDisabled.
    expect(controller.isReady, isFalse);
    expect(controller.state.value, const AdBlocked(AdBlockReason.adsDisabled));
    controller.dispose();
  });

  test('consent generation changes while the cap check is held → not '
      'dispatched, dropped and reloaded', () async {
    var generation = 0;
    final controller = build(
      isEnabled: () => true,
      consentGeneration: () => generation,
    );
    await controller.load();
    final handle = sdk.interstitials.single;

    caps.canShowHold = Completer<void>();
    final showFuture = controller.show();
    await pumpEventQueue();

    generation = 1; // a consent mutation landed while we were awaiting the cap

    caps.canShowHold!.complete();
    final shown = await showFuture;

    expect(shown, isFalse);
    expect(
      handle.showCalls,
      0,
      reason: 'a stale-consent ad must not be dispatched',
    );
    expect(coordinator.isFullScreenAdVisible, isFalse);
    // Dropped and a fresh one reloaded through the current gate.
    await pumpEventQueue();
    expect(sdk.interstitials.length, greaterThanOrEqualTo(2));
    controller.dispose();
  });

  test('the warm ad expires while the cap check is held → not dispatched, '
      'discarded and reloaded', () async {
    var clock = DateTime(2026, 1, 1, 12);
    final controller = build(
      isEnabled: () => true,
      maxAdAge: const Duration(minutes: 55),
      now: () => clock,
    );
    await controller.load();
    final handle = sdk.interstitials.single;

    caps.canShowHold = Completer<void>();
    final showFuture = controller.show();
    await pumpEventQueue();

    clock = clock.add(const Duration(hours: 2)); // age past maxAdAge mid-show

    caps.canShowHold!.complete();
    final shown = await showFuture;

    expect(shown, isFalse);
    expect(handle.showCalls, 0, reason: 'an expired ad must not be dispatched');
    expect(coordinator.isFullScreenAdVisible, isFalse);
    await pumpEventQueue();
    expect(sdk.interstitials.length, greaterThanOrEqualTo(2));
    controller.dispose();
  });
}
