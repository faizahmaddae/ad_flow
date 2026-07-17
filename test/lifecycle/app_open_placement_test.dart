import 'package:ad_flow/ad_flow.dart';
import 'package:ad_flow/ad_flow_testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// WHEN an app-open ad may appear on a foreground return (ADR-042, ADR-043).
void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late StoredFrequencyCapPolicy caps;
  late DateTime now;

  setUp(() {
    sdk = FakeAdSdk()
      ..enforceConsentGate = true
      ..canRequestAdsResult = true;
    now = DateTime(2026, 7, 14, 12);
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

  AppOpenAdController controller() => AppOpenAdController(
    sdk: sdk,
    gate: AdGate(canRequestAds: sdk.canRequestAds, isEnabled: () => true),
    caps: caps,
    coordinator: coordinator,
    config: const AppOpenConfig(
      adUnitId: PlatformAdUnitId(android: 'unit-ao'),
      cap: FrequencyCap(),
    ),
    adUnitId: 'unit-ao',
    now: () => now,
  );

  AppOpenAdManager manager(AppOpenAdController c) => AppOpenAdManager(
    controller: c,
    sdk: sdk,
    config: const AppOpenConfig(
      adUnitId: PlatformAdUnitId(android: 'unit-ao'),
      cap: FrequencyCap(),
    ),
    coordinator: coordinator,
    now: () => now,
  );

  /// Starts the manager and lets the preload land.
  Future<void> boot(AppOpenAdManager m) async {
    m.start();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'item 6: the FIRST genuine warm return shows an app-open ad (ADR-043)',
    () async {
      final c = controller();
      final m = manager(c);
      await boot(m);
      expect(c.isReady, isTrue);

      // The platform does NOT replay the cold-launch foreground (the seam calls
      // startListening() after the app is already foregrounded), so the first
      // event we ever receive IS a real background→return. Consuming it as a
      // "cold start" threw away one app-open impression in every single session.
      sdk.emitAppForeground();
      await Future<void>.delayed(Duration.zero);

      expect(
        sdk.appOpens.single.showCalls,
        1,
        reason:
            'the first warm return of a session is a real impression, not a '
            'cold start the platform never emits',
      );
      m.dispose();
      c.dispose();
    },
  );

  test(
    'item 6: a TRUE cold start still cannot show (no ad is loaded yet)',
    () async {
      final c = controller();
      final m = manager(c);
      sdk.loadHold = null;
      // Hold the preload so nothing is warm — this is what a genuine cold launch
      // looks like at the instant the app foregrounds.
      sdk.alwaysLoadError = const AdFlowError(
        AdFlowErrorKind.loadFailed,
        'still loading',
      );
      m.start();
      await Future<void>.delayed(Duration.zero);

      sdk.emitAppForeground();
      await Future<void>.delayed(Duration.zero);

      expect(
        sdk.appOpens,
        isEmpty,
        reason:
            'invariant 3: nothing can show on a cold launch because nothing '
            'is loaded yet — that is the structural guard, not the latch',
      );
      m.dispose();
      c.dispose();
    },
  );

  test(
    'item 4a: returning from a BANNER ad click shows no app-open (ADR-042)',
    () async {
      final c = controller();
      final m = manager(c);
      await boot(m);

      // The user taps the banner ad. The SDK opens the landing page and the app
      // goes to the background; the user comes back 20s later. That foreground
      // event is a return FROM AN AD, not a genuine warm return — stacking an
      // app-open ad on it is exactly the back-to-back-ads case AdMob objects to.
      coordinator.noteViewAdOpened();
      now = now.add(const Duration(seconds: 20));
      sdk.emitAppForeground();
      await Future<void>.delayed(Duration.zero);

      expect(sdk.appOpens.single.showCalls, 0);

      // The latch is one-shot: the NEXT genuine return is fine.
      now = now.add(const Duration(minutes: 1));
      sdk.emitAppForeground();
      await Future<void>.delayed(Duration.zero);
      expect(sdk.appOpens.single.showCalls, 1);

      m.dispose();
      c.dispose();
    },
  );

  test('item 4b: no app-open while the app declares a blocking view ad on '
      'screen (ADR-042)', () async {
    final c = controller();
    final m = manager(c);
    await boot(m);

    coordinator.blockingViewAdVisible = true;
    sdk.emitAppForeground();
    await Future<void>.delayed(Duration.zero);

    expect(
      sdk.appOpens.single.showCalls,
      0,
      reason:
          'an app-open ad must not cover content that is already showing '
          'an ad — the app knows its own layout, so it tells us',
    );

    coordinator.blockingViewAdVisible = false;
    sdk.emitAppForeground();
    await Future<void>.delayed(Duration.zero);
    expect(sdk.appOpens.single.showCalls, 1);

    m.dispose();
    c.dispose();
  });
}
