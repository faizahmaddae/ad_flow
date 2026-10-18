import 'dart:async';

import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/full_screen_ad_controller_base.dart';
import 'package:ad_flow/src/controllers/interstitial_ad_controller.dart';
import 'package:ad_flow/src/controllers/rewarded_interstitial_ad_controller.dart';
import 'package:ad_flow/src/core/ad_block_reason.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/retry_policy.dart';
import 'package:ad_flow/src/seam/ad_sdk.dart';
import 'package:ad_flow/src/seam/ad_sdk_types.dart';
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

/// A [FakeAdSdk] that counts the full-screen loads IN FLIGHT at the seam. Two
/// at once on one slot is ADR-024's double load: the later handle overwrites
/// the earlier one, which is then never disposed.
class _CountingSdk extends FakeAdSdk {
  int _inFlight = 0;

  /// The most full-screen loads that were ever in flight at once.
  int maxInFlight = 0;

  Future<T> _counted<T>(Future<T> Function() load) async {
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      return await load();
    } finally {
      _inFlight--;
    }
  }

  @override
  Future<InterstitialHandle> loadInterstitial(
    String adUnitId,
    AdRequestOptions options,
  ) => _counted(() => super.loadInterstitial(adUnitId, options));

  @override
  Future<RewardedInterstitialHandle> loadRewardedInterstitial(
    String adUnitId,
    AdRequestOptions options, {
    ServerSideVerification? ssv,
  }) => _counted(
    () => super.loadRewardedInterstitial(adUnitId, options, ssv: ssv),
  );
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
  late _CountingSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late _HoldableCaps caps;

  setUp(() {
    sdk = _CountingSdk()
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

  // "Show as soon as loaded": an app listener on `state` that calls show() the
  // moment it sees AdLoaded. A branch that drops the warm ad instead of showing
  // it (stale consent or expiry at the final guard, expiry after the rewarded
  // interstitial's intro) must reload ONCE and leak nothing, even when that
  // listener re-enters show() while the branch runs.
  group('a show() from an AdLoaded listener while the warm ad is dropped', () {
    /// Parks the listener's first show() in its pre-dispatch window (the
    /// caller holds [window]), makes the warm ad stale with [makeStale],
    /// releases the window, and checks that the slot reloads exactly once,
    /// leaks no handle and keeps the claim balanced. With [holdReload] the
    /// reload is kept in flight, so a second concurrent one is counted at the
    /// seam whatever the microtask order.
    Future<void> expectOneCleanReload(
      FullScreenAdControllerBase controller,
      List<FakeFullScreenAdHandle> handles, {
      required Future<bool> Function() show,
      required Completer<void> window,
      required void Function() makeStale,
      required bool holdReload,
    }) async {
      // Capped, so a regression that loops show() through a rollback fails
      // the asserts below instead of spinning the microtask queue forever.
      var autoShow = true;
      var autoShows = 0;
      controller.state.addListener(() {
        if (!autoShow || controller.state.value is! AdLoaded) return;
        if (++autoShows > 20) return;
        unawaited(show());
      });

      await controller.load(); // the listener's show() parks in the window
      await pumpEventQueue();
      expect(controller.state.value, isA<AdShowing>());
      final stale = handles.single;

      makeStale();
      if (holdReload) sdk.loadHold = Completer<void>();
      window.complete();
      await pumpEventQueue();

      expect(stale.showCalls, 0, reason: 'the stale ad is never dispatched');
      expect(stale.disposed, isTrue, reason: 'the stale ad is dropped');
      expect(sdk.maxInFlight, 1, reason: 'one reload, never two at once');
      if (holdReload) {
        expect(controller.state.value, isA<AdLoading>());
        expect(coordinator.isFullScreenAdVisible, isFalse);
        sdk.loadHold!.complete(); // the reload lands
        sdk.loadHold = null;
        await pumpEventQueue();
        expect(sdk.maxInFlight, 1);
      }

      // The listener shows the fresh ad.
      expect(handles, hasLength(2), reason: 'the first load + ONE reload');
      final fresh = handles.last;
      expect(fresh.showCalls, 1);
      expect(controller.state.value, isA<AdShowing>());
      expect(coordinator.isFullScreenAdVisible, isTrue);
      expect(handles.where((h) => !h.disposed), [fresh], reason: 'no leak');

      autoShow = false;
      fresh.simulateDismissed();
      await pumpEventQueue();
      expect(coordinator.isFullScreenAdVisible, isFalse);
      controller.dispose();
      await pumpEventQueue();
      expect(handles.every((h) => h.disposed), isTrue, reason: 'no leak');
    }

    for (final holdReload in [true, false]) {
      final held = holdReload ? 'reload held' : 'reload not held';

      test('final guard, consent generation changed ($held)', () async {
        var generation = 0;
        final controller = build(
          isEnabled: () => true,
          consentGeneration: () => generation,
        );
        caps.canShowHold = Completer<void>();
        await expectOneCleanReload(
          controller,
          sdk.interstitials,
          show: controller.show,
          window: caps.canShowHold!,
          makeStale: () => generation = 1,
          holdReload: holdReload,
        );
      });

      test('final guard, the ad expired ($held)', () async {
        var clock = DateTime(2026, 1, 1, 12);
        final controller = build(
          isEnabled: () => true,
          maxAdAge: const Duration(minutes: 55),
          now: () => clock,
        );
        caps.canShowHold = Completer<void>();
        await expectOneCleanReload(
          controller,
          sdk.interstitials,
          show: controller.show,
          window: caps.canShowHold!,
          makeStale: () => clock = clock.add(const Duration(hours: 2)),
          holdReload: holdReload,
        );
      });

      test('rewarded interstitial, the ad expired during the intro '
          '($held)', () async {
        var clock = DateTime(2026, 1, 1, 12);
        final intro = Completer<void>();
        final controller = RewardedInterstitialAdController(
          sdk: sdk,
          gate: AdGate(canRequestAds: () async => true, isEnabled: () => true),
          caps: caps,
          coordinator: coordinator,
          config: const RewardedInterstitialConfig(
            adUnitId: PlatformAdUnitId(android: 'unit-ri'),
          ),
          adUnitId: 'unit-ri',
          showIntro: (_) async {
            await intro.future;
            return true;
          },
          retry: RetryPolicy(const RetryConfig(), random: () => 0.5),
          now: () => clock,
        );
        await expectOneCleanReload(
          controller,
          sdk.rewardedInterstitials,
          show: () => controller.show(onReward: (_) {}),
          window: intro,
          makeStale: () => clock = clock.add(const Duration(hours: 2)),
          holdReload: holdReload,
        );
      });
    }
  });
}
