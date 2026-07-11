import 'package:ad_flow/src/config/ad_flow_config.dart';
import 'package:ad_flow/src/controllers/app_open_ad_controller.dart';
import 'package:ad_flow/src/core/ad_load_state.dart';
import 'package:ad_flow/src/lifecycle/app_open_ad_manager.dart';
import 'package:ad_flow/src/policy/ad_gate.dart';
import 'package:ad_flow/src/policy/frequency_cap_policy.dart';
import 'package:ad_flow/src/policy/full_screen_ad_coordinator.dart';
import 'package:ad_flow/src/policy/key_value_store.dart';
import 'package:ad_flow/src/seam/fake_ad_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeAdSdk sdk;
  late FullScreenAdCoordinator coordinator;
  late StoredFrequencyCapPolicy caps;
  late DateTime now;
  late bool consented;

  setUp(() {
    sdk = FakeAdSdk();
    sdk.enforceConsentGate = true;
    sdk.canRequestAdsResult = true;
    consented = true;
    coordinator = FullScreenAdCoordinator();
    now = DateTime(2026, 7, 11, 12);
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

  AppOpenAdController controller({AppOpenConfig? config}) =>
      AppOpenAdController(
        sdk: sdk,
        gate: AdGate(
          canRequestAds: () async => consented && sdk.canRequestAdsResult,
          isEnabled: () => true,
          caps: caps,
          coordinator: coordinator,
        ),
        caps: caps,
        coordinator: coordinator,
        config:
            config ??
            const AppOpenConfig(
              adUnitId: PlatformAdUnitId(android: 'unit-ao'),
              cap: FrequencyCap(),
            ),
        adUnitId: 'unit-ao',
        now: () => now,
      );

  AppOpenAdManager manager(AppOpenAdController c, {AppOpenConfig? config}) =>
      AppOpenAdManager(
        controller: c,
        sdk: sdk,
        config:
            config ??
            const AppOpenConfig(
              adUnitId: PlatformAdUnitId(android: 'unit-ao'),
              cap: FrequencyCap(),
            ),
      );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('no load while consent is closed (invariant 1)', () async {
    consented = false;
    sdk.canRequestAdsResult = false;
    final c = controller();
    await c.load();
    expect(sdk.loadLog, isEmpty); // enforceConsentGate would throw if hit
    c.dispose();
  });

  group('controller expiry (4h rule)', () {
    test('a fresh ad shows; a stale ad is discarded and reloaded', () async {
      final c = controller();
      await c.load();
      expect(c.isExpired, isFalse);

      now = now.add(const Duration(hours: 4));
      expect(c.isExpired, isTrue);

      final shown = await c.show();
      await settle();

      expect(shown, isFalse);
      expect(sdk.appOpens.first.showCalls, 0);
      expect(sdk.appOpens.first.disposed, isTrue);
      expect(sdk.appOpens, hasLength(2)); // fresh one warmed
      expect(c.state.value, const AdLoaded());
      expect(c.isExpired, isFalse); // new timestamp
      c.dispose();
    });

    test('just under the expiry still shows', () async {
      final c = controller();
      await c.load();
      now = now.add(const Duration(hours: 3, minutes: 59));
      expect(await c.show(), isTrue);
      c.dispose();
    });
  });

  group('manager lifecycle', () {
    test(
      'start warms a preload and never shows on the cold-start event',
      () async {
        final c = controller();
        final m = manager(c);
        m.start();
        await settle();
        expect(sdk.appOpens, hasLength(1)); // preload only

        sdk.emitAppForeground(); // cold start: platform emits on app start too
        await settle();
        expect(sdk.appOpens.single.showCalls, 0);

        sdk.emitAppForeground(); // warm return
        await settle();
        expect(sdk.appOpens.single.showCalls, 1);

        m.dispose();
        c.dispose();
      },
    );

    test(
      'showOnColdStart lets the first event show (splash-gate mode)',
      () async {
        const config = AppOpenConfig(
          adUnitId: PlatformAdUnitId(android: 'unit-ao'),
          cap: FrequencyCap(),
          showOnColdStart: true,
        );
        final c = controller(config: config);
        final m = manager(c, config: config);
        m.start();
        await settle();

        sdk.emitAppForeground();
        await settle();
        expect(sdk.appOpens.single.showCalls, 1);

        m.dispose();
        c.dispose();
      },
    );

    test('suppressed while another full-screen ad is visible', () async {
      final c = controller();
      final m = manager(c);
      m.start();
      await settle();
      sdk.emitAppForeground(); // consume cold-start event
      await settle();

      coordinator.enter(); // e.g. an interstitial is showing
      sdk.emitAppForeground();
      await settle();
      expect(sdk.appOpens.single.showCalls, 0);

      coordinator.exit();
      sdk.emitAppForeground();
      await settle();
      expect(sdk.appOpens.single.showCalls, 1);

      m.dispose();
      c.dispose();
    });

    test('expired ad on foreground is discarded, not shown', () async {
      final c = controller();
      final m = manager(c);
      m.start();
      await settle();
      sdk.emitAppForeground(); // cold start
      await settle();

      now = now.add(const Duration(hours: 5));
      sdk.emitAppForeground();
      await settle();

      expect(sdk.appOpens.first.showCalls, 0);
      expect(sdk.appOpens.first.disposed, isTrue);
      expect(sdk.appOpens, hasLength(2));

      m.dispose();
      c.dispose();
    });

    test('frequency cap paces foreground shows', () async {
      caps = StoredFrequencyCapPolicy(
        store: InMemoryKeyValueStore(),
        slotCaps: {
          'app_open': const FrequencyCap(minGap: Duration(minutes: 4)),
        },
        globalCap: const FrequencyCap(),
        now: () => now,
      );
      final c = controller();
      final m = manager(c);
      m.start();
      await settle();
      sdk.emitAppForeground(); // cold start
      await settle();

      sdk.emitAppForeground();
      await settle();
      expect(sdk.appOpens.first.showCalls, 1);
      sdk.appOpens.first.simulateDismissed();
      await settle();

      sdk.emitAppForeground(); // 0s later: capped
      await settle();
      expect(sdk.appOpens.last.showCalls, 0);

      now = now.add(const Duration(minutes: 4));
      sdk.emitAppForeground();
      await settle();
      expect(sdk.appOpens.last.showCalls, 1);

      m.dispose();
      c.dispose();
    });

    test('start is idempotent; stop unsubscribes', () async {
      final c = controller();
      final m = manager(c);
      m.start();
      m.start();
      await settle();
      expect(m.isStarted, isTrue);

      m.stop();
      expect(m.isStarted, isFalse);
      sdk.emitAppForeground();
      sdk.emitAppForeground();
      await settle();
      expect(sdk.appOpens.single.showCalls, 0);

      c.dispose();
    });
  });
}
