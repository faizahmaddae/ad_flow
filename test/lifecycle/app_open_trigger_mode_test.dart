import 'dart:async';

import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/app_open_ad_controller.dart';
import 'package:ad_flow/src/core/ad_flow_error.dart';
import 'package:ad_flow/src/lifecycle/app_open_ad_manager.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

/// App-open trigger modes + the explicit cold-launch opportunity (5.1).
///
/// Cold launch is NEVER faked from a lifecycle event; it is the explicit,
/// one-shot [AppOpenAdManager.showAtLaunchIfReady] taken from the app's loading
/// screen. `resumeOnly` (the v5 default) ignores it; `launchOnly` shows only
/// there and never on a warm return; `launchAndResume` supports both without a
/// startup duplicate.
void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late StoredFrequencyCapPolicy caps;
  late DateTime now;
  late bool consented;

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
    consented = true;
    now = DateTime(2026, 7, 20, 9);
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

  AppOpenConfig cfg(AppOpenTriggerMode mode) => AppOpenConfig(
    adUnitId: const PlatformAdUnitId(android: 'unit-ao'),
    cap: const FrequencyCap(),
    triggerMode: mode,
  );

  AppOpenAdController controller(AppOpenTriggerMode mode) => AppOpenAdController(
    sdk: sdk,
    gate: AdGate(
      canRequestAds: () async => consented && sdk.canRequestAdsResult,
      isEnabled: () => true,
    ),
    caps: caps,
    coordinator: coordinator,
    config: cfg(mode),
    adUnitId: 'unit-ao',
    now: () => now,
  );

  AppOpenAdManager manager(
    AppOpenAdController c,
    AppOpenTriggerMode mode, {
    LaunchOpportunity? launch,
  }) => AppOpenAdManager(
    controller: c,
    sdk: sdk,
    config: cfg(mode),
    coordinator: coordinator,
    now: () => now,
    launchOpportunity: launch ?? LaunchOpportunity(),
  );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<AppOpenAdManager> booted(
    AppOpenTriggerMode mode, {
    LaunchOpportunity? launch,
  }) async {
    final c = controller(mode);
    final m = manager(c, mode, launch: launch);
    m.start();
    await settle();
    return m;
  }

  group('resumeOnly (v5 default)', () {
    test('showAtLaunchIfReady is a no-op and never shows', () async {
      final m = await booted(AppOpenTriggerMode.resumeOnly);
      expect(await m.showAtLaunchIfReady(), isFalse);
      expect(sdk.appOpens.single.showCalls, 0);
      m.dispose();
    });

    test('a warm return still shows (unchanged behaviour)', () async {
      final m = await booted(AppOpenTriggerMode.resumeOnly);
      sdk.emitAppForeground();
      await settle();
      expect(sdk.appOpens.single.showCalls, 1);
      m.dispose();
    });
  });

  group('launchOnly', () {
    test('showAtLaunchIfReady shows the preloaded ad at launch', () async {
      final m = await booted(AppOpenTriggerMode.launchOnly);
      expect(await m.showAtLaunchIfReady(), isTrue);
      expect(sdk.appOpens.first.showCalls, 1);
      m.dispose();
    });

    test('a warm return does NOT auto-show (but keeps one warm)', () async {
      final m = await booted(AppOpenTriggerMode.launchOnly);
      sdk.emitAppForeground();
      await settle();
      expect(sdk.appOpens.single.showCalls, 0);
      expect(sdk.appOpens, isNotEmpty); // still warm for the launch path
      m.dispose();
    });
  });

  group('launchAndResume', () {
    test('shows at launch AND on a later warm return, no startup double',
        () async {
      final m = await booted(AppOpenTriggerMode.launchAndResume);
      expect(await m.showAtLaunchIfReady(), isTrue);
      final first = sdk.appOpens.first;
      expect(first.showCalls, 1);

      // Dismiss the launch ad; a fresh one warms.
      first.simulateDismissed();
      await settle();

      // A genuine warm return, comfortably past the post-dismiss window.
      now = now.add(const Duration(minutes: 5));
      sdk.emitAppForeground();
      await settle();
      expect(sdk.appOpens.last.showCalls, 1);
      m.dispose();
    });

    test('no startup duplicate: launch show holds the coordinator so a '
        'simultaneous foreground cannot stack a second ad', () async {
      final c = controller(AppOpenTriggerMode.launchAndResume);
      final m = manager(c, AppOpenTriggerMode.launchAndResume);
      m.start();
      await settle();

      // Launch show and a foreground event in the same turn.
      final launched = m.showAtLaunchIfReady();
      sdk.emitAppForeground();
      expect(await launched, isTrue);
      await settle();

      // Exactly one show happened (the launch ad); the foreground could not
      // stack a second because the coordinator was claimed.
      expect(sdk.appOpens.where((a) => a.showCalls > 0), hasLength(1));
      m.dispose();
    });
  });

  group('one-shot / not-ready / gates', () {
    test('one-shot: even with a FRESH ad warm after the launch ad dismissed, a '
        'second showAtLaunchIfReady returns false', () async {
      final c = controller(AppOpenTriggerMode.launchAndResume);
      final m = manager(c, AppOpenTriggerMode.launchAndResume);
      m.start();
      await settle();

      expect(await m.showAtLaunchIfReady(), isTrue);
      sdk.appOpens.first.simulateDismissed();
      await settle();
      expect(c.isReady, isTrue, reason: 'a fresh ad is warm again');

      // The launch moment is once per process — even a ready ad is refused.
      expect(await m.showAtLaunchIfReady(), isFalse);
      expect(
        sdk.appOpens.where((a) => a.showCalls > 0),
        hasLength(1),
        reason: 'only the launch ad ever showed',
      );
      m.dispose();
      c.dispose();
    });

    test('not ready: returns false immediately without kicking a load or show',
        () async {
      // Manager NOT started → nothing preloaded.
      final c = controller(AppOpenTriggerMode.launchAndResume);
      final m = manager(c, AppOpenTriggerMode.launchAndResume);
      expect(await m.showAtLaunchIfReady(), isFalse);
      expect(sdk.loadLog, isEmpty, reason: 'never waits for / triggers a load');
      expect(sdk.appOpens, isEmpty);
      m.dispose();
      c.dispose();
    });

    test('returning false at launch does NOT allow a surprise app-open once '
        'the ad later becomes ready (the one-shot is spent)', () async {
      // Hold the preload so nothing is ready at the launch moment.
      final c = controller(AppOpenTriggerMode.launchOnly);
      final m = manager(c, AppOpenTriggerMode.launchOnly);
      sdk.loadHold = Completer<void>();
      m.start();
      await settle();

      expect(await m.showAtLaunchIfReady(), isFalse); // not ready → spent

      // The preload now lands.
      sdk.loadHold!.complete();
      sdk.loadHold = null;
      await settle();
      expect(c.isReady, isTrue);

      // A second launch attempt (or any later one) must not show — the launch
      // moment is over.
      expect(await m.showAtLaunchIfReady(), isFalse);
      // And launchOnly never shows on a warm return.
      sdk.emitAppForeground();
      await settle();
      expect(sdk.appOpens.single.showCalls, 0);
      m.dispose();
    });

    test('consent closed: launch shows nothing', () async {
      consented = false;
      sdk.canRequestAdsResult = false;
      final c = controller(AppOpenTriggerMode.launchAndResume);
      final m = manager(c, AppOpenTriggerMode.launchAndResume);
      m.start();
      await settle();
      expect(c.isReady, isFalse);
      expect(await m.showAtLaunchIfReady(), isFalse);
      expect(sdk.appOpens, isEmpty);
      m.dispose();
      c.dispose();
    });

    test('expired ad at launch is discarded, not shown', () async {
      final c = controller(AppOpenTriggerMode.launchAndResume);
      final m = manager(c, AppOpenTriggerMode.launchAndResume);
      m.start();
      await settle();
      final first = sdk.appOpens.single;

      now = now.add(const Duration(hours: 5)); // past the 4h expiry
      expect(await m.showAtLaunchIfReady(), isFalse);
      await settle();
      expect(first.showCalls, 0);
      expect(first.disposed, isTrue);
      expect(sdk.appOpens, hasLength(2)); // fresh one warmed
      m.dispose();
    });

    test('full-screen overlap: launch is suppressed while another ad shows',
        () async {
      final c = controller(AppOpenTriggerMode.launchAndResume);
      final m = manager(c, AppOpenTriggerMode.launchAndResume);
      m.start();
      await settle();
      coordinator.enter(); // e.g. an interstitial is showing

      expect(await m.showAtLaunchIfReady(), isFalse);
      expect(sdk.appOpens.single.showCalls, 0);
      coordinator.exit();
      m.dispose();
    });
  });

  test('survives reinitialization: a second manager sharing the process latch '
      'gets no second launch opportunity', () async {
    final shared = LaunchOpportunity();

    final c1 = controller(AppOpenTriggerMode.launchAndResume);
    final m1 = manager(c1, AppOpenTriggerMode.launchAndResume, launch: shared);
    m1.start();
    await settle();
    expect(await m1.showAtLaunchIfReady(), isTrue);
    m1.dispose();
    c1.dispose();

    // Reinitialize: a fresh manager + controller, same process launch latch.
    final c2 = controller(AppOpenTriggerMode.launchAndResume);
    final m2 = manager(c2, AppOpenTriggerMode.launchAndResume, launch: shared);
    m2.start();
    await settle();
    expect(c2.isReady, isTrue);
    expect(
      await m2.showAtLaunchIfReady(),
      isFalse,
      reason: 'the cold-launch moment is once per process, not per initialize',
    );
    m2.dispose();
    c2.dispose();
  });

  test('post-dismiss suppression still guards the resume path after a launch '
      'show', () async {
    final m = await booted(AppOpenTriggerMode.launchAndResume);
    expect(await m.showAtLaunchIfReady(), isTrue);
    sdk.appOpens.first.simulateDismissed();
    await settle();

    // A warm return immediately behind the launch ad's dismiss is suppressed.
    sdk.emitAppForeground();
    await settle();
    expect(sdk.appOpens.last.showCalls, 0);

    // Past the window it is allowed.
    now = now.add(const Duration(seconds: 1));
    sdk.emitAppForeground();
    await settle();
    expect(sdk.appOpens.last.showCalls, 1);
    m.dispose();
  });
}
