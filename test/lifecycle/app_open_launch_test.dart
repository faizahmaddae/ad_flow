import 'dart:async';

import 'package:ad_flow/ad_flow_testing.dart'
    show resetAppOpenLaunchOpportunity;
import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/app_open_ad_controller.dart';
import 'package:ad_flow/src/core/ad_block_reason.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/core/ad_show_result.dart';
import 'package:ad_flow/src/lifecycle/app_open_ad_manager.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

/// The explicit cold-launch moment (`showAtLaunch`, 6.0) and the resume
/// switch (`AppOpenConfig.showOnResume`).
///
/// Cold launch is NEVER faked from a lifecycle event: it is the one-shot
/// [AppOpenAdManager.showAtLaunch], taken from the app's loading screen. It
/// waits (bounded) for the first load — the reason launch ads used to almost
/// never show — and completes when the ad CLOSES.
///
/// The one-shot latch is process-global (internal `LaunchLatch`), so every
/// test resets it in [setUp] via `resetAppOpenLaunchOpportunity()`.
void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late StoredFrequencyCapPolicy caps;
  late DateTime now;

  setUp(() {
    resetAppOpenLaunchOpportunity();
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
    now = DateTime(2026, 11, 18, 9);
    coordinator = FullScreenAdCoordinator(now: () => now);
    caps = StoredFrequencyCapPolicy(
      store: InMemoryKeyValueStore(),
      slotCaps: const {},
      globalCap: const FrequencyCap(),
      now: () => now,
    );
  });
  tearDown(() {
    coordinator.dispose();
    sdk.dispose();
  });

  AppOpenConfig cfg({bool showOnResume = true}) => AppOpenConfig(
    adUnitId: const PlatformAdUnitId(android: 'unit-ao'),
    cap: const FrequencyCap(),
    showOnResume: showOnResume,
  );

  AppOpenAdController controller({bool showOnResume = true}) =>
      AppOpenAdController(
        sdk: sdk,
        gate: AdGate(canRequestAds: sdk.canRequestAds, isEnabled: () => true),
        caps: caps,
        coordinator: coordinator,
        config: cfg(showOnResume: showOnResume),
        adUnitId: 'unit-ao',
        now: () => now,
      );

  AppOpenAdManager manager(AppOpenAdController c, {bool showOnResume = true}) =>
      AppOpenAdManager(
        controller: c,
        sdk: sdk,
        config: cfg(showOnResume: showOnResume),
        coordinator: coordinator,
        now: () => now,
      );

  group('showAtLaunch', () {
    test('shows a warm ad and completes only when it CLOSES', () async {
      final m = manager(controller())..start();
      await pumpEventQueue();

      AdShowResult? result;
      unawaited(m.showAtLaunch().then((r) => result = r));
      await pumpEventQueue();
      expect(sdk.appOpens.single.showCalls, 1);
      expect(result, isNull, reason: 'the ad is still on screen');

      sdk.appOpens.single.simulateDismissed();
      await pumpEventQueue();
      expect(result, const AdShowResult.shown());
      m.dispose();
    });

    test('WAITS for a load still in flight, within maxWait', () {
      fakeAsync((async) {
        sdk.loadHold = Completer<void>(); // the first load is in flight
        final m = manager(controller())..start();
        async.flushMicrotasks();

        AdShowResult? result;
        m.showAtLaunch().then((r) => result = r);
        async.elapse(const Duration(seconds: 1));
        expect(sdk.appOpens, isEmpty);

        sdk.loadHold!.complete(); // the ad lands 1 s into the launch
        sdk.loadHold = null;
        async.flushMicrotasks();
        expect(sdk.appOpens.single.showCalls, 1);

        sdk.appOpens.single.simulateDismissed();
        async.flushMicrotasks();
        expect(result?.shown, isTrue);
        m.dispose();
      });
    });

    test('gives up after maxWait and never shows that ad later', () {
      fakeAsync((async) {
        sdk.loadHold = Completer<void>();
        final m = manager(controller())..start();
        async.flushMicrotasks();

        AdShowResult? result;
        m
            .showAtLaunch(maxWait: const Duration(seconds: 3))
            .then((r) => result = r);
        async.elapse(const Duration(seconds: 3));
        expect(result, const AdShowResult.blocked(AdBlockReason.notReady));

        // The load lands after the launch moment: nothing appears.
        sdk.loadHold!.complete();
        sdk.loadHold = null;
        async.flushMicrotasks();
        expect(sdk.appOpens.single.showCalls, 0);
        m.dispose();
      });
    });

    test('maxWait zero shows only an ad that is already warm', () async {
      sdk.loadHold = Completer<void>();
      final m = manager(controller())..start();
      await pumpEventQueue();

      final result = await m.showAtLaunch(maxWait: Duration.zero);

      expect(result, const AdShowResult.blocked(AdBlockReason.notReady));
      sdk.loadHold!.complete();
      m.dispose();
    });

    test('a first-time user (no consent stored yet) gets no launch ad, and '
        'the call does not wait', () async {
      sdk.canRequestAdsResult = false; // no earlier consent on the device
      final m = manager(controller())..start();
      await pumpEventQueue();

      final result = await m.showAtLaunch();

      expect(
        result,
        const AdShowResult.blocked(AdBlockReason.consentNotGranted),
      );
      m.dispose();
    });

    test('one-shot: a second call — even with a fresh warm ad — returns at '
        'once, and so does a call after reinitialization', () async {
      final c = controller();
      final m = manager(c)..start();
      await pumpEventQueue();
      final first = m.showAtLaunch();
      await pumpEventQueue();
      sdk.appOpens.single.simulateDismissed();
      expect((await first).shown, isTrue);
      await pumpEventQueue();
      expect(c.isReady, isTrue); // the next ad preloaded on dismiss

      expect(
        await m.showAtLaunch(),
        const AdShowResult.blocked(AdBlockReason.notReady),
      );
      m.dispose();

      // A second manager in the same process (AdFlow re-initialized).
      final m2 = manager(controller())..start();
      await pumpEventQueue();
      expect(
        await m2.showAtLaunch(),
        const AdShowResult.blocked(AdBlockReason.notReady),
      );
      m2.dispose();
    });

    test('a manager disposed before its launch does not consume the '
        'opportunity', () async {
      final m = manager(controller())..start();
      m.dispose();
      expect(
        await m.showAtLaunch(),
        const AdShowResult.blocked(AdBlockReason.notReady),
      );

      final m2 = manager(controller())..start();
      await pumpEventQueue();
      final launch = m2.showAtLaunch();
      await pumpEventQueue();
      expect(sdk.appOpens.last.showCalls, 1);
      sdk.appOpens.last.simulateDismissed();
      expect((await launch).shown, isTrue);
      m2.dispose();
    });
  });

  group('showOnResume', () {
    test('default: a warm return shows', () async {
      final m = manager(controller())..start();
      await pumpEventQueue();
      sdk.emitAppForeground();
      await pumpEventQueue();
      expect(sdk.appOpens.single.showCalls, 1);
      m.dispose();
    });

    test('launch + resume: no startup double, and the next warm return shows '
        'again (after the post-dismiss gap)', () async {
      final m = manager(controller())..start();
      await pumpEventQueue();
      final launch = m.showAtLaunch();
      await pumpEventQueue();
      sdk.appOpens.first.simulateDismissed();
      expect((await launch).shown, isTrue);
      await pumpEventQueue();

      // A foreground event right behind the launch ad's dismiss is suppressed.
      sdk.emitAppForeground();
      await pumpEventQueue();
      expect(sdk.appOpens.last.showCalls, 0);

      now = now.add(const Duration(minutes: 5));
      sdk.emitAppForeground();
      await pumpEventQueue();
      expect(sdk.appOpens.last.showCalls, 1);
      m.dispose();
    });

    test('off: a warm return never shows (launch-only)', () async {
      final m = manager(controller(showOnResume: false), showOnResume: false)
        ..start();
      await pumpEventQueue();
      sdk.emitAppForeground();
      await pumpEventQueue();
      expect(sdk.appOpens.single.showCalls, 0);
      m.dispose();
    });

    test('off: after the launch the slot stops loading — no reload on '
        'dismiss, none on resume', () async {
      final c = controller(showOnResume: false);
      final m = manager(c, showOnResume: false)..start();
      await pumpEventQueue();
      final launch = m.showAtLaunch();
      await pumpEventQueue();
      sdk.appOpens.single.simulateDismissed();
      expect((await launch).shown, isTrue);
      await pumpEventQueue();

      sdk.emitAppForeground();
      await pumpEventQueue();
      expect(sdk.appOpens, hasLength(1), reason: 'never reloaded');
      expect(c.state.value, const AdIdle());
      m.dispose();
    });

    test('off, and no ad at launch: the slot still stops loading', () async {
      sdk.loadHold = Completer<void>();
      final c = controller(showOnResume: false);
      final m = manager(c, showOnResume: false)..start();
      await pumpEventQueue();

      await m.showAtLaunch(maxWait: Duration.zero);
      sdk.loadHold!.complete();
      sdk.loadHold = null;
      await pumpEventQueue();

      expect(c.isReady, isFalse, reason: 'a late ad is dropped, not kept');
      m.dispose();
    });
  });
}
