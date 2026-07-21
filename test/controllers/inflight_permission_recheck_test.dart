import 'dart:async';

import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/interstitial_ad_controller.dart';
import 'package:ad_flow/src/core/ad_block_reason.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/policy/retry_policy.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// The full-screen shared base must re-validate the cheap, current permission
/// immediately BEFORE publishing a newly-loaded handle (5.1.2). `recheckGate()`
/// cannot drop an `AdLoading` controller, so a disable that lands while the
/// load is in flight would otherwise end with warm full-screen inventory
/// retained under Remove-Ads. One shared-base regression covers every
/// full-screen format (none overrides `load()`).
///
/// It must ALSO keep the existing asymmetry: an INDETERMINATE permission read
/// (a transient `internalError`) must never destroy a good warm ad.
void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
    coordinator = FullScreenAdCoordinator();
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  InterstitialAdController build({
    required bool Function() isEnabled,
    bool Function()? canRequestThrows,
  }) => InterstitialAdController(
    sdk: sdk,
    gate: AdGate(
      canRequestAds: () async {
        if (canRequestThrows?.call() ?? false) {
          throw const FormatException('channel error');
        }
        return true;
      },
      isEnabled: isEnabled,
    ),
    caps: StoredFrequencyCapPolicy(
      store: InMemoryKeyValueStore(),
      slotCaps: const {},
      globalCap: const FrequencyCap(),
    ),
    coordinator: coordinator,
    config: const InterstitialConfig(
      adUnitId: PlatformAdUnitId(android: 'unit-i'),
    ),
    adUnitId: 'unit-i',
    retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
  );

  test('a full-screen load in flight when ads are disabled is dropped, never '
      'published as AdLoaded, and recovers when re-enabled', () async {
    var enabled = true;
    final controller = build(isEnabled: () => enabled);

    // Hold the SDK load so it is in flight (past the gate) when we disable.
    sdk.loadHold = Completer<void>();
    final loadFuture = controller.load();
    await pumpEventQueue(); // drain to the held loadInterstitial (past the gate)
    expect(controller.state.value, isA<AdLoading>());

    // Ads disabled while the request is in flight (Remove-Ads bought).
    enabled = false;

    sdk.loadHold!.complete();
    sdk.loadHold = null;
    await loadFuture; // deterministic completion

    expect(
      controller.state.value,
      const AdBlocked(AdBlockReason.adsDisabled),
      reason: 'a load that completes after disable must not publish AdLoaded',
    );
    expect(controller.isReady, isFalse);
    expect(
      sdk.interstitials.single.disposed,
      isTrue,
      reason: 'the late full-screen handle must be disposed, never kept warm',
    );

    // Re-enabling re-warms inventory (automatic recovery, no app code).
    enabled = true;
    await controller.recheckGate();
    await pumpEventQueue();
    expect(controller.isReady, isTrue);
    expect(sdk.interstitials, hasLength(2));

    controller.dispose();
  });

  test('a transient internalError while re-checking a warm ad does NOT drop '
      'it (indeterminate is not "revoked")', () async {
    var canRequestThrows = false;
    final controller = build(
      isEnabled: () => true,
      canRequestThrows: () => canRequestThrows,
    );

    await controller.load();
    expect(controller.state.value, isA<AdLoaded>());
    final warm = sdk.interstitials.single;

    // The consent read now throws (a channel hiccup) — recheckGate must treat
    // it as indeterminate and keep the perfectly good warm ad.
    canRequestThrows = true;
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (_) {}; // the contained throw is reported here
    addTearDown(() => FlutterError.onError = previousOnError);

    await controller.recheckGate();
    await pumpEventQueue();

    expect(
      controller.state.value,
      isA<AdLoaded>(),
      reason: 'a transient internalError must not destroy live/warm inventory',
    );
    expect(controller.isReady, isTrue);
    expect(warm.disposed, isFalse);

    controller.dispose();
  });
}
